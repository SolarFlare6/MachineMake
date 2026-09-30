import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Robot Dog 3D Simulator Widget ─────────────────────────────────
// Usage:
//   RobotSimulator()                        // standalone full screen
//   RobotSimulator(height: 300)             // fixed height
//   RobotSimulator(showControls: false)     // 3D view only, no sliders

// ── Robot geometry (matches physical robot) ──────────────────
const double kBodyL  = 26.5; // cm front to back
const double kBodyW  = 11.0; // cm left to right
const double kBodyH  = 7.0;  // cm height
const double kUpperL = 11.5; // cm shoulder to knee
const double kLowerL = 14.0; // cm knee to foot

// ── Servo index map ───────────────────────────────────────────────
const Map<String, List<int>> kLegIdx = {
  'fl': [2, 3, 4],
  'fr': [5, 6, 7],
  'bl': [8, 9, 10],
  'br': [11, 12, 13],
};

// ── IK offsets back-calculated from manual calibration ────────────
class LegOffset {
  final double s, u, l;
  final double sd, ud, ld;
  const LegOffset(this.s, this.u, this.l, this.sd, this.ud, this.ld);
}

const Map<String, LegOffset> kLegOffsets = {
  'fl': LegOffset(99,  111, 124,  1, -1, -1),
  'fr': LegOffset(121, 69,  76,  -1,  1,  1),
  'bl': LegOffset(119, 111, 114,  1, -1, -1),
  'br': LegOffset(101, 49,  86,  -1,  1,  1),
};

// ── Shoulder positions relative to body center ────────────────────
const Map<String, List<double>> kShoulderPos = {
  'fl': [ kBodyL/2,  kBodyW/2, 0],
  'fr': [ kBodyL/2, -kBodyW/2, 0],
  'bl': [-kBodyL/2,  kBodyW/2, 0],
  'br': [-kBodyL/2, -kBodyW/2, 0],
};

// ── Calibrated standing angles ────────────────────────────────────
const Map<int, double> kStandAngles = {
  2: 110, 3: 70,  4: 50,
  5: 110, 6: 110, 7: 150,
  8: 130, 9: 70,  10: 40,
  11: 80, 12: 90, 13: 160,
};

const Map<int, double> kRestAngles = {
  2: 110, 3: 180, 4: 180,
  5: 110, 6: 0,   7: 0,
  8: 130, 9: 180, 10: 180,
  11: 110, 12: 0,  13: 0,
};

// ── Leg colors ────────────────────────────────────────────────────
const Map<String, Color> kLegColors = {
  'fl': Color(0xFF4FC3F7),
  'fr': Color(0xFF81D4FA),
  'bl': Color(0xFF4DD0E1),
  'br': Color(0xFF80DEEA),
};

// ── 3D point helper ───────────────────────────────────────────────
class Vec3 {
  final double x, y, z;
  const Vec3(this.x, this.y, this.z);
  Vec3 operator +(Vec3 o) => Vec3(x+o.x, y+o.y, z+o.z);
}

// ── Main widget ───────────────────────────────────────────────────
class RobotSimulator extends StatefulWidget {
  final double? height;
  final bool showControls;
  final bool isMiniPreview;
  final bool isMirroring;
  final Map<int, double>? externalAngles;
  final Map<int, double>? initialAngles;
  final Function(int servoIndex, double angle)? onSingleServoChanged;
  final ValueChanged<Map<int, double>>? onAnglesChanged;

  const RobotSimulator({
    super.key,
    this.height,
    this.showControls = true,
    this.isMiniPreview = false,
    this.isMirroring = false,
    this.externalAngles,
    this.initialAngles,
    this.onSingleServoChanged,
    this.onAnglesChanged,
  });

  @override
  State<RobotSimulator> createState() => _RobotSimulatorState();
}

class _RobotSimulatorState extends State<RobotSimulator> {
  // camera & orientation
  double _camX = 0.35;
  double _camY = 0.55;
  double _camD = 90.0;
  double _zoom = 1.0;

  // gesture tracking
  double _prevScale = 1.0;

  // servo state
  late Map<int, double> _servos;

  // selected leg for sliders
  String _selectedLeg = 'fl';

  @override
  void initState() {
    super.initState();
    _servos = Map.from(widget.externalAngles ?? widget.initialAngles ?? kStandAngles);
    if (widget.isMiniPreview) {
      _camD = 100.0;
    }
  }

  @override
  void didUpdateWidget(covariant RobotSimulator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isMirroring && widget.externalAngles != null) {
      setState(() {
        _servos.addAll(widget.externalAngles!);
      });
    } else if (widget.initialAngles != null && widget.initialAngles != oldWidget.initialAngles) {
      setState(() {
        _servos = Map.from(widget.initialAngles!);
      });
    }
  }

  // ── FK: servo angles → 3 joint positions ─────────────────────
  Map<String, Vec3> _legPoints(String leg) {
    final o = kLegOffsets[leg]!;
    final idx = kLegIdx[leg]!;
    final s1 = _servos[idx[0]] ?? 90;
    final s2 = _servos[idx[1]] ?? 90;
    final s3 = _servos[idx[2]] ?? 90;

    final sR = ((s1 - o.s) / o.sd) * pi / 180;
    final uR = ((s2 - o.u) / o.ud) * pi / 180;
    final kA = pi - ((s3 - o.l) / o.ld) * pi / 180;

    final sp = kShoulderPos[leg]!;
    final sx = sp[0], sy = sp[1], sz = sp[2];

    // knee
    final kx = sx + kUpperL * sin(uR);
    final ky = sy + kUpperL * cos(uR) * sin(sR);
    final kz = sz - kUpperL * cos(uR) * cos(sR);

    // foot
    final lA = uR - (pi - kA);
    final fx = kx + kLowerL * sin(lA);
    final fy = ky + kLowerL * cos(lA) * sin(sR);
    final fz = kz - kLowerL * cos(lA) * cos(sR);

    return {
      'shoulder': Vec3(sx, sy, sz),
      'knee':     Vec3(kx, ky, kz),
      'foot':     Vec3(fx, fy, fz),
    };
  }

  // ── 3D → 2D projection ────────────────────────────────────────
  Offset _project(Vec3 v, Size size) {
    final cy = cos(_camY), sy = sin(_camY);
    final cx = cos(_camX), sx = sin(_camX);
    final rx = v.x * cy + v.z * sy;
    final tmp = -v.x * sy + v.z * cy;
    final ry = v.y * cx - tmp * sx;
    final rz = v.y * sx + tmp * cx;
    final sc = _camD / (_camD + rz + 10);
    final baseScale = widget.isMiniPreview ? 3.6 : 8.0;
    final scaleFactor = baseScale * _zoom;
    return Offset(
      size.width / 2 + rx * sc * scaleFactor,
      size.height / 2 - ry * sc * scaleFactor + (widget.isMiniPreview ? 6 : 8),
    );
  }

  void _onScaleStart(ScaleStartDetails d) {
    _prevScale = 1.0;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _camY += d.focalPointDelta.dx * 0.008;
      _camX = (_camX + d.focalPointDelta.dy * 0.008).clamp(-1.2, 1.2);
      if (d.scale != 1.0) {
        final scaleDelta = d.scale / _prevScale;
        _prevScale = d.scale;
        _zoom = (_zoom * scaleDelta).clamp(0.35, 3.5);
      }
    });
  }

  void _zoomIn() {
    setState(() {
      _zoom = (_zoom * 1.2).clamp(0.35, 3.5);
    });
  }

  void _zoomOut() {
    setState(() {
      _zoom = (_zoom / 1.2).clamp(0.35, 3.5);
    });
  }

  void _resetView() {
    setState(() {
      _camX = 0.35;
      _camY = 0.55;
      _zoom = 1.0;
    });
  }

  void _updateServo(int index, double angle) {
    setState(() {
      _servos[index] = angle;
    });
    widget.onSingleServoChanged?.call(index, angle);
    widget.onAnglesChanged?.call(_servos);
  }

  void _applyAnglePreset(Map<int, double> preset) {
    setState(() {
      _servos.addAll(preset);
    });
    preset.forEach((idx, angle) {
      widget.onSingleServoChanged?.call(idx, angle);
    });
    widget.onAnglesChanged?.call(_servos);
  }

  // ── Servo sliders for selected leg (compact & unclipped) ───────
  Widget _buildSliders() {
    final idx = kLegIdx[_selectedLeg]!;
    final labels = ['Shoulder', 'Upper leg', 'Lower leg'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.isMirroring)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF00E676),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Realtime Mirroring Active · Reflecting Robot Servos',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00E676),
                    ),
                  ),
                ],
              ),
            ),
          ...List.generate(3, (i) {
            final index = idx[i];
            final val = _servos[index] ?? 90.0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  SizedBox(
                    width: 86,
                    child: Text(
                      '$index · ${labels[i]}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF9E9E9E)),
                    ),
                  ),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3.0,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                        disabledActiveTrackColor: const Color(0xFF00E676),
                        disabledInactiveTrackColor: const Color(0xFF2A2A30),
                        disabledThumbColor: const Color(0xFF00E676),
                      ),
                      child: Slider(
                        value: val.clamp(0.0, 180.0),
                        min: 0,
                        max: 180,
                        activeColor: widget.isMirroring ? const Color(0xFF00E676) : const Color(0xFF4FC3F7),
                        inactiveColor: const Color(0xFF2A2A30),
                        onChanged: widget.isMirroring ? null : (v) => _updateServo(index, v),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      val.round().toString(),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        color: widget.isMirroring ? const Color(0xFF00E676) : const Color(0xFF4FC3F7),
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Leg selector tabs ─────────────────────────────────────────
  Widget _buildLegTabs() {
    const legs = ['fl', 'fr', 'bl', 'br'];
    const labels = ['Front L', 'Front R', 'Back L', 'Back R'];
    return Row(
      children: List.generate(4, (i) {
        final selected = _selectedLeg == legs[i];
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedLeg = legs[i]),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: selected ? const Color(0xFF4FC3F7) : Colors.transparent,
                    width: 2,
                  ),
                  right: const BorderSide(color: Color(0xFF2A2A30), width: 0.5),
                ),
                color: selected ? const Color(0xFF1A252E) : Colors.transparent,
              ),
              child: Text(
                labels[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? const Color(0xFF4FC3F7) : const Color(0xFF888888),
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  // ── Action buttons ────────────────────────────────────────────
  Widget _buildButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _btn('STAND', () => _applyAnglePreset(kStandAngles)),
          const SizedBox(width: 8),
          _btn('REST',  () => _applyAnglePreset(kRestAngles)),
          const Spacer(),
          _btn('COPY ANGLES', _copyAngles, accent: true),
        ],
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap, {bool accent = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E26),
          border: Border.all(
            color: accent ? const Color(0xFF4FC3F7) : const Color(0xFF2A2A30),
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: accent ? const Color(0xFF4FC3F7) : const Color(0xFFE0E0E0),
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }

  void _copyAngles() {
    const names = {
      2:'FL_MOTOR_1', 3:'FL_MOTOR_2', 4:'FL_MOTOR_3',
      5:'FR_MOTOR_1', 6:'FR_MOTOR_2', 7:'FR_MOTOR_3',
      8:'BL_MOTOR_1', 9:'BL_MOTOR_2', 10:'BL_MOTOR_3',
      11:'BR_MOTOR_1',12:'BR_MOTOR_2',13:'BR_MOTOR_3',
    };
    final lines = ['STAND_ANGLES = {'];
    names.forEach((i, name) {
      final val = _servos[i]?.round() ?? 90;
      lines.add('    $name: $val, #$i');
    });
    lines.add('}');
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF00E676), width: 1.2),
        ),
        backgroundColor: const Color(0xFF1E2028),
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Color(0xFF00E676), size: 20),
            const SizedBox(width: 10),
            Text(
              'Servo angles copied to clipboard',
              style: GoogleFonts.exo2(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Floating Zoom / Reset Control Overlay ───────────────────────
  Widget _buildZoomControls() {
    return Positioned(
      right: 10,
      top: 10,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF16161A).withAlpha(220),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF2A2A30), width: 1.0),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 6),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Zoom In (+)
            InkWell(
              onTap: _zoomIn,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(4.0),
                child: Icon(Icons.add, color: Color(0xFF4FC3F7), size: 20),
              ),
            ),
            // Zoom indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.0),
              child: Text(
                '${(_zoom * 100).toInt()}%',
                style: const TextStyle(
                  fontSize: 9,
                  color: Colors.white70,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Zoom Out (-)
            InkWell(
              onTap: _zoomOut,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(4.0),
                child: Icon(Icons.remove, color: Color(0xFF4FC3F7), size: 20),
              ),
            ),
            const SizedBox(height: 2),
            Container(height: 1, width: 22, color: const Color(0xFF2A2A30)),
            const SizedBox(height: 2),
            // Reset View
            InkWell(
              onTap: _resetView,
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(4.0),
                child: Icon(Icons.restart_alt, color: Colors.white70, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _build3DCanvas() {
    return ClipRect(
      child: Stack(
        children: [
          GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            child: SizedBox.expand(
              child: CustomPaint(
                painter: RobotPainter(
                  camX: _camX,
                  camY: _camY,
                  camD: _camD,
                  zoom: _zoom,
                  legPoints: { for (final l in kLegIdx.keys) l: _legPoints(l) },
                  project: _project,
                  isMini: widget.isMiniPreview,
                ),
              ),
            ),
          ),
          if (!widget.isMiniPreview) _buildZoomControls(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isMiniPreview) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: widget.height ?? 120,
          child: _build3DCanvas(),
        ),
      );
    }

    if (widget.height != null) {
      final canvasH = widget.showControls ? (widget.height! * 0.55) : widget.height!;
      return Container(
        color: const Color(0xFF0D0D0F),
        height: widget.height,
        child: Column(
          children: [
            SizedBox(
              height: canvasH,
              child: _build3DCanvas(),
            ),
            if (widget.showControls) ...[
              Container(height: 1, color: const Color(0xFF2A2A30)),
              Container(color: const Color(0xFF16161A), child: _buildButtons()),
              Container(height: 1, color: const Color(0xFF2A2A30)),
              Container(color: const Color(0xFF16161A), child: _buildLegTabs()),
              Container(height: 1, color: const Color(0xFF2A2A30)),
              Container(color: const Color(0xFF16161A), child: _buildSliders()),
            ],
          ],
        ),
      );
    }

    // Full screen / expanded mode: 3D canvas expands, controls stay pinned and visible at bottom
    return Container(
      color: const Color(0xFF0D0D0F),
      child: Column(
        children: [
          // ── 3D View (Fills remaining space, never overflows) ──
          Expanded(
            child: _build3DCanvas(),
          ),

          if (widget.showControls) ...[
            Container(height: 1, color: const Color(0xFF2A2A30)),
            Container(color: const Color(0xFF16161A), child: _buildButtons()),
            Container(height: 1, color: const Color(0xFF2A2A30)),
            Container(color: const Color(0xFF16161A), child: _buildLegTabs()),
            Container(height: 1, color: const Color(0xFF2A2A30)),
            Container(color: const Color(0xFF16161A), child: _buildSliders()),
          ],
        ],
      ),
    );
  }
}

// ── CustomPainter ─────────────────────────────────────────────────
class RobotPainter extends CustomPainter {
  final double camX, camY, camD, zoom;
  final Map<String, Map<String, Vec3>> legPoints;
  final Offset Function(Vec3, Size) project;
  final bool isMini;

  const RobotPainter({
    required this.camX,
    required this.camY,
    required this.camD,
    required this.zoom,
    required this.legPoints,
    required this.project,
    this.isMini = false,
  });

  void _line(Canvas c, Size s, Vec3 a, Vec3 b, Paint p) {
    c.drawLine(project(a, s), project(b, s), p);
  }

  void _dot(Canvas c, Size s, Vec3 v, double r, Color col) {
    final cy = cos(camY), sy = sin(camY), cx = cos(camX), sx = sin(camX);
    final tmp = -v.x*sy+v.z*cy;
    final rz = v.y*sx+tmp*cx;
    final sc = camD / (camD + rz + 10);
    final baseScale = isMini ? 3.6 : 8.0;
    final dotRadius = (r * sc * baseScale * zoom).clamp(2.0, 9.0);
    c.drawCircle(project(v, s), dotRadius, Paint()..color = col);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0D0D0F),
    );

    // ── grid ────────────────────────────────────────────────────
    if (!isMini) {
      final gridPaint = Paint()
        ..color = const Color(0xFF1A1A22)
        ..strokeWidth = 0.7;
      for (var i = -80; i <= 80; i += 10) {
        _line(canvas, size, Vec3(i.toDouble(), -22, -80), Vec3(i.toDouble(), -22, 80), gridPaint);
        _line(canvas, size, Vec3(-80, -22, i.toDouble()), Vec3(80, -22, i.toDouble()), gridPaint);
      }
    }

    // ── body box ─────────────────────────────────────────────────
    final bodyPaint = Paint()
      ..color = const Color(0xFF2E2E3A)
      ..strokeWidth = isMini ? 1.0 : 1.2
      ..style = PaintingStyle.stroke;

    final bx = kBodyL / 2, bw = kBodyW / 2;
    final corners = [
      Vec3( bx,  bw, 0), Vec3( bx, -bw, 0), Vec3(-bx, -bw, 0), Vec3(-bx,  bw, 0),
      Vec3( bx,  bw,-kBodyH), Vec3( bx,-bw,-kBodyH), Vec3(-bx,-bw,-kBodyH), Vec3(-bx, bw,-kBodyH),
    ];
    const edges = [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]];
    for (final e in edges) {
      _line(canvas, size, corners[e[0]], corners[e[1]], bodyPaint);
    }

    // front direction arrow
    _line(canvas, size, Vec3(bx, 0, -3.5), Vec3(bx + (isMini ? 3 : 5), 0, -3.5),
      Paint()..color = const Color(0xFFFF7043)..strokeWidth = isMini ? 1.5 : 2.5);

    // ── legs ─────────────────────────────────────────────────────
    for (final leg in kLegIdx.keys) {
      final pts = legPoints[leg]!;
      final col = kLegColors[leg]!;

      _line(canvas, size, pts['shoulder']!, pts['knee']!,
        Paint()..color = col..strokeWidth = isMini ? 1.8 : 2.6);
      _line(canvas, size, pts['knee']!, pts['foot']!,
        Paint()..color = col..strokeWidth = isMini ? 1.4 : 2.2);

      _dot(canvas, size, pts['shoulder']!, 0.5, const Color(0xFFCCCCCC));
      _dot(canvas, size, pts['knee']!,     0.4, col);
      _dot(canvas, size, pts['foot']!,     0.65, Colors.white);
    }

    // ── leg labels ───────────────────────────────────────────────
    if (!isMini) {
      final tp = TextPainter(textDirection: TextDirection.ltr);
      for (final entry in {'FL':[bx+3,bw+2.0,0.0],'FR':[bx+3,-bw-2.0,0.0],'BL':[-bx-3,bw+2.0,0.0],'BR':[-bx-3,-bw-2.0,0.0]}.entries) {
        final v = entry.value;
        final p = project(Vec3(v[0], v[1], v[2]), size);
        tp.text = TextSpan(
          text: entry.key,
          style: const TextStyle(fontSize: 10, color: Color(0xFF3A3A4A), fontFamily: 'monospace'),
        );
        tp.layout();
        tp.paint(canvas, p + const Offset(3, -3));
      }
    }
  }

  @override
  bool shouldRepaint(RobotPainter old) =>
    old.camX != camX || old.camY != camY || old.camD != camD || old.zoom != zoom || old.legPoints != legPoints;
}
