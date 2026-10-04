import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/device_manager.dart';
import '../services/device_registry.dart';
import '../theme/app_theme.dart';
import '../widgets/device_icons.dart';
import 'discovery_screen.dart';

/// Screen where users can view paired devices and delete saved credentials.
class DeviceManagerScreen extends StatefulWidget {
  const DeviceManagerScreen({super.key});

  @override
  State<DeviceManagerScreen> createState() => _DeviceManagerScreenState();
}

class _DeviceManagerScreenState extends State<DeviceManagerScreen> {
  final DeviceManager _deviceManager = DeviceManager();
  final DeviceRegistry _registry = DeviceRegistry();

  @override
  void initState() {
    super.initState();
    _deviceManager.addListener(_onStateChange);
    _registry.addListener(_onStateChange);
  }

  @override
  void dispose() {
    _deviceManager.removeListener(_onStateChange);
    _registry.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  void _confirmDeleteDevice(String deviceId, String deviceName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.modalBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.delete_forever, color: Colors.redAccent, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Delete Credentials',
                style: GoogleFonts.exo2(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete saved pairing credentials for "$deviceName" ($deviceId)?\n\nThis will disconnect the device and remove its authentication keys.',
          style: GoogleFonts.exo2(
            fontSize: 14,
            color: AppTheme.textMuted,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.exo2(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _deviceManager.removeDevice(deviceId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Credentials for $deviceName deleted.'),
                    backgroundColor: AppTheme.primaryOrange,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Delete',
              style: GoogleFonts.exo2(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showSshCredentialsDialog(String deviceId, String deviceName) {
    final known = _registry.findById(deviceId);
    final live = _deviceManager.allPairedDevices
        .where((d) => d.id == deviceId)
        .firstOrNull;
    final cfg = _deviceManager.getSSHConfig(deviceId);

    final initialHost = (known?.lastIp != null && known!.lastIp!.isNotEmpty)
        ? known.lastIp!
        : (live?.ipAddress ?? (cfg.hostname.isNotEmpty ? cfg.hostname : '192.168.1.102'));
    final initialPort = known?.sshPort ?? cfg.port;
    final initialUser = (known?.sshUsername != null && known!.sshUsername!.isNotEmpty)
        ? known.sshUsername!
        : (cfg.username.isNotEmpty ? cfg.username : 'pi');
    final initialPass = known?.sshPassword ?? cfg.password;
    final hasStored = _deviceManager.hasSavedSshCredentials(deviceId);

    final hostCtrl = TextEditingController(text: initialHost);
    final portCtrl = TextEditingController(text: initialPort.toString());
    final userCtrl = TextEditingController(text: initialUser);
    final passCtrl = TextEditingController(text: initialPass);
    bool obscurePass = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: AppTheme.modalBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppTheme.darkBorder, width: 1.5),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(22),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryOrange.withAlpha(30),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.terminal, color: AppTheme.primaryOrange, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'SSH Credentials',
                              style: GoogleFonts.exo2(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            Text(
                              deviceName,
                              style: GoogleFonts.exo2(
                                fontSize: 12,
                                color: AppTheme.primaryOrange,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Host & Port Row
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Host / IP',
                              style: GoogleFonts.exo2(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryOrange,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: hostCtrl,
                              style: GoogleFonts.exo2(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: '192.168.1.100',
                                hintStyle: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12),
                                filled: true,
                                fillColor: AppTheme.darkCard,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: AppTheme.darkBorder),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: AppTheme.primaryOrange),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Port',
                              style: GoogleFonts.exo2(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryOrange,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: portCtrl,
                              keyboardType: TextInputType.number,
                              style: GoogleFonts.exo2(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: '22',
                                hintStyle: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12),
                                filled: true,
                                fillColor: AppTheme.darkCard,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: AppTheme.darkBorder),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(color: AppTheme.primaryOrange),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Username
                  Text(
                    'Username',
                    style: GoogleFonts.exo2(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryOrange,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: userCtrl,
                    style: GoogleFonts.exo2(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'pi',
                      hintStyle: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12),
                      filled: true,
                      fillColor: AppTheme.darkCard,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.darkBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppTheme.primaryOrange),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Password
                  Text(
                    'Password',
                    style: GoogleFonts.exo2(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryOrange,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscurePass,
                    style: GoogleFonts.exo2(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Enter SSH password',
                      hintStyle: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12),
                      filled: true,
                      fillColor: AppTheme.darkCard,
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscurePass ? Icons.visibility_off : Icons.visibility,
                          color: AppTheme.textMuted,
                          size: 18,
                        ),
                        onPressed: () => setDialogState(() => obscurePass = !obscurePass),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: AppTheme.darkBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: AppTheme.primaryOrange),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Actions
                  ElevatedButton(
                    onPressed: () async {
                      final host = hostCtrl.text.trim();
                      final user = userCtrl.text.trim();
                      final pass = passCtrl.text;
                      final port = int.tryParse(portCtrl.text.trim()) ?? 22;

                      if (user.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Please specify a username', style: GoogleFonts.exo2()),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }

                      await _deviceManager.saveSshCredentials(
                        deviceId,
                        username: user,
                        password: pass,
                        hostname: host,
                        port: port,
                      );

                      if (ctx.mounted) Navigator.of(ctx).pop();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('SSH credentials saved for $deviceName', style: GoogleFonts.exo2()),
                            backgroundColor: AppTheme.primaryOrange,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryOrange,
                      foregroundColor: AppTheme.textDarkButton,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      hasStored ? 'Update Credentials' : 'Save Credentials',
                      style: GoogleFonts.exo2(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 8),

                  if (hasStored) ...[
                    OutlinedButton(
                      onPressed: () async {
                        await _deviceManager.removeSshCredentials(deviceId);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('SSH credentials removed for $deviceName', style: GoogleFonts.exo2()),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Remove SSH Credentials',
                        style: GoogleFonts.exo2(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.exo2(color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmClearAllCredentials() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.modalBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Delete All Credentials',
                style: GoogleFonts.exo2(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'This will remove saved pairing credentials for ALL devices. You will need to pair again to control them.\n\nContinue?',
          style: GoogleFonts.exo2(
            fontSize: 14,
            color: AppTheme.textMuted,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.exo2(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _deviceManager.clearAllDevices();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('All device credentials removed.'),
                    backgroundColor: AppTheme.primaryOrange,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Clear All',
              style: GoogleFonts.exo2(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final knownDevices = _registry.devices;
    final liveDevices = _deviceManager.allPairedDevices;

    // Collect all unique device IDs
    final allIds = <String>{
      ...knownDevices.map((d) => d.deviceId),
      ...liveDevices.map((d) => d.id),
    }.toList();

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkSurface,
        title: Text(
          'Device Manager',
          style: GoogleFonts.exo2(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: allIds.isEmpty ? _buildEmptyState() : _buildDeviceList(allIds),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primaryOrange.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.devices_other,
                size: 40,
                color: AppTheme.primaryOrange,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Saved Credentials',
              style: GoogleFonts.exo2(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You have no paired devices or saved credentials.\nScan a QR code or search the network to pair.',
              textAlign: TextAlign.center,
              style: GoogleFonts.exo2(
                fontSize: 14,
                color: AppTheme.textMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const DiscoveryScreen()),
                );
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(
                'Scan & Pair Device',
                style: GoogleFonts.exo2(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryOrange,
                foregroundColor: AppTheme.textDarkButton,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceList(List<String> deviceIds) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Saved Devices (${deviceIds.length})',
              style: GoogleFonts.exo2(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryOrange,
              ),
            ),
            TextButton.icon(
              onPressed: _confirmClearAllCredentials,
              icon: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 20),
              label: Text(
                'Clear All',
                style: GoogleFonts.exo2(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...deviceIds.map((id) {
          final known = _registry.findById(id);
          final live = _deviceManager.allPairedDevices
              .where((d) => d.id == id)
              .firstOrNull;

          final name = live?.name ?? known?.name ?? id;
          final profile = live?.profile ?? known?.type ?? 'quadruped';
          final address = live?.ipAddress ?? known?.lastIp ?? 'Direct';
          final port = live?.port ?? known?.lastPort ?? 8765;
          final isConnected = live?.isConnected ?? false;
          final hasPsk = known?.psk != null && known!.psk!.isNotEmpty;
          final hasSsh = _deviceManager.hasSavedSshCredentials(id);
          final sshUser = known?.sshUsername;

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isConnected
                    ? const Color(0xFF00E676).withAlpha(120)
                    : AppTheme.darkBorder,
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Icon + Name + Status Badge + Actions (SSH & Delete)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    DeviceProfileIcon(
                      iconKey: profile,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  style: GoogleFonts.exo2(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isConnected
                                      ? const Color(0xFF00E676).withAlpha(30)
                                      : Colors.white.withAlpha(15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isConnected
                                        ? const Color(0xFF00E676).withAlpha(80)
                                        : Colors.white.withAlpha(20),
                                  ),
                                ),
                                child: Text(
                                  isConnected ? 'Connected' : 'Saved',
                                  style: GoogleFonts.exo2(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isConnected
                                        ? const Color(0xFF00E676)
                                        : AppTheme.textMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'ID: $id',
                            style: GoogleFonts.exo2(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Action Buttons
                    IconButton(
                      tooltip: 'Manage SSH credentials',
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        Icons.terminal,
                        size: 22,
                        color: hasSsh ? AppTheme.primaryOrange : AppTheme.textMuted,
                      ),
                      onPressed: () => _showSshCredentialsDialog(id, name),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Delete credentials',
                      padding: const EdgeInsets.all(6),
                      constraints: const BoxConstraints(),
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 22,
                        color: Colors.redAccent,
                      ),
                      onPressed: () => _confirmDeleteDevice(id, name),
                    ),
                  ],
                ),

                const SizedBox(height: 10),
                const Divider(height: 1, color: AppTheme.darkBorder),
                const SizedBox(height: 10),

                // Middle Row: IP & PSK badge
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wifi,
                          size: 13,
                          color: AppTheme.primaryOrange.withAlpha(180),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '$address:$port',
                          style: GoogleFonts.exo2(
                            fontSize: 12,
                            color: AppTheme.primaryOrange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    if (hasPsk)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withAlpha(25),
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: Colors.amber.withAlpha(80)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.key,
                              size: 11,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'PSK Saved',
                              style: GoogleFonts.exo2(
                                fontSize: 10,
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 8),

                // Bottom Row: SSH Credentials button / pill
                InkWell(
                  onTap: () => _showSshCredentialsDialog(id, name),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: hasSsh
                          ? AppTheme.primaryOrange.withAlpha(20)
                          : Colors.white.withAlpha(8),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: hasSsh
                            ? AppTheme.primaryOrange.withAlpha(100)
                            : AppTheme.darkBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.vpn_key_outlined,
                          size: 13,
                          color: hasSsh
                              ? AppTheme.primaryOrange
                              : AppTheme.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          hasSsh ? 'SSH: $sshUser (Saved)' : 'Set SSH Credentials',
                          style: GoogleFonts.exo2(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: hasSsh
                                ? AppTheme.primaryOrange
                                : AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          hasSsh ? Icons.edit : Icons.add_circle_outline,
                          size: 12,
                          color: hasSsh
                              ? AppTheme.primaryOrange
                              : AppTheme.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
