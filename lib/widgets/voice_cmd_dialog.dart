import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/dcp_models.dart';
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
  late String _currentDeviceId;
  bool _isListeningStep = false;

  @override
  void initState() {
    super.initState();
    _currentDeviceId = widget.selectedDeviceId;
    if (widget.devices.isNotEmpty &&
        !widget.devices.any((d) => d.id == _currentDeviceId)) {
      _currentDeviceId = widget.devices.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.modalBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: AppTheme.darkBorder, width: 1.5),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 360),
        padding: const EdgeInsets.all(24),
        child: AnimatedCrossFade(
          duration: const Duration(milliseconds: 250),
          crossFadeState: _isListeningStep
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: _buildDeviceSelectionStep(),
          secondChild: _buildListeningStep(),
        ),
      ),
    );
  }

  Widget _buildDeviceSelectionStep() {
    final activeDevices = widget.devices.isEmpty
        ? [
            DeviceItem(
              id: 'quad-001',
              name: 'Quadruped bot',
              profile: 'quadruped',
              deviceType: 'Robot',
              availableTransports: ['wifi'],
              iconKey: 'quadruped',
            )
          ]
        : widget.devices;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Voice command',
          textAlign: TextAlign.center,
          style: GoogleFonts.exo2(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Device',
          style: GoogleFonts.exo2(
            fontSize: 18,
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
              items: activeDevices.map((device) {
                return DropdownMenuItem<String>(
                  value: device.id,
                  child: Text(
                    device.name,
                    style: GoogleFonts.exo2(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
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
        ElevatedButton(
          onPressed: () {
            setState(() => _isListeningStep = true);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primaryOrange,
            foregroundColor: AppTheme.textDarkButton,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: Text(
            'Select',
            style: GoogleFonts.exo2(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.textDarkButton,
            ),
          ),
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
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListeningStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Listening',
          textAlign: TextAlign.center,
          style: GoogleFonts.exo2(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        const VoiceSphere(size: 200),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            minimumSize: const Size(double.infinity, 50),
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
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
