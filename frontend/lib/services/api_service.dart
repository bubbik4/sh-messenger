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

  Map<String, String> _getHeaders({String? token}) {
    final headers = {
      'Content-Type': 'application/json',
      'Origin': 'https://chat.bubikit.pl',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  Future<String?> getToken() async {
    return await _storage.read(key: _jwtKey);
  }

  Future<String?> getWsTicket() async {
    final token = await getToken();
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/ws-ticket'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['ticket'];
      }
    } catch (e) {
      print('Błąd pobierania ticketu WS: $e');
    }
    return null;
  }

  Future<String?> getUsername() async {
    return await _storage.read(key: _usernameKey);
  }

  Future<void> _saveAuthData(String token, String username) async {
    await _storage.write(key: _jwtKey, value: token);
    await _storage.write(key: _usernameKey, value: username);
  }

  Future<bool> register(String username, String password, bool isVisible) async {
    // Zawsze generujemy nowe klucze przy rejestracji
    final publicKey = await _cryptoService.generateNewKeyPair();

    final response = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: _getHeaders(),
      body: jsonEncode({
        'username': username,
        'password': password,
        'public_key': publicKey,
        'is_visible': isVisible,
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
    // Generujemy lub pobieramy lokalny klucz publiczny PRZED logowaniem
    final publicKey = await _cryptoService.getOrGeneratePublicKey();

    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: _getHeaders(),
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

  Future<bool> adminLogin(String username, String password) async {
    final publicKey = await _cryptoService.getOrGeneratePublicKey();

    final response = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: _getHeaders(),
      body: jsonEncode({
        'username': username,
        'password': password,
        'public_key': publicKey,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['is_admin'] == true) {
        await _saveAuthData(data['token'], username);
        return true;
      }
    }
    return false;
  }

  Future<List<dynamic>> getUsersAdmin() async {
    final token = await getToken();
    final response = await http.get(
      Uri.parse('$baseUrl/admin/users'),
      headers: _getHeaders(token: token),
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
      headers: _getHeaders(token: token),
    );
    return response.statusCode == 200;
  }

  Future<bool> changePassword(String username, String newPassword) async {
    final token = await getToken();
    final response = await http.post(
      Uri.parse('$baseUrl/admin/change-password'),
      headers: _getHeaders(token: token),
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

  Future<bool> updateVisibility(bool isVisible) async {
    final token = await getToken();
    if (token == null) return false;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/settings/visibility'),
        headers: _getHeaders(token: token),
        body: jsonEncode({'is_visible': isVisible}),
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  Future<void> changeOwnPassword(String oldPassword, String newPassword) async {
    final token = await getToken();
    if (token == null) {
      throw Exception('Brak tokenu. Zaloguj się ponownie.');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/change_password'),
      headers: _getHeaders(token: token),
      body: jsonEncode({
        'old_password': oldPassword,
        'new_password': newPassword,
      }),
    );

    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['message'] ?? 'Nie udało się zmienić hasła (status ${response.statusCode})');
    }
  }

  Future<String?> uploadFile(List<int> bytes) async {
    final token = await getToken();
    if (token == null) return null;

    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/upload'));
    request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'encrypted_blob.bin'));

    try {
      final response = await request.send();
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        final json = jsonDecode(respStr);
        return json['file_id'];
      } else {
        print('Błąd uploadu: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Wyjątek uploadu: $e');
      return null;
    }
  }

  Future<List<int>?> downloadFile(String fileId) async {
    final token = await getToken();
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/download/$fileId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        print('Błąd downloadu: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Wyjątek downloadu: $e');
      return null;
    }
  }
}
