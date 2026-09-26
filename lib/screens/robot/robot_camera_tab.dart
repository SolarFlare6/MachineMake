import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

/// Live camera feed tab for robot navigation with HUD telemetry overlay.
class RobotCameraTab extends StatefulWidget {
  final bool isStreaming;
  final VoidCallback onToggleStream;
  final VoidCallback onSnapshot;

  const RobotCameraTab({
    super.key,
    required this.isStreaming,
    required this.onToggleStream,
    required this.onSnapshot,
  });

  @override
  State<RobotCameraTab> createState() => _RobotCameraTabState();
}

class _RobotCameraTabState extends State<RobotCameraTab> {
  bool _hudEnabled = true;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Viewport area
          Container(
            height: 260,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: widget.isStreaming
                    ? AppTheme.primaryOrange
                    : AppTheme.darkBorder,
                width: 1.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (widget.isStreaming)
                    Container(
                      color: const Color(0xFF14171E),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.videocam,
                              color: AppTheme.primaryOrange,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Live WebRTC Feed Active',
                              style: GoogleFonts.exo2(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '60 FPS · 1080p · 24ms latency',
                              style: GoogleFonts.exo2(
                                color: AppTheme.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Container(
                      color: AppTheme.darkSurface,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.videocam_off,
                              color: AppTheme.textMuted,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Camera Feed Inactive',
                              style: GoogleFonts.exo2(
                                color: AppTheme.textMuted,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // HUD Overlay
                  if (widget.isStreaming && _hudEnabled)
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _hudBadge('REC · DCP', const Color(0xFF00E676)),
                                _hudBadge('HD 1080p', Colors.white70),
                              ],
                            ),
                            // Crosshair
                            Center(
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppTheme.primaryOrange.withAlpha(160),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.add,
                                    color: AppTheme.primaryOrange,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _hudBadge('DIST: 1.4 m', Colors.white),
                                _hudBadge('HEAD: 042°', AppTheme.primaryOrange),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Controls Row
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: widget.onToggleStream,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.isStreaming
                        ? Colors.redAccent
                        : AppTheme.primaryOrange,
                    foregroundColor: widget.isStreaming
                        ? Colors.white
                        : AppTheme.textDarkButton,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: Icon(
                    widget.isStreaming ? Icons.stop : Icons.play_arrow,
                  ),
                  label: Text(
                    widget.isStreaming ? 'Stop Stream' : 'Start Camera',
                    style: GoogleFonts.exo2(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                onPressed: widget.isStreaming ? widget.onSnapshot : null,
                icon: const Icon(Icons.camera_alt),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.darkCard,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: AppTheme.darkBorder),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () => setState(() => _hudEnabled = !_hudEnabled),
                icon: Icon(
                  _hudEnabled ? Icons.visibility : Icons.visibility_off,
                  color: _hudEnabled ? AppTheme.primaryOrange : AppTheme.textMuted,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.darkCard,
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: AppTheme.darkBorder),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hudBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(160),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        text,
        style: GoogleFonts.exo2(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
