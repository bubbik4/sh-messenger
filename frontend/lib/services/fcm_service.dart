import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class FCMService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final String _baseUrl = 'https://chat.bubikit.pl/api';
  final _storage = const FlutterSecureStorage();

  Future<void> initFCM() async {
    // Prośba o uprawnienia (ważne na iOS i nowszych Androidach)
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('Użytkownik przyznał uprawnienia do powiadomień.');
      
      // Pobieranie tokenu FCM
      String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        print('FCM Token: $token');
        await sendTokenToBackend(token);
      }

      // Nasłuchiwanie odświeżenia tokenu
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        sendTokenToBackend(newToken);
      });
    } else {
      print('Użytkownik odmówił uprawnień do powiadomień.');
    }
  }

  Future<void> sendTokenToBackend(String token) async {
    try {
      final jwtToken = await _storage.read(key: 'jwt_token');
      if (jwtToken == null) return; // Jeśli użytkownik nie jest zalogowany, nie wysyłamy

      final response = await http.post(
        Uri.parse('$_baseUrl/fcm/token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({'token': token}),
      );

      if (response.statusCode == 200) {
        print('Token FCM zapisany na serwerze pomyślnie.');
      } else {
        print('Błąd zapisywania tokenu FCM: ${response.statusCode}');
      }
    } catch (e) {
      print('Błąd sieci podczas wysyłania tokenu FCM: $e');
    }
  }
}
