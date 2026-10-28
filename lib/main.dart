import 'package:flutter/material.dart';

import 'app_state.dart';
import 'home_shell.dart';
import 'licences.dart';
import 'setup_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledLicences();
  runApp(const BereaApp());
}

const startFailure =
    'Berea could not open the Bible. Close the app and open it again. If this keeps happening, '
    'restart the device and try once more.';

class BereaApp extends StatefulWidget {
  const BereaApp({super.key});

  @override
  State<BereaApp> createState() => _BereaAppState();
}

class _BereaAppState extends State<BereaApp> {
  final _launch = Stopwatch()..start();
  var _settingUp = false;
  late final Future<AppState> _state = AppState.bootstrap(
    onFirstSetup: () => setState(() => _settingUp = true),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Berea',
      debugShowCheckedModeBanner: false,
      theme: bereaTheme(Brightness.light),
      darkTheme: bereaTheme(Brightness.dark),
      home: FutureBuilder<AppState>(
        future: _state,
        builder: (context, snap) {
          if (snap.hasError) {
            debugPrint('Berea did not start: ${snap.error}\n${snap.stackTrace}');
            final error = snap.error;
            return SetupScreen(failure: error is StartupFailure ? error.message : startFailure);
          }
          if (!snap.hasData) return SetupScreen(settingUp: _settingUp);
          if (_launch.isRunning) {
            _launch.stop();
            debugPrint('Bible ready in ${_launch.elapsedMilliseconds} ms');
          }
          return HomeShell(state: snap.data!);
        },
      ),
    );
  }
}
