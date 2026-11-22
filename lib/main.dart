import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/location_service.dart';
import 'services/mode_service.dart';
import 'services/session.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => Session()),
      ChangeNotifierProvider(create: (_) => LocationService()),
      ChangeNotifierProvider(create: (_) => ModeService()),
    ],
    child: const CompanionApp(),
  ));
}

class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Companion',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Consumer<Session>(
        builder: (_, s, __) => s.isLoggedIn ? const HomeScreen() : const LoginScreen(),
      ),
    );
  }
}
