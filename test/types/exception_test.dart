import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_native_3d/flutter_native_3d.dart';

void main() {
  group('exception hierarchy', () {
    test('ModelLoadException is a Native3DException', () {
      const e = ModelLoadException('fail');
      expect(e, isA<Native3DException>());
      expect(e, isA<Exception>());
    });

    test('AssetNotFoundException is a ModelLoadException', () {
      const e = AssetNotFoundException('not found');
      expect(e, isA<ModelLoadException>());
      expect(e, isA<Native3DException>());
      expect(e.code, 'ASSET_NOT_FOUND');
    });

    test('FileNotFoundException is a ModelLoadException', () {
      const e = FileNotFoundException('not found');
      expect(e, isA<ModelLoadException>());
      expect(e.code, 'FILE_NOT_FOUND');
    });

    test('NetworkException is a ModelLoadException', () {
      const e = NetworkException('timeout', statusCode: 503);
      expect(e, isA<ModelLoadException>());
      expect(e.code, 'NETWORK_ERROR');
      expect(e.statusCode, 503);
    });

    test('FormatNotSupportedException is a ModelLoadException', () {
      const e = FormatNotSupportedException('obj not supported');
      expect(e, isA<ModelLoadException>());
      expect(e.code, 'FORMAT_ERROR');
    });

    test('LoadSupersededException is a ModelLoadException', () {
      const e = LoadSupersededException();
      expect(e, isA<ModelLoadException>());
      expect(e.code, 'LOAD_SUPERSEDED');
    });

    test('AnimationException is a Native3DException', () {
      const e = AnimationException('not found');
      expect(e, isA<Native3DException>());
    });

    test('SceneException is a Native3DException', () {
      const e = SceneException('GPU error');
      expect(e, isA<Native3DException>());
    });

    test('ModelLoadException carries source', () {
      const source = ModelSource.asset('test.glb');
      const e = ModelLoadException('fail', source: source);
      expect(e.source, source);
    });

    test('LoadSupersededException carries source', () {
      const source = ModelSource.network('https://x.com/m.glb');
      const e = LoadSupersededException(source: source);
      expect(e.source, source);
    });
  });

  group('exception toString', () {
    test('Native3DException', () {
      const e = Native3DException('something broke', code: 'ERR');
      expect(e.toString(), 'Native3DException(ERR): something broke');
    });

    test('ModelLoadException with source', () {
      const e = ModelLoadException(
        'parse error',
        code: 'MODEL_LOAD_ERROR',
        source: ModelSource.asset('bad.glb'),
      );
      expect(e.toString(), contains('parse error'));
      expect(e.toString(), contains('bad.glb'));
    });

    test('NetworkException with statusCode', () {
      const e = NetworkException('forbidden', statusCode: 403);
      expect(e.toString(), contains('403'));
    });

    test('LoadSupersededException', () {
      const e = LoadSupersededException();
      expect(e.toString(), contains('superseded'));
    });
  });

  group('hierarchical catching', () {
    test('catch AssetNotFoundException as ModelLoadException', () {
      try {
        throw const AssetNotFoundException('gone');
      } on ModelLoadException catch (e) {
        expect(e.code, 'ASSET_NOT_FOUND');
      }
    });

    test('catch ModelLoadException as Native3DException', () {
      try {
        throw const ModelLoadException('fail');
      } on Native3DException catch (e) {
        expect(e, isA<ModelLoadException>());
      }
    });

    test('catch LoadSupersededException specifically before ModelLoadException', () {
      var caughtSpecific = false;
      try {
        throw const LoadSupersededException();
      } on LoadSupersededException {
        caughtSpecific = true;
      } on ModelLoadException {
        fail('Should have been caught by LoadSupersededException');
      }
      expect(caughtSpecific, isTrue);
    });
  });
}
