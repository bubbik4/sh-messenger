import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CryptoService {
  final _storage = const FlutterSecureStorage();
  static const _privateKeyKey = 'e2ee_private_key';
  
  final _algorithm = X25519();
  final _cipher = AesGcm.with256bits();

  /// Pobiera lub generuje nową parę kluczy. Zwraca klucz publiczny w Base64.
  Future<String> getOrGeneratePublicKey() async {
    final existingKeyStr = await _storage.read(key: _privateKeyKey);
    
    if (existingKeyStr != null) {
      final privateKeyBytes = base64Decode(existingKeyStr);
      final keyPair = await _algorithm.newKeyPairFromSeed(privateKeyBytes);
      final publicKey = await keyPair.extractPublicKey();
      return base64Encode(publicKey.bytes);
    }

    // Generowanie nowego klucza
    final keyPair = await _algorithm.newKeyPair();
    final privateKey = await keyPair.extractPrivateKeyBytes();
    
    // Zapis w bezpiecznym schowku systemu
    await _storage.write(key: _privateKeyKey, value: base64Encode(privateKey));
    
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  /// Wymusza generację nowej pary kluczy i nadpisuje starą
  Future<String> generateNewKeyPair() async {
    final keyPair = await _algorithm.newKeyPair();
    final privateKey = await keyPair.extractPrivateKeyBytes();
    
    await _storage.write(key: _privateKeyKey, value: base64Encode(privateKey));
    
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  /// Wylicza wspólny sekret (Shared Secret) na podstawie obcego klucza publicznego
  Future<SecretKey> _calculateSharedSecret(String peerPublicKeyBase64) async {
    final privateKeyStr = await _storage.read(key: _privateKeyKey);
    if (privateKeyStr == null) {
      throw Exception("Brak klucza prywatnego!");
    }
    final privateKeyBytes = base64Decode(privateKeyStr);
    final myKeyPair = await _algorithm.newKeyPairFromSeed(privateKeyBytes);
    
    final peerPublicKeyBytes = base64Decode(peerPublicKeyBase64);
    final peerPublicKey = SimplePublicKey(peerPublicKeyBytes, type: KeyPairType.x25519);

    final sharedSecret = await _algorithm.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: peerPublicKey,
    );
    return sharedSecret;
  }

  /// Szyfruje wiadomość używając klucza publicznego odbiorcy
  Future<String> encryptMessage(String plaintext, String peerPublicKeyBase64) async {
    final sharedSecret = await _calculateSharedSecret(peerPublicKeyBase64);
    
    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: sharedSecret,
    );
    
    // Dołączamy nonce (IV) i mac do zaszyfrowanej wiadomości (format: nonce|mac|ciphertext)
    final combined = [...secretBox.nonce, ...secretBox.mac.bytes, ...secretBox.cipherText];
    return base64Encode(combined);
  }

  /// Deszyfruje wiadomość używając klucza publicznego nadawcy
  Future<String> decryptMessage(String encryptedBase64, String peerPublicKeyBase64) async {
    final sharedSecret = await _calculateSharedSecret(peerPublicKeyBase64);
    
    final combined = base64Decode(encryptedBase64);
    if (combined.length < 12 + 16) {
      throw Exception("Nieprawidłowy format zaszyfrowanej wiadomości");
    }
    
    // AES-GCM nonce to zazwyczaj 12 bajtów, MAC to 16 bajtów
    final nonce = combined.sublist(0, 12);
    final macBytes = combined.sublist(12, 28);
    final ciphertext = combined.sublist(28);
    
    final secretBox = SecretBox(
      ciphertext,
      nonce: nonce,
      mac: Mac(macBytes),
    );
    
    final plaintextBytes = await _cipher.decrypt(
      secretBox,
      secretKey: sharedSecret,
    );
    
    return utf8.decode(plaintextBytes);
  }
}
