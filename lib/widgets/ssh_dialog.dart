import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class SSHDialog extends StatefulWidget {
  final String initialHostname;
  final String initialUsername;
  final String initialPassword;
  final int initialPort;
  final bool initialSaveCredentials;
  final bool showSaveCheckbox;
  final Function(String hostname, String password)? onConnect;
  final Function(String hostname, String username, String password, int port)? onConnectDetailed;
  final Function(String hostname, String username, String password, int port, bool saveCredentials)? onConnectDetailedWithSave;

  const SSHDialog({
    super.key,
    this.initialHostname = '',
    this.initialUsername = 'pi',
    this.initialPassword = '',
    this.initialPort = 22,
    this.initialSaveCredentials = true,
    this.showSaveCheckbox = true,
    this.onConnect,
    this.onConnectDetailed,
    this.onConnectDetailedWithSave,
  });

  @override
  State<SSHDialog> createState() => _SSHDialogState();
}

class _SSHDialogState extends State<SSHDialog> {
  late final TextEditingController _hostnameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _portController;
  bool _obscurePassword = true;
  bool _saveCredentials = true;

  @override
  void initState() {
    super.initState();
    _saveCredentials = widget.initialSaveCredentials;
    _hostnameController = TextEditingController(text: widget.initialHostname);
    _usernameController = TextEditingController(text: widget.initialUsername);
    _passwordController = TextEditingController(text: widget.initialPassword);
    _portController = TextEditingController(text: widget.initialPort.toString());
  }

  @override
  void dispose() {
    _hostnameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _portController.dispose();
    super.dispose();
  }

  void _handleConnect() {
    String rawHost = _hostnameController.text.trim();
    String username = _usernameController.text.trim();
    String password = _passwordController.text;
    int port = int.tryParse(_portController.text.trim()) ?? 22;

    // Smart-parse if user typed username@host:port in the hostname field
    if (rawHost.contains('@')) {
      final parts = rawHost.split('@');
      if (parts.length == 2) {
        if (parts[0].isNotEmpty) username = parts[0];
        rawHost = parts[1];
      }
    }
    if (rawHost.contains(':')) {
      final parts = rawHost.split(':');
      if (parts.length == 2) {
        rawHost = parts[0];
        port = int.tryParse(parts[1]) ?? port;
      }
    }

    if (rawHost.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a valid hostname or IP address', style: GoogleFonts.exo2()),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    Navigator.of(context).pop();

    if (widget.onConnectDetailedWithSave != null) {
      widget.onConnectDetailedWithSave!(rawHost, username, password, port, _saveCredentials);
    } else if (widget.onConnectDetailed != null) {
      widget.onConnectDetailed!(rawHost, username, password, port);
    } else if (widget.onConnect != null) {
      widget.onConnect!(rawHost, password);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.modalBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppTheme.darkBorder, width: 1.5),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryOrange.withAlpha(35),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.terminal, color: AppTheme.primaryOrange, size: 24),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'SSH Shell',
                    style: GoogleFonts.exo2(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Hostname & Port row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hostname / IP',
                          style: GoogleFonts.exo2(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryOrange,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _hostnameController,
                          style: GoogleFonts.exo2(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: '192.168.1.100',
                            hintStyle: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 13),
                            filled: true,
                            fillColor: AppTheme.darkCard,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: AppTheme.primaryOrange, width: 1.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: AppTheme.accentOrange, width: 2),
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
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryOrange,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _portController,
                          keyboardType: TextInputType.number,
                          style: GoogleFonts.exo2(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: '22',
                            hintStyle: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 13),
                            filled: true,
                            fillColor: AppTheme.darkCard,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: AppTheme.primaryOrange, width: 1.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: AppTheme.accentOrange, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Username field
              Text(
                'Username',
                style: GoogleFonts.exo2(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryOrange,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _usernameController,
                style: GoogleFonts.exo2(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'pi',
                  hintStyle: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 13),
                  filled: true,
                  fillColor: AppTheme.darkCard,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.primaryOrange, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.accentOrange, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Password field
              Text(
                'Password',
                style: GoogleFonts.exo2(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryOrange,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: GoogleFonts.exo2(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Enter password',
                  hintStyle: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 13),
                  filled: true,
                  fillColor: AppTheme.darkCard,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: AppTheme.textMuted,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.primaryOrange, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.accentOrange, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              if (widget.showSaveCheckbox)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () => setState(() => _saveCredentials = !_saveCredentials),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: Checkbox(
                            value: _saveCredentials,
                            activeColor: AppTheme.primaryOrange,
                            onChanged: (val) => setState(() => _saveCredentials = val ?? false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Save credentials for this device',
                            style: GoogleFonts.exo2(color: Colors.white, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              ElevatedButton.icon(
                icon: const Icon(Icons.login, size: 20),
                label: Text(
                  'Connect Shell',
                  style: GoogleFonts.exo2(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textDarkButton,
                  ),
                ),
                onPressed: _handleConnect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOrange,
                  foregroundColor: AppTheme.textDarkButton,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
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
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
