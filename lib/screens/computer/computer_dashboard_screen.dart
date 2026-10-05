import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../core/models/device_manifest.dart';
import '../../models/dcp_models.dart';
import '../../services/device_manager.dart';
import '../../theme/app_theme.dart';
import '../../widgets/ssh_dialog.dart';
import '../../widgets/telemetry_gauge.dart';
import '../ssh_terminal_screen.dart';
import 'computer_mapping_tab.dart';

/// Specialized dashboard for computer / SBC profiles (Raspberry Pi, PC, Laptop).
/// Features:
/// - Tab 0 (System): Telemetry gauges (CPU, RAM, GPU, Temp), system operations (Reboot, Shutdown), SSH terminal.
/// - Tab 1 (Mapping): Remote mouse trackpad, virtual keyboard typing & shortcuts, workstation lock, media control.
class ComputerDashboardScreen extends StatefulWidget {
  final DeviceItem device;
  final DeviceConnection? conn;
  final DeviceManifest? manifest;

  const ComputerDashboardScreen({
    super.key,
    required this.device,
    this.conn,
    this.manifest,
  });

  @override
  State<ComputerDashboardScreen> createState() => _ComputerDashboardScreenState();
}

class _ComputerDashboardScreenState extends State<ComputerDashboardScreen> {
  final DeviceManager _deviceManager = DeviceManager();
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    // Rebuild whenever DeviceManager receives new telemetry events.
    _deviceManager.addListener(_onManagerChange);
  }

  @override
  void dispose() {
    _deviceManager.removeListener(_onManagerChange);
    super.dispose();
  }

  void _onManagerChange() {
    if (mounted) setState(() {});
  }

  void _openSsh() {
    final cfg = _deviceManager.getSSHConfig(widget.device.id);
    final defaultHost = cfg.hostname.isNotEmpty
        ? cfg.hostname
        : (widget.device.ipAddress ?? '');

    showDialog(
      context: context,
      builder: (_) => SSHDialog(
        initialHostname: defaultHost,
        initialUsername: cfg.username.isNotEmpty ? cfg.username : 'pi',
        initialPassword: cfg.password,
        initialPort: cfg.port,
        onConnectDetailed: (hostname, username, password, port) {
          _deviceManager.saveSSHConfig(
            widget.device.id,
            hostname,
            password,
            username: username,
            port: port,
          );

          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SshTerminalScreen(
                host: hostname,
                port: port,
                username: username,
                password: password,
                deviceName: widget.device.name,
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmSystemAction(String actionTitle, String command) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.modalBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.darkBorder),
        ),
        title: Text(actionTitle, style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to $actionTitle on ${widget.device.name}?', style: GoogleFonts.exo2(color: AppTheme.textMuted)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('Cancel', style: GoogleFonts.exo2(color: Colors.white70))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryOrange, foregroundColor: AppTheme.textDarkButton),
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.conn?.session?.executeTool(command, {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Command sent: $command', style: GoogleFonts.exo2()), backgroundColor: AppTheme.primaryOrange),
              );
            },
            child: Text('Confirm', style: GoogleFonts.exo2(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkSurface,
        title: Text(
          widget.device.name,
          style: GoogleFonts.exo2(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.terminal, color: AppTheme.primaryOrange),
            tooltip: 'Open SSH Shell',
            onPressed: _openSsh,
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          _buildSystemTab(),
          ComputerMappingTab(
            device: widget.device,
            conn: widget.conn,
          ),
        ],
      ),
      bottomNavigationBar: isKeyboardOpen ? null : _buildBottomNav(),
    );
  }

  // ── Tab 0: System & Telemetry Tab ─────────────────────────────────
  Widget _buildSystemTab() {
    final telemetry = _deviceManager.getTelemetry(widget.device.id);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Device Info Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryOrange.withAlpha(35),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.computer, color: AppTheme.primaryOrange, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.device.deviceType,
                        style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 13),
                      ),
                      Text(
                        widget.device.ipAddress != null
                            ? 'IP: ${widget.device.ipAddress}'
                            : 'Connected over ${widget.device.selectedTransport.toUpperCase()}',
                        style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF00E676).withAlpha(120)),
                  ),
                  child: Text('Online', style: GoogleFonts.exo2(color: const Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
          Text('System Telemetry', style: GoogleFonts.exo2(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 14),

          // Gauges (CPU, RAM, GPU, Temp)
          Row(
            children: [
              Expanded(child: TelemetryGauge(value: telemetry.cpuUsage, label: 'CPU', displayValue: '${telemetry.cpuUsage.toStringAsFixed(0)}%', color: AppTheme.cpuOrange)),
              const SizedBox(width: 14),
              Expanded(child: TelemetryGauge(value: telemetry.ramUsage, label: 'RAM', displayValue: '${telemetry.ramUsage.toStringAsFixed(0)}%', color: AppTheme.ramPink)),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TelemetryGauge(
                  value: telemetry.gpuUsage,
                  label: 'GPU',
                  displayValue: telemetry.gpuUsage != null
                      ? '${telemetry.gpuUsage!.toStringAsFixed(0)}%'
                      : 'N/A',
                  color: AppTheme.gpuCyan,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: TelemetryGauge(
                  value: telemetry.temperature,
                  label: 'Temp',
                  displayValue: '${telemetry.temperature.toStringAsFixed(0)}°C',
                  color: AppTheme.tempBlue,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          Text('System Operations', style: GoogleFonts.exo2(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 14),

          // Quick Operations
          _buildActionTile(icon: Icons.terminal, title: 'Open SSH Terminal', subtitle: 'Launch remote command line interface', color: AppTheme.primaryOrange, onTap: _openSsh),
          const SizedBox(height: 10),
          _buildActionTile(icon: Icons.restart_alt, title: 'Reboot System', subtitle: 'Soft reboot the operating system', color: Colors.amberAccent, onTap: () => _confirmSystemAction('Reboot System', 'system_reboot')),
          const SizedBox(height: 10),
          _buildActionTile(icon: Icons.power_settings_new, title: 'Shutdown Host', subtitle: 'Safely halt and power down the device', color: Colors.redAccent, onTap: () => _confirmSystemAction('Shutdown Host', 'system_shutdown')),
        ],
      ),
    );
  }

  // ── Bottom Navigation Bar ─────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1C21),
        border: Border(
          top: BorderSide(color: AppTheme.darkBorder, width: 1.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.computer, 'System'),
              _buildNavItem(1, Icons.tune, 'Mapping'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _currentTabIndex = index),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? AppTheme.primaryOrange : AppTheme.textMuted,
              size: 22,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.exo2(
                color: isSelected ? AppTheme.primaryOrange : AppTheme.textMuted,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(title, style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text(subtitle, style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
        onTap: onTap,
      ),
    );
  }
}
