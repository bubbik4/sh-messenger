import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/api_service.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

// Przechowuje informację o obecnym statusie widoczności uzytkownika w ustawieniach.
// Default to true.
class VisibilityNotifier extends Notifier<bool> {
  @override
  bool build() => true;
  void set(bool val) => state = val;
}
final visibilityProvider = NotifierProvider<VisibilityNotifier, bool>(VisibilityNotifier.new);

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

  void updateStatus(String username, bool isOnline) {
    final newState = [...state];
    for (int i = 0; i < newState.length; i++) {
      if (newState[i]['username'] == username) {
        final updatedUser = Map<String, dynamic>.from(newState[i]);
        updatedUser['is_online'] = isOnline;
        newState[i] = updatedUser;
      }
    }
    state = newState;
  }
}
final contactsProvider = NotifierProvider<ContactsNotifier, List<Map<String, dynamic>>>(ContactsNotifier.new);

class MitMWarningsNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => {};
  
  void setWarning(String username, bool hasWarning) {
    state = {...state, username: hasWarning};
  }
  
  bool hasWarning(String username) => state[username] ?? false;
}
final mitmWarningsProvider = NotifierProvider<MitMWarningsNotifier, Map<String, bool>>(MitMWarningsNotifier.new);

class OnlineStatusNotifier extends Notifier<Map<String, bool>> {
  @override
  Map<String, bool> build() => {};
  
  void setStatus(String username, bool isOnline) {
    if (state[username] != isOnline) {
      state = {...state, username: isOnline};
    }
  }
  
  void setStatuses(Map<String, bool> newStatuses) {
    state = {...state, ...newStatuses};
  }
}
final onlineStatusProvider = NotifierProvider<OnlineStatusNotifier, Map<String, bool>>(OnlineStatusNotifier.new);

enum ConnectionStatus {
  connecting,
  connected,
  disconnected,
}

class ConnectionStatusNotifier extends Notifier<ConnectionStatus> {
  @override
  ConnectionStatus build() => ConnectionStatus.disconnected;
  void set(ConnectionStatus val) => state = val;
}
final connectionStatusProvider = NotifierProvider<ConnectionStatusNotifier, ConnectionStatus>(ConnectionStatusNotifier.new);
