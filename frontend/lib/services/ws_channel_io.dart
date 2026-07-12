import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

WebSocketChannel connectWs(Uri uri) {
  return IOWebSocketChannel.connect(
    uri,
    headers: {'Origin': 'https://chat.bubikit.pl'},
  );
}
