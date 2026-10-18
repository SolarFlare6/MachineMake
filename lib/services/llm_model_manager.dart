import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/needle/llm/local_llm_runtime.dart';
import '../core/needle/llm/model_catalog.dart';

/// Lifecycle states of the downloadable local GGUF model (`SmolLM2-360M-Instruct`).
enum LlmModelState {
  /// Model file is not on disk (0 MB used).
  notInstalled,

  /// Model is actively downloading from Hugging Face.
  downloading,

  /// Download was paused or interrupted; `.part` file exists for HTTP Range resume.
  downloadPaused,

  /// Verifying GGUF magic header and file integrity.
  verifying,

  /// `.gguf` file is verified on disk (~271 MB), not currently loaded in RAM.
  installed,

  /// Loading `.gguf` weights into native `llama.cpp` memory.
  loadingIntoRam,

  /// Model is loaded in RAM and ready for instant inference.
  readyInRam,

  /// An error occurred during download, verification, or loading.
  error,
}

/// Manages downloading, verifying, deleting, and loading the optional
/// `SmolLM2-360M-Instruct` (`Q4_K_M`, ~271 MB) model on the user's phone.
class LlmModelManager extends ChangeNotifier {
  static final LlmModelManager _instance = LlmModelManager._internal();
  factory LlmModelManager() => _instance;
  static LlmModelManager get instance => _instance;

  static const String _prefEnabled = 'needle_llm_enabled';
  static const String _prefWifiOnly = 'needle_llm_wifi_only';
  static const String _prefPreload = 'needle_llm_preload_on_voice';

  final LlmModelSpec modelSpec = ModelCatalog.defaultModel;
  late LocalLlmRuntime _runtime;

  LlmModelState _state = LlmModelState.notInstalled;
  double _downloadProgress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = ModelCatalog.defaultModel.expectedSizeBytes;
  String? _errorMessage;

  bool _isEnabled = true;
  bool _wifiOnly = true;
  bool _preloadOnVoiceDialog = true;

  http.Client? _activeHttpClient;
  bool _cancelRequested = false;

  LlmModelManager._internal() {
    _runtime = LlamaFlutterRuntime(
      onStateChanged: () {
        if (_runtime.isLoaded && _state != LlmModelState.readyInRam) {
          _state = LlmModelState.readyInRam;
          notifyListeners();
        } else if (!_runtime.isLoaded && _state == LlmModelState.readyInRam) {
          _state = LlmModelState.installed;
          notifyListeners();
        }
      },
    );
  }

  /// Allows unit tests to inject a mock [LocalLlmRuntime].
  @visibleForTesting
  void setRuntimeForTesting(LocalLlmRuntime mockRuntime, {LlmModelState? state}) {
    _runtime = mockRuntime;
    if (state != null) {
      _state = state;
    }
    notifyListeners();
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  LlmModelState get state => _state;
  double get downloadProgress => _downloadProgress;
  int get downloadedBytes => _downloadedBytes;
  int get totalBytes => _totalBytes;
  String? get errorMessage => _errorMessage;

  bool get isEnabled => _isEnabled;
  bool get wifiOnly => _wifiOnly;
  bool get preloadOnVoiceDialog => _preloadOnVoiceDialog;

  LocalLlmRuntime get runtime => _runtime;

  bool get isInstalled =>
      _state == LlmModelState.installed ||
      _state == LlmModelState.loadingIntoRam ||
      _state == LlmModelState.readyInRam;

  bool get isReadyForInference =>
      _isEnabled &&
      (_state == LlmModelState.installed || _state == LlmModelState.readyInRam);

  String get formattedDownloadedMb =>
      '${(_downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  String get formattedTotalMb =>
      '${(_totalBytes / (1024 * 1024)).toStringAsFixed(0)} MB';

  // ── Initialization & Persistence ──────────────────────────────────────────

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(_prefEnabled) ?? true;
    _wifiOnly = prefs.getBool(_prefWifiOnly) ?? true;
    _preloadOnVoiceDialog = prefs.getBool(_prefPreload) ?? true;

    await refreshDiskState();
  }

  Future<void> setEnabled(bool value) async {
    _isEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, value);
    if (!value && _runtime.isLoaded) {
      await _runtime.unload();
      await refreshDiskState();
    }
    notifyListeners();
  }

  Future<void> setWifiOnly(bool value) async {
    _wifiOnly = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefWifiOnly, value);
    notifyListeners();
  }

  Future<void> setPreloadOnVoiceDialog(bool value) async {
    _preloadOnVoiceDialog = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefPreload, value);
    notifyListeners();
  }

  // ── File Paths & Disk Verification ────────────────────────────────────────

  Future<Directory> _getModelDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    final modelDir = Directory('${supportDir.path}/models');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return modelDir;
  }

  Future<File> getModelFile() async {
    final dir = await _getModelDirectory();
    return File('${dir.path}/${modelSpec.fileName}');
  }

  Future<File> _getPartFile() async {
    final dir = await _getModelDirectory();
    return File('${dir.path}/${modelSpec.fileName}.part');
  }

  /// Checks if the `.gguf` model or `.part` file exists on disk and updates [state].
  Future<void> refreshDiskState() async {
    try {
      final file = await getModelFile();
      if (await file.exists()) {
        final len = await file.length();
        final valid = await _verifyGgufFile(file);
        if (valid) {
          _downloadedBytes = len;
          _totalBytes = len;
          _downloadProgress = 1.0;
          _state = _runtime.isLoaded
              ? LlmModelState.readyInRam
              : LlmModelState.installed;
          _errorMessage = null;
          notifyListeners();
          return;
        } else {
          // Corrupted file: remove it
          await file.delete();
        }
      }

      final partFile = await _getPartFile();
      if (await partFile.exists()) {
        final partLen = await partFile.length();
        if (partLen > 0) {
          _downloadedBytes = partLen;
          _totalBytes = modelSpec.expectedSizeBytes;
          _downloadProgress =
              (partLen / _totalBytes).clamp(0.0, 0.99);
          _state = LlmModelState.downloadPaused;
          notifyListeners();
          return;
        }
      }

      _downloadedBytes = 0;
      _totalBytes = modelSpec.expectedSizeBytes;
      _downloadProgress = 0.0;
      _state = LlmModelState.notInstalled;
      notifyListeners();
    } catch (e) {
      _state = LlmModelState.notInstalled;
      notifyListeners();
    }
  }

  /// Verifies that [file] has at least [modelSpec.minIntegrityBytes] and starts
  /// with the 4-byte ASCII magic header `GGUF` (`0x47, 0x47, 0x55, 0x46`).
  Future<bool> _verifyGgufFile(File file) async {
    try {
      if (!await file.exists()) return false;
      final length = await file.length();
      if (length < modelSpec.minIntegrityBytes) return false;

      final raf = await file.open(mode: FileMode.read);
      try {
        final magic = await raf.read(4);
        if (magic.length < 4) return false;
        // 'G' = 0x47, 'G' = 0x47, 'U' = 0x55, 'F' = 0x46
        return magic[0] == 0x47 &&
            magic[1] == 0x47 &&
            magic[2] == 0x55 &&
            magic[3] == 0x46;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  // ── Download / Cancel / Delete / Load ─────────────────────────────────────

  /// Downloads `SmolLM2-360M-Instruct-Q4_K_M.gguf` from Hugging Face with HTTP
  /// Range resume support and live progress updates.
  Future<bool> downloadModel() async {
    if (_state == LlmModelState.downloading ||
        _state == LlmModelState.verifying) {
      return false;
    }

    _cancelRequested = false;
    _errorMessage = null;
    _state = LlmModelState.downloading;
    notifyListeners();

    final partFile = await _getPartFile();
    final targetFile = await getModelFile();

    int existingBytes = 0;
    if (await partFile.exists()) {
      existingBytes = await partFile.length();
    }

    _downloadedBytes = existingBytes;
    _activeHttpClient = http.Client();

    try {
      http.StreamedResponse? response = await _sendDownloadRequest(
        _activeHttpClient!,
        modelSpec.downloadUrl,
        existingBytes,
      );

      // Try fallback URL if primary fails
      if (response == null ||
          (response.statusCode != 200 && response.statusCode != 206)) {
        response = await _sendDownloadRequest(
          _activeHttpClient!,
          modelSpec.fallbackDownloadUrl,
          existingBytes,
        );
      }

      if (response == null ||
          (response.statusCode != 200 && response.statusCode != 206)) {
        throw HttpException(
          'Download server returned HTTP ${response?.statusCode ?? "error"}',
        );
      }

      // If server returned 200 instead of 206 Partial Content, restart from 0
      final isResumed = response.statusCode == 206 && existingBytes > 0;
      if (!isResumed) {
        existingBytes = 0;
        _downloadedBytes = 0;
      }

      final contentLen = response.contentLength ?? 0;
      if (contentLen > 0) {
        _totalBytes = existingBytes + contentLen;
      } else {
        _totalBytes = modelSpec.expectedSizeBytes;
      }

      final sink = partFile.openWrite(
        mode: isResumed ? FileMode.append : FileMode.write,
      );

      int lastNotifiedBytes = _downloadedBytes;
      try {
        await for (final chunk in response.stream) {
          if (_cancelRequested) {
            await sink.flush();
            await sink.close();
            _state = LlmModelState.downloadPaused;
            notifyListeners();
            return false;
          }

          sink.add(chunk);
          _downloadedBytes += chunk.length;
          if (_totalBytes > 0) {
            _downloadProgress =
                (_downloadedBytes / _totalBytes).clamp(0.0, 0.99);
          }

          // Throttle UI notifications to ~every 512 KB
          if (_downloadedBytes - lastNotifiedBytes >= 512 * 1024) {
            lastNotifiedBytes = _downloadedBytes;
            notifyListeners();
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      // Verify GGUF magic header & size before renaming
      _state = LlmModelState.verifying;
      _downloadProgress = 1.0;
      notifyListeners();

      final isValid = await _verifyGgufFile(partFile);
      if (!isValid) {
        await partFile.delete();
        throw const FileSystemException(
          'Downloaded file failed GGUF header or size verification.',
        );
      }

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await partFile.rename(targetFile.path);

      _totalBytes = await targetFile.length();
      _downloadedBytes = _totalBytes;
      _state = LlmModelState.installed;
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      if (_cancelRequested) {
        _state = LlmModelState.downloadPaused;
      } else {
        _state = LlmModelState.error;
        _errorMessage = _formatError(e);
      }
      notifyListeners();
      return false;
    } finally {
      _activeHttpClient?.close();
      _activeHttpClient = null;
    }
  }

  Future<http.StreamedResponse?> _sendDownloadRequest(
    http.Client client,
    String url,
    int rangeStart,
  ) async {
    try {
      final req = http.Request('GET', Uri.parse(url));
      if (rangeStart > 0) {
        req.headers['Range'] = 'bytes=$rangeStart-';
      }
      return await client.send(req).timeout(const Duration(seconds: 25));
    } catch (_) {
      return null;
    }
  }

  /// Pauses/cancels an in-progress download while keeping the `.part` file for
  /// resuming later.
  void pauseDownload() {
    if (_state == LlmModelState.downloading) {
      _cancelRequested = true;
      _activeHttpClient?.close();
      _state = LlmModelState.downloadPaused;
      notifyListeners();
    }
  }

  /// Unloads the model from RAM (if loaded) and deletes both `.gguf` and `.part`
  /// files from device storage, freeing ~271 MB immediately.
  Future<void> deleteModel() async {
    _cancelRequested = true;
    _activeHttpClient?.close();

    if (_runtime.isLoaded) {
      await _runtime.unload();
    }

    try {
      final modelFile = await getModelFile();
      if (await modelFile.exists()) {
        await modelFile.delete();
      }
    } catch (_) {}

    try {
      final partFile = await _getPartFile();
      if (await partFile.exists()) {
        await partFile.delete();
      }
    } catch (_) {}

    _downloadedBytes = 0;
    _totalBytes = modelSpec.expectedSizeBytes;
    _downloadProgress = 0.0;
    _errorMessage = null;
    _state = LlmModelState.notInstalled;
    notifyListeners();
  }

  /// Ensures the model is loaded into native `llama.cpp` RAM before inference.
  Future<bool> ensureLoadedInRam() async {
    if (!_isEnabled) return false;
    if (_runtime.isLoaded) {
      _state = LlmModelState.readyInRam;
      return true;
    }

    final file = await getModelFile();
    if (!await file.exists()) {
      await refreshDiskState();
      return false;
    }

    final prevState = _state;
    _state = LlmModelState.loadingIntoRam;
    _errorMessage = null;
    notifyListeners();

    try {
      await _runtime.loadModel(
        file.path,
        threads: 4,
        contextSize: modelSpec.contextSize,
      );
      _state = LlmModelState.readyInRam;
      notifyListeners();
      return true;
    } catch (e) {
      _state = prevState == LlmModelState.installed
          ? LlmModelState.installed
          : LlmModelState.error;
      _errorMessage = 'Failed to load model into RAM: ${_formatError(e)}';
      notifyListeners();
      return false;
    }
  }

  String _formatError(Object error) {
    if (error is PlatformException) {
      final msg = error.message ?? error.code;
      final firstLine = msg.split('\n').first.trim();
      if (firstLine.contains('Local AI is not supported on this device')) {
        return 'Native llama.cpp library was not packaged for this CPU ABI (rebuild the APK with flutter run). Falling back to Fast Rules.';
      }
      return firstLine;
    }
    final raw = error.toString();
    final idx = raw.indexOf(', Stacktrace:');
    if (idx != -1) {
      return raw.substring(0, idx);
    }
    return raw.split('\n').first.trim();
  }

  /// Preloads the model in the background when the user opens the Voice Command
  /// dialog (if enabled in Settings).
  void preloadIfConfigured() {
    if (_isEnabled &&
        _preloadOnVoiceDialog &&
        _state == LlmModelState.installed &&
        !_runtime.isLoaded) {
      unawaited(ensureLoadedInRam());
    }
  }
}
