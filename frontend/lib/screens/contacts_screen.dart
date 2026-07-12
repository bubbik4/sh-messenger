import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../providers.dart';
import '../services/ws_service.dart';
import 'chat_screen.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  @override
  void initState() {
    super.initState();
    // Inicjujemy połączenie WS po zalogowaniu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final wsService = ref.read(wsServiceProvider);
      wsService.onUsersUpdated = (users) {
        if (mounted) {
          ref.read(contactsProvider.notifier).set(users);
        }
      };
      // Gdyby przyszła jakaś wiadomość w tle (odśwież listę, notyfikację itp.)
      wsService.onNewMessage = () {
        // TODO: Update unread counters or re-sort contacts
      };
      
      wsService.connect();
    });
  }

  @override
  void dispose() {
    // wsService.disconnect() wywołamy przy wylogowaniu
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider);
    final myUsername = ref.watch(currentUsernameProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kontakty'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.read(wsServiceProvider).getUsers();
            },
          ),
        ],
      ),
      body: contacts.isEmpty
          ? const Center(child: Text('Brak dostępnych kontaktów', style: TextStyle(color: Colors.white54)))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: contacts.length,
              itemBuilder: (context, index) {
                final user = contacts[index];
                final username = user['username'] as String;
                final publicKey = user['public_key'] as String?;
                
                // Nie pokazuj nas samych na liście kontaktów do czatu
                if (username == myUsername) return const SizedBox.shrink();

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryBlue.withOpacity(0.2),
                    child: Text(
                      username.substring(0, 1).toUpperCase(),
                      style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Dotknij, aby rozpocząć szyfrowany czat', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  onTap: () {
                    if (publicKey == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ten użytkownik nie posiada wygenerowanego klucza E2E')),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          receiverUsername: username,
                          receiverPublicKey: publicKey,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
