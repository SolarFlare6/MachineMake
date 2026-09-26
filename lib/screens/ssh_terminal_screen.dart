import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:xterm/xterm.dart';

import '../theme/app_theme.dart';

/// Full interactive SSH terminal window powered by dartssh2 and xterm.
/// Establishes an SSH connection with a remote host and displays an interactive shell.
/// Shows a Toast notification whenever the SSH session terminates.
class SshTerminalScreen extends StatefulWidget {
  final String host;
  final int port;
  final String username;
  final String password;
  final String? deviceName;

  const SshTerminalScreen({
    super.key,
    required this.host,
    this.port = 22,
    this.username = 'pi',
    required this.password,
    this.deviceName,
    this.autoConnect = true,
  });

  final bool autoConnect;

  @override
  State<SshTerminalScreen> createState() => _SshTerminalScreenState();
}

class _SshTerminalScreenState extends State<SshTerminalScreen> {
  late final Terminal _terminal;
  final TerminalController _terminalController = TerminalController();

  SSHClient? _client;
  SSHSession? _session;
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;

  bool _isConnecting = false;
  bool _isConnected = false;
  String _status = 'Initializing...';
  bool _hasTerminated = false;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 2500);

    // Forward terminal keyboard input to remote SSH shell
    _terminal.onOutput = (data) {
      if (_session != null && _isConnected) {
        _session!.stdin.add(utf8.encode(data));
      }
    };

    // Forward terminal viewport resize to remote pty
    _terminal.onResize = (width, height, pixelWidth, pixelHeight) {
      if (_session != null && _isConnected) {
        _session!.resizeTerminal(width, height, pixelWidth, pixelHeight);
      }
    };

    if (widget.autoConnect) {
      _connect();
    }
  }

  Future<void> _connect() async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _isConnected = false;
      _status = 'Connecting...';
      _hasTerminated = false;
    });

    _terminal.write('\x1b[36mConnecting to ${widget.username}@${widget.host}:${widget.port}...\x1b[0m\r\n');

    try {
      final socket = await SSHSocket.connect(
        widget.host,
        widget.port,
        timeout: const Duration(seconds: 12),
      );

      _client = SSHClient(
        socket,
        username: widget.username,
        onPasswordRequest: () => widget.password,
      );

      _terminal.write('\x1b[33mAuthenticating credentials...\x1b[0m\r\n');

      final session = await _client!.shell(
        pty: SSHPtyConfig(
          width: _terminal.viewWidth > 0 ? _terminal.viewWidth : 80,
          height: _terminal.viewHeight > 0 ? _terminal.viewHeight : 25,
        ),
      );

      _session = session;

      _terminal.write('\x1b[32mSSH interactive shell ready.\x1b[0m\r\n\r\n');

      if (mounted) {
        setState(() {
          _isConnected = true;
          _isConnecting = false;
          _status = 'Connected';
        });
      }

      // Stream remote stdout to local terminal
      _stdoutSub = session.stdout.listen(
        (data) {
          _terminal.write(utf8.decode(data, allowMalformed: true));
        },
        onError: (err) {
          _terminal.write('\r\n\x1b[31m[Stdout error: $err]\x1b[0m\r\n');
        },
      );

      // Stream remote stderr to local terminal
      _stderrSub = session.stderr.listen(
        (data) {
          _terminal.write(utf8.decode(data, allowMalformed: true));
        },
        onError: (err) {
          _terminal.write('\r\n\x1b[31m[Stderr error: $err]\x1b[0m\r\n');
        },
      );

      // Watch for remote session termination (e.g. `exit` or disconnect)
      session.done.then((_) {
        _handleSessionTerminated('Session completed by remote host');
      }).catchError((e) {
        _handleSessionTerminated('Session ended with error: $e');
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _isConnected = false;
          _status = 'Failed';
        });
      }
      _terminal.write('\r\n\x1b[31m[Connection error: $e]\x1b[0m\r\n');
      _handleSessionTerminated('Connection failed: $e');
    }
  }

  void _handleSessionTerminated(String reason) {
    if (_hasTerminated) return;
    _hasTerminated = true;

    if (mounted) {
      setState(() {
        _isConnected = false;
        _isConnecting = false;
        _status = 'Terminated';
      });
    }

    _terminal.write('\r\n\x1b[33m--- $reason ---\x1b[0m\r\n');

    // Show Toast notification when the session terminates
    _showTerminationToast(reason);
  }

  void _showTerminationToast(String reason) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppTheme.darkCard,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppTheme.primaryOrange, width: 1.5),
        ),
        duration: const Duration(seconds: 4),
        content: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.amberAccent.withAlpha(35),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.terminal,
                color: Colors.amberAccent,
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
                    'SSH Session Terminated',
                    style: GoogleFonts.exo2(
                      color: Colors.amberAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Connection to ${widget.host} closed',
                    style: GoogleFonts.exo2(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendRawInput(String input) {
    if (_session != null && _isConnected) {
      _session!.stdin.add(utf8.encode(input));
    }
  }

  void _clearTerminal() {
    _terminal.buffer.clear();
    _terminal.write('\x1b[2J\x1b[H');
  }

  @override
  void dispose() {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _session?.close();
    _client?.close();
    _terminalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.deviceName ?? '${widget.username}@${widget.host}';

    return Scaffold(
      backgroundColor: const Color(0xFF0F1012),
      appBar: AppBar(
        backgroundColor: AppTheme.darkSurface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.exo2(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isConnected
                        ? const Color(0xFF00E676)
                        : (_isConnecting ? AppTheme.primaryOrange : Colors.redAccent),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${widget.host}:${widget.port} • $_status',
                  style: GoogleFonts.exo2(
                    fontSize: 11,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear terminal',
            icon: const Icon(Icons.cleaning_services_outlined, color: AppTheme.textMuted, size: 20),
            onPressed: _clearTerminal,
          ),
          if (!_isConnected && !_isConnecting)
            IconButton(
              tooltip: 'Reconnect',
              icon: const Icon(Icons.refresh, color: AppTheme.primaryOrange),
              onPressed: _connect,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Terminal Viewport
            Expanded(
              child: Container(
                color: const Color(0xFF0C0D0E),
                child: TerminalView(
                  _terminal,
                  controller: _terminalController,
                  autofocus: true,
                  backgroundOpacity: 1.0,
                  textStyle: const TerminalStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                  theme: const TerminalTheme(
                    cursor: AppTheme.primaryOrange,
                    selection: Color(0x66F37032),
                    foreground: Color(0xFFE6E6E6),
                    background: Color(0xFF0C0D0E),
                    black: Color(0xFF000000),
                    red: Color(0xFFFF5252),
                    green: Color(0xFF00E676),
                    yellow: Color(0xFFFFD740),
                    blue: Color(0xFF448AFF),
                    magenta: Color(0xFFFF4081),
                    cyan: Color(0xFF18FFFF),
                    white: Color(0xFFFFFFFF),
                    brightBlack: Color(0xFF757575),
                    brightRed: Color(0xFFFF1744),
                    brightGreen: Color(0xFF00E676),
                    brightYellow: Color(0xFFFFEA00),
                    brightBlue: Color(0xFF2979FF),
                    brightMagenta: Color(0xFFF50057),
                    brightCyan: Color(0xFF00E5FF),
                    brightWhite: Color(0xFFFFFFFF),
                    searchHitBackground: Color(0x80F37032),
                    searchHitBackgroundCurrent: AppTheme.primaryOrange,
                    searchHitForeground: Color(0xFF000000),
                  ),
                ),
              ),
            ),

            // Virtual Keyboard Quick Keys Bar (mobile touch convenience)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: const BoxDecoration(
                color: AppTheme.darkSurface,
                border: Border(
                  top: BorderSide(color: AppTheme.darkBorder, width: 1),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _buildQuickKey('ESC', () => _sendRawInput('\x1b')),
                    _buildQuickKey('TAB', () => _sendRawInput('\t')),
                    _buildQuickKey('Ctrl+C', () => _sendRawInput('\x03')),
                    _buildQuickKey('Ctrl+D', () => _sendRawInput('\x04')),
                    _buildQuickKey('▲', () => _sendRawInput('\x1b[A')),
                    _buildQuickKey('▼', () => _sendRawInput('\x1b[B')),
                    _buildQuickKey('◀', () => _sendRawInput('\x1b[D')),
                    _buildQuickKey('▶', () => _sendRawInput('\x1b[C')),
                    _buildQuickKey('ENTER', () => _sendRawInput('\r')),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickKey(String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Text(
              label,
              style: GoogleFonts.exo2(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
