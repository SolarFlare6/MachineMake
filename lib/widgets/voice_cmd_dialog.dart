import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/dcp_models.dart';
import '../screens/discovery_screen.dart';
import '../services/device_manager.dart';
import '../theme/app_theme.dart';
import 'voice_sphere.dart';

class VoiceCmdDialog extends StatefulWidget {
  final List<DeviceItem> devices;
  final String selectedDeviceId;
  final Function(String deviceId, String command) onCommandExecuted;

  const VoiceCmdDialog({
    super.key,
    required this.devices,
    required this.selectedDeviceId,
    required this.onCommandExecuted,
  });

  @override
  State<VoiceCmdDialog> createState() => _VoiceCmdDialogState();
}

class _VoiceCmdDialogState extends State<VoiceCmdDialog> {
  String? _currentDeviceId;
  bool _isListeningStep = false;

  // Speech-to-text state
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  double _soundLevel = 0.0;
  String _recognizedText = '';
  String? _speechError;
  bool _hasSubmitted = false;

  // Manual fallback controller if speech recognition is unavailable
  final TextEditingController _fallbackTextController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initCurrentDevice();
  }

  void _initCurrentDevice() {
    if (widget.devices.isNotEmpty) {
      final matches = widget.devices.any((d) => d.id == widget.selectedDeviceId);
      _currentDeviceId = matches ? widget.selectedDeviceId : widget.devices.first.id;
    } else {
      _currentDeviceId = null;
    }
  }

  DeviceItem? get _selectedDevice {
    if (_currentDeviceId == null || widget.devices.isEmpty) return null;
    return widget.devices.firstWhere(
      (d) => d.id == _currentDeviceId,
      orElse: () => widget.devices.first,
    );
  }

  Future<void> _startListeningFlow() async {
    setState(() {
      _isListeningStep = true;
      _recognizedText = '';
      _speechError = null;
      _hasSubmitted = false;
    });

    try {
      // 1. Request microphone permission
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        if (mounted) {
          setState(() {
            _speechError = 'Microphone permission denied. Enable it in settings.';
          });
        }
        return;
      }

      // 2. Initialize speech recognition service
      final available = await _speechToText.initialize(
        onError: _onSpeechError,
        onStatus: _onSpeechStatus,
      );

      if (mounted) {
        setState(() {
          _speechEnabled = available;
        });

        if (available) {
          _startSpeechListening();
        } else {
          setState(() {
            _speechError = 'Speech recognition service is not available on this device.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _speechError = 'Could not start speech recognition: $e';
        });
      }
    }
  }

  Future<void> _startSpeechListening() async {
    if (!_speechEnabled) return;

    try {
      await _speechToText.listen(
        onResult: _onSpeechResult,
        onSoundLevelChange: _onSoundLevelChanged,
        listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          cancelOnError: false,
          partialResults: true,
        ),
      );

      if (mounted) {
        setState(() => _isListening = true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _speechError = 'Listening failed: $e';
          _isListening = false;
        });
      }
    }
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    setState(() {
      _recognizedText = result.recognizedWords;
    });

    // If speech recognizer finalized the sentence, automatically submit command
    if (result.finalResult && _recognizedText.trim().isNotEmpty) {
      _submitCommand(_recognizedText.trim());
    }
  }

  void _onSoundLevelChanged(double level) {
    if (!mounted) return;
    final normalized = _normalizeSoundLevel(level);
    setState(() {
      // Exponential moving average for smooth sphere pulsing
      _soundLevel = _soundLevel * 0.35 + normalized * 0.65;
    });
  }

  double _normalizeSoundLevel(double level) {
    if (level.isNaN || level.isInfinite) return 0.0;
    if (level > 1.0) {
      if (level <= 15.0) {
        return (level / 10.0).clamp(0.0, 1.0);
      } else {
        return (level / 100.0).clamp(0.0, 1.0);
      }
    } else if (level < 0.0) {
      // dB range typically -50 to 0 dB or -100 to 0 dB
      return ((level + 45.0) / 45.0).clamp(0.0, 1.0);
    }
    return level.clamp(0.0, 1.0);
  }

  void _onSpeechStatus(String status) {
    if (!mounted) return;
    setState(() {
      _isListening = status == 'listening';
      if (status == 'done' || status == 'notListening') {
        _isListening = false;
        _soundLevel = 0.0;
      }
    });
  }

  void _onSpeechError(SpeechRecognitionError errorNotification) {
    if (!mounted) return;
    // Don't show scary error for simple no-match timeouts
    if (errorNotification.errorMsg == 'error_no_match') {
      setState(() {
        _isListening = false;
        _soundLevel = 0.0;
      });
      return;
    }
    setState(() {
      _speechError = errorNotification.errorMsg;
      _isListening = false;
      _soundLevel = 0.0;
    });
  }

  Future<void> _submitCommand(String commandText) async {
    if (_hasSubmitted || commandText.trim().isEmpty) return;
    _hasSubmitted = true;

    try {
      await _speechToText.stop();
    } catch (_) {}

    final targetId = _currentDeviceId ?? (widget.devices.isNotEmpty ? widget.devices.first.id : '');
    final deviceName = _selectedDevice?.name ?? 'Device';

    // 1. Invoke callback for command dispatch
    widget.onCommandExecuted(targetId, commandText.trim());

    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    // Pop the dialog
    Navigator.of(context).pop();

    // 2. Dispatch command to robot server via DeviceManager
    final result = await DeviceManager().executeVoiceCommand(targetId, commandText.trim());

    final isSuccess = result.success;
    final accentColor = isSuccess
        ? const Color(0xFF00E676)
        : (result.toolName != null ? AppTheme.primaryOrange : const Color(0xFFFF5252));

    // 3. Show execution feedback Toast (floating SnackBar)
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.darkCard,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: accentColor, width: 1.5),
        ),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accentColor.withAlpha(35),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSuccess
                    ? Icons.check
                    : (result.toolName != null ? Icons.warning_amber : Icons.help_outline),
                color: accentColor,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Voice: "$commandText"  •  $deviceName',
                    style: GoogleFonts.exo2(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    result.message,
                    style: GoogleFonts.exo2(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _speechToText.cancel();
    _fallbackTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Ensure _currentDeviceId is valid whenever devices list is available
    if (widget.devices.isNotEmpty) {
      if (_currentDeviceId == null || !widget.devices.any((d) => d.id == _currentDeviceId)) {
        _currentDeviceId = widget.devices.first.id;
      }
    }

    return Dialog(
      backgroundColor: AppTheme.modalBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: AppTheme.darkBorder, width: 1.5),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.all(24),
        child: AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState: _isListeningStep ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: _buildDeviceSelectionStep(),
          secondChild: _buildListeningStep(),
        ),
      ),
    );
  }

  /// Step 1: Device selection or empty state if no devices are connected
  Widget _buildDeviceSelectionStep() {
    // If no devices connected, show clear empty state — NEVER throw assertion error!
    if (widget.devices.isEmpty) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.primaryOrange.withAlpha(25),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.primaryOrange.withAlpha(80)),
            ),
            child: const Icon(
              Icons.sensors_off,
              color: AppTheme.primaryOrange,
              size: 32,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No Connected Devices',
            textAlign: TextAlign.center,
            style: GoogleFonts.exo2(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Voice commands require an active device connection. Connect a device from the discovery scan first.',
            textAlign: TextAlign.center,
            style: GoogleFonts.exo2(
              color: AppTheme.textMuted,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.radar, size: 20),
            label: Text(
              'Scan for Devices',
              style: GoogleFonts.exo2(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
              foregroundColor: AppTheme.textDarkButton,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DiscoveryScreen(),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: AppTheme.darkBorder, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              'Close',
              style: GoogleFonts.exo2(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Voice Command',
          textAlign: TextAlign.center,
          style: GoogleFonts.exo2(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose target device to receive command',
          textAlign: TextAlign.center,
          style: GoogleFonts.exo2(
            color: AppTheme.textMuted,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Target Device',
          style: GoogleFonts.exo2(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppTheme.primaryOrange,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.primaryOrange, width: 2),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _currentDeviceId,
              isExpanded: true,
              dropdownColor: AppTheme.darkCard,
              icon: const Icon(
                Icons.arrow_drop_down,
                color: AppTheme.primaryOrange,
                size: 32,
              ),
              items: widget.devices.map((device) {
                return DropdownMenuItem<String>(
                  value: device.id,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF00E676),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          device.name,
                          style: GoogleFonts.exo2(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        device.deviceType,
                        style: GoogleFonts.exo2(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _currentDeviceId = val);
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 28),
        ElevatedButton.icon(
          icon: const Icon(Icons.mic, size: 20),
          label: Text(
            'Start Listening',
            style: GoogleFonts.exo2(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDarkButton,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryOrange,
            foregroundColor: AppTheme.textDarkButton,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          onPressed: _startListeningFlow,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            side: const BorderSide(
              color: AppTheme.borderLavender,
              width: 1.8,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Text(
            'Close',
            style: GoogleFonts.exo2(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  /// Step 2: Listening view with real microphone-driven VoiceSphere & live transcription
  Widget _buildListeningStep() {
    final dev = _selectedDevice;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Target device chip header
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primaryOrange.withAlpha(90)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.devices, color: AppTheme.primaryOrange, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    dev?.name ?? 'Connected Device',
                    style: GoogleFonts.exo2(
                      color: AppTheme.primaryOrange,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _isListening ? 'Listening...' : (_recognizedText.isNotEmpty ? 'Processed' : 'Ready'),
          textAlign: TextAlign.center,
          style: GoogleFonts.exo2(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 14),

        // Reactive VoiceSphere listening to microphone sound input
        VoiceSphere(
          size: 190,
          audioLevel: _soundLevel,
          isListening: _isListening,
        ),
        const SizedBox(height: 16),

        // Live Recognized Speech Text Container
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.darkCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _recognizedText.isNotEmpty
                  ? AppTheme.primaryOrange
                  : AppTheme.darkBorder,
            ),
          ),
          child: Center(
            child: _recognizedText.isNotEmpty
                ? Text(
                    '"$_recognizedText"',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.exo2(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Text(
                    _speechError ?? 'Say something like "walk forward", "stop", or "take snapshot"...',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.exo2(
                      color: _speechError != null ? Colors.redAccent : AppTheme.textMuted,
                      fontSize: 13,
                    ),
                  ),
          ),
        ),

        // Manual text fallback if speech recognition error occurred
        if (_speechError != null) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _fallbackTextController,
                  style: GoogleFonts.exo2(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Type command manually...',
                    hintStyle: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12),
                    filled: true,
                    fillColor: AppTheme.darkBackground,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.darkBorder),
                    ),
                  ),
                  onSubmitted: (txt) => _submitCommand(txt),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send, color: AppTheme.primaryOrange),
                onPressed: () {
                  if (_fallbackTextController.text.trim().isNotEmpty) {
                    _submitCommand(_fallbackTextController.text.trim());
                  }
                },
              ),
            ],
          ),
        ],

        const SizedBox(height: 18),

        // Action Buttons: Send Command & Close
        if (_recognizedText.trim().isNotEmpty) ...[
          ElevatedButton.icon(
            icon: const Icon(Icons.check, size: 18),
            label: Text(
              'Send: "${_recognizedText.length > 20 ? '${_recognizedText.substring(0, 20)}...' : _recognizedText}"',
              style: GoogleFonts.exo2(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOrange,
              foregroundColor: AppTheme.textDarkButton,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => _submitCommand(_recognizedText.trim()),
          ),
          const SizedBox(height: 10),
        ],

        Row(
          children: [
            if (_isListening)
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.mic_off, size: 16),
                  label: Text('Stop Listening', style: GoogleFonts.exo2(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: AppTheme.darkBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    await _speechToText.stop();
                    if (mounted) setState(() => _isListening = false);
                  },
                ),
              )
            else
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text('Try Again', style: GoogleFonts.exo2(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryOrange,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: AppTheme.primaryOrange),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _startSpeechListening,
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  _speechToText.cancel();
                  Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(
                    color: AppTheme.borderLavender,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Close',
                  style: GoogleFonts.exo2(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
