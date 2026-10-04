import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/connection_state_enum.dart';
import '../../core/connection/device_connection.dart';
import '../../core/models/device_manifest.dart';
import '../../theme/app_theme.dart';

/// Exclusive header widget for the Robot / Quadruped profile.
/// Replaces the standard app bar with custom robot telemetry,
/// session control status, battery indicators, and emergency stop.
class RobotDashboardHeader extends StatelessWidget {
  final DeviceManifest? manifest;
  final DeviceConnection? conn;
  final VoidCallback onEmergencyStop;
  final VoidCallback onBack;
  final int? batteryLevel; // 0 - 100, null if no battery indicator
  final bool isControlSession;

  const RobotDashboardHeader({
    super.key,
    this.manifest,
    this.conn,
    required this.onEmergencyStop,
    required this.onBack,
    this.batteryLevel,
    this.isControlSession = true,
  });

  @override
  Widget build(BuildContext context) {
    final name = manifest?.name ?? 'Quadruped Bot';
    final state = conn?.state ?? DeviceConnectionState.connected;
    final isOnline = state == DeviceConnectionState.connected;

    Color batteryColor = AppTheme.primaryOrange;
    if (batteryLevel != null) {
      if (batteryLevel! > 50) {
        batteryColor = const Color(0xFF00E676);
      } else if (batteryLevel! <= 20) {
        batteryColor = Colors.redAccent;
      }
    }

    return Container(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1C21),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
        border: Border(
          bottom: BorderSide(
            color: AppTheme.primaryOrange.withAlpha(90),
            width: 1.5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(120),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Row: Back button, Title & Status, Emergency Stop
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                onPressed: onBack,
                tooltip: 'Back to devices',
              ),
              const SizedBox(width: 4),

              // Status dot + Name
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isOnline ? const Color(0xFF00E676) : Colors.grey,
                  boxShadow: isOnline
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00E676).withAlpha(180),
                            blurRadius: 8,
                            spreadRadius: 1,
                          )
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 8),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.exo2(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      isOnline ? 'Online · DCP v1.0' : state.label,
                      style: GoogleFonts.exo2(
                        fontSize: 12,
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),

              // Emergency Stop Button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onEmergencyStop,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.withAlpha(35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.redAccent, width: 1.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cancel, color: Colors.redAccent, size: 18),
                        const SizedBox(width: 6),
                        Text(
                          'E-STOP',
                          style: GoogleFonts.exo2(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Bottom Bar: Telemetry badges (Transport, Session Role, Battery)
          Row(
            children: [
              // Transport Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.darkBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.wifi, size: 13, color: AppTheme.primaryOrange),
                    const SizedBox(width: 6),
                    Text(
                      'Wi-Fi 8765',
                      style: GoogleFonts.exo2(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Session Ownership Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isControlSession
                      ? AppTheme.primaryOrange.withAlpha(30)
                      : Colors.grey.withAlpha(30),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isControlSession
                        ? AppTheme.primaryOrange
                        : Colors.grey,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isControlSession ? Icons.verified_user : Icons.remove_red_eye,
                      size: 13,
                      color: isControlSession ? AppTheme.primaryOrange : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isControlSession ? 'CONTROL' : 'READ ONLY',
                      style: GoogleFonts.exo2(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isControlSession ? AppTheme.primaryOrange : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Battery / Power status indicator
              if (batteryLevel != null)
                Row(
                  children: [
                    Icon(
                      batteryLevel! > 20 ? Icons.battery_full : Icons.battery_alert,
                      size: 18,
                      color: batteryColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$batteryLevel%',
                      style: GoogleFonts.exo2(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: batteryColor,
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    const Icon(
                      Icons.power,
                      size: 15,
                      color: Color(0xFF00E676),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'DC In',
                      style: GoogleFonts.exo2(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF00E676),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
