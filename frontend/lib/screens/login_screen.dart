import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../providers.dart';
import 'contacts_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isVisible = true;
  String? _errorMessage;

  Future<void> _submit(bool isRegister) async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    if (username.isEmpty || password.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      bool success;
      if (isRegister) {
        success = await apiService.register(username, password, _isVisible);
      } else {
        success = await apiService.login(username, password);
      }

      if (success) {
        ref.read(authStateProvider.notifier).set(true);
        ref.read(currentUsernameProvider.notifier).set(username);
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/contacts');
        }
      } else {
        setState(() {
          _errorMessage = isRegister ? 'Błąd rejestracji' : 'Błędny login lub hasło';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Błąd połączenia z serwerem: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: AppTheme.primaryBlue),
              const SizedBox(height: 24),
              Text(
                'sh-messenger',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Bezpieczna komunikacja E2E',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 48),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppTheme.elevatedShadow,
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Nazwa użytkownika',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Hasło',
                        prefixIcon: Icon(Icons.key),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.visibility_outlined, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Konto widoczne w globalnej liście',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Switch(
                          value: _isVisible,
                          onChanged: (val) {
                            setState(() {
                              _isVisible = val;
                            });
                          },
                        ),
                      ],
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                    ],
                    const SizedBox(height: 24),
                    if (_isLoading)
                      const CircularProgressIndicator()
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton(
                            onPressed: () => _submit(false),
                            child: const Text('Zaloguj'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: () => _submit(true),
                            child: const Text('Zarejestruj się'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
