import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../services/event_manager.dart';
import '../../theme/app_theme.dart';

/// Live camera feed tab for robot navigation with HUD telemetry overlay
/// and interactive Tap-to-Track / Drag-to-Track object selection.
class RobotCameraTab extends StatefulWidget {
  final String? deviceId;
  final DeviceConnection? conn;
  final bool isStreaming;
  final VoidCallback onToggleStream;
  final VoidCallback onSnapshot;

  const RobotCameraTab({
    super.key,
    this.deviceId,
    this.conn,
    required this.isStreaming,
    required this.onToggleStream,
    required this.onSnapshot,
  });

  @override
  State<RobotCameraTab> createState() => _RobotCameraTabState();
}

class _RobotCameraTabState extends State<RobotCameraTab> {
  bool _hudEnabled = true;

  // Interactive tap / drag selection state
  Offset? _lastTapNormalized;
  Offset? _dragStart;
  Offset? _dragCurrent;

  String get _resolvedDeviceId =>
      widget.deviceId ?? widget.conn?.deviceId ?? '';

  Future<Map<String, dynamic>?> _invokeTool(
    String toolName,
    Map<String, dynamic> params,
  ) async {
    try {
      final session = widget.conn?.session;
      if (session != null) {
        final response = await session.executeTool(toolName, params);
        final res = response.result;
        if (res is Map) {
          return Map<String, dynamic>.from(res);
        }
      }
    } catch (e) {
      debugPrint('[RobotCameraTab] Tool "$toolName" error: $e');
    }
    return null;
  }

  void _showTrackingSnackBar(String message, {Color? backgroundColor}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.exo2()),
          backgroundColor: backgroundColor ?? const Color(0xFF00E5FF),
          duration: const Duration(milliseconds: 900),
        ),
      );
  }

  void _handleTapTrack(TapUpDetails details, Size viewSize) {
    if (viewSize.width <= 0 || viewSize.height <= 0) return;
    final u = (details.localPosition.dx / viewSize.width).clamp(0.0, 1.0);
    final v = (details.localPosition.dy / viewSize.height).clamp(0.0, 1.0);

    setState(() {
      _lastTapNormalized = Offset(u, v);
      _dragStart = null;
      _dragCurrent = null;
    });

    EventManager().setTrackingState(
      _resolvedDeviceId,
      active: true,
      label: 'tap (${(u * 640).round()}, ${(v * 480).round()})',
    );

    _invokeTool('track_object', {
      'u': double.parse(u.toStringAsFixed(4)),
      'v': double.parse(v.toStringAsFixed(4)),
    });

    _showTrackingSnackBar(
      'Tracking target at (${(u * 100).round()}%, ${(v * 100).round()}%)',
    );
  }

  void _handlePanStart(DragStartDetails details) {
    setState(() {
      _dragStart = details.localPosition;
      _dragCurrent = details.localPosition;
    });
  }

  void _handlePanUpdate(DragUpdateDetails details, Size viewSize) {
    setState(() {
      _dragCurrent = Offset(
        details.localPosition.dx.clamp(0.0, viewSize.width),
        details.localPosition.dy.clamp(0.0, viewSize.height),
      );
    });
  }

  void _handlePanEnd(Size viewSize) {
    final start = _dragStart;
    final end = _dragCurrent;
    setState(() {
      _dragStart = null;
      _dragCurrent = null;
    });

    if (start == null || end == null || viewSize.width <= 0 || viewSize.height <= 0) {
      return;
    }

    final left = math.min(start.dx, end.dx).clamp(0.0, viewSize.width);
    final top = math.min(start.dy, end.dy).clamp(0.0, viewSize.height);
    final width = (start.dx - end.dx).abs();
    final height = (start.dy - end.dy).abs();

    // If the drag was very small (< 14 px), treat it as a tap at the center point
    if (width < 14 || height < 14) {
      final u = ((start.dx + end.dx) / 2.0 / viewSize.width).clamp(0.0, 1.0);
      final v = ((start.dy + end.dy) / 2.0 / viewSize.height).clamp(0.0, 1.0);
      setState(() => _lastTapNormalized = Offset(u, v));
      EventManager().setTrackingState(
        _resolvedDeviceId,
        active: true,
        label: 'tap_target',
      );
      _invokeTool('track_object', {
        'u': double.parse(u.toStringAsFixed(4)),
        'v': double.parse(v.toStringAsFixed(4)),
      });
      return;
    }

    // Scale selection rectangle to native 640x480 camera resolution
    final camX = ((left / viewSize.width) * 640.0).round().clamp(0, 639);
    final camY = ((top / viewSize.height) * 480.0).round().clamp(0, 479);
    final camW = ((width / viewSize.width) * 640.0).round().clamp(12, 640 - camX);
    final camH = ((height / viewSize.height) * 480.0).round().clamp(12, 480 - camY);

    setState(() {
      _lastTapNormalized = Offset(
        (left + width / 2.0) / viewSize.width,
        (top + height / 2.0) / viewSize.height,
      );
    });

    EventManager().setTrackingState(
      _resolvedDeviceId,
      active: true,
      label: 'box [${camW}x$camH]',
    );

    _invokeTool('track_object', {
      'x': camX,
      'y': camY,
      'w': camW,
      'h': camH,
    });

    _showTrackingSnackBar(
      'Tracking selected box [$camX, $camY, $camW, $camH]',
    );
  }

  Future<void> _trackByLabel(String label) async {
    setState(() => _lastTapNormalized = null);
    EventManager().setTrackingState(
      _resolvedDeviceId,
      active: true,
      label: label,
    );
    _showTrackingSnackBar(
      label == 'person'
          ? 'Tracking Person in camera view'
          : 'Tracking target in view: "$label"',
    );
    final result = await _invokeTool('track_object', {'label': label});
    if (result != null) {
      final status = (result['status'] ?? '').toString();
      if (status == 'not_in_view' || status == 'failed') {
        EventManager().setTrackingState(_resolvedDeviceId, active: false);
        _showTrackingSnackBar(
          result['message']?.toString() ??
              '"$label" is not in the camera\'s view.',
          backgroundColor: Colors.redAccent,
        );
      }
    }
  }

  void _stopTracking() {
    setState(() {
      _lastTapNormalized = null;
      _dragStart = null;
      _dragCurrent = null;
    });
    EventManager().setTrackingState(_resolvedDeviceId, active: false);
    _invokeTool('stop_tracking', {});
    _showTrackingSnackBar(
      'Stopped object tracking',
      backgroundColor: Colors.amber[800],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EventManager(),
      builder: (context, _) {
        final frameBytes = EventManager().latestCameraFrame(_resolvedDeviceId);
        final isTracking = EventManager().isTrackingActive(_resolvedDeviceId);
        final trackedLabel = EventManager().trackingTargetLabel(_resolvedDeviceId);

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Viewport area with interactive Tap-to-Track & Drag-to-Track
              Container(
                height: 260,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isTracking
                        ? const Color(0xFF00E5FF)
                        : (widget.isStreaming
                            ? AppTheme.primaryOrange
                            : AppTheme.darkBorder),
                    width: isTracking ? 2.0 : 1.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final viewSize = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) => _handleTapTrack(details, viewSize),
                        onPanStart: _handlePanStart,
                        onPanUpdate: (details) =>
                            _handlePanUpdate(details, viewSize),
                        onPanEnd: (_) => _handlePanEnd(viewSize),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (widget.isStreaming && frameBytes != null)
                              Image.memory(
                                frameBytes,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              )
                            else if (widget.isStreaming)
                              Container(
                                color: const Color(0xFF14171E),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.videocam,
                                        color: AppTheme.primaryOrange,
                                        size: 48,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Connecting to Robot Camera Stream...',
                                        style: GoogleFonts.exo2(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tap or drag on video to track an object',
                                        style: GoogleFonts.exo2(
                                          color: AppTheme.textMuted,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else if (frameBytes != null)
                              Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.memory(
                                    frameBytes,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                  ),
                                  Container(
                                    color: Colors.black.withAlpha(110),
                                    alignment: Alignment.center,
                                    child: Text(
                                      'Stream Paused (Tap or Drag to Track)',
                                      style: GoogleFonts.exo2(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
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

                            // Live drag selection rectangle (yellow, matching laptop dashboard)
                            if (_dragStart != null && _dragCurrent != null)
                              Positioned(
                                left: math.min(_dragStart!.dx, _dragCurrent!.dx),
                                top: math.min(_dragStart!.dy, _dragCurrent!.dy),
                                width: (_dragStart!.dx - _dragCurrent!.dx).abs(),
                                height: (_dragStart!.dy - _dragCurrent!.dy).abs(),
                                child: IgnorePointer(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.amberAccent,
                                        width: 2,
                                      ),
                                      color: Colors.amberAccent.withAlpha(35),
                                    ),
                                  ),
                                ),
                              ),

                            // Tap reticle indicator
                            if (_lastTapNormalized != null && isTracking)
                              Positioned(
                                left: (_lastTapNormalized!.dx * viewSize.width) - 18,
                                top: (_lastTapNormalized!.dy * viewSize.height) - 18,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFF00E5FF),
                                        width: 2,
                                      ),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        Icons.my_location,
                                        color: Color(0xFF00E5FF),
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                            // HUD Overlay
                            if (widget.isStreaming && _hudEnabled)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            _hudBadge(
                                              'LIVE · DCP',
                                              const Color(0xFF00E676),
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: _hudBadge(
                                                isTracking
                                                    ? 'LOCKED · ${(trackedLabel ?? "TARGET").toUpperCase()}'
                                                    : 'TAP / DRAG TO TRACK',
                                                isTracking
                                                    ? const Color(0xFF00E5FF)
                                                    : Colors.white70,
                                              ),
                                            ),
                                          ],
                                        ),
                                        // Center Crosshair
                                        Center(
                                          child: Container(
                                            width: 36,
                                            height: 36,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: AppTheme.primaryOrange
                                                    .withAlpha(160),
                                                width: 1.5,
                                              ),
                                            ),
                                            child: Center(
                                              child: Icon(
                                                Icons.add,
                                                color: AppTheme.primaryOrange,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            _hudBadge('USB CAM', Colors.white),
                                            _hudBadge(
                                              isTracking
                                                  ? 'TRACKING ACTIVE'
                                                  : 'STREAMING',
                                              isTracking
                                                  ? const Color(0xFF00E5FF)
                                                  : AppTheme.primaryOrange,
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // Controls Row (Start/Stop Stream, Stop Tracking, Snapshot, HUD toggle)
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 14,
                        ),
                        minimumSize: const Size(0, 48),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: Icon(
                        widget.isStreaming ? Icons.stop : Icons.play_arrow,
                        size: 18,
                      ),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          widget.isStreaming ? 'Stop Stream' : 'Start Camera',
                          maxLines: 1,
                          softWrap: false,
                          style: GoogleFonts.exo2(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _stopTracking,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isTracking
                            ? const Color(0xFF00E5FF)
                            : AppTheme.darkCard,
                        foregroundColor:
                            isTracking ? Colors.black : Colors.white70,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 14,
                        ),
                        minimumSize: const Size(0, 48),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: isTracking
                                ? const Color(0xFF00E5FF)
                                : AppTheme.darkBorder,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.gps_off, size: 17),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Stop Track',
                          maxLines: 1,
                          softWrap: false,
                          style: GoogleFonts.exo2(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: widget.onSnapshot,
                    icon: const Icon(Icons.camera_alt, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.darkCard,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.all(13),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                      size: 20,
                      color: _hudEnabled
                          ? AppTheme.primaryOrange
                          : AppTheme.textMuted,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.darkCard,
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.all(13),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: AppTheme.darkBorder),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Object Tracking Target Selector Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isTracking
                        ? const Color(0xFF00E5FF).withAlpha(140)
                        : AppTheme.darkBorder,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                isTracking
                                    ? Icons.gps_fixed
                                    : Icons.track_changes,
                                color: isTracking
                                    ? const Color(0xFF00E5FF)
                                    : AppTheme.primaryOrange,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Object Tracking (Person or Selected in View)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.exo2(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isTracking) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              trackedLabel ?? 'LOCKED',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.exo2(
                                color: const Color(0xFF00E5FF),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tap or drag an object in the camera view, or select a mode below:',
                      style: GoogleFonts.exo2(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final preset in const <String>[
                          'person',
                          'center',
                        ])
                          ActionChip(
                            avatar: Icon(
                              trackedLabel?.toLowerCase() == preset.toLowerCase()
                                  ? Icons.my_location
                                  : Icons.center_focus_strong,
                              size: 15,
                              color: trackedLabel?.toLowerCase() ==
                                      preset.toLowerCase()
                                  ? Colors.black
                                  : const Color(0xFF00E5FF),
                            ),
                            label: Text(
                              preset,
                              style: GoogleFonts.exo2(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: trackedLabel?.toLowerCase() ==
                                        preset.toLowerCase()
                                    ? Colors.black
                                    : Colors.white,
                              ),
                            ),
                            backgroundColor: trackedLabel?.toLowerCase() ==
                                    preset.toLowerCase()
                                ? const Color(0xFF00E5FF)
                                : const Color(0xFF1B1E26),
                            side: BorderSide(
                              color: trackedLabel?.toLowerCase() ==
                                      preset.toLowerCase()
                                  ? const Color(0xFF00E5FF)
                                  : AppTheme.darkBorder,
                            ),
                            onPressed: () => _trackByLabel(preset),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.exo2(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
