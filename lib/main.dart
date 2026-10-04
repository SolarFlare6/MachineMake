import 'package:flutter/material.dart';
import 'screens/main_layout.dart';
import 'screens/welcome_screen.dart';
import 'services/app_startup_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStartupService.run();
  runApp(const MachineMakeApp());
}

class MachineMakeApp extends StatelessWidget {
  final Widget? home;
  const MachineMakeApp({super.key, this.home});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: AppTheme.accentColorNotifier,
      builder: (context, _, __) {
        return MaterialApp(
          title: 'MachineMake',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          home: home ??
              (AppStartupService.isFirstSetupDone
                  ? const MainLayout()
                  : const WelcomeScreen()),
        );
      },
    );
  }
}
