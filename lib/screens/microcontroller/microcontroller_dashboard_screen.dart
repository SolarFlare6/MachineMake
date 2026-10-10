import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../core/models/device_manifest.dart';
import '../../models/dcp_models.dart';
import '../../services/device_manager.dart';
import '../../services/event_manager.dart';
import '../../theme/app_theme.dart';

/// Specialized dashboard for Raspberry Pi Pico & microcontroller devices.
/// Provides real-time control for:
///   - Built-in LED toggle and animations
///   - Internal temperature sensor readings (°C and °F)
///   - I2C bus device scanner with refresh
///   - Analog ADC channel reader (GP26-28)
///   - Dynamic GPIO pin mode selector (Digital Out, Digital In, PWM, Servo)
class MicrocontrollerDashboardScreen extends StatefulWidget {
  final DeviceItem device;
  final DeviceConnection? conn;
  final DeviceManifest? manifest;

  const MicrocontrollerDashboardScreen({
    super.key,
    required this.device,
    this.conn,
    this.manifest,
  });

  @override
  State<MicrocontrollerDashboardScreen> createState() => _MicrocontrollerDashboardScreenState();
}

class _MicrocontrollerDashboardScreenState extends State<MicrocontrollerDashboardScreen> {
  // Common RP2040 user GPIO pins
  static const List<int> _userGpioPins = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22,
  ];

  static const List<int> _adcPins = [26, 27, 28];

  // Pin Configuration & States
  final Map<int, String> _pinModes = {}; // 'digital_out', 'digital_in', 'pwm', 'servo'
  final Map<int, bool> _gpioOutStates = {};
  final Map<int, bool?> _gpioInStates = {};
  final Map<int, double> _pwmDuties = {}; // 0.0 - 1.0
  final Map<int, int> _pwmFrequencies = {}; // Hz
  final Map<int, double> _servoAngles = {}; // 0.0 - 180.0

  // ADC State
  final Map<int, double> _adcVoltages = {26: 0.0, 27: 0.0, 28: 0.0};
  final Map<int, int> _adcRaw = {26: 0, 27: 0, 28: 0};
  final Map<int, bool> _adcLoading = {26: false, 27: false, 28: false};

  // I2C State
  List<Map<String, dynamic>> _i2cBuses = [];
  bool _isScanningI2c = false;
  String? _i2cStatusMessage;

  // Onboard Hardware State
  bool _builtinLedOn = false;
  double? _temperatureC;
  double? _temperatureF;
  bool _isLoadingTemp = false;

  StreamSubscription? _eventSub;
  Timer? _pollingTimer;

  DeviceConnection? get _effectiveConn =>
      widget.conn ?? DeviceManager().getConnection(widget.device.id);

  @override
  void initState() {
    super.initState();
    _initDefaults();
    _subscribeToEvents();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fetchInitialTelemetryAndStatus();
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _initDefaults() {
    for (final pin in _userGpioPins) {
      _pinModes[pin] = 'digital_out';
      _gpioOutStates[pin] = false;
      _gpioInStates[pin] = null;
      _pwmDuties[pin] = 0.5;
      _pwmFrequencies[pin] = 1000;
      _servoAngles[pin] = 90.0;
    }
  }

  void _subscribeToEvents() {
    _eventSub = EventManager().eventsForDevice(widget.device.id).listen((event) {
      if (!mounted) return;
      final data = event.data;

      if (event.eventType == 'telemetry') {
        if (data['temp'] is num) {
          final c = (data['temp'] as num).toDouble();
          setState(() {
            _temperatureC = c;
            _temperatureF = double.parse((c * 9 / 5 + 32).toStringAsFixed(1));
          });
        }
        if (data['led'] is bool) {
          setState(() => _builtinLedOn = data['led'] as bool);
        }
        if (data['servos'] is Map) {
          final servos = data['servos'] as Map;
          setState(() {
            servos.forEach((key, val) {
              final pin = int.tryParse(key.toString());
              if (pin != null && val is num) {
                _servoAngles[pin] = val.toDouble();
                _pinModes[pin] = 'servo';
              }
            });
          });
        }
      }
    });
  }

  Future<void> _fetchInitialTelemetryAndStatus() async {
    final session = _effectiveConn?.session;
    if (session == null) return;
    try {
      await _refreshTemperature();
      if (mounted) await _refreshBuiltinLed();
      if (mounted) await _readAllAdcs();
      if (mounted) await _refreshI2c();
    } catch (_) {}
  }

  // ── Communication Helpers ──────────────────────────────────────────────────

  Future<dynamic> _invokeTool(String toolName, Map<String, dynamic> params) async {
    final session = _effectiveConn?.session;
    if (session == null) {
      // In mock/demo mode or disconnected fallback
      return null;
    }
    try {
      final res = await session.executeTool(toolName, params);
      if (res.success) {
        return res.result;
      } else {
        _showToast(res.error ?? 'Execution failed for $toolName', isError: true);
        return null;
      }
    } catch (e) {
      _showToast('Tool error ($toolName): $e', isError: true);
      return null;
    }
  }

  void _showToast(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: isError ? Colors.redAccent.shade700 : AppTheme.darkCard,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Onboard LED & Temperature Actions ──────────────────────────────────────

  Future<void> _toggleBuiltinLed() async {
    final targetState = !_builtinLedOn;
    setState(() => _builtinLedOn = targetState);
    final res = await _invokeTool('set_led', {'on': targetState});
    if (res is Map && res['led_state'] != null && mounted) {
      setState(() => _builtinLedOn = res['led_state'] as bool);
    }
  }

  Future<void> _blinkOk() async {
    _showToast('Pico flashing confirmation sequence');
    await _invokeTool('blink_oke', {});
  }

  Future<void> _flashAlert() async {
    _showToast('Pico flashing alert sequence', isError: true);
    await _invokeTool('flash_alert', {});
  }

  Future<void> _refreshBuiltinLed() async {
    final res = await _invokeTool('get_led', {});
    if (res is Map && res['led_state'] != null && mounted) {
      setState(() => _builtinLedOn = res['led_state'] as bool);
    }
  }

  Future<void> _refreshTemperature() async {
    if (_isLoadingTemp) return;
    setState(() => _isLoadingTemp = true);
    try {
      final res = await _invokeTool('get_temperature', {});
      if (res is Map && mounted) {
        final c = (res['temperature_c'] as num?)?.toDouble();
        final f = (res['temperature_f'] as num?)?.toDouble() ??
            (c != null ? double.parse((c * 9 / 5 + 32).toStringAsFixed(1)) : null);
        setState(() {
          _temperatureC = c;
          _temperatureF = f;
        });
      }
    } finally {
      if (mounted) setState(() => _isLoadingTemp = false);
    }
  }

  // ── I2C Bus Scanning Actions ───────────────────────────────────────────────

  Future<void> _refreshI2c() async {
    if (_isScanningI2c) return;
    setState(() {
      _isScanningI2c = true;
      _i2cStatusMessage = 'Scanning I2C buses on GP4/GP5 and GP6/GP7...';
    });

    try {
      final res = await _invokeTool('i2c_scan', {});
      if (res is Map && res['buses'] is List && mounted) {
        final list = (res['buses'] as List)
            .map((e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
            .toList();
        setState(() {
          _i2cBuses = list;
          _i2cStatusMessage = null;
        });
      } else if (mounted) {
        setState(() => _i2cStatusMessage = null);
      }
    } finally {
      if (mounted) setState(() => _isScanningI2c = false);
    }
  }

  // ── Analog ADC Actions ─────────────────────────────────────────────────────

  Future<void> _readAdcPin(int pin) async {
    setState(() => _adcLoading[pin] = true);
    try {
      final res = await _invokeTool('adc_read', {'pin': pin, 'samples': 8});
      if (res is Map && mounted) {
        final v = (res['voltage'] as num?)?.toDouble() ?? 0.0;
        final raw = (res['raw_u16'] as num?)?.toInt() ?? 0;
        setState(() {
          _adcVoltages[pin] = v;
          _adcRaw[pin] = raw;
        });
      }
    } finally {
      if (mounted) setState(() => _adcLoading[pin] = false);
    }
  }

  Future<void> _readAllAdcs() async {
    for (final pin in _adcPins) {
      _readAdcPin(pin);
    }
  }

  // ── Digital & PWM / Servo GPIO Pin Actions ─────────────────────────────────

  void _onPinModeChanged(int pin, String newMode) {
    setState(() => _pinModes[pin] = newMode);

    if (newMode == 'digital_out') {
      _writeDigitalPin(pin, _gpioOutStates[pin] ?? false);
    } else if (newMode == 'digital_in') {
      _readDigitalPin(pin);
    } else if (newMode == 'pwm') {
      _sendPwm(pin, _pwmDuties[pin] ?? 0.5, _pwmFrequencies[pin] ?? 1000);
    } else if (newMode == 'servo') {
      _sendServoAngle(pin, _servoAngles[pin] ?? 90.0);
    }
  }

  Future<void> _toggleDigitalOut(int pin) async {
    final current = _gpioOutStates[pin] ?? false;
    final newState = !current;
    setState(() => _gpioOutStates[pin] = newState);
    await _writeDigitalPin(pin, newState);
  }

  Future<void> _writeDigitalPin(int pin, bool state) async {
    await _invokeTool('gpio_write', {'pin': pin, 'state': state});
  }

  Future<void> _readDigitalPin(int pin) async {
    final res = await _invokeTool('gpio_read', {'pin': pin});
    if (res is Map && mounted) {
      final state = res['state'] as bool?;
      setState(() => _gpioInStates[pin] = state);
    }
  }

  Future<void> _sendPwm(int pin, double duty, int freq) async {
    setState(() {
      _pwmDuties[pin] = duty;
      _pwmFrequencies[pin] = freq;
    });
    await _invokeTool('pwm_set', {'pin': pin, 'value': duty, 'duty': duty, 'freq': freq});
  }

  Future<void> _stopPwm(int pin) async {
    setState(() => _pwmDuties[pin] = 0.0);
    await _invokeTool('pwm_stop', {'pin': pin});
  }

  Future<void> _sendServoAngle(int pin, double angle) async {
    setState(() => _servoAngles[pin] = angle);
    await _invokeTool('set_servo_angle', {'pin': pin, 'angle': angle});
  }

  Future<void> _emergencyStop() async {
    _showToast('Emergency Stop Triggered: Stopping all PWM & Servos', isError: true);
    await _invokeTool('emergency_stop', {});
    if (!mounted) return;
    setState(() {
      for (final p in _userGpioPins) {
        _pwmDuties[p] = 0.0;
        _gpioOutStates[p] = false;
      }
    });
  }

  // ── UI Builder ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkSurface,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.device.name,
              style: GoogleFonts.exo2(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18),
            ),
            Text(
              'Raspberry Pi Pico W Hardware Controller',
              style: GoogleFonts.exo2(color: AppTheme.primaryOrange, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Emergency Stop',
            icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent, size: 26),
            onPressed: _emergencyStop,
          ),
          IconButton(
            tooltip: 'Refresh All',
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _fetchInitialTelemetryAndStatus,
          ),
        ],
      ),
      // NOTE: the old Builder + try/catch was removed. try/catch cannot catch
      // layout-phase errors, so it never did anything useful here.
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDeviceStatusBar(),
            const SizedBox(height: 16),
            _buildOnboardControlsSection(),
            const SizedBox(height: 16),
            _buildAdcSection(),
            const SizedBox(height: 16),
            _buildI2cSection(),
            const SizedBox(height: 20),
            _buildGpioSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ── 1. Device Status Bar ───────────────────────────────────────────────────

  Widget _buildDeviceStatusBar() {
    final ip = widget.device.ipAddress ?? '192.168.x.x';
    final port = widget.device.port;
    final transport = (widget.device.selectedTransport.isNotEmpty ? widget.device.selectedTransport : 'wifi').toUpperCase();
    final isOnline = (_effectiveConn?.isConnected ?? false) || widget.device.isConnected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            child: Icon(Icons.memory, color: AppTheme.primaryOrange, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.greenAccent : Colors.amberAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isOnline ? 'CONNECTED ($transport)' : 'STANDBY ($transport)',
                        style: GoogleFonts.exo2(
                          color: isOnline ? Colors.greenAccent : Colors.amberAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'ws://$ip:$port/dcp',
                  style: GoogleFonts.exo2(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // FIX: override minimumSize so a theme-level Size(double.infinity, x)
          // can't give this button infinite width inside a Row.
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.withAlpha(35),
              foregroundColor: Colors.redAccent,
              elevation: 0,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.power_settings_new, size: 16),
            label: Text('All Off', style: GoogleFonts.exo2(fontSize: 11, fontWeight: FontWeight.bold)),
            onPressed: _emergencyStop,
          ),
        ],
      ),
    );
  }

  // ── 2. Built-in LED & Onboard Temperature Section ──────────────────────────

  Widget _buildOnboardControlsSection() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Built-in LED Card
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _builtinLedOn ? AppTheme.primaryOrange : AppTheme.darkBorder,
                width: _builtinLedOn ? 1.5 : 1.0,
              ),
              boxShadow: _builtinLedOn
                  ? [
                BoxShadow(
                  color: AppTheme.primaryOrange.withAlpha(40),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                )
              ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(
                      _builtinLedOn ? Icons.lightbulb : Icons.lightbulb_outline,
                      color: _builtinLedOn ? AppTheme.primaryOrange : AppTheme.textMuted,
                      size: 24,
                    ),
                    Switch(
                      value: _builtinLedOn,
                      activeTrackColor: AppTheme.primaryOrange,
                      activeThumbColor: Colors.white,
                      onChanged: (_) => _toggleBuiltinLed(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Built-in LED', style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                Text(_builtinLedOn ? 'ACTIVE (HIGH)' : 'OFF (LOW)',
                    style: GoogleFonts.exo2(
                      color: _builtinLedOn ? AppTheme.primaryOrange : AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    )),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: const BorderSide(color: AppTheme.darkBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _blinkOk,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Flash OK', style: GoogleFonts.exo2(fontSize: 10, color: Colors.greenAccent)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: const BorderSide(color: AppTheme.darkBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _flashAlert,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Alert', style: GoogleFonts.exo2(fontSize: 10, color: Colors.amberAccent)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),

        // RP2040 Core Temperature Sensor Card
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(Icons.thermostat, color: AppTheme.tempBlue, size: 24),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: _isLoadingTemp
                          ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.tempBlue),
                      )
                          : const Icon(Icons.refresh, color: AppTheme.textMuted, size: 20),
                      onPressed: _refreshTemperature,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Core Temp', style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  _temperatureC != null ? '${_temperatureC!.toStringAsFixed(1)} °C' : '-- °C',
                  style: GoogleFonts.exo2(
                    color: AppTheme.tempBlue,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _temperatureF != null ? '${_temperatureF!.toStringAsFixed(1)} °F (RP2040 ADC4)' : 'Reading internal sensor...',
                  style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 10),
                ),
                const SizedBox(height: 8),
                // Simple Temperature Visual Indicator
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _temperatureC != null ? ((_temperatureC! - 20) / 60).clamp(0.0, 1.0) : 0.2,
                    backgroundColor: AppTheme.darkSurface,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      (_temperatureC ?? 25) > 60
                          ? Colors.redAccent
                          : ((_temperatureC ?? 25) > 45 ? Colors.orangeAccent : AppTheme.tempBlue),
                    ),
                    minHeight: 5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 3. Analog ADC Pins Section (GP26, GP27, GP28) ──────────────────────────

  Widget _buildAdcSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.darkBorder),
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
                    Icon(Icons.waves, color: AppTheme.gpuCyan, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Analog ADC Inputs (GP26 - GP28)',
                        style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.refresh, size: 16, color: AppTheme.gpuCyan),
                label: Text('Read All', style: GoogleFonts.exo2(color: AppTheme.gpuCyan, fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _readAllAdcs,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: _adcPins.map((pin) {
              final voltage = _adcVoltages[pin] ?? 0.0;
              final raw = _adcRaw[pin] ?? 0;
              final isLoading = _adcLoading[pin] ?? false;
              final fraction = (voltage / 3.3).clamp(0.0, 1.0);

              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: pin != 28 ? 8 : 0),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.darkBorder),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('GP$pin', style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          Text('ADC${pin - 26}', style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 9)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${voltage.toStringAsFixed(3)} V',
                          style: GoogleFonts.exo2(color: AppTheme.gpuCyan, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      Text('Raw: $raw', style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 10)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 4,
                          backgroundColor: AppTheme.darkCard,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.gpuCyan),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 30,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.darkCard,
                            foregroundColor: Colors.white,
                            minimumSize: Size.zero,
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: isLoading ? null : () => _readAdcPin(pin),
                          child: isLoading
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text('Read', style: GoogleFonts.exo2(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── 4. I2C Bus & Connected Devices Section ─────────────────────────────────

  Widget _buildI2cSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.darkBorder),
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
                    const Icon(Icons.device_hub, color: AppTheme.ramPink, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'I2C Buses & Connected Peripherals',
                        style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // FIX: minimumSize override (see status bar button).
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.ramPink.withAlpha(30),
                  foregroundColor: AppTheme.ramPink,
                  elevation: 0,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isScanningI2c
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.ramPink))
                    : const Icon(Icons.refresh, size: 16),
                label: Text('Scan I2C', style: GoogleFonts.exo2(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: _isScanningI2c ? null : _refreshI2c,
              ),
            ],
          ),
          if (_i2cStatusMessage != null) ...[
            const SizedBox(height: 8),
            Text(_i2cStatusMessage!, style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 11)),
          ],
          const SizedBox(height: 12),
          if (_i2cBuses.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.darkBorder),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppTheme.textMuted, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No I2C devices currently detected. Connect devices to SDA (GP4/GP6) & SCL (GP5/GP7) and tap "Scan I2C".',
                      style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            )
          else
            Column(
              children: _i2cBuses.map((bus) {
                final int busId = (bus['bus'] as num?)?.toInt() ?? 0;
                final int sda = (bus['sda'] as num?)?.toInt() ?? 4;
                final int scl = (bus['scl'] as num?)?.toInt() ?? 5;
                final List devices = (bus['devices'] as List?) ?? [];
                final error = bus['error']?.toString();

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.darkBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text('I2C$busId (SDA: GP$sda | SCL: GP$scl)',
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                          const SizedBox(width: 8),
                          Text('${devices.length} device(s)', style: GoogleFonts.exo2(color: AppTheme.ramPink, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Error: $error', style: GoogleFonts.exo2(color: Colors.redAccent, fontSize: 11)),
                        ),
                      if (devices.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: devices.map((d) {
                            final addr = d is Map ? (d['address'] ?? '0x??') : d.toString();
                            final candidates = (d is Map && d['candidates'] is List)
                                ? (d['candidates'] as List).join(', ')
                                : '';
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.darkCard,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppTheme.ramPink.withAlpha(90)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    addr.toString(),
                                    style: GoogleFonts.exo2(color: AppTheme.ramPink, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                  if (candidates.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      '($candidates)',
                                      style: GoogleFonts.exo2(color: Colors.white70, fontSize: 11),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // ── 5. Configurable GPIO Pins (Mode Dropdown & Direct Control) ─────────────

  Widget _buildGpioSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'User GPIO Header Controls (GP0 - GP22)',
                style: GoogleFonts.exo2(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withAlpha(25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'PWM / Servo Capable',
                style: GoogleFonts.exo2(color: AppTheme.primaryOrange, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          children: _userGpioPins.map((pin) => _buildPinControlCard(pin)).toList(),
        ),
      ],
    );
  }

  Widget _buildPinControlCard(int pin) {
    final rawMode = _pinModes[pin] ?? 'digital_out';
    final mode = ['digital_out', 'digital_in', 'pwm', 'servo'].contains(rawMode) ? rawMode : 'digital_out';
    final isOutHigh = _gpioOutStates[pin] ?? false;
    final inState = _gpioInStates[pin];
    final pwmDuty = _pwmDuties[pin] ?? 0.5;
    final pwmFreq = _pwmFrequencies[pin] ?? 1000;
    final servoAngle = _servoAngles[pin] ?? 90.0;

    // Pin hints (I2C, UART, SPI, etc.)
    String? pinTag;
    if (pin == 4) pinTag = 'I2C0 SDA';
    if (pin == 5) pinTag = 'I2C0 SCL';
    if (pin == 6) pinTag = 'I2C1 SDA';
    if (pin == 7) pinTag = 'I2C1 SCL';
    if (pin == 0) pinTag = 'UART0 TX';
    if (pin == 1) pinTag = 'UART0 RX';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (mode == 'digital_out' && isOutHigh) ? AppTheme.primaryOrange.withAlpha(120) : AppTheme.darkBorder,
          width: (mode == 'digital_out' && isOutHigh) ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Pin Badge + Tag + Mode Dropdown
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.darkSurface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.darkBorder),
                    ),
                    child: Text('GP$pin', style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  if (pinTag != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryOrange.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(pinTag, style: GoogleFonts.exo2(color: AppTheme.primaryOrange, fontSize: 10, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),

              // Dropdown to choose which mode
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.darkBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isDense: true,
                    value: mode,
                    dropdownColor: AppTheme.darkSurface,
                    icon: Icon(Icons.arrow_drop_down, color: AppTheme.primaryOrange, size: 20),
                    style: GoogleFonts.exo2(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    items: const [
                      DropdownMenuItem(value: 'digital_out', child: Text('Digital Out')),
                      DropdownMenuItem(value: 'digital_in', child: Text('Digital In')),
                      DropdownMenuItem(value: 'pwm', child: Text('PWM')),
                      DropdownMenuItem(value: 'servo', child: Text('Servo')),
                    ],
                    onChanged: (newVal) {
                      if (newVal != null) _onPinModeChanged(pin, newVal);
                    },
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Mode-Specific Control Body ──
          if (mode == 'digital_out') ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isOutHigh ? AppTheme.primaryOrange : AppTheme.darkSurface,
                      foregroundColor: isOutHigh ? AppTheme.textDarkButton : Colors.white,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isOutHigh ? AppTheme.primaryOrange : AppTheme.darkBorder,
                        ),
                      ),
                    ),
                    onPressed: () => _toggleDigitalOut(pin),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        isOutHigh ? 'STATE: HIGH (3.3V) — TAP TO TURN LOW' : 'STATE: LOW (0V) — TAP TO TURN HIGH',
                        style: GoogleFonts.exo2(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (mode == 'digital_in') ...[
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.darkSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.darkBorder),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Pin State:', style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12)),
                        Text(
                          inState == null ? 'Not Read Yet' : (inState ? 'HIGH (1)' : 'LOW (0)'),
                          style: GoogleFonts.exo2(
                            color: inState == true ? Colors.greenAccent : (inState == false ? Colors.orangeAccent : Colors.white54),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // FIX: minimumSize override (see status bar button).
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.darkSurface,
                    foregroundColor: Colors.white,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text('Read Pin', style: GoogleFonts.exo2(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => _readDigitalPin(pin),
                ),
              ],
            ),
          ] else if (mode == 'pwm') ...[
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Duty: ${(pwmDuty * 100).toInt()}%', style: GoogleFonts.exo2(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    Text('$pwmFreq Hz', style: GoogleFonts.exo2(color: AppTheme.primaryOrange, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: pwmDuty.clamp(0.0, 1.0),
                  min: 0.0,
                  max: 1.0,
                  activeColor: AppTheme.primaryOrange,
                  inactiveColor: AppTheme.darkSurface,
                  onChanged: (val) => _sendPwm(pin, val, pwmFreq),
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: const BorderSide(color: AppTheme.darkBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _sendPwm(pin, 0.25, pwmFreq),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('25%', style: GoogleFonts.exo2(fontSize: 11, color: Colors.white70)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: const BorderSide(color: AppTheme.darkBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _sendPwm(pin, 0.50, pwmFreq),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('50%', style: GoogleFonts.exo2(fontSize: 11, color: Colors.white70)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          side: const BorderSide(color: AppTheme.darkBorder),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => _sendPwm(pin, 1.0, pwmFreq),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('100%', style: GoogleFonts.exo2(fontSize: 11, color: Colors.white70)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _stopPwm(pin),
                      child: Text('Stop', style: GoogleFonts.exo2(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ] else if (mode == 'servo') ...[
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Angle: ${servoAngle.toInt()}°', style: GoogleFonts.exo2(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                    Text('${(1000 + (servoAngle / 180.0) * 1000).toInt()} µs pulse', style: GoogleFonts.exo2(color: AppTheme.primaryOrange, fontSize: 11)),
                  ],
                ),
                Slider(
                  value: servoAngle.clamp(0.0, 180.0),
                  min: 0.0,
                  max: 180.0,
                  divisions: 180,
                  activeColor: AppTheme.primaryOrange,
                  inactiveColor: AppTheme.darkSurface,
                  onChanged: (val) => _sendServoAngle(pin, val),
                ),
                Row(
                  children: [0, 45, 90, 135, 180].map((preset) {
                    final isSel = (servoAngle - preset).abs() < 1;
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: isSel ? AppTheme.primaryOrange.withAlpha(40) : null,
                            side: BorderSide(color: isSel ? AppTheme.primaryOrange : AppTheme.darkBorder),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () => _sendServoAngle(pin, preset.toDouble()),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('$preset°', style: GoogleFonts.exo2(fontSize: 10, color: isSel ? AppTheme.primaryOrange : Colors.white70, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}