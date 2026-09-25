import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/pairing_manager.dart';
import '../services/permission_service.dart';
import '../theme/app_theme.dart';

/// QR scanner screen for out-of-band device pairing (Phase 3).
///
/// The device displays a QR code on its terminal/display.
/// The user taps "Scan QR" in the DiscoveryScreen, which pushes this route.
/// On a successful scan the payload is handed to [PairingManager.parseQrPayload],
/// and if valid, [PairingManager.initiatePairing] is called before popping.
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _permissionGranted = false;
  bool _scanned = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final granted = await PermissionService.instance.requestCameraPermission();
    if (mounted) setState(() => _permissionGranted = granted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkSurface,
        title: Text(
          'Scan Device QR',
          style: GoogleFonts.exo2(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.white),
            tooltip: 'Toggle torch',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _permissionGranted
                ? _buildScanner()
                : _buildPermissionDenied(),
          ),
          _buildInstructions(),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
        ),
        // Scan frame overlay
        Center(
          child: Container(
            width: 240,
            height: 240,
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.primaryOrange, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        // Corner decorations
        _buildCornerDecor(),

        // Success overlay
        if (_scanned)
          Container(
            color: Colors.black.withAlpha(160),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF00E676), size: 72),
                  const SizedBox(height: 16),
                  Text(
                    'QR Scanned!',
                    style: GoogleFonts.exo2(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Error banner
        if (_error != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.red.withAlpha(220),
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: GoogleFonts.exo2(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPermissionDenied() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt, color: Colors.white38, size: 64),
            const SizedBox(height: 16),
            Text(
              'Camera permission required',
              style: GoogleFonts.exo2(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Grant camera permission in Settings to scan the device QR code.',
              style: GoogleFonts.exo2(color: AppTheme.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: AppTheme.textDarkButton,
              ),
              onPressed: _checkPermission,
              child: Text('Grant Permission', style: GoogleFonts.exo2()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    return Container(
      color: AppTheme.darkSurface,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline, color: AppTheme.primaryOrange, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Point the camera at the QR code displayed on your device terminal or screen.',
                  style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFD4CBE5)),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancel', style: GoogleFonts.exo2()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCornerDecor() {
    const color = AppTheme.primaryOrange;
    const size = 24.0;
    const thickness = 3.0;
    return Center(
      child: SizedBox(
        width: 240,
        height: 240,
        child: Stack(
          children: [
            // Top-left
            Positioned(top: 0, left: 0,
              child: _corner(color, size, thickness, top: true, left: true)),
            // Top-right
            Positioned(top: 0, right: 0,
              child: _corner(color, size, thickness, top: true, left: false)),
            // Bottom-left
            Positioned(bottom: 0, left: 0,
              child: _corner(color, size, thickness, top: false, left: true)),
            // Bottom-right
            Positioned(bottom: 0, right: 0,
              child: _corner(color, size, thickness, top: false, left: false)),
          ],
        ),
      ),
    );
  }

  Widget _corner(Color c, double s, double t,
      {required bool top, required bool left}) {
    return SizedBox(
      width: s,
      height: s,
      child: CustomPaint(
        painter: _CornerPainter(c, t, top: top, left: left),
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      final payload = PairingManager().parseQrPayload(raw);
      if (payload == null) {
        setState(() => _error = 'Not a valid MachineMake QR code. Try again.');
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _error = null);
        });
        return;
      }

      setState(() => _scanned = true);
      _controller.stop();

      // Initiate pairing then return result to caller
      final deviceId   = payload['device_id'] as String? ?? '';
      final deviceName = (payload['name'] as String?) ?? 'Unknown Device';
      final transport  = (payload['transport'] as String?) ?? 'wifi';
      final address    = payload['address'] as String?;

      PairingManager()
          .initiatePairing(
            deviceId: deviceId,
            deviceName: deviceName,
            transport: transport,
            address: address,
          )
          .then((req) {
        if (mounted) {
          Navigator.of(context).pop(req); // Pop with PairingRequest result
        }
      });
      break;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool top;
  final bool left;

  _CornerPainter(this.color, this.thickness,
      {required this.top, required this.left});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final x = left ? 0.0 : size.width;
    final y = top ? 0.0 : size.height;
    final dx = left ? size.width : -size.width;
    final dy = top ? size.height : -size.height;

    canvas.drawLine(Offset(x, y), Offset(x + dx, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, y + dy), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
