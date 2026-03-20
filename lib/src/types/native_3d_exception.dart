import 'model_source.dart';

/// Base exception for all flutter_native_3d errors.
///
/// Catch this to handle any plugin error. Use subtypes for specific handling.
///
/// ## Error codes
///
/// Each native error arrives with a string [code] that identifies the category.
/// The Dart layer maps these to typed exception subtypes:
///
/// | Code | Dart type | Meaning |
/// |------|-----------|---------|
/// | `MODEL_LOAD_ERROR` | [ModelLoadException] | glTF parse failure, file I/O error |
/// | `ASSET_NOT_FOUND` | [AssetNotFoundException] | Flutter asset path doesn't exist |
/// | `FILE_NOT_FOUND` | [FileNotFoundException] | Local file path doesn't exist |
/// | `NETWORK_ERROR` | [NetworkException] | HTTP error, timeout, DNS failure |
/// | `FORMAT_ERROR` | [FormatException] | Unsupported file extension |
/// | `ANIMATION_ERROR` | [AnimationException] | Invalid animation name/index |
/// | `LOAD_SUPERSEDED` | [LoadSupersededException] | Newer loadModel call replaced this one |
/// | `DISPOSED` | [StateError] (not a Native3DException) | Controller/view used after dispose |
class Native3DException implements Exception {
  final String message;
  final String? code;
  const Native3DException(this.message, {this.code});

  @override
  String toString() => 'Native3DException($code): $message';
}

// ---------------------------------------------------------------------------
// Model loading errors
// ---------------------------------------------------------------------------

/// Base class for all model loading failures.
class ModelLoadException extends Native3DException {
  /// The source that failed to load, if available.
  final ModelSource? source;

  const ModelLoadException(
    super.message, {
    super.code,
    this.source,
  });

  @override
  String toString() {
    final src = source != null ? ' source=$source' : '';
    return 'ModelLoadException($code): $message$src';
  }
}

/// A Flutter asset path could not be found in the app bundle.
class AssetNotFoundException extends ModelLoadException {
  const AssetNotFoundException(super.message, {super.source})
      : super(code: 'ASSET_NOT_FOUND');
}

/// A local file path does not exist or is not readable.
class FileNotFoundException extends ModelLoadException {
  const FileNotFoundException(super.message, {super.source})
      : super(code: 'FILE_NOT_FOUND');
}

/// A network request failed (HTTP error, timeout, DNS, etc.).
class NetworkException extends ModelLoadException {
  /// HTTP status code, if available.
  final int? statusCode;

  const NetworkException(
    super.message, {
    super.source,
    this.statusCode,
  }) : super(code: 'NETWORK_ERROR');

  @override
  String toString() {
    final status = statusCode != null ? ' HTTP $statusCode' : '';
    return 'NetworkException: $message$status';
  }
}

/// The file format is not supported (not .glb or .gltf).
class FormatNotSupportedException extends ModelLoadException {
  const FormatNotSupportedException(super.message, {super.source})
      : super(code: 'FORMAT_ERROR');
}

/// A newer [loadModel] call was made before this one completed.
///
/// This is not a real error -- it's a control flow signal. The widget
/// handles it automatically. User code can safely ignore it:
/// ```dart
/// try {
///   await controller.loadModel(source);
/// } on LoadSupersededException {
///   // Another load is in progress -- this one was cancelled. Fine.
/// }
/// ```
class LoadSupersededException extends ModelLoadException {
  const LoadSupersededException({ModelSource? source})
      : super('Load superseded by a newer request',
            code: 'LOAD_SUPERSEDED', source: source);
}

// ---------------------------------------------------------------------------
// Animation errors
// ---------------------------------------------------------------------------

/// An animation operation failed (invalid name, index out of range, etc.).
class AnimationException extends Native3DException {
  const AnimationException(super.message, {super.code});
}

// ---------------------------------------------------------------------------
// Scene errors
// ---------------------------------------------------------------------------

/// A native rendering error not tied to a specific operation.
///
/// Received via the [SceneErrorEvent] on the events stream.
/// Examples: GPU resource exhaustion, renderer crash, Metal/Filament error.
class SceneException extends Native3DException {
  const SceneException(super.message, {super.code});
}
