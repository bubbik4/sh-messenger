import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';

final webSocketProvider = Provider<WebSocketService>((ref) {
  // Automatyczne dopasowanie URL do środowiska
  final wsUrl = kIsWeb 
      ? 'wss://chat.bubikit.pl/ws' 
      : 'ws://10.10.0.74:8089/ws';

  final channel = WebSocketChannel.connect(
    Uri.parse(wsUrl),
  );
  return WebSocketService(channel);
});

class WebSocketService {
  final WebSocketChannel _channel;

  WebSocketService(this._channel);

  Stream<dynamic> get messages => _channel.stream;

  void sendMessage(String message) {
    _channel.sink.add(message);
  }

  void close() {
    _channel.sink.close();
  }
}

// Provider trzymający listę wiadomości
final chatMessagesProvider = StateNotifierProvider<ChatMessagesNotifier, List<String>>((ref) {
  final wsService = ref.watch(webSocketProvider);
  final notifier = ChatMessagesNotifier();

  // Nasłuchiwanie na wiadomości z serwera
  wsService.messages.listen((message) {
    notifier.addMessage(message.toString(), isMe: false);
  });

  return notifier;
});

class ChatMessagesNotifier extends StateNotifier<List<String>> {
  ChatMessagesNotifier() : super([]);

  void addMessage(String message, {required bool isMe}) {
    // Prosty prefiks dla demonstracji, w Fazie 3 to będzie zdeszyfrowany obiekt
    final prefix = isMe ? "ME: " : "OTHER: ";
    state = [...state, "$prefix$message"];
  }
}
