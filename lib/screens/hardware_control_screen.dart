import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/connection/device_connection.dart';
import '../core/models/device_capability.dart';
import '../services/capability_manager.dart';
import '../services/device_manager.dart';
import '../services/event_manager.dart';
import '../theme/app_theme.dart';

/// Screen to interactively inspect and control hardware interfaces (GPIO, PWM)
/// dynamically generated from the server's hardware map and capability manifest.
class HardwareControlScreen extends StatefulWidget {
  final String deviceName;
  final String? deviceId;
  final DeviceConnection? conn;

  const HardwareControlScreen({
    super.key,
    required this.deviceName,
    this.deviceId,
    this.conn,
  });

  @override
  State<HardwareControlScreen> createState() => _HardwareControlScreenState();
}

class _HardwareControlScreenState extends State<HardwareControlScreen> {
  final DeviceManager _deviceManager = DeviceManager();
  final CapabilityManager _capabilityManager = CapabilityManager();
  final EventManager _eventManager = EventManager();

  late final String _targetDeviceId;
  final Map<int, bool> _gpioStates = {};
  final Map<int, double> _servoAngles = {};
  List<int> _detectedPins = [];
  bool _hasPwmCapability = false;
  StreamSubscription? _eventSub;

  @override
  void initState() {
    super.initState();
    _targetDeviceId = widget.deviceId ?? _deviceManager.selectedDeviceId;
    _initHardwareFromMap();
    _listenToDeviceEvents();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  void _initHardwareFromMap() {
    final effectiveConn = widget.conn ?? _deviceManager.getConnection(_targetDeviceId);
    final gpioCap = _capabilityManager.getCapability(_targetDeviceId, CapabilityType.gpio) ??
        effectiveConn?.manifest?.capabilities.cast<DeviceCapability?>().firstWhere(
              (c) => c?.type == CapabilityType.gpio,
              orElse: () => null,
            );

    // Extract pin list from server's hardware map / capability params
    final rawPins = gpioCap?.params['pins'];
    if (rawPins is List && rawPins.isNotEmpty) {
      _detectedPins = rawPins.map((p) => int.tryParse(p.toString()) ?? 0).toList();
    } else if (gpioCap != null) {
      // Default common digital GPIO pins for SBC / microcontrollers only if capability declared
      _detectedPins = [2, 3, 4, 14, 15, 17, 18, 27, 22, 23, 24, 25, 5, 6, 12, 13, 16, 19, 20, 21, 26];
    } else {
      _detectedPins = [];
    }

    for (final pin in _detectedPins) {
      _gpioStates.putIfAbsent(pin, () => false);
    }

    // Check for PWM / Servo capability
    final pwmCap = _capabilityManager.getCapability(_targetDeviceId, CapabilityType.pwm) ??
        effectiveConn?.manifest?.capabilities.cast<DeviceCapability?>().firstWhere(
              (c) => c?.type == CapabilityType.pwm,
              orElse: () => null,
            );

    _hasPwmCapability = pwmCap != null;
    final channels = (pwmCap?.params['channels'] as num?)?.toInt() ?? 8;
    for (int i = 0; i < channels.clamp(0, 16); i++) {
      _servoAngles.putIfAbsent(i, () => 90.0);
    }
  }

  void _listenToDeviceEvents() {
    if (_targetDeviceId.isEmpty) return;
    _eventSub = _eventManager.eventsForDevice(_targetDeviceId).listen((event) {
      if (event.eventType == 'gpio_change') {
        final pin = (event.data['pin'] as num?)?.toInt();
        final state = event.data['state'] as bool?;
        if (pin != null && state != null && mounted) {
          setState(() {
            _gpioStates[pin] = state;
          });
        }
      }
    });
  }

  Future<void> _setGpioState(int pin, bool state) async {
    setState(() => _gpioStates[pin] = state);

    final effectiveConn = widget.conn ?? _deviceManager.getConnection(_targetDeviceId);
    try {
      if (effectiveConn?.session != null) {
        await effectiveConn!.session!.executeTool('gpio_write', {'pin': pin, 'state': state});
      } else if (_targetDeviceId.isNotEmpty) {
        await _deviceManager.executeTool(_targetDeviceId, 'gpio_write', {'pin': pin, 'state': state});
      }
    } catch (_) {
      // Offline fallback
    }
  }

  Future<void> _setServoAngle(int channel, double angle) async {
    setState(() => _servoAngles[channel] = angle);

    final effectiveConn = widget.conn ?? _deviceManager.getConnection(_targetDeviceId);
    try {
      if (effectiveConn?.session != null) {
        await effectiveConn!.session!.executeTool('pwm_set', {'channel': channel, 'angle': angle});
      } else if (_targetDeviceId.isNotEmpty) {
        await _deviceManager.executeTool(_targetDeviceId, 'pwm_set', {'channel': channel, 'angle': angle});
      }
    } catch (_) {
      // Offline fallback
    }
  }

  void _setAllPins(bool state) {
    for (final pin in _detectedPins) {
      _setGpioState(pin, state);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveConn = widget.conn ?? _deviceManager.getConnection(_targetDeviceId);
    final isOnline = effectiveConn?.isConnected ?? false;
    final highCount = _gpioStates.values.where((v) => v).length;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkSurface,
        title: Text(
          '${widget.deviceName} Hardware',
          style: GoogleFonts.exo2(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isOnline
                      ? Colors.greenAccent.withAlpha(30)
                      : Colors.redAccent.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isOnline
                        ? Colors.greenAccent.withAlpha(120)
                        : Colors.redAccent.withAlpha(120),
                  ),
                ),
                child: Text(
                  isOnline ? 'Online' : 'Offline',
                  style: GoogleFonts.exo2(
                    color: isOnline ? Colors.greenAccent : Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hardware Map Info Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryOrange.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.memory, color: AppTheme.primaryOrange, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _detectedPins.isNotEmpty
                              ? 'Hardware Map: ${_detectedPins.length} GPIO Pins'
                              : (_hasPwmCapability
                                  ? 'Hardware Map: PWM Channels'
                                  : 'Hardware Map: System Overview'),
                          style: GoogleFonts.exo2(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _detectedPins.isNotEmpty
                              ? '$highCount pins HIGH  •  Target: ${widget.deviceName}'
                              : 'Target: ${widget.deviceName}',
                          style: GoogleFonts.exo2(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_detectedPins.isEmpty && (!_hasPwmCapability || _servoAngles.isEmpty)) ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.darkBorder),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.developer_board_off, color: AppTheme.textMuted, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'No Configurable Hardware Detected',
                      style: GoogleFonts.exo2(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This device does not expose digital GPIO pins or PWM servo channels. Hardware capabilities like digital pins, PWM controllers, and sensors will automatically appear here once detected by the hardware scanner.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.exo2(
                        fontSize: 13,
                        color: AppTheme.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_detectedPins.isNotEmpty) ...[
              // GPIO Controls Header & Quick Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'GPIO Digital Pins',
                    style: GoogleFonts.exo2(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => _setAllPins(false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text('All LOW', style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12)),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () => _setAllPins(true),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text('All HIGH', style: GoogleFonts.exo2(color: AppTheme.primaryOrange, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

            // GPIO Pin Grid
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _detectedPins.map((pin) {
                final isHigh = _gpioStates[pin] ?? false;
                return GestureDetector(
                  onTap: () => _setGpioState(pin, !isHigh),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: (MediaQuery.of(context).size.width - 40 - 24) / 4,
                    height: 60,
                    decoration: BoxDecoration(
                      color: isHigh
                          ? AppTheme.primaryOrange.withAlpha(35)
                          : AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isHigh
                            ? AppTheme.primaryOrange
                            : AppTheme.darkBorder,
                        width: isHigh ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'GPIO $pin',
                          style: GoogleFonts.exo2(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isHigh ? Colors.white : AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: isHigh ? Colors.greenAccent.withAlpha(40) : Colors.black26,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isHigh ? 'HIGH (1)' : 'LOW (0)',
                            style: GoogleFonts.exo2(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isHigh ? Colors.greenAccent : AppTheme.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          // PWM Servo Section (shown if hardware map includes PWM/Servos)
            if (_hasPwmCapability && _servoAngles.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text(
                'PWM Servo Channels (PCA9685 / PWM)',
                style: GoogleFonts.exo2(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),

              ..._servoAngles.entries.map((entry) {
                final ch = entry.key;
                final angle = entry.value;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.darkBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Channel $ch',
                            style: GoogleFonts.exo2(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            '${angle.toInt()}°',
                            style: GoogleFonts.exo2(
                              color: AppTheme.primaryOrange,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: angle,
                        min: 0.0,
                        max: 180.0,
                        activeColor: AppTheme.primaryOrange,
                        inactiveColor: AppTheme.darkBackground,
                        onChanged: (val) => _setServoAngle(ch, val),
                      ),
                    ],
                  ),
                );
              }),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
