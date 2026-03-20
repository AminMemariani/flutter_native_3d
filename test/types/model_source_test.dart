import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_native_3d/flutter_native_3d.dart';
import 'package:flutter_native_3d/src/platform/model_source_serializer.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Equality & hashCode
  // ---------------------------------------------------------------------------
  group('ModelSource equality', () {
    test('asset sources with same path are equal', () {
      const a = ModelSource.asset('assets/model.glb');
      const b = ModelSource.asset('assets/model.glb');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('asset sources with different paths are not equal', () {
      const a = ModelSource.asset('assets/a.glb');
      const b = ModelSource.asset('assets/b.glb');
      expect(a, isNot(equals(b)));
    });

    test('file sources with same path are equal', () {
      const a = ModelSource.file('/path/to/model.glb');
      const b = ModelSource.file('/path/to/model.glb');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('network sources with same url are equal', () {
      const a = ModelSource.network('https://example.com/model.glb');
      const b = ModelSource.network('https://example.com/model.glb');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('network sources with same url but different headers are equal', () {
      // Headers are intentionally excluded from equality -- ephemeral tokens
      // should not trigger model reloads via didUpdateWidget.
      const a = ModelSource.network(
        'https://example.com/model.glb',
        headers: {'Authorization': 'Bearer old'},
      );
      const b = ModelSource.network(
        'https://example.com/model.glb',
        headers: {'Authorization': 'Bearer new'},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different source types are never equal', () {
      const asset = ModelSource.asset('model.glb');
      const file = ModelSource.file('model.glb');
      const network = ModelSource.network('model.glb');
      expect(asset, isNot(equals(file)));
      expect(asset, isNot(equals(network)));
      expect(file, isNot(equals(network)));
    });

    test('memory sources use identity equality', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final a = ModelSource.memory(bytes);
      final b = ModelSource.memory(bytes);
      // Same Uint8List instance -> same identity
      expect(identical(a, a), isTrue);
      // Different instances with same bytes -> not equal (identity only)
      expect(a, isNot(equals(b)));
    });
  });

  // ---------------------------------------------------------------------------
  // toString
  // ---------------------------------------------------------------------------
  group('ModelSource toString', () {
    test('asset', () {
      const source = ModelSource.asset('assets/chair.glb');
      expect(source.toString(), 'ModelSource.asset(assets/chair.glb)');
    });

    test('file', () {
      const source = ModelSource.file('/tmp/model.glb');
      expect(source.toString(), 'ModelSource.file(/tmp/model.glb)');
    });

    test('network without headers', () {
      const source = ModelSource.network('https://example.com/m.glb');
      expect(source.toString(), 'ModelSource.network(https://example.com/m.glb)');
    });

    test('network with headers', () {
      const source = ModelSource.network(
        'https://example.com/m.glb',
        headers: {'Authorization': 'Bearer x'},
      );
      expect(source.toString(), 'ModelSource.network(https://example.com/m.glb, +headers)');
    });

    test('memory', () {
      final source = ModelSource.memory(Uint8List(1024), formatHint: 'gltf');
      expect(source.toString(), 'ModelSource.memory(1024 bytes, gltf)');
    });
  });

  // ---------------------------------------------------------------------------
  // Validation (asserts fire in debug mode only)
  // ---------------------------------------------------------------------------
  group('ModelSource validation', () {
    test('asset rejects empty path in debug', () {
      expect(
        () => ModelSource.asset(''),
        throwsA(isA<AssertionError>()),
      );
    });

    test('file rejects empty path in debug', () {
      expect(
        () => ModelSource.file(''),
        throwsA(isA<AssertionError>()),
      );
    });

    test('network rejects empty url in debug', () {
      expect(
        () => ModelSource.network(''),
        throwsA(isA<AssertionError>()),
      );
    });

    test('memory rejects empty bytes in debug', () {
      expect(
        () => ModelSource.memory(Uint8List(0)),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Serialization (internal, but tested to ensure channel protocol correctness)
  // ---------------------------------------------------------------------------
  group('serializeModelSource', () {
    test('asset', () {
      const source = ModelSource.asset('assets/model.glb');
      expect(serializeModelSource(source), {
        'type': 'asset',
        'path': 'assets/model.glb',
      });
    });

    test('file', () {
      const source = ModelSource.file('/data/model.glb');
      expect(serializeModelSource(source), {
        'type': 'file',
        'path': '/data/model.glb',
      });
    });

    test('network without headers', () {
      const source = ModelSource.network('https://example.com/model.glb');
      final map = serializeModelSource(source);
      expect(map, {
        'type': 'network',
        'path': 'https://example.com/model.glb',
      });
      expect(map.containsKey('headers'), isFalse);
    });

    test('network with headers', () {
      const source = ModelSource.network(
        'https://example.com/model.glb',
        headers: {'Authorization': 'Bearer token123'},
      );
      expect(serializeModelSource(source), {
        'type': 'network',
        'path': 'https://example.com/model.glb',
        'headers': {'Authorization': 'Bearer token123'},
      });
    });

    test('network with empty headers omits key', () {
      const source = ModelSource.network(
        'https://example.com/model.glb',
        headers: {},
      );
      final map = serializeModelSource(source);
      expect(map.containsKey('headers'), isFalse);
    });

    test('memory', () {
      final bytes = Uint8List.fromList([0x67, 0x6C, 0x54, 0x46]);
      final source = ModelSource.memory(bytes, formatHint: 'glb');
      final map = serializeModelSource(source);
      expect(map['type'], 'memory');
      expect(map['bytes'], same(bytes));
      expect(map['formatHint'], 'glb');
    });

    test('memory default formatHint is glb', () {
      final source = ModelSource.memory(Uint8List.fromList([1]));
      final map = serializeModelSource(source);
      expect(map['formatHint'], 'glb');
    });
  });

  // ---------------------------------------------------------------------------
  // Exhaustive pattern matching (compile-time guarantee)
  // ---------------------------------------------------------------------------
  group('sealed class exhaustiveness', () {
    test('switch covers all cases', () {
      // This test verifies that all subtypes are matchable.
      // If a new subtype is added without updating this switch,
      // the analyzer will emit a compile error.
      final sources = <ModelSource>[
        const ModelSource.asset('a.glb'),
        const ModelSource.file('/b.glb'),
        const ModelSource.network('https://c.glb'),
        ModelSource.memory(Uint8List.fromList([1])),
      ];

      for (final source in sources) {
        final label = switch (source) {
          AssetModelSource() => 'asset',
          FileModelSource() => 'file',
          NetworkModelSource() => 'network',
          MemoryModelSource() => 'memory',
        };
        expect(label, isNotEmpty);
      }
    });
  });
}
