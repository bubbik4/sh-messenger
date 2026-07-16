import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../providers.dart';
import '../services/ws_service.dart';
import '../services/storage_service.dart';
import '../services/fcm_service.dart';
import 'chat_screen.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final StorageService _storageService = StorageService();
  final FCMService _fcmService = FCMService();
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _fcmService.initFCM();
    // Inicjujemy połączenie WS po zalogowaniu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final wsService = ref.read(wsServiceProvider);
      wsService.onUsersUpdated = (users) {
        if (mounted) {
          ref.read(contactsProvider.notifier).set(users);
        }
      };
      wsService.onUserStatusChanged = (username, isOnline) {
        if (mounted) {
          // Stan jest już w onlineStatusProvider, nie musimy tu ręcznie
          // aktualizować _searchResults, bo polegamy teraz na onlineStatusProvider w build()
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
    final onlineStatuses = ref.watch(onlineStatusProvider);

    // Budujemy wspólną listę: najpierw wyniki wyszukiwania, potem reszta bez duplikatów
    final Set<String> seenUsernames = {myUsername ?? ''};
    final List<Map<String, dynamic>> combinedContacts = [];

    void addUser(String username, String? pubKey) {
      if (username.isEmpty || seenUsernames.contains(username)) return;
      seenUsernames.add(username);
      
      final messages = _storageService.getMessagesForRoom(username);
      String lastMessageText = '';
      DateTime? lastMessageTime;
      
      if (messages.isNotEmpty) {
        final lastMsg = messages.last;
        final text = lastMsg['message'] as String;
        if (text.startsWith('[IMG_E2E]:')) {
          lastMessageText = '📷 Zdjęcie';
        } else {
          lastMessageText = text;
        }
        lastMessageTime = DateTime.parse(lastMsg['timestamp'] as String);
      }
      
      combinedContacts.add({
         'username': username,
         'public_key': pubKey,
         'is_online': onlineStatuses[username] == true,
         'last_message': lastMessageText,
         'last_message_time': lastMessageTime,
      });
    }

    // 1. Dodajemy z wyszukiwania
    for (var u in _searchResults) {
      addUser(u['username'], u['public_key']);
    }

    // 2. Dodajemy z historii lokalnej (dają najwięcej kontekstu bo mają wiadomości)
    final oldRoomIds = _storageService.getChattedRoomIds();
    for (var roomId in oldRoomIds) {
      final savedPubKey = _storageService.getPeerPublicKey(roomId);
      addUser(roomId, savedPubKey);
    }

    // 3. Dodajemy z kontaktów publicznych
    for (var u in publicContacts) {
      addUser(u['username'], u['public_key']);
    }
    
    // Sortowanie: ci z nowszymi wiadomościami na górę
    combinedContacts.sort((a, b) {
      final timeA = a['last_message_time'] as DateTime?;
      final timeB = b['last_message_time'] as DateTime?;
      if (timeA == null && timeB == null) return 0;
      if (timeA == null) return 1;
      if (timeB == null) return -1;
      return timeB.compareTo(timeA); // malejąco
    });

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
                final isOnline = user['is_online'] == true;
                final lastMessage = user['last_message'] as String;
                final lastMessageTime = user['last_message_time'] as DateTime?;
                
                String timeStr = '';
                if (lastMessageTime != null) {
                  final localTime = lastMessageTime.toLocal();
                  final now = DateTime.now();
                  if (now.difference(localTime).inDays == 0 && now.day == localTime.day) {
                    timeStr = '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
                  } else {
                    timeStr = '${localTime.day.toString().padLeft(2, '0')}.${localTime.month.toString().padLeft(2, '0')}';
                  }
                }
                
                // Nie pokazuj nas samych na liście kontaktów do czatu
                if (username == myUsername) return const SizedBox.shrink();

                return ListTile(
                  leading: Stack(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
                        child: Text(
                          username.substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (isOnline)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.greenAccent,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppTheme.backgroundDark, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      if (timeStr.isNotEmpty)
                        Text(timeStr, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                    ],
                  ),
                  subtitle: lastMessage.isNotEmpty 
                    ? Text(
                        lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      )
                    : Text(
                        isOnline ? 'Aktywny(a) teraz' : 'Offline', 
                        style: TextStyle(color: isOnline ? Colors.greenAccent.withValues(alpha: 0.8) : Colors.white54, fontSize: 13)
                      ),
                  onTap: () async {
                    if (publicKey == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ten użytkownik nie posiada wygenerowanego klucza E2E')),
                      );
                      return;
                    }
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          receiverUsername: username,
                          receiverPublicKey: publicKey,
                        ),
                      ),
                    );
                    // Odśwież listę po powrocie z czatu, żeby pokazać nową ostatnią wiadomość
                    if (mounted) setState(() {});
                  },
                );
              },
            ),
          ),
          Consumer(
            builder: (context, ref, child) {
              final status = ref.watch(connectionStatusProvider);
              String text;
              Color color;
              
              switch (status) {
                case ConnectionStatus.connecting:
                  text = 'Łączenie z serwerem...';
                  color = Colors.orange;
                  break;
                case ConnectionStatus.connected:
                  text = 'Połączono';
                  color = Colors.green;
                  break;
                case ConnectionStatus.disconnected:
                  text = 'Brak połączenia';
                  color = Colors.red;
                  break;
              }
              
              return Container(
                width: double.infinity,
                color: AppTheme.cardColor,
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                        ),
                        const SizedBox(width: 8),
                        Text(text, style: TextStyle(color: color, fontSize: 12)),
                      ],
                    ),
                    const Text('v1.3.0', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
