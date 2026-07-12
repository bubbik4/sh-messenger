import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../providers.dart';
import '../services/ws_service.dart';
import '../services/storage_service.dart';
import 'chat_screen.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final StorageService _storageService = StorageService();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

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
      wsService.onSearchResults = (users) {
        if (mounted) {
          setState(() {
            _searchResults = users;
            _isSearching = false;
          });
        }
      };
      wsService.onNewMessage = () {
        if (mounted) {
           setState(() {}); // Odświeża listę, jeśli dostaliśmy wiadomość od nowej ukrytej osoby
        }
      };
      
      wsService.connect().then((_) {
         // Po zalogowaniu pobieramy najświeższe klucze do ukrytych kontaktów z historii
         final oldRoomIds = _storageService.getChattedRoomIds();
         if (oldRoomIds.isNotEmpty) {
           wsService.getSpecificUsers(oldRoomIds);
         }
      });
    });
  }

  @override
  void dispose() {
    // wsService.disconnect() wywołamy przy wylogowaniu
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final publicContacts = ref.watch(contactsProvider);
    final myUsername = ref.watch(currentUsernameProvider);

    // Budujemy wspólną listę: najpierw wyniki wyszukiwania, potem reszta bez duplikatów
    final Set<String> seenUsernames = {myUsername ?? ''};
    final List<Map<String, dynamic>> combinedContacts = [];

    // 1. Dodajemy wyniki wyszukiwania
    for (var u in _searchResults) {
      if (!seenUsernames.contains(u['username'])) {
        seenUsernames.add(u['username']);
        combinedContacts.add(u);
      }
    }

    // 2. Dodajemy publiczne kontakty + te ukryte, do których już mamy historię (przyszły z getSpecificUsers i są w _publicKeys)
    // Jednak w naszym przypadku wszystkie powiadomienia (w tym specific_users_list) wpadają do _publicKeys, ale onUsersUpdated tylko dla publicznych.
    // Dlatego możemy na razie użyć po prostu publicContacts, oraz dodać tych z lokalnej bazy (jeśli mamy ich klucze publiczne).
    for (var u in publicContacts) {
      if (!seenUsernames.contains(u['username'])) {
        seenUsernames.add(u['username']);
        combinedContacts.add(u);
      }
    }
    
    // 3. Dodajemy z historii lokalnej
    final oldRoomIds = _storageService.getChattedRoomIds();
    for (var roomId in oldRoomIds) {
      if (!seenUsernames.contains(roomId)) {
        final savedPubKey = _storageService.getPeerPublicKey(roomId);
        if (savedPubKey != null) {
          seenUsernames.add(roomId);
          combinedContacts.add({
             'username': roomId,
             'public_key': savedPubKey,
          });
        }
      }
    }

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
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Wyszukaj dokładną nazwę konta...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    final q = _searchController.text.trim();
                    if (q.isNotEmpty) {
                      setState(() {
                        _isSearching = true;
                      });
                      ref.read(wsServiceProvider).searchUsers(q);
                    } else {
                      setState(() {
                         _searchResults.clear();
                      });
                    }
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: (q) {
                 if (q.trim().isNotEmpty) {
                    setState(() {
                      _isSearching = true;
                    });
                    ref.read(wsServiceProvider).searchUsers(q.trim());
                 }
              },
            ),
          ),
          if (_isSearching) const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()),
          Expanded(
            child: combinedContacts.isEmpty
                ? const Center(child: Text('Brak dostępnych kontaktów', style: TextStyle(color: Colors.white54)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: combinedContacts.length,
                    itemBuilder: (context, index) {
                      final user = combinedContacts[index];
                final username = user['username'] as String;
                final publicKey = user['public_key'] as String?;
                
                // Nie pokazuj nas samych na liście kontaktów do czatu
                if (username == myUsername) return const SizedBox.shrink();

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
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
          ),
        ],
      ),
    );
  }
}
