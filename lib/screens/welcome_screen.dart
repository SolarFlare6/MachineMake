import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/machine_make_logo.dart';
import 'discovery_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: Stack(
        children: [
          // Background grid pattern
          Positioned.fill(
            child: CustomPaint(
              painter: GridBackgroundPainter(),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  // Big Center Logo
                  const MachineMakeLogo(
                    logoHeight: 80,
                    fontSize: 32,
                    isHorizontal: false,
                  ),

                  const Spacer(flex: 3),

                  // Welcome Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppTheme.modalBackground,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppTheme.darkBorder,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: GoogleFonts.exo2(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              height: 1.2,
                            ),
                            children: const [
                              TextSpan(
                                text: 'Welcome to the\n',
                                style: TextStyle(color: Colors.white),
                              ),
                              TextSpan(
                                text: 'machinery',
                                style: TextStyle(color: AppTheme.primaryOrange),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'connect, control & create through\none app',
                          style: GoogleFonts.exo2(
                            fontSize: 16,
                            color: AppTheme.textMuted,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const DiscoveryScreen(),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryOrange,
                            foregroundColor: AppTheme.textDarkButton,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Scan for devices',
                            style: GoogleFonts.exo2(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textDarkButton,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 1),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
