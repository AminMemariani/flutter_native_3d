import 'dart:typed_data';

/// Where to load a 3D model from.
///
/// Supported formats: glTF (.gltf), GLB (.glb).
///
/// All source types are immutable value objects with proper [==] and [hashCode].
/// Serialization to the native platform is handled internally and is not
/// part of the public API.
sealed class ModelSource {
  const ModelSource();

  /// Load from a Flutter asset bundle path.
  ///
  /// The [path] must include the full asset path as declared in pubspec.yaml.
  ///
  /// ```dart
  /// ModelSource.asset('assets/models/chair.glb')
  /// ```
  const factory ModelSource.asset(String path) = AssetModelSource;

  /// Load from an absolute file path on the device.
  ///
  /// The [path] should be an absolute path (e.g. from `getApplicationDocumentsDirectory()`).
  ///
  /// ```dart
  /// ModelSource.file('/data/user/0/com.example/files/model.glb')
  /// ```
  const factory ModelSource.file(String path) = FileModelSource;

  /// Load from a network URL.
  ///
  /// The file is downloaded and cached locally. Optionally pass [headers]
  /// for authenticated endpoints (e.g. Bearer tokens, API keys).
  ///
  /// ```dart
  /// ModelSource.network(
  ///   'https://api.example.com/models/chair.glb',
  ///   headers: {'Authorization': 'Bearer token123'},
  /// )
  /// ```
  const factory ModelSource.network(
    String url, {
    Map<String, String>? headers,
  }) = NetworkModelSource;

  /// Load from raw bytes already in memory.
  ///
  /// Useful for models that are decrypted at runtime, generated procedurally,
  /// or loaded from a custom source. [formatHint] tells the native loader
  /// which parser to use (defaults to `'glb'`).
  ///
  /// ```dart
  /// final bytes = await decryptModel(encryptedData);
  /// ModelSource.memory(bytes, formatHint: 'glb')
  /// ```
  factory ModelSource.memory(
    Uint8List bytes, {
    String formatHint,
  }) = MemoryModelSource;
}

// ---------------------------------------------------------------------------
// Subtypes
// ---------------------------------------------------------------------------

final class AssetModelSource extends ModelSource {
  final String path;

  const AssetModelSource(this.path)
      : assert(path != '', 'Asset path must not be empty');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssetModelSource && other.path == path;

  @override
  int get hashCode => Object.hash(runtimeType, path);

  @override
  String toString() => 'ModelSource.asset($path)';
}

final class FileModelSource extends ModelSource {
  final String path;

  const FileModelSource(this.path)
      : assert(path != '', 'File path must not be empty');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileModelSource && other.path == path;

  @override
  int get hashCode => Object.hash(runtimeType, path);

  @override
  String toString() => 'ModelSource.file($path)';
}

final class NetworkModelSource extends ModelSource {
  final String url;

  /// Optional HTTP headers sent with the download request.
  /// Useful for authentication (Bearer tokens, API keys, etc.).
  final Map<String, String>? headers;

  const NetworkModelSource(this.url, {this.headers})
      : assert(url != '', 'URL must not be empty');

  /// Equality is based on URL only. Headers are intentionally excluded
  /// because they often contain ephemeral tokens -- changing a token
  /// should not trigger a model reload via `didUpdateWidget`.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkModelSource && other.url == url;

  @override
  int get hashCode => Object.hash(runtimeType, url);

  @override
  String toString() {
    final hasHeaders = headers != null && headers!.isNotEmpty;
    return 'ModelSource.network($url${hasHeaders ? ', +headers' : ''})';
  }
}

final class MemoryModelSource extends ModelSource {
  final Uint8List bytes;

  /// Hint for the native loader to select the correct parser.
  /// Common values: `'glb'`, `'gltf'`.
  final String formatHint;

  MemoryModelSource(this.bytes, {this.formatHint = 'glb'})
      : assert(bytes.isNotEmpty, 'Bytes must not be empty');

  /// Identity equality only. Comparing byte arrays is O(n) and would
  /// make didUpdateWidget expensive for large models.
  @override
  String toString() => 'ModelSource.memory(${bytes.length} bytes, $formatHint)';
}
