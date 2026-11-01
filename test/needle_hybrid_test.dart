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
    String? toolsJson,
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

    test('Matches multi-step fast rule chains and robot LED strip + camera servo commands', () {
      final robotTools = ToolRelevanceFilter.defaultToolsForProfile('quadruped');
      final chainPlan = RuleIntentMatcher.match(
        'stand up and then walk forward two meters',
        robotTools,
      );
      expect(chainPlan.steps.length, equals(2));
      expect(chainPlan.steps[0].toolName, equals('stand'));
      expect(chainPlan.steps[1].toolName, equals('walk'));
      expect(chainPlan.steps[1].parameters['distance'], equals(2.0));

      final stripAndCamPlan = RuleIntentMatcher.match(
        'turn on the led strip and move the camera to the left',
        robotTools,
        targetDeviceId: 'robot-1',
        targetDeviceName: 'Spot Quadruped',
      );
      expect(stripAndCamPlan.steps.length, equals(2));
      expect(
        stripAndCamPlan.steps[0].toolName,
        equals('turn_on_strip_with_color'),
      );
      expect(stripAndCamPlan.steps[1].toolName, equals('pan_to_left'));
      expect(stripAndCamPlan.steps[1].parameters['index'], equals(0));

      // Verify the exact same robot command is rejected when given to a PC
      final pcTools = ToolRelevanceFilter.defaultToolsForProfile('pc');
      final rejectedOnPc = RuleIntentMatcher.match(
        'turn on the led strip and move the camera to the left',
        pcTools,
        targetDeviceId: 'pc-1',
        targetDeviceName: 'Desktop PC',
      );
      expect(rejectedOnPc.toolName, isEmpty);
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

    test('Always uses Cactus Needle 3 when installed, enforces device-specific tools, and falls back to Fast Rules on LLM failure', () async {
      final mockRuntime = _MockLlmRuntime(
        cannedJsonResponse:
            '{"type":"call","function_calls":[{"name":"media_control","arguments":{"action":"vol_down"}}],"confidence":0.94}',
      );
      mockRuntime._loaded = true;
      LlmModelManager.instance.setRuntimeForTesting(
        mockRuntime,
        state: LlmModelState.readyInRam,
      );

      final router = HybridNeedleRouter(llmManager: LlmModelManager.instance);

      // 1. When Cactus Needle 3 is installed, voice commands use Local LLM (NeedlePlanSource.localLlm)
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

      // 2. Robot-only tools ("turn_on_strip_with_color", "pan_to_left") work on Robot but are rejected on PC
      final robotMockRuntime = _MockLlmRuntime(
        cannedJsonResponse:
            '{"type":"call","function_calls":[{"name":"turn_on_strip_with_color","arguments":{"r":0,"g":230,"b":118}},{"name":"pan_to_left","arguments":{"index":0}}],"confidence":0.95}',
      );
      robotMockRuntime._loaded = true;
      LlmModelManager.instance.setRuntimeForTesting(
        robotMockRuntime,
        state: LlmModelState.readyInRam,
      );

      final robotRouting = await router.routeAndPlan(
        prompt: 'turn on the led strip and move the camera to the left',
        defaultDevice: robotDevice,
        connectedDevices: allDevices,
        toolsProvider: (_) =>
            ToolRelevanceFilter.defaultToolsForProfile('quadruped'),
      );
      expect(robotRouting.plan.source, equals(NeedlePlanSource.localLlm));
      expect(robotRouting.plan.steps.length, equals(2));
      expect(
        robotRouting.plan.steps[0].toolName,
        equals('turn_on_strip_with_color'),
      );
      expect(robotRouting.plan.steps[1].toolName, equals('pan_to_left'));
      expect(robotRouting.plan.steps[1].parameters['index'], equals(0));

      final rejectedPcRouting = await router.routeAndPlan(
        prompt: 'turn on the led strip and move the camera to the left',
        defaultDevice: pcDevice,
        connectedDevices: [pcDevice],
        toolsProvider: (_) => ToolRelevanceFilter.defaultToolsForProfile('pc'),
      );
      expect(rejectedPcRouting.plan.toolName, isEmpty);

      // 3. When LLM fails -> falls back to device-validated Fast Rules
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

    test('Builds valid Needle 3 JSON Schema tools, GBNF grammar, and parses Needle 3 function_calls', () {
      final tools = ToolRelevanceFilter.defaultToolsForProfile('pc');
      final needleToolsJson = ToolPromptBuilder.buildNeedleToolsJson(tools);
      expect(needleToolsJson, contains('"name":"keyboard_press"'));
      expect(needleToolsJson, contains('"parameters":{"type":"object"'));

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

      // Official Cactus Compute Needle 3 response format
      final parsedNeedle3 = LlmPlanParser.parse(
        '{"type":"call","success":true,"function_calls":[{"name":"keyboard_press","arguments":{"key":"enter"}}],"reasoning":"press enter -> keyboard_press","confidence":0.95}',
        targetDeviceId: 'pc-1',
        targetDeviceName: 'Desktop PC',
      );
      expect(parsedNeedle3.toolName, equals('keyboard_press'));
      expect(parsedNeedle3.parameters['key'], equals('enter'));
      expect(parsedNeedle3.confidence, closeTo(0.95, 0.01));

      final parsed = LlmPlanParser.parse(
        '{"calls":[{"tool":"keyboard_press","params":{"key":"enter"}}]}',
        targetDeviceId: 'pc-1',
        targetDeviceName: 'Desktop PC',
      );
      expect(parsed.toolName, equals('keyboard_press'));
      expect(parsed.parameters['key'], equals('enter'));
    });

    testWidgets('NeedleModelSettingsCard builds and renders under AppTheme.darkTheme without layout errors', (tester) async {
      final mockRuntime = _MockLlmRuntime(cannedJsonResponse: '{"function_calls":[]}');
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
      expect(find.textContaining('Cactus Needle 3'), findsWidgets);
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
