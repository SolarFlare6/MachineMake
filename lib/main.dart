import 'package:flutter/material.dart';
import 'screens/welcome_screen.dart';
import 'services/app_startup_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStartupService.run();
  runApp(const MachineMakeApp());
}

class MachineMakeApp extends StatelessWidget {
  const MachineMakeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MachineMake',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const WelcomeScreen(),
    );
  }
}
