import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_startup_service.dart';
import '../services/discovery_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/machine_make_logo.dart';
import 'discovery_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final DiscoveryManager _discovery = DiscoveryManager();
  Timer? _autoNavTimer;
  bool _autoNavigated = false;

  @override
  void initState() {
    super.initState();
    // Start scanning immediately
    _discovery.startScan();
    _discovery.addListener(_onDiscoveryChange);
    // Auto-navigate after 3s even without finding a device
    _autoNavTimer = Timer(const Duration(seconds: 3), _navigateIfReady);
  }

  @override
  void dispose() {
    _discovery.removeListener(_onDiscoveryChange);
    _autoNavTimer?.cancel();
    super.dispose();
  }

  void _onDiscoveryChange() {
    if (_discovery.discovered.isNotEmpty && !_autoNavigated) {
      _navigateIfReady();
    }
  }

  void _navigateIfReady() {
    if (_autoNavigated || !mounted) return;
    _autoNavigated = true;
    AppStartupService.setFirstSetupDone(true);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
    );
  }

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
                            children: [
                              const TextSpan(
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
                        const SizedBox(height: 20),
                        // Scanning indicator
                        ListenableBuilder(
                          listenable: _discovery,
                          builder: (context, _) {
                            final count = _discovery.discovered.length;
                            return Row(
                              children: [
                                if (_discovery.isScanning)
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.primaryOrange,
                                    ),
                                  ),
                                const SizedBox(width: 10),
                                Text(
                                  _discovery.isScanning
                                      ? (count > 0
                                          ? 'Found $count device${count > 1 ? 's' : ''}…'
                                          : 'Scanning for devices…')
                                      : (count > 0
                                          ? 'Found $count device${count > 1 ? 's' : ''}'
                                          : 'No devices found nearby'),
                                  style: GoogleFonts.exo2(
                                    fontSize: 13,
                                    color: count > 0
                                        ? Colors.greenAccent
                                        : AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _navigateIfReady,
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
