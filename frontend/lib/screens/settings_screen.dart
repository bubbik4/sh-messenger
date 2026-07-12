import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';
import '../theme.dart';
import '../constants.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isLoading = false;
  bool _isChangingPassword = false;
  final TextEditingController _oldPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();

  Future<void> _changePassword() async {
    final oldPass = _oldPasswordController.text;
    final newPass = _newPasswordController.text;

    if (oldPass.isEmpty || newPass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wypełnij oba pola')));
      return;
    }

    setState(() {
      _isChangingPassword = true;
    });

    try {
      await ref.read(apiServiceProvider).changeOwnPassword(oldPass, newPass);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hasło zostało zmienione')));
        _oldPasswordController.clear();
        _newPasswordController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isChangingPassword = false;
        });
      }
    }
  }

  Future<void> _toggleVisibility(bool val) async {
    setState(() {
      _isLoading = true;
    });

    final apiService = ref.read(apiServiceProvider);
    final success = await apiService.updateVisibility(val);

    if (success) {
      ref.read(visibilityProvider.notifier).set(val);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ustawienia zapisane poprawnie')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Błąd podczas zapisywania ustawień')),
        );
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVisible = ref.watch(visibilityProvider);
    final myUsername = ref.watch(currentUsernameProvider) ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ustawienia'),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(24.0),
            children: [
              const Text(
                'Twój Profil',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.2),
                  child: Text(
                    myUsername.isNotEmpty ? myUsername.substring(0, 1).toUpperCase() : '?',
                    style: const TextStyle(color: AppTheme.primaryBlue, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(myUsername, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('Zalogowano', style: TextStyle(color: Colors.white54)),
              ),
              const Divider(color: Colors.white24, height: 48),
              const Text(
                'Prywatność i Bezpieczeństwo',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.visibility_outlined, color: Colors.grey),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Widoczność konta', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('Konto widoczne w globalnej liście kontaktów', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
                    _isLoading
                        ? const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : Switch(
                            value: isVisible,
                            onChanged: _toggleVisibility,
                          ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Zmiana hasła',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _oldPasswordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Stare hasło',
                        prefixIcon: Icon(Icons.lock_outline, color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _newPasswordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Nowe hasło',
                        prefixIcon: Icon(Icons.lock, color: Colors.grey),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isChangingPassword ? null : _changePassword,
                      child: _isChangingPassword
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Zmień hasło'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withValues(alpha: 0.8),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.logout),
                label: const Text('Wyloguj się'),
                onPressed: () async {
                  await ref.read(apiServiceProvider).logout();
                  ref.read(authStateProvider.notifier).set(false);
                  if (context.mounted) {
                    Navigator.pushReplacementNamed(context, '/');
                  }
                },
              )
            ],
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: Text(
              'v$appVersion',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
