import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import 'chat_screen.dart';

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Przykładowe dane
    final contacts = [
      {'name': 'Alex R.', 'status': 'Online'},
      {'name': 'Sarah Chen', 'status': 'Zabezpieczone'},
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Czaty'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              // TODO: Dodaj nowy kontakt po kluczu publicznym
            },
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: contacts.length,
        itemBuilder: (context, index) {
          final contact = contacts[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppTheme.cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppTheme.elevatedShadow,
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: AppTheme.primaryBlue,
                child: Text(contact['name']![0]),
              ),
              title: Text(
                contact['name']!,
                style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
              ),
              subtitle: Row(
                children: [
                  const Icon(Icons.lock, size: 14, color: Colors.greenAccent),
                  const SizedBox(width: 4),
                  Text(contact['status']!),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatScreen(contactName: contact['name']!),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
