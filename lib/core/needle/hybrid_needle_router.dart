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

  /// True when the prompt is a complicated/multi-step/conversational sentence
  /// and the Local LLM is ready to plan it in [HybridNeedleRouter.routeAndPlan].
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

/// Orchestrates the 4-stage Hybrid Needle AI pipeline:
/// - **Stage 0**: [TargetResolver] + [IntentNormalizer]
/// - **Stage 1**: [RuleIntentMatcher] (0 MB, < 1 ms) for simple, direct commands
/// - **Stage 2**: On-Device Local LLM (`SmolLM2-360M-Instruct` via [LlmModelManager])
///   for complicated, conversational, or multi-step sentences
/// - **Fallback**: Fast Rules fallback if Local LLM is not installed or fails
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

  /// Determines whether a command is a simple, direct imperative command
  /// (e.g., "press enter", "stand up", "turn on pin 4", "walk forward 2 meters")
  /// that should be handled immediately by Fast Rules without waking the LLM.
  ///
  /// Complicated sentences (multi-step chains, conversational requests, indirect
  /// phrasing, or sentences > 4 words) return `false` so the Local LLM handles
  /// them when installed (with Fast Rules as a fallback if the LLM fails).
  static bool isSimpleCommand({
    required String rawActionPrompt,
    required String normalizedPrompt,
    required NeedlePlan rulePlan,
  }) {
    if (rulePlan.toolName.isEmpty || rulePlan.confidence < 0.90) {
      return false;
    }

    // Multi-step plans or prompts with multiple clauses are complicated
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

    // Direct literal typing (e.g. "type hello world") is simple up to 5 words
    if (rulePlan.toolName == 'keyboard_type') {
      return words.length <= 5;
    }

    // Standard simple commands have at most 4 words (e.g. "turn on pin 4",
    // "walk forward 2 meters", "press enter", "volume up").
    return words.length <= 4;
  }

  /// Synchronous preview planning (Stages 0 + 1 only) for instant UI badges.
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
    final normalized = IntentNormalizer.normalize(targetRes.cleanedActionPrompt);
    final tools = toolsProvider(targetDevice.id);
    final effectiveTools = tools.isNotEmpty
        ? tools
        : ToolRelevanceFilter.defaultToolsForProfile(
            '${targetDevice.profile} ${targetDevice.deviceType}',
          );

    final rawRulePlan = RuleIntentMatcher.match(
      normalized,
      effectiveTools,
      targetDeviceId: targetDevice.id,
      targetDeviceName: targetDevice.name,
    );
    final validatedPlan = PlanValidator.validateAndCoerce(rawRulePlan, tools);
    final isSimple = isSimpleCommand(
      rawActionPrompt: targetRes.cleanedActionPrompt,
      normalizedPrompt: normalized,
      rulePlan: validatedPlan,
    );
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
      preferLocalLlm: llmReady && !isSimple,
    );
  }

  /// Full asynchronous hybrid planning:
  /// - Simple commands -> Stage 1 Fast Rules (< 1 ms, do not use LLM)
  /// - Complicated sentences -> Stage 2 Local LLM (`SmolLM2-360M-Instruct`) when installed
  /// - Fallback -> Stage 1 Fast Rules if Local LLM is not installed or fails
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

    final deviceTools = toolsProvider(targetDevice.id);
    final profileStr = '${targetDevice.profile} ${targetDevice.deviceType}';
    final effectiveTools = deviceTools.isNotEmpty
        ? deviceTools
        : ToolRelevanceFilter.defaultToolsForProfile(profileStr);

    // ── Stage 1: Fast Deterministic & Fuzzy Rules (< 1 ms, 0 MB) ────────────
    final rulePlan = RuleIntentMatcher.match(
      normalized,
      effectiveTools,
      targetDeviceId: targetDevice.id,
      targetDeviceName: targetDevice.name,
    );
    final validatedRulePlan =
        PlanValidator.validateAndCoerce(rulePlan, deviceTools);

    final isSimple = isSimpleCommand(
      rawActionPrompt: rawActionPrompt,
      normalizedPrompt: normalized,
      rulePlan: validatedRulePlan,
    );

    // If it's a simple direct command, use Fast Rules immediately without LLM
    if (isSimple) {
      return HybridRoutingResult(
        targetResolution: targetRes,
        normalizedActionPrompt: normalized,
        plan: validatedRulePlan,
        llmWasAvailable: _llmManager.isReadyForInference,
        preferLocalLlm: false,
      );
    }

    // ── Stage 2: Local LLM (`SmolLM2-360M-Instruct`) for Complicated Sentences
    if (_llmManager.isReadyForInference) {
      final loaded = await _llmManager.ensureLoadedInRam();
      if (loaded) {
        try {
          final llmInputPrompt =
              rawActionPrompt.isNotEmpty ? rawActionPrompt : normalized;
          final filteredTools = ToolRelevanceFilter.filter(
            prompt: llmInputPrompt,
            availableTools: effectiveTools,
            deviceProfile: profileStr,
            maxTools: 10,
          );
          final systemPrompt = ToolPromptBuilder.buildSystemPrompt(
            deviceName: targetDevice.name,
            deviceProfile: profileStr,
            filteredTools: filteredTools,
          );
          final grammar = ToolGrammarBuilder.buildGrammar(filteredTools);

          final rawJson = await _llmManager.runtime.generateStructured(
            systemPrompt: systemPrompt,
            userPrompt: llmInputPrompt,
            gbnfGrammar: grammar,
            maxTokens: 96,
            temperature: 0.05,
          );

          final parsedLlmPlan = LlmPlanParser.parse(
            rawJson,
            targetDeviceId: targetDevice.id,
            targetDeviceName: targetDevice.name,
          );
          final validatedLlmPlan =
              PlanValidator.validateAndCoerce(parsedLlmPlan, deviceTools);

          if (validatedLlmPlan.toolName.isNotEmpty) {
            return HybridRoutingResult(
              targetResolution: targetRes,
              normalizedActionPrompt: normalized,
              plan: validatedLlmPlan,
              llmWasAvailable: true,
              preferLocalLlm: true,
            );
          }
        } catch (_) {
          // Fall through gracefully to Fast Rules fallback if LLM inference fails
        }
      }
    }

    // ── Fallback: Use Fast Rules if LLM is not installed or if LLM failed ───
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
}
