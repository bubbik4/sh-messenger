import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/api_service.dart';
import 'services/ws_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

// WsService jest już w ws_service.dart jako wsServiceProvider, ale możemy scentralizować stan tutaj

final authStateProvider = StateProvider<bool>((ref) => false);
final currentUsernameProvider = StateProvider<String?>((ref) => null);

// Lista kontaktów
final contactsProvider = StateProvider<List<Map<String, dynamic>>>((ref) => []);
