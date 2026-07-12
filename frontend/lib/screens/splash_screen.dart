import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../providers.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final apiService = ref.read(apiServiceProvider);
    final token = await apiService.getToken();
    final username = await apiService.getUsername();

    if (token != null && username != null && username.isNotEmpty) {
      ref.read(authStateProvider.notifier).set(true);
      ref.read(currentUsernameProvider.notifier).set(username);
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/contacts');
      }
    } else {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
