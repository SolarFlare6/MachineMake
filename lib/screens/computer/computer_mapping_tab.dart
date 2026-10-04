import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../models/dcp_models.dart';
import '../../theme/app_theme.dart';

/// Mapping actions available for PC and computer-class devices.
enum ComputerMappingAction {
  mouse,
  keyboard,
  lock,
  media,
}

/// Tab dedicated to remote device mapping and input control:
/// - Virtual Trackpad for mouse control (drag, click, scroll, sensitivity)
/// - Virtual Keyboard & quick action key buttons
/// - Device Lock action (Windows Win+L, macOS Cmd+Ctrl+Q, Linux Super+L)
/// - Media controls (Play/Pause, Next, Prev, Stop, Volume)
class ComputerMappingTab extends StatefulWidget {
  final DeviceItem device;
  final DeviceConnection? conn;

  const ComputerMappingTab({
    super.key,
    required this.device,
    this.conn,
  });

  @override
  State<ComputerMappingTab> createState() => _ComputerMappingTabState();
}

class _ComputerMappingTabState extends State<ComputerMappingTab> {
  ComputerMappingAction _selectedAction = ComputerMappingAction.mouse;

  // ── Mouse / Trackpad State ─────────────────────────────────────────
  double _mouseSensitivity = 1.5;
  final ValueNotifier<Offset> _deltaNotifier = ValueNotifier<Offset>(Offset.zero);
  bool _isDragging = false;

  // ── Keyboard State ─────────────────────────────────────────────────
  final TextEditingController _keyboardTextCtrl = TextEditingController();
  bool _autoClearText = true;
  String? _lastSentKey;

  // ── Lock Device State ──────────────────────────────────────────────
  String _selectedOs = 'windows'; // 'windows', 'macos', 'linux'
  bool _confirmBeforeLock = false;

  // ── Media State ────────────────────────────────────────────────────
  double _mediaVolume = 0.7;

  @override
  void dispose() {
    _keyboardTextCtrl.dispose();
    _deltaNotifier.dispose();
    super.dispose();
  }

  // ── DCP Helper ─────────────────────────────────────────────────────
  void _exec(String tool, Map<String, dynamic> params, {bool fireAndForget = false}) {
    widget.conn?.session?.executeTool(tool, params, fireAndForget: fireAndForget);
  }

  void _showFeedback(String message, {Color? color}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final effectiveColor = color ?? AppTheme.primaryOrange;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.exo2(fontWeight: FontWeight.w600)),
          backgroundColor: effectiveColor,
          duration: const Duration(milliseconds: 500),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  // ── Mouse Actions ──────────────────────────────────────────────────
  void _sendMouseMove(double dx, double dy) {
    // 2.5x base multiplier provides natural 1:1 feel on high-DPI desktop displays
    final scaledDx = dx * _mouseSensitivity * 2.5;
    final scaledDy = dy * _mouseSensitivity * 2.5;
    _deltaNotifier.value = Offset(scaledDx, scaledDy);
    _exec('mouse_move', {'dx': scaledDx, 'dy': scaledDy}, fireAndForget: true);
  }

  void _sendMouseClick(String button, {bool isDouble = false}) {
    _exec('mouse_click', {'button': button, 'double': isDouble});
    _showFeedback(
      isDouble ? 'Double Click ($button)' : '${button.toUpperCase()} Click',
      color: button == 'left' ? AppTheme.primaryOrange : const Color(0xFF00E5FF),
    );
  }

  void _sendMouseScroll(double dy) {
    _exec('mouse_scroll', {'dy': dy * 1.5}, fireAndForget: true);
  }

  // ── Keyboard Actions ───────────────────────────────────────────────
  void _sendTypedText() {
    final text = _keyboardTextCtrl.text;
    if (text.isEmpty) return;

    _exec('keyboard_type', {'text': text});
    HapticFeedback.lightImpact();
    setState(() {
      _lastSentKey = 'Text: "$text"';
    });

    if (_autoClearText) {
      _keyboardTextCtrl.clear();
    }
  }

  void _sendKeyPress(String key) {
    _exec('keyboard_press', {'key': key});
    HapticFeedback.lightImpact();
    setState(() {
      _lastSentKey = key;
    });
  }

  // ── Lock Device Actions ────────────────────────────────────────────
  void _lockDevice() {
    if (_confirmBeforeLock) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.modalBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.redAccent, width: 1.5),
          ),
          title: Row(
            children: [
              const Icon(Icons.lock, color: Colors.redAccent, size: 24),
              const SizedBox(width: 10),
              Text(
                'Lock Device',
                style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to lock ${widget.device.name} ($_selectedOs)?',
            style: GoogleFonts.exo2(color: AppTheme.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: GoogleFonts.exo2(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                _triggerLock();
              },
              child: Text('Lock Now', style: GoogleFonts.exo2(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } else {
      _triggerLock();
    }
  }

  void _triggerLock() {
    _exec('lock_device', {'os': _selectedOs});
    _showFeedback(
      'Locked device (${_selectedOs.toUpperCase()})',
      color: Colors.redAccent,
    );
  }

  // ── Media Actions ──────────────────────────────────────────────────
  void _sendMediaAction(String action) {
    _exec('media_control', {'action': action});
    _showFeedback('Media: ${action.replaceAll('_', ' ').toUpperCase()}');
  }

  // ───────────────────────────────────────────────────────────────────
  // BUILD UI
  // ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header / Instruction card
          _buildHeaderBanner(),

          const SizedBox(height: 16),

          // Action Selection Menu
          _buildActionSelectionMenu(),

          const SizedBox(height: 18),

          // Selected Action Content
          _buildActiveActionView(),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeaderBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primaryOrange.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.tune, color: AppTheme.primaryOrange, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Input & Device Mapping',
                  style: GoogleFonts.exo2(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  'Control mouse, keyboard, lock session, or playback remotely',
                  style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Action Selection Menu ──────────────────────────────────────────
  Widget _buildActionSelectionMenu() {
    final actions = [
      (ComputerMappingAction.mouse, Icons.mouse, 'Mouse'),
      (ComputerMappingAction.keyboard, Icons.keyboard, 'Keyboard'),
      (ComputerMappingAction.lock, Icons.lock_outline, 'Lock PC'),
      (ComputerMappingAction.media, Icons.music_note, 'Media'),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Row(
        children: actions.map((item) {
          final isSelected = _selectedAction == item.$1;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedAction = item.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primaryOrange : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppTheme.primaryOrange.withAlpha(80),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item.$2,
                          color: isSelected ? Colors.black : AppTheme.textMuted,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item.$3,
                          style: GoogleFonts.exo2(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Active Action View Switcher ────────────────────────────────────
  Widget _buildActiveActionView() {
    switch (_selectedAction) {
      case ComputerMappingAction.mouse:
        return _buildMouseView();
      case ComputerMappingAction.keyboard:
        return _buildKeyboardView();
      case ComputerMappingAction.lock:
        return _buildLockView();
      case ComputerMappingAction.media:
        return _buildMediaView();
    }
  }

  // ───────────────────────────────────────────────────────────────────
  // 1. MOUSE VIEW (VIRTUAL TRACKPAD)
  // ───────────────────────────────────────────────────────────────────
  Widget _buildMouseView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Trackpad area with gesture detector
        Container(
          height: 260,
          decoration: BoxDecoration(
            color: const Color(0xFF191B20),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _isDragging ? AppTheme.primaryOrange : AppTheme.darkBorder,
              width: _isDragging ? 1.8 : 1.2,
            ),
            boxShadow: _isDragging
                ? [
                    BoxShadow(
                      color: AppTheme.primaryOrange.withAlpha(40),
                      blurRadius: 16,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              // Subtle grid or crosshair pattern background
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.touch_app,
                      color: AppTheme.textMuted.withAlpha(50),
                      size: 42,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'VIRTUAL TRACKPAD',
                      style: GoogleFonts.firaCode(
                        color: AppTheme.textMuted.withAlpha(80),
                        fontSize: 11,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Slide to move • Tap left click • Long press right click',
                      style: GoogleFonts.exo2(
                        color: AppTheme.textMuted.withAlpha(100),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),

              // Full trackpad touch target
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => setState(() => _isDragging = true),
                  onPanEnd: (_) => setState(() => _isDragging = false),
                  onPanCancel: () => setState(() => _isDragging = false),
                  onPanUpdate: (details) {
                    _sendMouseMove(details.delta.dx, details.delta.dy);
                  },
                  onTap: () => _sendMouseClick('left'),
                  onDoubleTap: () => _sendMouseClick('left', isDouble: true),
                  onLongPress: () => _sendMouseClick('right'),
                ),
              ),

              // Vertical Scroll Strip on right side
              Positioned(
                right: 8,
                top: 20,
                bottom: 20,
                width: 36,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {
                    _sendMouseScroll(-details.delta.dy);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.darkSurface.withAlpha(160),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.darkBorder.withAlpha(120)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Icon(Icons.keyboard_arrow_up, color: AppTheme.primaryOrange, size: 16),
                        const Icon(Icons.swap_vert, color: AppTheme.textMuted, size: 14),
                        Icon(Icons.keyboard_arrow_down, color: AppTheme.primaryOrange, size: 16),
                      ],
                    ),
                  ),
                ),
              ),

              // Live cursor delta tag
              if (_isDragging)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: ValueListenableBuilder<Offset>(
                    valueListenable: _deltaNotifier,
                    builder: (context, delta, _) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.darkCard.withAlpha(200),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppTheme.primaryOrange.withAlpha(80)),
                        ),
                        child: Text(
                          'ΔX: ${delta.dx.toStringAsFixed(1)}  ΔY: ${delta.dy.toStringAsFixed(1)}',
                          style: GoogleFonts.firaCode(
                            color: AppTheme.primaryOrange,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Physical-style Mouse Buttons Row (Left Click, Middle, Right Click)
        Row(
          children: [
            // Left Click (Primary, larger)
            Expanded(
              flex: 5,
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.darkCard,
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppTheme.darkBorder, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _sendMouseClick('left'),
                  icon: Icon(Icons.mouse, color: AppTheme.primaryOrange, size: 18),
                  label: Text(
                    'Left Click',
                    style: GoogleFonts.exo2(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Middle Click
            SizedBox(
              height: 52,
              width: 58,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: AppTheme.darkBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: EdgeInsets.zero,
                ),
                onPressed: () => _sendMouseClick('middle'),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.circle, size: 12, color: AppTheme.primaryOrange),
                    const SizedBox(height: 2),
                    Text('Mid', style: GoogleFonts.exo2(fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Right Click (Larger)
            Expanded(
              flex: 5,
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.darkCard,
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppTheme.darkBorder, width: 1.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _sendMouseClick('right'),
                  icon: const Icon(Icons.touch_app, color: Color(0xFF00E5FF), size: 18),
                  label: Text(
                    'Right Click',
                    style: GoogleFonts.exo2(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Sensitivity slider
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.darkBorder),
          ),
          child: Row(
            children: [
              Icon(Icons.speed, color: AppTheme.primaryOrange, size: 18),
              const SizedBox(width: 10),
              Text(
                'Speed',
                style: GoogleFonts.exo2(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppTheme.primaryOrange,
                    inactiveTrackColor: AppTheme.darkBorder,
                    thumbColor: AppTheme.primaryOrange,
                    overlayColor: AppTheme.primaryOrange.withAlpha(30),
                  ),
                  child: Slider(
                    value: _mouseSensitivity,
                    min: 0.5,
                    max: 4.0,
                    divisions: 35,
                    onChanged: (v) => setState(() => _mouseSensitivity = v),
                  ),
                ),
              ),
              Text(
                '${_mouseSensitivity.toStringAsFixed(1)}x',
                style: GoogleFonts.firaCode(
                  color: AppTheme.primaryOrange,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────
  // 2. KEYBOARD VIEW (TYPING + QUICK ACTION KEYS)
  // ───────────────────────────────────────────────────────────────────
  Widget _buildKeyboardView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Text Input Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.darkBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Row: Title + Last Sent Key Chip
              Row(
                children: [
                  Icon(Icons.keyboard, color: AppTheme.primaryOrange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Type on Remote Host',
                      style: GoogleFonts.exo2(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (_lastSentKey != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryOrange.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.primaryOrange.withAlpha(80)),
                      ),
                      child: Text(
                        _lastSentKey!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.firaCode(
                          color: AppTheme.primaryOrange,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Sub-row: instruction + auto-clear toggle chip
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Direct input to host machine',
                      style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() => _autoClearText = !_autoClearText),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _autoClearText ? Icons.check_box : Icons.check_box_outline_blank,
                            size: 15,
                            color: _autoClearText ? AppTheme.primaryOrange : AppTheme.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Clear after send',
                            style: GoogleFonts.exo2(
                              color: _autoClearText ? AppTheme.primaryOrange : AppTheme.textMuted,
                              fontSize: 10,
                              fontWeight: _autoClearText ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Text Field with clear icon
              TextField(
                controller: _keyboardTextCtrl,
                style: GoogleFonts.firaCode(color: Colors.white, fontSize: 13),
                textInputAction: TextInputAction.send,
                decoration: InputDecoration(
                  hintText: 'Type text to send to host...',
                  hintStyle: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12),
                  filled: true,
                  fillColor: AppTheme.darkSurface,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _keyboardTextCtrl,
                    builder: (_, value, __) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(Icons.clear, size: 16, color: AppTheme.textMuted),
                        onPressed: () => _keyboardTextCtrl.clear(),
                      );
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.darkBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.primaryOrange, width: 1.5),
                  ),
                ),
                onSubmitted: (_) => _sendTypedText(),
              ),
              const SizedBox(height: 12),

              // Send button
              SizedBox(
                height: 44,
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryOrange,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _sendTypedText,
                  icon: const Icon(Icons.send, size: 16),
                  label: Text(
                    'Send Text to Device',
                    style: GoogleFonts.exo2(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Quick Function Keys Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.darkBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick Keystrokes & Shortcuts',
                style: GoogleFonts.exo2(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),

              // Essential editing row
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _keyButton('Enter', 'enter', icon: Icons.keyboard_return),
                  _keyButton('Backspace', 'backspace', icon: Icons.backspace_outlined),
                  _keyButton('Space', 'space', icon: Icons.space_bar),
                  _keyButton('Tab', 'tab', icon: Icons.keyboard_tab),
                  _keyButton('Esc', 'escape'),
                  _keyButton('Del', 'delete'),
                ],
              ),

              const SizedBox(height: 14),
              const Divider(color: AppTheme.darkBorder, height: 1),
              const SizedBox(height: 14),

              Text(
                'Shortcuts & Modifiers',
                style: GoogleFonts.exo2(
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _keyButton('Ctrl + C', 'ctrl+c'),
                  _keyButton('Ctrl + V', 'ctrl+v'),
                  _keyButton('Ctrl + Z', 'ctrl+z'),
                  _keyButton('Ctrl + A', 'ctrl+a'),
                  _keyButton('Alt + Tab', 'alt+tab'),
                  _keyButton('Win / Super', 'win'),
                  _keyButton('Alt + F4', 'alt+f4'),
                ],
              ),

              const SizedBox(height: 14),
              const Divider(color: AppTheme.darkBorder, height: 1),
              const SizedBox(height: 14),

              // Navigation Keys section (Proper Inverted-T layout!)
              Text(
                'Navigation Keys',
                style: GoogleFonts.exo2(
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),

              Center(
                child: Column(
                  children: [
                    _navButton('▲', 'up', label: 'UP'),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _navButton('◀', 'left', label: 'LEFT'),
                        const SizedBox(width: 8),
                        _navButton('▼', 'down', label: 'DOWN'),
                        const SizedBox(width: 8),
                        _navButton('▶', 'right', label: 'RIGHT'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _navButton(String symbol, String keyParam, {String? label}) {
    return SizedBox(
      width: 58,
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.darkSurface,
          foregroundColor: Colors.white,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppTheme.darkBorder),
          ),
          elevation: 0,
        ),
        onPressed: () => _sendKeyPress(keyParam),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              symbol,
              style: TextStyle(fontSize: 16, color: AppTheme.primaryOrange, fontWeight: FontWeight.bold),
            ),
            if (label != null)
              Text(
                label,
                style: GoogleFonts.exo2(fontSize: 8, color: AppTheme.textMuted, fontWeight: FontWeight.bold),
              ),
          ],
        ),
      ),
    );
  }

  Widget _keyButton(String label, String keyParam, {IconData? icon}) {
    return SizedBox(
      height: 38,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.darkSurface,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppTheme.darkBorder),
          ),
          elevation: 0,
        ),
        onPressed: () => _sendKeyPress(keyParam),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: AppTheme.primaryOrange),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: GoogleFonts.firaCode(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────
  // 3. LOCK VIEW (LOCK THE DEVICE)
  // ───────────────────────────────────────────────────────────────────
  Widget _buildLockView() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock, color: Colors.redAccent, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lock Remote Device',
                      style: GoogleFonts.exo2(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Immediately secure the workstation screen session',
                      style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // OS Selection
          Text(
            'Target Operating System',
            style: GoogleFonts.exo2(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              _buildOsRadio('windows', 'Windows', 'Win + L'),
              const SizedBox(width: 8),
              _buildOsRadio('linux', 'Linux', 'Super + L'),
              const SizedBox(width: 8),
              _buildOsRadio('macos', 'macOS', 'Cmd+Ctrl+Q'),
            ],
          ),

          const SizedBox(height: 18),

          // Confirmation toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Row(
              children: [
                Icon(Icons.security, color: AppTheme.primaryOrange, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Confirm before locking',
                    style: GoogleFonts.exo2(color: Colors.white70, fontSize: 12),
                  ),
                ),
                Switch(
                  value: _confirmBeforeLock,
                  activeThumbColor: AppTheme.primaryOrange,
                  activeTrackColor: AppTheme.primaryOrange.withAlpha(80),
                  onChanged: (v) => setState(() => _confirmBeforeLock = v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Large glowing Lock Device Button
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
                shadowColor: Colors.redAccent.withAlpha(120),
              ),
              onPressed: _lockDevice,
              icon: const Icon(Icons.lock, size: 22),
              label: Text(
                'LOCK DEVICE NOW',
                style: GoogleFonts.exo2(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),
          Center(
            child: Text(
              'Sends DCP command "lock_device" with os: $_selectedOs',
              style: GoogleFonts.firaCode(
                color: AppTheme.textMuted,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOsRadio(String id, String title, String shortcut) {
    final isSelected = _selectedOs == id;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedOs = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryOrange.withAlpha(25) : AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppTheme.primaryOrange : AppTheme.darkBorder,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Text(
                title,
                style: GoogleFonts.exo2(
                  color: isSelected ? AppTheme.primaryOrange : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                shortcut,
                style: GoogleFonts.firaCode(
                  color: AppTheme.textMuted,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────
  // 4. MEDIA VIEW (PLAY/PAUSE MUSIC & AUDIO CONTROLS)
  // ───────────────────────────────────────────────────────────────────
  Widget _buildMediaView() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.music_note, color: Color(0xFF00E5FF), size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Media & Music Control',
                      style: GoogleFonts.exo2(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Control media player playback and audio levels on PC',
                      style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Playback Control Buttons Row (Prev, Play/Pause, Next, Stop)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Previous
              IconButton.filledTonal(
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.darkSurface,
                  padding: const EdgeInsets.all(14),
                ),
                icon: const Icon(Icons.skip_previous, color: Colors.white, size: 26),
                onPressed: () => _sendMediaAction('prev'),
                tooltip: 'Previous Track',
              ),

              // Play / Pause Main Button
              GestureDetector(
                onTap: () => _sendMediaAction('play_pause'),
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryOrange,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryOrange.withAlpha(90),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Icons.play_arrow,
                        color: Colors.black,
                        size: 26,
                      ),
                      SizedBox(width: 1),
                      Icon(
                        Icons.pause,
                        color: Colors.black,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),

              // Next
              IconButton.filledTonal(
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.darkSurface,
                  padding: const EdgeInsets.all(14),
                ),
                icon: const Icon(Icons.skip_next, color: Colors.white, size: 26),
                onPressed: () => _sendMediaAction('next'),
                tooltip: 'Next Track',
              ),

              // Stop
              IconButton.filledTonal(
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.darkSurface,
                  padding: const EdgeInsets.all(14),
                ),
                icon: const Icon(Icons.stop, color: Colors.redAccent, size: 26),
                onPressed: () => _sendMediaAction('stop'),
                tooltip: 'Stop Playback',
              ),
            ],
          ),

          const SizedBox(height: 24),
          const Divider(color: AppTheme.darkBorder, height: 1),
          const SizedBox(height: 20),

          // Volume Adjustment Row
          Text(
            'Host Volume Control',
            style: GoogleFonts.exo2(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              IconButton(
                icon: Icon(Icons.volume_down, color: AppTheme.primaryOrange),
                onPressed: () => _sendMediaAction('volume_down'),
                tooltip: 'Volume Down',
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color(0xFF00E5FF),
                    inactiveTrackColor: AppTheme.darkBorder,
                    thumbColor: const Color(0xFF00E5FF),
                    overlayColor: const Color(0xFF00E5FF).withAlpha(30),
                  ),
                  child: Slider(
                    value: _mediaVolume,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) {
                      setState(() => _mediaVolume = v);
                      _exec('set_volume', {'volume': v});
                    },
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.volume_up, color: AppTheme.primaryOrange),
                onPressed: () => _sendMediaAction('volume_up'),
                tooltip: 'Volume Up',
              ),
              IconButton(
                icon: const Icon(Icons.volume_off, color: Colors.amberAccent),
                onPressed: () => _sendMediaAction('mute'),
                tooltip: 'Mute / Unmute',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
