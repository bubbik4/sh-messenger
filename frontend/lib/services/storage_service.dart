import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

class StorageService {
  static const _encryptionKeyKey = 'hive_encryption_key';
  final _storage = const FlutterSecureStorage();

  Future<void> init() async {
    await Hive.initFlutter();

    // Szukamy klucza szyfrującego bazę Hive w Secure Storage
    String? encryptionKeyStr = await _storage.read(key: _encryptionKeyKey);
    late List<int> encryptionKey;
    
    if (encryptionKeyStr == null) {
      // Pierwsze uruchomienie - tworzymy klucz i zapisujemy
      encryptionKey = Hive.generateSecureKey();
      await _storage.write(key: _encryptionKeyKey, value: base64UrlEncode(encryptionKey));
    } else {
      encryptionKey = base64Url.decode(encryptionKeyStr);
    }

    // Otwieramy zaszyfrowaną skrzynkę z wiadomościami
    await Hive.openBox<Map>(
      'messages',
      encryptionCipher: HiveAesCipher(encryptionKey),
    );

    // Skrzynka na znane klucze publiczne (ochrona przed MitM)
    await Hive.openBox<String>(
      'peer_keys',
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
  }

  /// Zapisuje klucz publiczny rozmówcy (Trust On First Use)
  Future<void> savePeerPublicKey(String username, String publicKey) async {
    final box = Hive.box<String>('peer_keys');
    await box.put(username, publicKey);
  }

  /// Pobiera zapisany klucz publiczny rozmówcy
  String? getPeerPublicKey(String username) {
    final box = Hive.box<String>('peer_keys');
    return box.get(username);
  }

  Future<void> saveMessage({
    required String roomId,
    required String senderId,
    required String plaintextMessage,
    required DateTime timestamp,
    int messageId = 0, // 0 oznacza lokalną wiadomość nadaną przez nas (nie z serwera)
  }) async {
    final box = Hive.box<Map>('messages');
    
    final messageData = {
      'messageId': messageId,
      'roomId': roomId,
      'senderId': senderId,
      'message': plaintextMessage,
      'timestamp': timestamp.toIso8601String(),
    };
    
    await box.add(messageData);
  }

  /// Pobiera historię wiadomości dla danego pokoju (odszyfrowaną z Hive)
  List<Map> getMessagesForRoom(String roomId) {
    final box = Hive.box<Map>('messages');
    final allMessages = box.values.toList();
    
    // Filtrujemy tylko dla danego pokoju i sortujemy chronologicznie
    final roomMessages = allMessages.where((msg) => msg['roomId'] == roomId).toList();
    roomMessages.sort((a, b) {
      final dateA = DateTime.parse(a['timestamp'] as String);
      final dateB = DateTime.parse(b['timestamp'] as String);
      return dateA.compareTo(dateB);
    });
    
    return roomMessages;
  }

  List<String> getChattedRoomIds() {
    final box = Hive.box<Map>('messages');
    final allMessages = box.values.toList();
    final Set<String> roomIds = {};
    for (var msg in allMessages) {
      if (msg['roomId'] != null) {
        roomIds.add(msg['roomId'] as String);
      }
    }
    return roomIds.toList();
  }

  /// Pobiera najwyższe znane MessageID pobrane z serwera
  int getLastMessageId() {
    final box = Hive.box<Map>('messages');
    final allMessages = box.values.toList();
    int maxId = 0;
    for (var msg in allMessages) {
      final msgId = msg['messageId'] as int?;
      if (msgId != null && msgId > maxId) {
        maxId = msgId;
      }
    }
    return maxId;
  }
}
