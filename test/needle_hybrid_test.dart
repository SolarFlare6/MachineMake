import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:machmake2/core/dcp/dcp_message.dart';
import 'package:machmake2/core/needle/hybrid_needle_router.dart';
import 'package:machmake2/core/needle/intent_normalizer.dart';
import 'package:machmake2/core/needle/llm/llm_plan_parser.dart';
import 'package:machmake2/core/needle/llm/local_llm_runtime.dart';
import 'package:machmake2/core/needle/llm/tool_grammar_builder.dart';
import 'package:machmake2/core/needle/llm/tool_prompt_builder.dart';
import 'package:machmake2/core/needle/llm/tool_relevance_filter.dart';
import 'package:machmake2/core/needle/needle_engine.dart';
import 'package:machmake2/core/needle/needle_models.dart';
import 'package:machmake2/core/needle/rule_intent_matcher.dart';
import 'package:machmake2/core/needle/target_resolver.dart';
import 'package:machmake2/models/dcp_models.dart';
import 'package:machmake2/services/llm_model_manager.dart';
import 'package:machmake2/theme/app_theme.dart';
import 'package:machmake2/widgets/needle_model_settings_card.dart';

class _MockLlmRuntime implements LocalLlmRuntime {
  bool _loaded = false;
  final String cannedJsonResponse;

  _MockLlmRuntime({required this.cannedJsonResponse});

  @override
  bool get isLoaded => _loaded;

  @override
  bool get isGenerating => false;

  @override
  Future<void> loadModel(
    String modelPath, {
    int threads = 4,
    int contextSize = 1024,
  }) async {
    _loaded = true;
  }

  @override
  Future<String> generateStructured({
    required String systemPrompt,
    required String userPrompt,
    String? gbnfGrammar,
    int maxTokens = 96,
    double temperature = 0.05,
    Duration timeout = const Duration(milliseconds: 2800),
  }) async {
    return cannedJsonResponse;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> unload() async {
    _loaded = false;
  }
}

void main() {
  final pcDevice = DeviceItem(
    id: 'pc-1',
    name: 'Desktop PC',
    profile: 'pc',
    deviceType: 'Desktop PC',
    availableTransports: const ['wifi'],
    selectedTransport: 'wifi',
    isPaired: true,
    isConnected: true,
    iconKey: 'laptop',
  );

  final robotDevice = DeviceItem(
    id: 'robot-1',
    name: 'Spot Quadruped',
    profile: 'quadruped',
    deviceType: 'Quadruped Robot',
    availableTransports: const ['wifi'],
    selectedTransport: 'wifi',
    isPaired: true,
    isConnected: true,
    iconKey: 'quadruped',
  );

  final picoDevice = DeviceItem(
    id: 'pico-1',
    name: 'Pi Pico W',
    profile: 'pico',
    deviceType: 'Pi Pico',
    availableTransports: const ['wifi'],
    selectedTransport: 'wifi',
    isPaired: true,
    isConnected: true,
    iconKey: 'pico',
  );

  final allDevices = [robotDevice, pcDevice, picoDevice];

  group('Stage 0: IntentNormalizer & TargetResolver', () {
    test('Fixes STT mishears and converts spoken number words', () {
      expect(
        IntentNormalizer.normalize('Please press inter'),
        equals('press enter'),
      );
      expect(
        IntentNormalizer.normalize('press control see'),
        equals('press ctrl+c'),
      );
      expect(
        IntentNormalizer.normalize('set jeepio four high'),
        equals('set gpio 4 high'),
      );
      expect(
        IntentNormalizer.normalize('turn left ninety degrees'),
        equals('turn left 90 degrees'),
      );
    });

    test('Preserves literal text in keyboard type commands', () {
      expect(
        IntentNormalizer.normalize('type Hello World one two three'),
        equals('type Hello World one two three'),
      );
    });

    test('Resolves "On the connected PC press enter" to PC device', () {
      final res = TargetResolver.resolve(
        rawOrNormalizedPrompt: 'On the connected PC press enter',
        connectedDevices: allDevices,
        defaultDevice: robotDevice,
      );
      expect(res.explicitlyMatched, isTrue);
      expect(res.targetDevice.id, equals('pc-1'));
      expect(res.cleanedActionPrompt.toLowerCase(), equals('press enter'));
    });

    test('Resolves "Tell the robot to walk forward" and "On the Pico turn on pin 4"', () {
      final robotRes = TargetResolver.resolve(
        rawOrNormalizedPrompt: 'Tell the robot to walk forward',
        connectedDevices: allDevices,
        defaultDevice: pcDevice,
      );
      expect(robotRes.explicitlyMatched, isTrue);
      expect(robotRes.targetDevice.id, equals('robot-1'));
      expect(robotRes.cleanedActionPrompt.toLowerCase(), equals('walk forward'));

      final picoRes = TargetResolver.resolve(
        rawOrNormalizedPrompt: 'On the Pico turn on pin 4',
        connectedDevices: allDevices,
        defaultDevice: pcDevice,
      );
      expect(picoRes.explicitlyMatched, isTrue);
      expect(picoRes.targetDevice.id, equals('pico-1'));
      expect(picoRes.cleanedActionPrompt.toLowerCase(), equals('turn on pin 4'));
    });
  });

  group('Stage 1: RuleIntentMatcher (PC, Robot, Pico)', () {
    test('Matches PC keyboard, media, lock, and mouse tools', () {
      final pcTools = ToolRelevanceFilter.defaultToolsForProfile('pc');

      final enterPlan = RuleIntentMatcher.match('press enter', pcTools);
      expect(enterPlan.toolName, equals('keyboard_press'));
      expect(enterPlan.parameters['key'], equals('enter'));
      expect(enterPlan.confidence, greaterThanOrEqualTo(0.95));

      final typePlan = RuleIntentMatcher.match('type git status', pcTools);
      expect(typePlan.toolName, equals('keyboard_type'));
      expect(typePlan.parameters['text'], equals('git status'));

      final lockPlan = RuleIntentMatcher.match('lock screen', pcTools);
      expect(lockPlan.toolName, equals('lock_device'));

      final volPlan = RuleIntentMatcher.match('volume up', pcTools);
      expect(volPlan.toolName, equals('media_control'));
      expect(volPlan.parameters['action'], equals('vol_up'));

      final clickPlan = RuleIntentMatcher.match('double click', pcTools);
      expect(clickPlan.toolName, equals('mouse_click'));
      expect(clickPlan.parameters['double'], isTrue);
    });

    test('Flags destructive PC power commands with requiresConfirmation', () {
      final pcTools = ToolRelevanceFilter.defaultToolsForProfile('pc');

      final shutdownPlan = RuleIntentMatcher.match('shutdown', pcTools);
      expect(shutdownPlan.toolName, equals('shutdown'));
      expect(shutdownPlan.requiresConfirmation, isTrue);

      final rebootPlan = RuleIntentMatcher.match('reboot', pcTools);
      expect(rebootPlan.toolName, equals('reboot'));
      expect(rebootPlan.requiresConfirmation, isTrue);
    });

    test('Matches multi-step fast rule chains', () {
      final robotTools = ToolRelevanceFilter.defaultToolsForProfile('quadruped');
      final chainPlan = RuleIntentMatcher.match(
        'stand up and then walk forward two meters',
        robotTools,
      );
      expect(chainPlan.steps.length, equals(2));
      expect(chainPlan.steps[0].toolName, equals('stand'));
      expect(chainPlan.steps[1].toolName, equals('walk'));
      expect(chainPlan.steps[1].parameters['distance'], equals(2.0));
    });
  });

  group('Stage 2 & Fallback: HybridNeedleRouter & NeedleEngine', () {
    test('End-to-end execution of "On the connected PC press enter" without LLM installed', () async {
      LlmModelManager.instance.setRuntimeForTesting(
        _MockLlmRuntime(cannedJsonResponse: ''),
        state: LlmModelState.notInstalled,
      );

      String? executedDeviceId;
      String? executedTool;
      Map<String, dynamic>? executedParams;

      final engine = NeedleEngine(
        toolExecutor: (devId, tool, params) async {
          executedDeviceId = devId;
          executedTool = tool;
          executedParams = params;
          return DcpExecuteResponse(success: true, result: {'ok': true});
        },
      );

      final response = await engine.execute(
        device: robotDevice, // Selected device is Robot, but prompt targets PC!
        manifest: null,
        tools: const [],
        connectedDevices: allDevices,
        toolsProvider: (id) => const [],
        prompt: 'On the connected PC press enter',
      );

      expect(response.success, isTrue);
      expect(executedDeviceId, equals('pc-1'));
      expect(executedTool, equals('keyboard_press'));
      expect(executedParams, equals({'key': 'enter'}));
      expect(response.plan?.source, equals(NeedlePlanSource.rules));
    });

    test('Uses Fast Rules for simple commands and Local LLM for complicated sentences (with Fast Rules fallback)', () async {
      final mockRuntime = _MockLlmRuntime(
        cannedJsonResponse:
            '{"calls":[{"tool":"media_control","params":{"action":"vol_down"}}]}',
      );
      mockRuntime._loaded = true;
      LlmModelManager.instance.setRuntimeForTesting(
        mockRuntime,
        state: LlmModelState.readyInRam,
      );

      final router = HybridNeedleRouter(llmManager: LlmModelManager.instance);

      // 1. Simple command ("press enter") -> uses Fast Rules even when LLM is loaded
      final simpleRouting = await router.routeAndPlan(
        prompt: 'On the PC press enter',
        defaultDevice: robotDevice,
        connectedDevices: allDevices,
        toolsProvider: (_) => ToolRelevanceFilter.defaultToolsForProfile('pc'),
      );
      expect(simpleRouting.targetResolution.targetDevice.id, equals('pc-1'));
      expect(simpleRouting.plan.source, equals(NeedlePlanSource.rules));
      expect(simpleRouting.plan.toolName, equals('keyboard_press'));

      // 2. Complicated sentence ("On the PC it is way too loud in here") -> uses Local LLM
      final complexRouting = await router.routeAndPlan(
        prompt: 'On the PC it is way too loud in here',
        defaultDevice: robotDevice,
        connectedDevices: allDevices,
        toolsProvider: (_) => ToolRelevanceFilter.defaultToolsForProfile('pc'),
      );
      expect(complexRouting.targetResolution.targetDevice.id, equals('pc-1'));
      expect(complexRouting.plan.source, equals(NeedlePlanSource.localLlm));
      expect(complexRouting.plan.toolName, equals('media_control'));
      expect(complexRouting.plan.parameters['action'], equals('vol_down'));

      // 3. Complicated sentence when LLM fails -> falls back to Fast Rules
      final failingRuntime = _MockLlmRuntime(cannedJsonResponse: 'invalid json');
      failingRuntime._loaded = true;
      LlmModelManager.instance.setRuntimeForTesting(
        failingRuntime,
        state: LlmModelState.readyInRam,
      );

      final fallbackRouting = await router.routeAndPlan(
        prompt: 'On the PC can you please type hello and press enter',
        defaultDevice: robotDevice,
        connectedDevices: allDevices,
        toolsProvider: (_) => ToolRelevanceFilter.defaultToolsForProfile('pc'),
      );
      expect(fallbackRouting.plan.source, equals(NeedlePlanSource.rules));
      expect(fallbackRouting.plan.steps.length, equals(2));
      expect(fallbackRouting.plan.steps[0].toolName, equals('keyboard_type'));
      expect(fallbackRouting.plan.steps[1].toolName, equals('keyboard_press'));
    });

    test('Builds valid GBNF grammar and ChatML prompt', () {
      final tools = ToolRelevanceFilter.defaultToolsForProfile('pc');
      final grammar = ToolGrammarBuilder.buildGrammar(tools);
      expect(grammar, contains('keyboard_press'));
      expect(grammar, contains('root   ::='));

      final sysPrompt = ToolPromptBuilder.buildSystemPrompt(
        deviceName: 'Desktop PC',
        deviceProfile: 'pc',
        filteredTools: tools,
      );
      expect(sysPrompt, contains('keyboard_press'));
      expect(sysPrompt, contains('{"calls":['));

      final parsed = LlmPlanParser.parse(
        '{"calls":[{"tool":"keyboard_press","params":{"key":"enter"}}]}',
        targetDeviceId: 'pc-1',
        targetDeviceName: 'Desktop PC',
      );
      expect(parsed.toolName, equals('keyboard_press'));
      expect(parsed.parameters['key'], equals('enter'));
    });

    testWidgets('NeedleModelSettingsCard builds and renders under AppTheme.darkTheme without layout errors', (tester) async {
      final mockRuntime = _MockLlmRuntime(cannedJsonResponse: '{"calls":[]}');
      LlmModelManager.instance.setRuntimeForTesting(
        mockRuntime,
        state: LlmModelState.notInstalled,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: NeedleModelSettingsCard(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('SmolLM2-360M-Instruct'), findsWidgets);
      expect(find.text('Test Rules'), findsOneWidget);

      // Also verify Installed / Ready in RAM button row under AppTheme.darkTheme
      mockRuntime._loaded = true;
      LlmModelManager.instance.setRuntimeForTesting(
        mockRuntime,
        state: LlmModelState.readyInRam,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Test Voice AI'), findsOneWidget);
      expect(find.text('Delete Model'), findsOneWidget);
    });
  });
}
