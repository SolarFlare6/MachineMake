import '../../models/dcp_models.dart';
import '../../services/llm_model_manager.dart';
import '../models/tool_definition.dart';
import 'intent_normalizer.dart';
import 'llm/llm_plan_parser.dart';
import 'llm/tool_grammar_builder.dart';
import 'llm/tool_prompt_builder.dart';
import 'llm/tool_relevance_filter.dart';
import 'needle_models.dart';
import 'plan_validator.dart';
import 'rule_intent_matcher.dart';
import 'target_resolver.dart';

/// Result of the Hybrid Needle Router planning pipeline (Stages 0 → 1 → 2).
class HybridRoutingResult {
  final TargetResolutionResult targetResolution;
  final String normalizedActionPrompt;
  final NeedlePlan plan;
  final List<String> suggestions;
  final bool llmWasAvailable;

  /// True when Cactus Needle 3 (Local LLM) is ready and will plan the command.
  final bool preferLocalLlm;

  const HybridRoutingResult({
    required this.targetResolution,
    required this.normalizedActionPrompt,
    required this.plan,
    this.suggestions = const [],
    this.llmWasAvailable = false,
    this.preferLocalLlm = false,
  });
}

/// Orchestrates the Hybrid Needle AI pipeline:
/// - **Stage 0**: [TargetResolver] + [IntentNormalizer]
/// - **Primary (when installed)**: Cactus Compute Needle 3 (`needle3.cact` via [LlmModelManager])
///   using strictly device-specific tool schemas for the resolved target device.
/// - **Fallback (when Needle 3 is not installed or fails)**: [RuleIntentMatcher]
///   validated strictly against the target device's available tools.
class HybridNeedleRouter {
  final LlmModelManager _llmManager;

  HybridNeedleRouter({LlmModelManager? llmManager})
      : _llmManager = llmManager ?? LlmModelManager.instance;

  static final RegExp _clauseConnectorPattern = RegExp(
    r'\b(and|then|after|before|while|because|followed by|also)\b|[,;]',
    caseSensitive: false,
  );

  static final RegExp _conversationalPattern = RegExp(
    r"\b(can you|could you|would you|please|i want|i need|i would like|make it|make the|tell the|have the|let's|lets|go ahead|it is|it's|its|too loud|too quiet|way too|a little|a bit|take a break|what is|what's|how is|how much|check if|show me)\b",
    caseSensitive: false,
  );

  /// Helper to determine if a command is a short single-step imperative phrase.
  static bool isSimpleCommand({
    required String rawActionPrompt,
    required String normalizedPrompt,
    required NeedlePlan rulePlan,
  }) {
    if (rulePlan.toolName.isEmpty || rulePlan.confidence < 0.90) {
      return false;
    }

    if (rulePlan.steps.length > 1 ||
        IntentNormalizer.splitMultiStep(normalizedPrompt).length > 1) {
      return false;
    }

    final rawTrimmed = rawActionPrompt.trim();
    if (rawTrimmed.isEmpty) return false;

    if (_clauseConnectorPattern.hasMatch(rawTrimmed)) {
      return false;
    }

    if (_conversationalPattern.hasMatch(rawTrimmed)) {
      return false;
    }

    final words = rawTrimmed
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (rulePlan.toolName == 'keyboard_type') {
      return words.length <= 5;
    }

    return words.length <= 4;
  }

  /// Builds the strict device-specific tool catalog for [targetDevice].
  static List<ToolDefinition> _resolveDeviceTools(
    DeviceItem targetDevice,
    List<ToolDefinition> reportedTools,
  ) {
    final profileStr = '${targetDevice.profile} ${targetDevice.deviceType} ${targetDevice.name}';
    final profileDefaults = ToolRelevanceFilter.defaultToolsForProfile(profileStr);
    if (reportedTools.isEmpty) {
      return profileDefaults;
    }

    // Merge reported tools with profile defaults (keeping reported tool definitions first)
    final byName = <String, ToolDefinition>{};
    for (final t in reportedTools) {
      if (t.name != 'needle_prompt' && t.name != 'ai_prompt') {
        byName[t.name] = t;
      }
    }
    for (final d in profileDefaults) {
      byName.putIfAbsent(d.name, () => d);
    }
    return byName.values.toList();
  }

  /// Synchronous preview planning for instant UI badges in the Voice Command dialog.
  HybridRoutingResult planSync({
    required String prompt,
    required DeviceItem defaultDevice,
    required List<DeviceItem> connectedDevices,
    required List<ToolDefinition> Function(String deviceId) toolsProvider,
  }) {
    final targetRes = TargetResolver.resolve(
      rawOrNormalizedPrompt: prompt,
      connectedDevices: connectedDevices,
      defaultDevice: defaultDevice,
    );
    final targetDevice = targetRes.targetDevice;
    final normalized =
        IntentNormalizer.normalize(targetRes.cleanedActionPrompt);
    final rawReportedTools = toolsProvider(targetDevice.id);
    final effectiveTools = _resolveDeviceTools(targetDevice, rawReportedTools);

    final rawRulePlan = RuleIntentMatcher.match(
      normalized,
      effectiveTools,
      targetDeviceId: targetDevice.id,
      targetDeviceName: targetDevice.name,
    );
    final validatedPlan =
        PlanValidator.validateAndCoerce(rawRulePlan, effectiveTools);
    final llmReady = _llmManager.isReadyForInference;

    return HybridRoutingResult(
      targetResolution: targetRes,
      normalizedActionPrompt: normalized,
      plan: validatedPlan,
      suggestions: PlanValidator.suggestExamples(
        effectiveTools,
        deviceProfile: '${targetDevice.profile} ${targetDevice.deviceType}',
      ),
      llmWasAvailable: llmReady,
      // When Cactus Needle 3 is installed & enabled, always prefer it for voice commands
      preferLocalLlm: llmReady && targetRes.cleanedActionPrompt.trim().isNotEmpty,
    );
  }

  /// Full asynchronous planning:
  /// - When Cactus Needle 3 (`needle3.cact`) is installed and enabled, always uses
  ///   Cactus Needle 3 first with the target device's specific tool schemas.
  /// - Falls back to device-validated Fast Rules if Needle 3 is not installed or
  ///   cannot produce a valid tool call.
  Future<HybridRoutingResult> routeAndPlan({
    required String prompt,
    required DeviceItem defaultDevice,
    required List<DeviceItem> connectedDevices,
    required List<ToolDefinition> Function(String deviceId) toolsProvider,
  }) async {
    // ── Stage 0: Target Device Resolution + Speech Normalization ────────────
    final targetRes = TargetResolver.resolve(
      rawOrNormalizedPrompt: prompt,
      connectedDevices: connectedDevices,
      defaultDevice: defaultDevice,
    );
    final targetDevice = targetRes.targetDevice;
    final rawActionPrompt = targetRes.cleanedActionPrompt.trim();
    final normalized = IntentNormalizer.normalize(rawActionPrompt);

    final rawReportedTools = toolsProvider(targetDevice.id);
    final profileStr =
        '${targetDevice.profile} ${targetDevice.deviceType} ${targetDevice.name}';
    final effectiveTools = _resolveDeviceTools(targetDevice, rawReportedTools);

    // Pre-compute Stage 1 Fast Rule plan (strictly validated against effectiveTools)
    final rulePlan = RuleIntentMatcher.match(
      normalized,
      effectiveTools,
      targetDeviceId: targetDevice.id,
      targetDeviceName: targetDevice.name,
    );
    final validatedRulePlan =
        PlanValidator.validateAndCoerce(rulePlan, effectiveTools);

    // ── Stage 2 (Primary when installed): Cactus Needle 3 Local LLM ─────────
    if (_llmManager.isReadyForInference) {
      final loaded = await _llmManager.ensureLoadedInRam();
      if (loaded) {
        try {
          final llmInputPrompt =
              rawActionPrompt.isNotEmpty ? rawActionPrompt : normalized;
          final validatedLlmPlan = await _planWithNeedleLlm(
            llmInputPrompt: llmInputPrompt,
            normalizedPrompt: normalized,
            targetDevice: targetDevice,
            profileStr: profileStr,
            effectiveTools: effectiveTools,
          );

          if (validatedLlmPlan != null && validatedLlmPlan.toolName.isNotEmpty) {
            return HybridRoutingResult(
              targetResolution: targetRes,
              normalizedActionPrompt: normalized,
              plan: validatedLlmPlan,
              llmWasAvailable: true,
              preferLocalLlm: true,
            );
          }
        } catch (_) {
          // Fall through gracefully to device-validated Fast Rules if native inference throws
        }
      }
    }

    // ── Fallback: Device-Validated Fast Rules ───────────────────────────────
    final suggestions = PlanValidator.suggestExamples(
      effectiveTools,
      deviceProfile: profileStr,
    );

    return HybridRoutingResult(
      targetResolution: targetRes,
      normalizedActionPrompt: normalized,
      plan: validatedRulePlan,
      suggestions: suggestions,
      llmWasAvailable: _llmManager.isReadyForInference,
      preferLocalLlm: false,
    );
  }

  Future<NeedlePlan?> _planWithNeedleLlm({
    required String llmInputPrompt,
    required String normalizedPrompt,
    required DeviceItem targetDevice,
    required String profileStr,
    required List<ToolDefinition> effectiveTools,
  }) async {
    final filteredTools = ToolRelevanceFilter.filter(
      prompt: llmInputPrompt,
      availableTools: effectiveTools,
      deviceProfile: profileStr,
      maxTools: 12,
    );
    final systemPrompt = ToolPromptBuilder.buildSystemPrompt(
      deviceName: targetDevice.name,
      deviceProfile: profileStr,
      filteredTools: filteredTools,
    );
    final toolsJson = ToolPromptBuilder.buildNeedleToolsJson(filteredTools);
    final grammar = ToolGrammarBuilder.buildGrammar(filteredTools);

    final rawJson = await _llmManager.runtime.generateStructured(
      systemPrompt: systemPrompt,
      userPrompt: llmInputPrompt,
      gbnfGrammar: grammar,
      toolsJson: toolsJson,
      maxTokens: 256,
      temperature: 0.0,
    );

    final parsedLlmPlan = LlmPlanParser.parse(
      rawJson,
      targetDeviceId: targetDevice.id,
      targetDeviceName: targetDevice.name,
    );
    final validatedLlmPlan =
        PlanValidator.validateAndCoerce(parsedLlmPlan, effectiveTools);

    // If the prompt contains multiple clauses (e.g. "turn on the led strip and move the camera to the left")
    // and a single pass only emitted 1 step, plan each clause with Needle 3 so all steps execute!
    final subClauses = IntentNormalizer.splitMultiStep(normalizedPrompt);
    if (subClauses.length > 1 && validatedLlmPlan.steps.length < subClauses.length) {
      final clausePlans = <NeedlePlan>[];
      int llmClauseMatches = 0;
      for (final clause in subClauses) {
        final clauseTools = ToolRelevanceFilter.filter(
          prompt: clause,
          availableTools: effectiveTools,
          deviceProfile: profileStr,
          maxTools: 10,
        );
        final clauseSysPrompt = ToolPromptBuilder.buildSystemPrompt(
          deviceName: targetDevice.name,
          deviceProfile: profileStr,
          filteredTools: clauseTools,
        );
        final clauseToolsJson =
            ToolPromptBuilder.buildNeedleToolsJson(clauseTools);
        final clauseGrammar = ToolGrammarBuilder.buildGrammar(clauseTools);

        final clauseRaw = await _llmManager.runtime.generateStructured(
          systemPrompt: clauseSysPrompt,
          userPrompt: clause,
          gbnfGrammar: clauseGrammar,
          toolsJson: clauseToolsJson,
          maxTokens: 160,
          temperature: 0.0,
        );
        final parsedClause = LlmPlanParser.parse(
          clauseRaw,
          targetDeviceId: targetDevice.id,
          targetDeviceName: targetDevice.name,
        );
        var validatedClause =
            PlanValidator.validateAndCoerce(parsedClause, effectiveTools);

        if (validatedClause.toolName.isNotEmpty) {
          llmClauseMatches++;
        } else {
          // If Needle 3 missed one sub-clause, check if a strict device-validated rule matches that sub-clause
          final fallbackClause = RuleIntentMatcher.match(
            clause,
            effectiveTools,
            targetDeviceId: targetDevice.id,
            targetDeviceName: targetDevice.name,
          );
          validatedClause =
              PlanValidator.validateAndCoerce(fallbackClause, effectiveTools);
        }

        if (validatedClause.toolName.isEmpty) {
          clausePlans.clear();
          break;
        }
        clausePlans.add(
          NeedlePlan(
            toolName: validatedClause.toolName,
            parameters: validatedClause.parameters,
            explanation: validatedClause.explanation,
            confidence: validatedClause.confidence,
            thoughts: validatedClause.thoughts,
            source: NeedlePlanSource.localLlm,
            requiresConfirmation: validatedClause.requiresConfirmation,
            targetDeviceId: targetDevice.id,
            targetDeviceName: targetDevice.name,
          ),
        );
      }

      if (clausePlans.length == subClauses.length && llmClauseMatches > 0) {
        final first = clausePlans.first;
        return NeedlePlan(
          toolName: first.toolName,
          parameters: first.parameters,
          explanation: clausePlans.map((s) => s.explanation).join(' → '),
          confidence: clausePlans
              .map((s) => s.confidence)
              .reduce((a, b) => a < b ? a : b),
          thoughts: [
            'Cactus Needle 3 generated ${clausePlans.length}-step device plan',
            ...clausePlans.expand((s) => s.thoughts),
          ],
          source: NeedlePlanSource.localLlm,
          requiresConfirmation:
              clausePlans.any((s) => s.requiresConfirmation),
          steps: clausePlans,
          targetDeviceId: targetDevice.id,
          targetDeviceName: targetDevice.name,
        );
      }
    }

    return validatedLlmPlan;
  }
}
