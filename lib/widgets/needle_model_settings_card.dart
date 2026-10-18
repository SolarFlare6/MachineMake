import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/llm_model_manager.dart';
import '../services/needle_ai_service.dart';
import '../theme/app_theme.dart';

/// Settings card allowing the user to download, pause/resume, test, or delete
/// the optional on-device `SmolLM2-360M-Instruct` (`Q4_K_M`, ~271 MB) model.
class NeedleModelSettingsCard extends StatefulWidget {
  const NeedleModelSettingsCard({super.key});

  @override
  State<NeedleModelSettingsCard> createState() =>
      _NeedleModelSettingsCardState();
}

class _NeedleModelSettingsCardState extends State<NeedleModelSettingsCard> {
  final LlmModelManager _manager = LlmModelManager.instance;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onManagerUpdate);
    AppTheme.accentColorNotifier.addListener(_onManagerUpdate);
    _manager.refreshDiskState();
  }

  @override
  void dispose() {
    AppTheme.accentColorNotifier.removeListener(_onManagerUpdate);
    _manager.removeListener(_onManagerUpdate);
    super.dispose();
  }

  void _onManagerUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmAndDeleteModel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.modalBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.redAccent, width: 1.2),
        ),
        title: Row(
          children: [
            const Icon(Icons.delete_outline, color: Colors.redAccent, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Delete Local AI Model?',
                style: GoogleFonts.exo2(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'This will unload SmolLM2-360M-Instruct from memory and delete the ~271 MB model file from your phone.\n\n'
          'Voice commands will seamlessly fall back to Stage 1 Fast Rules (0 MB) and connected device servers. You can re-download the model anytime.',
          style: GoogleFonts.exo2(
            fontSize: 13.5,
            color: AppTheme.textMuted,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.exo2(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Delete (Free ~271 MB)',
              style: GoogleFonts.exo2(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _manager.deleteModel();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Local AI model deleted. Switched to Fast Rules (0 MB) mode.',
              style: GoogleFonts.exo2(fontWeight: FontWeight.w600),
            ),
            backgroundColor: AppTheme.primaryOrange,
          ),
        );
      }
    }
  }

  Future<void> _runSelfTest() async {
    setState(() => _isTesting = true);
    try {
      final report = await NeedleAiService.instance.runDiagnosticTest();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.modalBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppTheme.primaryOrange, width: 1.4),
          ),
          title: Row(
            children: [
              Icon(Icons.psychology, color: AppTheme.primaryOrange, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Needle AI Diagnostic Test',
                  style: GoogleFonts.exo2(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          content: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Text(
              report,
              style: GoogleFonts.exo2(
                fontSize: 13,
                color: Colors.white,
                height: 1.5,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Close',
                style: GoogleFonts.exo2(
                  color: AppTheme.primaryOrange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _manager.state;
    final spec = _manager.modelSpec;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.darkBorder,
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Model Title & Status Pill
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primaryOrange.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.psychology_alt,
                  color: AppTheme.primaryOrange,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Offline Voice AI (${spec.displayName})',
                      style: GoogleFonts.exo2(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${spec.quantization}  •  ~${spec.formattedSizeMb} GGUF',
                      style: GoogleFonts.exo2(
                        fontSize: 12,
                        color: AppTheme.primaryOrange,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _buildStateBadge(state),
            ],
          ),
          const SizedBox(height: 12),

          Text(
            spec.description,
            style: GoogleFonts.exo2(
              fontSize: 13,
              color: AppTheme.textMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),

          // Active Engine Status Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.darkBorder),
            ),
            child: Row(
              children: [
                Icon(
                  _manager.isReadyForInference
                      ? Icons.bolt
                      : Icons.rule_folder_outlined,
                  size: 16,
                  color: _manager.isReadyForInference
                      ? const Color(0xFF00E676)
                      : AppTheme.primaryOrange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _manager.isReadyForInference
                        ? 'Active Engine: Stage 1 Fast Rules + Stage 2 Local LLM (${spec.displayName})'
                        : 'Active Engine: Stage 1 Fast Rules (0 MB) + Device Server Fallback',
                    style: GoogleFonts.exo2(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (_manager.errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent.withAlpha(100)),
              ),
              child: Text(
                _manager.errorMessage!,
                style: GoogleFonts.exo2(
                  fontSize: 12,
                  color: Colors.redAccent,
                ),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Download Progress or Action Buttons based on state
          if (state == LlmModelState.downloading ||
              state == LlmModelState.verifying) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: state == LlmModelState.verifying
                    ? null
                    : _manager.downloadProgress,
                minHeight: 8,
                backgroundColor: AppTheme.darkCard,
                color: AppTheme.primaryOrange,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    state == LlmModelState.verifying
                        ? 'Verifying GGUF model integrity...'
                        : 'Downloading: ${_manager.formattedDownloadedMb} / ${_manager.formattedTotalMb} (${(_manager.downloadProgress * 100).toInt()}%)',
                    style: GoogleFonts.exo2(
                      fontSize: 12,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton.icon(
                      onPressed: _manager.pauseDownload,
                      icon: const Icon(Icons.pause, size: 16),
                      label: Text('Pause', style: GoogleFonts.exo2(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryOrange,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _manager.deleteModel,
                      icon: const Icon(Icons.close, size: 16),
                      label: Text('Cancel', style: GoogleFonts.exo2(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ] else if (state == LlmModelState.downloadPaused) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _manager.downloadProgress,
                minHeight: 8,
                backgroundColor: AppTheme.darkCard,
                color: Colors.amber,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _manager.downloadModel(),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text(
                      'Resume (${_manager.formattedDownloadedMb} / ${_manager.formattedTotalMb})',
                      style: GoogleFonts.exo2(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryOrange,
                      foregroundColor: AppTheme.textDarkButton,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        vertical: 11,
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _manager.deleteModel,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(
                    'Discard',
                    style: GoogleFonts.exo2(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(
                      vertical: 11,
                      horizontal: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_manager.isInstalled) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isTesting ? null : _runSelfTest,
                    icon: _isTesting
                        ? SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryOrange,
                            ),
                          )
                        : const Icon(Icons.play_circle_outline, size: 18),
                    label: Text(
                      'Test Voice AI',
                      style: GoogleFonts.exo2(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryOrange,
                      side: BorderSide(color: AppTheme.primaryOrange),
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        vertical: 11,
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _confirmAndDeleteModel,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(
                      'Delete Model',
                      style: GoogleFonts.exo2(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        vertical: 11,
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _manager.downloadModel(),
                    icon: const Icon(Icons.download_rounded, size: 19),
                    label: Text(
                      'Download Model (~${spec.formattedSizeMb})',
                      style: GoogleFonts.exo2(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryOrange,
                      foregroundColor: AppTheme.textDarkButton,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _isTesting ? null : _runSelfTest,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryOrange,
                    side: BorderSide(color: AppTheme.primaryOrange.withAlpha(180)),
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Test Rules',
                    style: GoogleFonts.exo2(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 14),
          const Divider(color: AppTheme.darkBorder, height: 1),
          const SizedBox(height: 8),

          // Toggles
          _buildCompactToggle(
            title: 'Enable Local LLM for complex commands',
            subtitle:
                'Uses SmolLM2-360M when fast rules are unsure or for multi-step commands',
            value: _manager.isEnabled,
            onChanged: (v) => _manager.setEnabled(v),
          ),
          _buildCompactToggle(
            title: 'Preload model when Voice Command opens',
            subtitle:
                'Warms up model in RAM when mic dialog opens, auto-unloads after 2 min idle',
            value: _manager.preloadOnVoiceDialog,
            onChanged: (v) => _manager.setPreloadOnVoiceDialog(v),
          ),
        ],
      ),
    );
  }

  Widget _buildStateBadge(LlmModelState state) {
    String label;
    Color color;
    switch (state) {
      case LlmModelState.readyInRam:
        label = 'Ready in RAM';
        color = const Color(0xFF00E676);
        break;
      case LlmModelState.loadingIntoRam:
        label = 'Loading...';
        color = Colors.amber;
        break;
      case LlmModelState.installed:
        label = 'Downloaded';
        color = const Color(0xFF00E676);
        break;
      case LlmModelState.downloading:
      case LlmModelState.verifying:
        label = 'Downloading';
        color = AppTheme.primaryOrange;
        break;
      case LlmModelState.downloadPaused:
        label = 'Paused';
        color = Colors.amber;
        break;
      case LlmModelState.error:
        label = 'Error';
        color = Colors.redAccent;
        break;
      case LlmModelState.notInstalled:
        label = 'Not Installed';
        color = AppTheme.textMuted;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(140)),
      ),
      child: Text(
        label,
        style: GoogleFonts.exo2(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildCompactToggle({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.exo2(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.exo2(
                    fontSize: 11.5,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: value,
              activeThumbColor: AppTheme.primaryOrange,
              activeTrackColor: AppTheme.primaryOrange.withAlpha(80),
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: AppTheme.darkBorder,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
