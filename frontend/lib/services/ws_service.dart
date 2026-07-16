import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_service.dart';
import 'crypto_service.dart';
import 'storage_service.dart';

import '../providers.dart';

import 'ws_channel_provider.dart';

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
  Function(String, bool)? onUserStatusChanged;

  Timer? _reconnectTimer;
  Timer? _pingTimer;

  Timer? _pongTimeoutTimer;

  Future<void> connect() async {
    final token = await _apiService.getToken();
    if (token == null) return;

    try {
      _channel = connectWs(Uri.parse(wsUrl));
      await _channel!.ready;

      _channel!.stream.listen(
        (message) {
          _handleMessage(message.toString());
        },
        onDone: () {
          print('WebSocket disconnected');
          _scheduleReconnect();
        },
        onError: (error) {
          print('WebSocket error: $error');
          _scheduleReconnect();
        },
        cancelOnError: true,
      );

      _sendJson({
        'type': 'auth',
        'token': token,
      });

      _pingTimer?.cancel();
      _pongTimeoutTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        _sendJson({'type': 'ping'});
        
        // Czekaj 10 sekund na odpowiedź PONG lub dowolną inną wiadomość
        _pongTimeoutTimer?.cancel();
        _pongTimeoutTimer = Timer(const Duration(seconds: 10), () {
          print('Brak odpowiedzi od serwera (PING timeout). Zamykanie połączenia.');
          _channel?.sink.close();
        });
      });
    } catch (e) {
      print('WebSocket connection failed: $e');
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _channel = null;
    _pingTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      print('Próba ponownego połączenia WebSocket...');
      connect();
    });
  }

  void _sendJson(Map<String, dynamic> data) {
    if (_channel != null) {
      try {
        _channel!.sink.add(jsonEncode(data));
      } catch (e) {
        print('Błąd podczas wysyłania na WebSocket: $e');
      }
    }
  }

  final Map<String, String> _publicKeys = {};

  Future<void> _handleMessage(String messageStr) async {
    final data = jsonDecode(messageStr);
    final type = data['type'];

    // Otrzymaliśmy dowolną wiadomość - serwer żyje
    _pongTimeoutTimer?.cancel();

    if (type == 'pong') {
      return; // Tylko resetujemy timeout, brak innej akcji
    } else if (type == 'user_status_change') {
      final usersList = data['users'] as List<dynamic>? ?? [];
      for (var u in usersList) {
        final username = u['username'];
        final isOnline = u['is_online'] == true;
        ref.read(onlineStatusProvider.notifier).setStatus(username, isOnline);
        if (onUserStatusChanged != null) {
          onUserStatusChanged!(username, isOnline);
        }
      }
    } else if (type == 'auth_success') {
      print('Autoryzacja udana, synchronizacja wiadomości...');
      final lastMsgId = _storageService.getLastMessageId();
      _sendJson({'type': 'sync_messages', 'last_message_id': lastMsgId});
      getUsers();
    } else if (type == 'user_list' || type == 'specific_users_list' || type == 'search_results') {
      final usersList = data['users'] as List<dynamic>? ?? [];
      final users = List<Map<String, dynamic>>.from(usersList);
      final Map<String, bool> newStatuses = {};
      
      for (var u in users) {
        newStatuses[u['username']] = u['is_online'] == true;
        await _processIncomingPublicKey(u['username'], u['public_key']);
      }
      
      ref.read(onlineStatusProvider.notifier).setStatuses(newStatuses);

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
          final messageId = msg['message_id'] as int? ?? 0;
          
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
                 timestamp: DateTime.parse(timestampStr),
                 messageId: messageId,
               );
               print('Deszyfrowanie udane! Wysyłam ACK do serwera (msg_id: $messageId)');
               if (messageId > 0) {
                 _sendJson({
                   'type': 'msg_ack',
                   'message_id': messageId,
                 });
               }
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

  final Map<String, String> _pendingKeys = {};

  Future<void> _processIncomingPublicKey(String username, String newKey) async {
    final oldKey = _storageService.getPeerPublicKey(username);
    if (oldKey != null && oldKey != newKey) {
      // MITM WARNING
      print('OSTRZEŻENIE MITM: Klucz dla $username się zmienił!');
      ref.read(mitmWarningsProvider.notifier).setWarning(username, true);
      _pendingKeys[username] = newKey;
      _publicKeys[username] = oldKey;
    } else {
      if (oldKey == null) {
        await _storageService.savePeerPublicKey(username, newKey);
      }
      _publicKeys[username] = newKey;
      ref.read(mitmWarningsProvider.notifier).setWarning(username, false);
    }
  }

  Future<void> acceptNewKey(String username) async {
    final newKey = _pendingKeys[username];
    if (newKey != null) {
      await _storageService.savePeerPublicKey(username, newKey);
      _publicKeys[username] = newKey;
      _pendingKeys.remove(username);
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
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
  }
}
