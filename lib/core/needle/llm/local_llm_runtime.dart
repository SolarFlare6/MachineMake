import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

/// Abstract interface for Needle AI's on-device LLM runtime.
///
/// Supports both the official Cactus Compute Needle 3 C runtime (`.cact` via
/// `libneedle_bridge.so` + `libneedle.a`) and `llama.cpp` GGUF models, while
/// allowing unit tests to inject a mock runtime.
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
    String? toolsJson,
    int maxTokens = 96,
    double temperature = 0.05,
    Duration timeout = const Duration(milliseconds: 2800),
  });

  Future<void> stop();
  Future<void> unload();
}

// ── Native FFI Typedefs for libneedle_bridge.so (Cactus Compute Needle 3) ───

typedef _AllocNative = ffi.Pointer<ffi.Uint8> Function(ffi.Int32 size);
typedef _AllocDart = ffi.Pointer<ffi.Uint8> Function(int size);

typedef _FreeNative = ffi.Void Function(ffi.Pointer<ffi.Uint8> ptr);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Uint8> ptr);

typedef _IsSupportedAbiNative = ffi.Int32 Function();
typedef _IsSupportedAbiDart = int Function();

typedef _LastErrorNative = ffi.Pointer<ffi.Uint8> Function();
typedef _LastErrorDart = ffi.Pointer<ffi.Uint8> Function();

typedef _LoadFileNative = ffi.Int32 Function(ffi.Pointer<ffi.Uint8> path);
typedef _LoadFileDart = int Function(ffi.Pointer<ffi.Uint8> path);

typedef _InitNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> systemPrompt,
  ffi.Pointer<ffi.Uint8> toolsJson,
);
typedef _InitDart = int Function(
  ffi.Pointer<ffi.Uint8> systemPrompt,
  ffi.Pointer<ffi.Uint8> toolsJson,
);

typedef _CompleteNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> input,
  ffi.Int32 maxNewTokens,
  ffi.Pointer<ffi.Uint8> out,
  ffi.Int32 outCapacity,
);
typedef _CompleteDart = int Function(
  ffi.Pointer<ffi.Uint8> input,
  int maxNewTokens,
  ffi.Pointer<ffi.Uint8> out,
  int outCapacity,
);

typedef _ResetNative = ffi.Void Function();
typedef _ResetDart = void Function();

class _NeedleBridgeFfi {
  final ffi.DynamicLibrary lib;
  late final _AllocDart alloc;
  late final _FreeDart free;
  late final _IsSupportedAbiDart isSupportedAbi;
  late final _LastErrorDart lastError;
  late final _LoadFileDart loadFile;
  late final _InitDart init;
  late final _CompleteDart complete;
  late final _ResetDart reset;

  _NeedleBridgeFfi(this.lib) {
    alloc = lib.lookupFunction<_AllocNative, _AllocDart>('machmake_needle_alloc');
    free = lib.lookupFunction<_FreeNative, _FreeDart>('machmake_needle_free');
    isSupportedAbi = lib.lookupFunction<_IsSupportedAbiNative, _IsSupportedAbiDart>(
      'machmake_needle_is_supported_abi',
    );
    lastError = lib.lookupFunction<_LastErrorNative, _LastErrorDart>(
      'machmake_needle_last_error',
    );
    loadFile = lib.lookupFunction<_LoadFileNative, _LoadFileDart>(
      'machmake_needle_load_file',
    );
    init = lib.lookupFunction<_InitNative, _InitDart>('machmake_needle_init');
    complete = lib.lookupFunction<_CompleteNative, _CompleteDart>(
      'machmake_needle_complete',
    );
    reset = lib.lookupFunction<_ResetNative, _ResetDart>('machmake_needle_reset');
  }

  static _NeedleBridgeFfi? _instance;
  static _NeedleBridgeFfi open() {
    return _instance ??= _NeedleBridgeFfi(
      ffi.DynamicLibrary.open('libneedle_bridge.so'),
    );
  }

  ffi.Pointer<ffi.Uint8> toNativeUtf8(String text) {
    final bytes = utf8.encode(text);
    final ptr = alloc(bytes.length + 1);
    if (ptr == ffi.nullptr) {
      throw StateError('Failed to allocate native UTF-8 buffer');
    }
    final list = ptr.asTypedList(bytes.length + 1);
    list.setRange(0, bytes.length, bytes);
    list[bytes.length] = 0;
    return ptr;
  }

  String readNullTerminatedUtf8(ffi.Pointer<ffi.Uint8> ptr, {int maxBytes = 65536}) {
    if (ptr == ffi.nullptr) return '';
    int len = 0;
    while (len < maxBytes && (ptr + len).value != 0) {
      len++;
    }
    if (len == 0) return '';
    return utf8.decode(ptr.asTypedList(len), allowMalformed: true);
  }

  String getLastErrorString() {
    return readNullTerminatedUtf8(lastError(), maxBytes: 1024);
  }
}

/// Top-level isolate worker that loads `needle3.cact` via `libneedle_bridge.so`.
void _isolateLoadNeedleModel(String modelPath) {
  final bridge = _NeedleBridgeFfi.open();
  if (bridge.isSupportedAbi() == 0) {
    throw UnsupportedError(bridge.getLastErrorString());
  }
  final pathPtr = bridge.toNativeUtf8(modelPath);
  try {
    final rc = bridge.loadFile(pathPtr);
    if (rc < 0) {
      throw StateError(
        'Failed to load Cactus Needle 3 model: ${bridge.getLastErrorString()}',
      );
    }
  } finally {
    bridge.free(pathPtr);
  }
}

/// Top-level isolate worker that initializes tool grammar & completes a user prompt.
String _isolateCompleteNeedlePrompt(List<Object?> args) {
  final modelPath = args[0] as String;
  final systemPrompt = args[1] as String;
  final toolsJson = args[2] as String;
  final userPrompt = args[3] as String;
  final maxTokens = args[4] as int;

  final bridge = _NeedleBridgeFfi.open();
  if (bridge.isSupportedAbi() == 0) {
    throw UnsupportedError(bridge.getLastErrorString());
  }

  final pathPtr = bridge.toNativeUtf8(modelPath);
  final sysPtr = bridge.toNativeUtf8(systemPrompt);
  final toolsPtr = bridge.toNativeUtf8(toolsJson);
  final inputPtr = bridge.toNativeUtf8(userPrompt);
  const outCapacity = 65536;
  final outPtr = bridge.alloc(outCapacity);

  try {
    final loadRc = bridge.loadFile(pathPtr);
    if (loadRc < 0) {
      throw StateError(
        'Needle model not loaded: ${bridge.getLastErrorString()}',
      );
    }

    bridge.reset();

    final initRc = bridge.init(sysPtr, toolsPtr);
    if (initRc < 0) {
      throw StateError(
        'needle_init failed (rc=$initRc): ${bridge.getLastErrorString()}',
      );
    }

    final compRc = bridge.complete(inputPtr, maxTokens, outPtr, outCapacity);
    final output = bridge.readNullTerminatedUtf8(outPtr, maxBytes: outCapacity);
    if (compRc < 0 && output.isEmpty) {
      throw StateError(
        'needle_complete failed (rc=$compRc): ${bridge.getLastErrorString()}',
      );
    }
    return output;
  } finally {
    bridge.free(pathPtr);
    bridge.free(sysPtr);
    bridge.free(toolsPtr);
    bridge.free(inputPtr);
    bridge.free(outPtr);
  }
}

/// Official Cactus Compute Needle 3 runtime (`needle3.cact`, 34 MB) using
/// `dart:ffi` to invoke `needle_load`, `needle_init`, and `needle_complete`
/// from `libneedle.a`.
///
/// Automatically delegates `.gguf` files to [LlamaFlutterRuntime] if a GGUF
/// model path is provided.
class CactusNeedleRuntime implements LocalLlmRuntime {
  String? _loadedModelPath;
  bool _isLoaded = false;
  bool _isGenerating = false;
  Timer? _idleTimer;
  Future<void>? _serialLock;
  LlamaFlutterRuntime? _ggufFallback;

  final Duration idleUnloadDuration;
  final VoidCallback? onStateChanged;

  CactusNeedleRuntime({
    this.idleUnloadDuration = const Duration(minutes: 5),
    this.onStateChanged,
  });

  @override
  bool get isLoaded => _isLoaded || (_ggufFallback?.isLoaded ?? false);

  @override
  bool get isGenerating =>
      _isGenerating || (_ggufFallback?.isGenerating ?? false);

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleUnloadDuration, () {
      unload();
    });
  }

  Future<T> _runSerialized<T>(Future<T> Function() action) async {
    while (_serialLock != null) {
      try {
        await _serialLock;
      } catch (_) {}
    }
    final completer = Completer<void>();
    _serialLock = completer.future;
    try {
      return await action();
    } finally {
      _serialLock = null;
      completer.complete();
    }
  }

  @override
  Future<void> loadModel(
    String modelPath, {
    int threads = 4,
    int contextSize = 2048,
  }) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Cactus Needle 3 native runtime is supported on Android devices.',
      );
    }

    final file = File(modelPath);
    if (!await file.exists()) {
      throw FileSystemException('Model file not found', modelPath);
    }

    if (modelPath.toLowerCase().endsWith('.gguf')) {
      _ggufFallback ??= LlamaFlutterRuntime(
        idleUnloadDuration: idleUnloadDuration,
        onStateChanged: onStateChanged,
      );
      await _ggufFallback!.loadModel(
        modelPath,
        threads: threads,
        contextSize: contextSize,
      );
      return;
    }

    await _runSerialized(() async {
      await compute(_isolateLoadNeedleModel, modelPath);
      _loadedModelPath = modelPath;
      _isLoaded = true;
      _resetIdleTimer();
      onStateChanged?.call();
    });
  }

  /// Extracts a clean 1-line role description for `needle_init` without GGUF
  /// ChatML few-shot examples that use a different JSON schema.
  static String _sanitizeNeedleSystemPrompt(String rawSystemPrompt) {
    final trimmed = rawSystemPrompt.trim();
    if (trimmed.isEmpty) return '';
    final firstLine = trimmed.split('\n').first.trim();
    if (firstLine.startsWith('You are')) {
      return firstLine;
    }
    return '';
  }

  @override
  Future<String> generateStructured({
    required String systemPrompt,
    required String userPrompt,
    String? gbnfGrammar,
    String? toolsJson,
    int maxTokens = 128,
    double temperature = 0.0,
    Duration timeout = const Duration(milliseconds: 6000),
  }) async {
    if (_ggufFallback != null && _ggufFallback!.isLoaded) {
      return _ggufFallback!.generateStructured(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        gbnfGrammar: gbnfGrammar,
        toolsJson: toolsJson,
        maxTokens: maxTokens,
        temperature: temperature,
        timeout: timeout,
      );
    }

    if (!_isLoaded || _loadedModelPath == null) {
      throw StateError('Cactus Needle 3 model is not loaded in memory.');
    }

    _resetIdleTimer();
    final modelPath = _loadedModelPath!;
    final needleSysPrompt = _sanitizeNeedleSystemPrompt(systemPrompt);
    final effectiveToolsJson =
        (toolsJson != null && toolsJson.trim().isNotEmpty) ? toolsJson : '[]';
    final payload = <Object?>[
      modelPath,
      needleSysPrompt,
      effectiveToolsJson,
      userPrompt,
      maxTokens,
    ];

    return _runSerialized(() async {
      _isGenerating = true;
      try {
        return await compute(_isolateCompleteNeedlePrompt, payload)
            .timeout(timeout);
      } finally {
        _isGenerating = false;
        _resetIdleTimer();
      }
    });
  }

  @override
  Future<void> stop() async {
    await _ggufFallback?.stop();
  }

  @override
  Future<void> unload() async {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_ggufFallback != null) {
      await _ggufFallback!.unload();
    }
    if (_isLoaded) {
      _isLoaded = false;
      onStateChanged?.call();
    }
  }
}

/// Concrete Android `llama.cpp` runtime powered by `llama_flutter_android`
/// (retained for GGUF compatibility).
class LlamaFlutterRuntime implements LocalLlmRuntime {
  LlamaController? _controller;
  bool _isLoaded = false;
  Timer? _idleTimer;

  final Duration idleUnloadDuration;
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
    String? toolsJson,
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
