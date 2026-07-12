import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/html.dart';

WebSocketChannel connectWs(Uri uri) {
  return HtmlWebSocketChannel.connect(uri);
}
