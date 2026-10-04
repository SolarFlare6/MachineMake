import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/connection/device_connection.dart';
import '../../core/models/tool_definition.dart';
import '../../theme/app_theme.dart';

/// Renders a [ToolDefinition] as an interactive card with auto-generated
/// form inputs based on each parameter's type.
///
/// Supported parameter types: string, int, float, bool, enum
class ToolInvokeCard extends StatefulWidget {
  final ToolDefinition tool;
  final DeviceConnection? conn;

  const ToolInvokeCard({super.key, required this.tool, this.conn});

  @override
  State<ToolInvokeCard> createState() => _ToolInvokeCardState();
}

class _ToolInvokeCardState extends State<ToolInvokeCard> {
  late Map<String, dynamic> _values;
  final Map<String, TextEditingController> _controllers = {};
  bool _isRunning = false;
  String? _lastResult;

  @override
  void initState() {
    super.initState();
    _values = {
      for (final p in widget.tool.parameters)
        p.name: p.defaultValue ?? _defaultFor(p.type),
    };
    for (final p in widget.tool.parameters) {
      if (p.type == 'string' || p.type == 'int' || p.type == 'float') {
        _controllers[p.name] = TextEditingController(
          text: (_values[p.name] ?? '').toString(),
        );
      }
    }
  }

  dynamic _defaultFor(String type) {
    switch (type) {
      case 'bool':
        return false;
      case 'int':
        return 0;
      case 'float':
        return 0.0;
      default:
        return '';
    }
  }

  Future<void> _run() async {
    if (_isRunning) return;
    // Sync text controller values back into _values
    for (final p in widget.tool.parameters) {
      final ctrl = _controllers[p.name];
      if (ctrl != null) {
        if (p.type == 'int') {
          _values[p.name] = int.tryParse(ctrl.text) ?? 0;
        } else if (p.type == 'float') {
          _values[p.name] = double.tryParse(ctrl.text) ?? 0.0;
        } else {
          _values[p.name] = ctrl.text;
        }
      }
    }

    setState(() {
      _isRunning = true;
      _lastResult = null;
    });

    try {
      final resp = await widget.conn?.session?.executeTool(widget.tool.name, Map.from(_values));
      if (mounted) {
        setState(() {
          _isRunning = false;
          _lastResult = resp?.success == true
              ? '✓ Success${resp?.result != null ? ': ${resp!.result}' : ''}'
              : '✗ ${resp?.error ?? 'No response'}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRunning = false;
          _lastResult = '✗ Error: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasParams = widget.tool.parameters.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primaryOrange.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.build_circle_outlined, color: AppTheme.primaryOrange, size: 20),
          ),
          title: Text(
            widget.tool.name,
            style: GoogleFonts.exo2(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          subtitle: Text(
            widget.tool.description,
            style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: widget.tool.isAsync
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withAlpha(25),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Colors.amberAccent.withAlpha(80)),
                  ),
                  child: Text('ASYNC', style: GoogleFonts.exo2(color: Colors.amberAccent, fontSize: 9, fontWeight: FontWeight.bold)),
                )
              : null,
          children: [
            if (hasParams) ...[
              ...widget.tool.parameters.map((p) => _buildParamInput(p)),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryOrange,
                      foregroundColor: AppTheme.textDarkButton,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: widget.conn?.session != null ? _run : null,
                    child: _isRunning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text('Execute', style: GoogleFonts.exo2(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            if (_lastResult != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.darkBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _lastResult!.startsWith('✓')
                        ? Colors.greenAccent.withAlpha(80)
                        : Colors.redAccent.withAlpha(80),
                  ),
                ),
                child: Text(
                  _lastResult!,
                  style: GoogleFonts.exo2(
                    color: _lastResult!.startsWith('✓') ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildParamInput(ToolParameter param) {
    switch (param.type) {
      case 'bool':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(param.name, style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 13)),
              ),
              Switch(
                value: _values[param.name] as bool? ?? false,
                onChanged: (v) => setState(() => _values[param.name] = v),
                activeThumbColor: AppTheme.primaryOrange,
              ),
            ],
          ),
        );

      case 'enum':
        final options = param.enumValues ?? [];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(param.name, style: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: options.map((opt) {
                  final selected = _values[param.name] == opt;
                  return ChoiceChip(
                    label: Text(opt, style: GoogleFonts.exo2(fontSize: 12)),
                    selected: selected,
                    selectedColor: AppTheme.primaryOrange,
                    backgroundColor: AppTheme.darkBackground,
                    labelStyle: GoogleFonts.exo2(
                        color: selected ? AppTheme.textDarkButton : AppTheme.textMuted),
                    onSelected: (_) => setState(() => _values[param.name] = opt),
                  );
                }).toList(),
              ),
            ],
          ),
        );

      default: // string, int, float
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextField(
            controller: _controllers[param.name],
            keyboardType: param.type == 'int'
                ? TextInputType.number
                : param.type == 'float'
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
            style: GoogleFonts.exo2(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: '${param.name}${param.required ? ' *' : ''}',
              labelStyle: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 12),
              helperText: param.description.isNotEmpty ? param.description : null,
              helperStyle: GoogleFonts.exo2(color: AppTheme.textMuted, fontSize: 11),
              filled: true,
              fillColor: AppTheme.darkBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.darkBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppTheme.darkBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppTheme.primaryOrange),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        );
    }
  }
}
