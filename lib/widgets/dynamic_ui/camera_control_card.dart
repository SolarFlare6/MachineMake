import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../core/models/device_capability.dart';
import '../../services/event_manager.dart';
import '../../services/snapshot_saver_service.dart';
import '../../theme/app_theme.dart';

/// Camera control card for a generic device with camera capability.
/// Provides start/stop stream and snapshot buttons.
class CameraControlCard extends StatefulWidget {
  final DeviceCapability capability;
  final DeviceConnection? conn;

  const CameraControlCard({super.key, required this.capability, this.conn});

  @override
  State<CameraControlCard> createState() => _CameraControlCardState();
}

class _CameraControlCardState extends State<CameraControlCard> {
  bool _isStreaming = false;

  void _toggleStream() {
    final next = !_isStreaming;
    setState(() => _isStreaming = next);
    if (next) {
      widget.conn?.session?.executeTool('start_camera', {});
    } else {
      widget.conn?.session?.executeTool('stop_camera', {});
    }
  }

  Future<void> _takeSnapshot() async {
    await SnapshotSaverService.saveCurrentFrame(
      context,
      deviceId: widget.conn?.deviceId,
      deviceName: widget.capability.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.gpuCyan.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.videocam, color: AppTheme.gpuCyan, size: 20),
              const SizedBox(width: 8),
              Text(
                widget.capability.name,
                style: GoogleFonts.exo2(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              _StatusDot(isActive: _isStreaming),
              const SizedBox(width: 6),
              Text(
                _isStreaming ? 'Streaming' : 'Idle',
                style: GoogleFonts.exo2(
                  color: _isStreaming ? AppTheme.gpuCyan : AppTheme.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Preview placeholder / live frame
          ListenableBuilder(
            listenable: EventManager(),
            builder: (context, _) {
              final frameBytes = EventManager().latestCameraFrame(widget.conn?.deviceId);
              return Container(
                height: 140,
                decoration: BoxDecoration(
                  color: AppTheme.darkBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.darkBorder),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: (_isStreaming && frameBytes != null)
                      ? Image.memory(
                          frameBytes,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                        )
                      : Center(
                          child: _isStreaming
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.play_circle_outline, color: AppTheme.gpuCyan, size: 40),
                                    const SizedBox(height: 6),
                                    Text('Connecting to live stream...', style: GoogleFonts.exo2(color: AppTheme.gpuCyan, fontSize: 12)),
                                  ],
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.videocam_off, color: AppTheme.textMuted.withAlpha(100), size: 40),
                                    const SizedBox(height: 6),
                                    Text('Camera inactive', style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12)),
                                  ],
                                ),
                        ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isStreaming ? Colors.redAccent : AppTheme.gpuCyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: Icon(_isStreaming ? Icons.stop : Icons.play_arrow, size: 18),
                  label: Text(
                    _isStreaming ? 'Stop Stream' : 'Start Stream',
                    style: GoogleFonts.exo2(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: _toggleStream,
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppTheme.darkBorder),
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.photo_camera, size: 18),
                label: Text('Snapshot', style: GoogleFonts.exo2(fontSize: 13)),
                onPressed: _takeSnapshot,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final bool isActive;
  const _StatusDot({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? AppTheme.gpuCyan : AppTheme.textMuted,
      ),
    );
  }
}
