import 'package:flutter/material.dart';
import 'screens/main_layout.dart';
import 'screens/welcome_screen.dart';
import 'services/app_startup_service.dart';
import 'theme/app_theme.dart';

// TODO : add to the app so when in operations and the user presses on ssh session the app opens that devices ssh session using the stored credentials (also have an option to save ssh cretentials for a given device)
// TODO : fix the device screen so its uneque to the robot and generic for the rest of the devices
// TODO : check needle ai implementation (the idea was that the hardware is checked and if it is capable it needle ai runs on the device and if not it runs in the app it just revices the devices hardware)
// TODO : in what format do the overview stats on the overview screen expect from the server so that it updates propperly

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
    return MaterialApp(
      title: 'MachineMake',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: home ??
          (AppStartupService.isFirstSetupDone
              ? const MainLayout()
              : const WelcomeScreen()),
    );
  }
}
