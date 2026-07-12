import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme.dart';
import 'screens/login_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/admin_login_screen.dart';
import 'screens/admin_dashboard.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Inicjalizacja zaszyfrowanej bazy lokalnej (Hive)
  final storageService = StorageService();
  await storageService.init();

  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'sh-messenger',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginScreen(),
        '/login': (context) => const LoginScreen(),
        '/contacts': (context) => const ContactsScreen(),
        '/admin/login': (context) => const AdminLoginScreen(),
        '/admin/dashboard': (context) => const AdminDashboardScreen(),
      },
    );
  }
}
