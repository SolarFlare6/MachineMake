/// Metadata describing a downloadable on-device model for Needle AI local inference.
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

  /// Human-readable size in MB (e.g. "34 MB").
  String get formattedSizeMb =>
      '${(expectedSizeBytes / (1024 * 1024)).round()} MB';
}

/// Catalog of supported on-device models for Needle AI.
class ModelCatalog {
  ModelCatalog._();

  /// Official Cactus Compute Needle 3 on-device function-calling model (`needle3.cact`, ~34 MB).
  /// Source: https://github.com/cactus-compute/needle & https://huggingface.co/Cactus-Compute/needle3
  static const LlmModelSpec needle3 = LlmModelSpec(
    id: 'cactus-needle-3-cact',
    displayName: 'Cactus Needle 3',
    fileName: 'needle3.cact',
    downloadUrl:
        'https://huggingface.co/Cactus-Compute/needle3/resolve/main/needle3.cact',
    fallbackDownloadUrl:
        'https://huggingface.co/Cactus-Compute/needle3/resolve/main/needle3.cact?download=true',
    expectedSizeBytes: 35337728, // ~33.7 MB
    minIntegrityBytes: 30 * 1024 * 1024, // At least 30 MB + .cact magic header
    contextSize: 2048,
    quantization: 'CQ2 (2.125-bit SAN)',
    description:
        'Official Cactus Compute Needle 3 (110M params, 34 MB) purpose-built for fast on-device grammar-constrained tool calling.',
  );

  /// Secondary GGUF model (`SmolLM2-360M-Instruct`, `Q4_K_M`, ~271 MB).
  static const LlmModelSpec smolLm2_360m = LlmModelSpec(
    id: 'smollm2-360m-instruct-q4_k_m',
    displayName: 'SmolLM2-360M-Instruct',
    fileName: 'SmolLM2-360M-Instruct-Q4_K_M.gguf',
    downloadUrl:
        'https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q4_k_m.gguf',
    fallbackDownloadUrl:
        'https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q4_K_M.gguf',
    expectedSizeBytes: 270840000,
    minIntegrityBytes: 200 * 1024 * 1024,
    contextSize: 1024,
    quantization: 'Q4_K_M (4-bit)',
    description:
        'Offline instruction-tuned GGUF model for complex phrasing and multi-step tool chains.',
  );

  static const LlmModelSpec defaultModel = needle3;
}
