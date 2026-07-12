import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'crypto_service.dart';

class ApiService {
  final String baseUrl = 'https://chat.bubikit.pl/api'; // Zmienimy na domenę produkcyjną
  final _storage = const FlutterSecureStorage();
  final _cryptoService = CryptoService();

  static const _jwtKey = 'jwt_token';
  static const _usernameKey = 'logged_username';

  Future<String?> getToken() async {
    return await _storage.read(key: _jwtKey);
  }

  Future<String?> getUsername() async {
    return await _storage.read(key: _usernameKey);
  }

  Future<void> _saveAuthData(String token, String username) async {
    await _storage.write(key: _jwtKey, value: token);
    await _storage.write(key: _usernameKey, value: username);
  }

  Future<bool> register(String username, String password) async {
    // Generujemy klucze przy rejestracji
    final publicKey = await _cryptoService.getOrGeneratePublicKey();

    final response = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        'public_key': publicKey,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _saveAuthData(data['token'], username);
      return true;
    }
    return false;
  }

  Future<bool> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _saveAuthData(data['token'], username);
      
      // Upewniamy się, że klucz istnieje (lub generujemy, jeśli to np. świeża apka po reinstalacji, 
      // chociaż to mogłoby sprawić problemy z odkodowaniem starych wiadomości - na razie to omijamy)
      await _cryptoService.getOrGeneratePublicKey();
      return true;
    }
    return false;
  }

  Future<bool> adminLogin(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['is_admin'] == true) {
        await _saveAuthData(data['token'], username);
        await _cryptoService.getOrGeneratePublicKey();
        return true;
      }
    }
    return false;
  }

  Future<List<dynamic>> getUsersAdmin() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/admin/users'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body) as List<dynamic>;
    }
    return [];
  }

  Future<bool> deleteUser(String username) async {
    final token = await getToken();
    final response = await http.delete(
      Uri.parse('$baseUrl/admin/users?username=$username'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );
    return response.statusCode == 200;
  }

  Future<bool> changePassword(String username, String newPassword) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/admin/change-password'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'username': username,
        'new_password': newPassword,
      }),
    );
    return response.statusCode == 200;
  }

  Future<void> logout() async {
    await _storage.delete(key: _jwtKey);
    await _storage.delete(key: _usernameKey);
  }
}
