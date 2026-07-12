import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../providers.dart';
import '../services/storage_service.dart';
import '../services/ws_service.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String receiverUsername;
  final String receiverPublicKey;
  const ChatScreen({
    super.key,
    required this.receiverUsername,
    required this.receiverPublicKey,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final StorageService _storageService = StorageService();
  List<Map> _messages = [];
  String _myUsername = '';

  @override
  void initState() {
    super.initState();
    _myUsername = ref.read(currentUsernameProvider) ?? '';
    _loadMessages();

    // Rejestrujemy nasłuch na nowe wiadomości (żeby ekran się odświeżał na żywo)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final wsService = ref.read(wsServiceProvider);
      _oldCallback = wsService.onNewMessage;
      wsService.onNewMessage = () {
        if (mounted) _loadMessages();
        if (_oldCallback != null) _oldCallback!();
      };
    });
  }

  Function()? _oldCallback;

  @override
  void dispose() {
    ref.read(wsServiceProvider).onNewMessage = _oldCallback;
    super.dispose();
  }

  void _loadMessages() {
    setState(() {
      _messages = _storageService.getMessagesForRoom(widget.receiverUsername);
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    _messageController.clear();
    
    // WsService szyfruje wiadomość (wewnątrz używa algorytmu AES-256 z kluczem ECDH) 
    // i wysyła na WebSocket. Zapisuje też do lokalnego Hive.
    await ref.read(wsServiceProvider).sendMessage(
      widget.receiverUsername,
      text,
      widget.receiverPublicKey,
    );
    
    _loadMessages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primaryBlue,
              child: Text(widget.receiverUsername[0].toUpperCase(), style: const TextStyle(fontSize: 14)),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.receiverUsername, style: const TextStyle(fontSize: 16)),
                const Row(
                  children: [
                    Icon(Icons.lock, size: 12, color: Colors.greenAccent),
                    SizedBox(width: 4),
                    Text('E2E Encrypted', style: TextStyle(fontSize: 12, color: Colors.greenAccent)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (widget.receiverPublicKey.isEmpty)
            Container(
              width: double.infinity,
              color: Colors.redAccent.withOpacity(0.2),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: const Text(
                'Użytkownik został usunięty. Konwersacja w trybie tylko do odczytu.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
              ),
            ),
          Consumer(
            builder: (context, ref, child) {
              final hasWarning = ref.watch(mitmWarningsProvider)[widget.receiverUsername] ?? false;
              if (hasWarning) {
                return Container(
                  width: double.infinity,
                  color: Colors.orangeAccent.withValues(alpha: 0.2),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: const Text(
                    'Klucz tożsamości użytkownika uległ zmianie! Zweryfikuj odcisk palca (fingerprint) przed dalszym pisaniem.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msgData = _messages[index];
                final isMe = msgData['senderId'] == _myUsername;
                final text = msgData['message'] as String;
                return _buildMessageBubble(text, isMe: isMe);
              },
            ),
          ),
          Consumer(
            builder: (context, ref, child) {
               final hasWarning = ref.watch(mitmWarningsProvider)[widget.receiverUsername] ?? false;
               if (widget.receiverPublicKey.isNotEmpty && !hasWarning) {
                  return _buildMessageInput();
               }
               return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(String text, {required bool isMe}) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.primaryBlueDark : AppTheme.cardColor.withValues(alpha: 0.8),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 16),
          ),
          boxShadow: AppTheme.elevatedShadow,
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16).copyWith(bottom: 32),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: InputDecoration(
                hintText: 'Napisz bezpieczną wiadomość...',
                prefixIcon: const Icon(Icons.lock_outline, size: 18),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                filled: true,
                fillColor: AppTheme.cardColor.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.primaryBlue,
              shape: BoxShape.circle,
              boxShadow: AppTheme.elevatedShadow,
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
