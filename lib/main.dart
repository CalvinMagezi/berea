import 'package:flutter/material.dart';

import 'app_state.dart';
import 'attributions_screen.dart';
import 'home_shell.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledLicences();
  runApp(const BereaApp());
}

class BereaApp extends StatelessWidget {
  const BereaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Berea',
      debugShowCheckedModeBanner: false,
      theme: bereaTheme(Brightness.light),
      darkTheme: bereaTheme(Brightness.dark),
      home: FutureBuilder<AppState>(
        future: AppState.bootstrap(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Scaffold(body: Center(child: Text('Failed to start: ${snap.error}')));
          }
          if (!snap.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return HomeShell(state: snap.data!);
        },
      ),
    );
  }
}
