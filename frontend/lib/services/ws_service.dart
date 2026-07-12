import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';
import 'crypto_service.dart';
import 'storage_service.dart';

import '../providers.dart';

final wsServiceProvider = Provider<WsService>((ref) {
  return WsService(ref);
});

class WsService {
  final Ref ref;
  WsService(this.ref);

  final String wsUrl = 'wss://chat.bubikit.pl/ws';
  WebSocketChannel? _channel;
  final ApiService _apiService = ApiService();
  final CryptoService _cryptoService = CryptoService();
  final StorageService _storageService = StorageService();

  // Callbacks for UI updates
  Function(List<Map<String, dynamic>>)? onUsersUpdated;
  Function(List<Map<String, dynamic>>)? onSearchResults;
  Function()? onNewMessage;

  Future<void> connect() async {
    final token = await _apiService.getToken();
    if (token == null) return;

    _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    // Oczekujemy na wiadomości
    _channel!.stream.listen(
      (message) {
        _handleMessage(message.toString());
      },
      onDone: () {
        print('WebSocket disconnected');
        // Tutaj można dodać logikę reconnect
      },
      onError: (error) {
        print('WebSocket error: $error');
      },
    );

    // Wysyłamy autoryzację jako pierwszy pakiet
    _sendJson({
      'type': 'auth',
      'token': token,
    });
  }

  void _sendJson(Map<String, dynamic> data) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  final Map<String, String> _publicKeys = {};

  Future<void> _handleMessage(String messageStr) async {
    final data = jsonDecode(messageStr);
    final type = data['type'];

    if (type == 'auth_success') {
      print('Autoryzacja udana, synchronizacja wiadomości...');
      _sendJson({'type': 'sync_messages'});
      getUsers();
    } else if (type == 'user_list' || type == 'specific_users_list' || type == 'search_results') {
      final users = List<Map<String, dynamic>>.from(data['users']);
      for (var u in users) {
        await _processIncomingPublicKey(u['username'], u['public_key']);
      }
      if (type == 'user_list' && onUsersUpdated != null) {
        onUsersUpdated!(users);
      } else if (type == 'search_results' && onSearchResults != null) {
        onSearchResults!(users);
      }
    } else if (type == 'sync_messages' || type == 'new_message') {
      final messages = data['messages'] as List<dynamic>?;
      if (messages != null) {
        for (var msg in messages) {
          final senderUsername = msg['sender_username'];
          final encryptedContent = msg['encrypted_content'];
          final timestampStr = msg['timestamp'];
          
          final senderPublicKeyFromMessage = msg['sender_public_key'];
          
          if (senderPublicKeyFromMessage != null) {
            await _processIncomingPublicKey(senderUsername, senderPublicKeyFromMessage);
          }

          final peerPublicKey = _publicKeys[senderUsername];
          if (peerPublicKey != null) {
             print('Odebrano zaszyfrowaną wiadomość od $senderUsername, próbuję zdeszyfrować...');
             try {
               final decrypted = await _cryptoService.decryptMessage(encryptedContent, peerPublicKey);
               await _storageService.saveMessage(
                 roomId: senderUsername, 
                 senderId: senderUsername, 
                 plaintextMessage: decrypted, 
                 timestamp: DateTime.parse(timestampStr)
               );
               print('Deszyfrowanie udane!');
             } catch (e) {
               print('Błąd deszyfrowania wiadomości: $e');
             }
          } else {
             print('Odebrano wiadomość od $senderUsername, ale brakuje klucza publicznego. Ignoruję...');
          }
        }
        if (onNewMessage != null) onNewMessage!();
      }
    } else if (type == 'error') {
      print('Błąd z serwera: ${data['encrypted_content']}');
    }
  }

  Future<void> _processIncomingPublicKey(String username, String newKey) async {
    final oldKey = _storageService.getPeerPublicKey(username);
    if (oldKey != null && oldKey != newKey) {
      // MITM WARNING
      print('OSTRZEŻENIE MITM: Klucz dla $username się zmienił!');
      ref.read(mitmWarningsProvider.notifier).setWarning(username, true);
      // Nie aktualizujemy _publicKeys, używamy starego
      _publicKeys[username] = oldKey;
    } else {
      if (oldKey == null) {
        await _storageService.savePeerPublicKey(username, newKey);
      }
      _publicKeys[username] = newKey;
      ref.read(mitmWarningsProvider.notifier).setWarning(username, false);
    }
  }

  void getUsers() {
    _sendJson({'type': 'get_users'});
  }

  void searchUsers(String query) {
    _sendJson({'type': 'search_users', 'search_query': query});
  }

  void getSpecificUsers(List<String> usernames) {
    if (usernames.isEmpty) return;
    _sendJson({'type': 'get_specific_users', 'usernames': usernames});
  }

  Future<void> sendMessage(String receiverUsername, String plaintext, String fallbackReceiverPublicKey) async {
    // Pobieramy najświeższy klucz z pamięci lub używamy przekazanego, jeśli z jakiegoś powodu go brak
    final receiverPublicKey = _publicKeys[receiverUsername] ?? fallbackReceiverPublicKey;

    if (receiverPublicKey.isEmpty) return; // Użytkownik usunięty lub klucz pusty

    final encrypted = await _cryptoService.encryptMessage(plaintext, receiverPublicKey);
    
    // Zapisujemy najpierw własną wiadomość do bazy lokalnej (nie zaszyfrowaną, bo my jesteśmy nadawcą)
    final myUsername = await _apiService.getUsername() ?? 'Me';
    await _storageService.saveMessage(
      roomId: receiverUsername,
      senderId: myUsername,
      plaintextMessage: plaintext,
      timestamp: DateTime.now(),
    );
    if (onNewMessage != null) onNewMessage!();

    // Wysyłamy zaszyfrowaną na serwer
    _sendJson({
      'type': 'send_message',
      'receiver_username': receiverUsername,
      'encrypted_content': encrypted,
    });
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
