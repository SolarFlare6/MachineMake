import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/device_manager.dart';
import '../services/event_manager.dart';
import '../services/snapshot_saver_service.dart';
import '../theme/app_theme.dart';

class CameraFeedScreen extends StatefulWidget {
  final String deviceName;
  final String? deviceId;

  const CameraFeedScreen({
    super.key,
    required this.deviceName,
    this.deviceId,
  });

  @override
  State<CameraFeedScreen> createState() => _CameraFeedScreenState();
}

class _CameraFeedScreenState extends State<CameraFeedScreen> {
  bool _isStreaming = true;

  String get _targetId => widget.deviceId ?? DeviceManager().selectedDeviceId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      EventManager().setCameraStreaming(_targetId, true);
      DeviceManager().executeTool(_targetId, 'start_camera', {});
    });
  }

  void _toggleStream() {
    setState(() => _isStreaming = !_isStreaming);
    EventManager().setCameraStreaming(_targetId, _isStreaming);
    if (_isStreaming) {
      DeviceManager().executeTool(_targetId, 'start_camera', {});
    } else {
      DeviceManager().executeTool(_targetId, 'stop_camera', {});
    }
  }

  Future<void> _captureSnapshot() async {
    await SnapshotSaverService.saveCurrentFrame(
      context,
      deviceId: _targetId,
      deviceName: widget.deviceName,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: Text(
          '${widget.deviceName} Camera',
          style: GoogleFonts.exo2(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.primaryOrange),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: EventManager(),
          builder: (context, _) {
            final frameBytes = EventManager().latestCameraFrame(_targetId);
            return Column(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.primaryOrange, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_isStreaming && frameBytes != null)
                            Image.memory(
                              frameBytes,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            )
                          else if (frameBytes != null)
                            Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(
                                  frameBytes,
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                ),
                                Container(
                                  color: Colors.black.withAlpha(120),
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Stream Paused',
                                    style: GoogleFonts.exo2(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          else
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _isStreaming ? Icons.videocam : Icons.videocam_off,
                                    size: 64,
                                    color: AppTheme.primaryOrange.withAlpha(200),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _isStreaming
                                        ? 'CONNECTING TO LIVE DCP STREAM...'
                                        : 'CAMERA STREAM PAUSED',
                                    style: GoogleFonts.exo2(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '640x480 • MJPEG over DCP WebSocket',
                                    style: GoogleFonts.exo2(
                                      color: AppTheme.textMuted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // HUD Overlay
                          Positioned(
                            top: 16,
                            left: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _isStreaming ? Colors.red : Colors.grey[800],
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircleAvatar(
                                      radius: 4, backgroundColor: Colors.white),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isStreaming ? 'LIVE' : 'PAUSED',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(
                          _isStreaming
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          color: _isStreaming
                              ? Colors.redAccent
                              : AppTheme.primaryOrange,
                          size: 38,
                        ),
                        tooltip: _isStreaming ? 'Pause Stream' : 'Start Stream',
                        onPressed: _toggleStream,
                      ),
                      IconButton(
                        icon: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 32),
                        tooltip: 'Capture Snapshot',
                        onPressed: _captureSnapshot,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
