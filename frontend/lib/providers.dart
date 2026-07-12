import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/api_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

class AuthStateNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool val) => state = val;
}
final authStateProvider = NotifierProvider<AuthStateNotifier, bool>(AuthStateNotifier.new);

class CurrentUsernameNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? val) => state = val;
}
final currentUsernameProvider = NotifierProvider<CurrentUsernameNotifier, String?>(CurrentUsernameNotifier.new);

class ContactsNotifier extends Notifier<List<Map<String, dynamic>>> {
  @override
  List<Map<String, dynamic>> build() => [];
  void set(List<Map<String, dynamic>> val) => state = val;
}
final contactsProvider = NotifierProvider<ContactsNotifier, List<Map<String, dynamic>>>(ContactsNotifier.new);
