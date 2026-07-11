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
  }

  /// Zapisuje nową wiadomość
  Future<void> saveMessage({
    required String roomId,
    required String senderId,
    required String plaintextMessage,
    required DateTime timestamp,
  }) async {
    final box = Hive.box<Map>('messages');
    
    final messageData = {
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
}
