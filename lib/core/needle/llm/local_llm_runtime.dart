import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

/// Abstract interface for Needle AI's on-device LLM runtime.
///
/// Decouples the hybrid router from the native `llama.cpp` plugin so unit tests
/// can inject a mock runtime and non-Android platforms fail gracefully.
abstract class LocalLlmRuntime {
  bool get isLoaded;
  bool get isGenerating;

  Future<void> loadModel(
    String modelPath, {
    int threads = 4,
    int contextSize = 1024,
  });

  Future<String> generateStructured({
    required String systemPrompt,
    required String userPrompt,
    String? gbnfGrammar,
    int maxTokens = 96,
    double temperature = 0.05,
    Duration timeout = const Duration(milliseconds: 2800),
  });

  Future<void> stop();
  Future<void> unload();
}

/// Concrete Android `llama.cpp` runtime powered by `llama_flutter_android`.
///
/// Features:
/// - Automatic Vulkan GPU offload detection via `LlamaController.detectGpu()`
/// - Idle auto-unload timer (frees ~320 MB RAM after 2 minutes of inactivity)
/// - Low-temperature ChatML generation (`temperature: 0.05`, `topK: 10`)
class LlamaFlutterRuntime implements LocalLlmRuntime {
  LlamaController? _controller;
  bool _isLoaded = false;
  Timer? _idleTimer;

  /// How long to keep the model in RAM after the last voice command before
  /// automatically unloading it to save battery/RAM.
  final Duration idleUnloadDuration;

  /// Optional callback notified when the runtime loads or unloads the model.
  final VoidCallback? onStateChanged;

  LlamaFlutterRuntime({
    this.idleUnloadDuration = const Duration(minutes: 2),
    this.onStateChanged,
  });

  @override
  bool get isLoaded => _isLoaded;

  @override
  bool get isGenerating => _controller?.isGenerating ?? false;

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleUnloadDuration, () {
      unload();
    });
  }

  @override
  Future<void> loadModel(
    String modelPath, {
    int threads = 4,
    int contextSize = 1024,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'llama_flutter_android is only supported on Android devices.',
      );
    }

    final file = File(modelPath);
    if (!await file.exists()) {
      throw FileSystemException('GGUF model file not found', modelPath);
    }

    _controller ??= LlamaController();

    final alreadyLoaded = await _controller!.isModelLoaded();
    if (alreadyLoaded) {
      _isLoaded = true;
      _resetIdleTimer();
      onStateChanged?.call();
      return;
    }

    await _controller!.loadModel(
      modelPath: modelPath,
      threads: threads,
      contextSize: contextSize,
      gpuLayers: 0,
    );

    _isLoaded = true;
    _resetIdleTimer();
    onStateChanged?.call();
  }

  @override
  Future<String> generateStructured({
    required String systemPrompt,
    required String userPrompt,
    String? gbnfGrammar,
    int maxTokens = 140,
    double temperature = 0.05,
    Duration timeout = const Duration(milliseconds: 9000),
  }) async {
    if (!_isLoaded || _controller == null) {
      throw StateError('Local LLM is not loaded in memory.');
    }

    _resetIdleTimer();

    if (_controller!.isGenerating) {
      await _controller!.stop();
      await Future.delayed(const Duration(milliseconds: 120));
    }

    try {
      await _controller!.clearContext();
    } catch (_) {}

    final buffer = StringBuffer();
    final completer = Completer<String>();
    StreamSubscription<String>? sub;

    // Seed assistant message with `{"calls":[{"tool":"` so SmolLM2-360M-Instruct
    // immediately emits the tool name and JSON parameters without preamble.
    const assistantPrefix = '{"calls":[{"tool":"';
    final rawChatMlPrompt = '<|im_start|>system\n'
        '$systemPrompt<|im_end|>\n'
        '<|im_start|>user\n'
        '$userPrompt<|im_end|>\n'
        '<|im_start|>assistant\n'
        '$assistantPrefix';

    final timer = Timer(timeout, () async {
      if (!completer.isCompleted) {
        try {
          await _controller?.stop();
        } catch (_) {}
        completer.complete(
          _combinePrefixAndBuffer(assistantPrefix, buffer.toString()),
        );
      }
    });

    try {
      final stream = _controller!.generate(
        prompt: rawChatMlPrompt,
        maxTokens: maxTokens,
        temperature: temperature,
        topP: 0.9,
        topK: 10,
        repeatPenalty: 1.1,
      );

      sub = stream.listen(
        (token) {
          buffer.write(token);
          final current =
              _combinePrefixAndBuffer(assistantPrefix, buffer.toString());
          // Early stop as soon as the root JSON object closes `]}`
          if (_isCompleteJsonCalls(current) && !completer.isCompleted) {
            completer.complete(current);
            _controller?.stop();
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete(
              _combinePrefixAndBuffer(assistantPrefix, buffer.toString()),
            );
          }
        },
        onError: (Object err) {
          if (!completer.isCompleted) {
            completer.completeError(err);
          }
        },
        cancelOnError: true,
      );

      return await completer.future;
    } finally {
      timer.cancel();
      await sub?.cancel();
      _resetIdleTimer();
    }
  }

  String _combinePrefixAndBuffer(String assistantPrefix, String rawBuffer) {
    final trimmed = rawBuffer.trimLeft();
    if (trimmed.startsWith('{"calls"')) {
      return trimmed;
    }
    if (trimmed.startsWith('[{"tool"')) {
      return '{"calls":$trimmed';
    }
    if (trimmed.startsWith('{"tool"')) {
      return '{"calls":[$trimmed';
    }
    if (trimmed.startsWith('"') && assistantPrefix.endsWith('"')) {
      return '$assistantPrefix${trimmed.substring(1)}';
    }
    return '$assistantPrefix$rawBuffer';
  }

  bool _isCompleteJsonCalls(String text) {
    final trimmed = text.trim();
    if (!trimmed.startsWith('{')) return false;
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (int i = 0; i < trimmed.length; i++) {
      final ch = trimmed[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (ch == r'\') {
        escaped = true;
        continue;
      }
      if (ch == '"') {
        inString = !inString;
        continue;
      }
      if (!inString) {
        if (ch == '{') depth++;
        if (ch == '}') {
          depth--;
          if (depth == 0) return true;
        }
      }
    }
    return false;
  }

  @override
  Future<void> stop() async {
    try {
      await _controller?.stop();
    } catch (_) {}
  }

  @override
  Future<void> unload() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_controller != null) {
      try {
        await _controller!.dispose();
      } catch (_) {}
      _controller = null;
    }
    if (_isLoaded) {
      _isLoaded = false;
      onStateChanged?.call();
    }
  }
}
