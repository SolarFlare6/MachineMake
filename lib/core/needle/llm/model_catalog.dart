/// Metadata describing a downloadable GGUF model for Needle AI local inference.
class LlmModelSpec {
  final String id;
  final String displayName;
  final String fileName;
  final String downloadUrl;
  final String fallbackDownloadUrl;
  final int expectedSizeBytes;
  final int minIntegrityBytes;
  final int contextSize;
  final String quantization;
  final String description;

  const LlmModelSpec({
    required this.id,
    required this.displayName,
    required this.fileName,
    required this.downloadUrl,
    required this.fallbackDownloadUrl,
    required this.expectedSizeBytes,
    required this.minIntegrityBytes,
    this.contextSize = 1024,
    required this.quantization,
    required this.description,
  });

  /// Human-readable size in MB (e.g. "271 MB").
  String get formattedSizeMb =>
      '${(expectedSizeBytes / (1024 * 1024)).round()} MB';
}

/// Catalog of supported on-device GGUF models for Needle AI.
class ModelCatalog {
  ModelCatalog._();

  /// Default recommended model: `SmolLM2-360M-Instruct` (`Q4_K_M`, ~271 MB).
  static const LlmModelSpec smolLm2_360m = LlmModelSpec(
    id: 'smollm2-360m-instruct-q4_k_m',
    displayName: 'SmolLM2-360M-Instruct',
    fileName: 'SmolLM2-360M-Instruct-Q4_K_M.gguf',
    downloadUrl:
        'https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q4_k_m.gguf',
    fallbackDownloadUrl:
        'https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q4_K_M.gguf',
    expectedSizeBytes: 270840000, // ~258-271 MB
    minIntegrityBytes: 200 * 1024 * 1024, // At least 200 MB + GGUF magic header
    contextSize: 1024,
    quantization: 'Q4_K_M (4-bit)',
    description:
        'Fast offline instruction-tuned model for complex phrasing, indirect commands, and multi-step tool chains.',
  );

  static const LlmModelSpec defaultModel = smolLm2_360m;
}
