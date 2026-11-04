import 'package:flutter/material.dart';

import 'screens/home.dart';
import 'screens/login.dart';
import 'screens/web_shell.dart';
import 'session.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(OftobApp(session: Session()..restore()));
}

class OftobApp extends StatelessWidget {
  const OftobApp({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Oftob CRM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1E6FD9), useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: const Color(0xFF1E6FD9), brightness: Brightness.dark, useMaterial3: true),
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          if (session.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          if (session.webActive) return WebShell(session: session);
          return session.signedIn ? HomeScreen(session: session) : LoginScreen(session: session);
        },
      ),
    );
  }
}
