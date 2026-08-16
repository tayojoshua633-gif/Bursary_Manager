// test_server_ui.dart
// Simple Flutter app to test ServerConfigScreen directly

import 'package:flutter/material.dart';
import 'lib/screens/server/server_config_screen.dart';

void main() {
  runApp(const TestServerApp());
}

class TestServerApp extends StatelessWidget {
  const TestServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Server Test',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
      ),
      home: const ServerConfigScreen(),
    );
  }
}
