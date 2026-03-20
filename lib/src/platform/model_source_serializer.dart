import '../types/model_source.dart';

/// Serialize a [ModelSource] to a map suitable for method channel transport.
///
/// Internal to the plugin. Not part of the public API.
///
/// The native side expects:
/// - asset:   `{type: 'asset',   path: String}`
/// - file:    `{type: 'file',    path: String}`
/// - network: `{type: 'network', path: String, headers?: Map<String,String>}`
/// - memory:  `{type: 'memory',  bytes: Uint8List, formatHint: String}`
Map<String, dynamic> serializeModelSource(ModelSource source) {
  return switch (source) {
    AssetModelSource(:final path) => {
      'type': 'asset',
      'path': path,
    },
    FileModelSource(:final path) => {
      'type': 'file',
      'path': path,
    },
    NetworkModelSource(:final url, :final headers) => {
      'type': 'network',
      'path': url,
      if (headers != null && headers.isNotEmpty) 'headers': headers,
    },
    MemoryModelSource(:final bytes, :final formatHint) => {
      'type': 'memory',
      'bytes': bytes,
      'formatHint': formatHint,
    },
  };
}
