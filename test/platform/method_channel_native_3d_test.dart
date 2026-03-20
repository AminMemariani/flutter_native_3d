import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_native_3d/src/platform/method_channel_native_3d.dart';
import 'package:flutter_native_3d/flutter_native_3d.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannelNative3D platform;
  late List<MethodCall> log;

  setUp(() {
    log = [];
    platform = MethodChannelNative3D(42);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_native_3d/scene_42'),
      (MethodCall call) async {
        log.add(call);
        switch (call.method) {
          case 'loadModel':
            return {'animationNames': ['Walk', 'Run']};
          case 'getAnimationNames':
            return ['Walk', 'Run'];
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_native_3d/scene_42'),
      null,
    );
  });

  // ---------------------------------------------------------------------------
  // loadModel
  // ---------------------------------------------------------------------------
  group('loadModel', () {
    test('asset source', () async {
      final info =
          await platform.loadModel(const ModelSource.asset('test.glb'));
      expect(log.first.method, 'loadModel');
      expect(log.first.arguments, {'type': 'asset', 'path': 'test.glb'});
      expect(info.animationNames, ['Walk', 'Run']);
    });

    test('file source', () async {
      await platform.loadModel(const ModelSource.file('/tmp/model.glb'));
      expect(log.first.arguments, {'type': 'file', 'path': '/tmp/model.glb'});
    });

    test('network source without headers', () async {
      await platform
          .loadModel(const ModelSource.network('https://example.com/m.glb'));
      final args = log.first.arguments as Map;
      expect(args['type'], 'network');
      expect(args['path'], 'https://example.com/m.glb');
      expect(args.containsKey('headers'), isFalse);
    });

    test('network source with headers', () async {
      await platform.loadModel(const ModelSource.network(
        'https://example.com/m.glb',
        headers: {'Authorization': 'Bearer xyz'},
      ));
      final args = log.first.arguments as Map;
      expect(args['headers'], {'Authorization': 'Bearer xyz'});
    });

    test('memory source', () async {
      final bytes = Uint8List.fromList([0x67, 0x6C, 0x54, 0x46]);
      await platform.loadModel(ModelSource.memory(bytes, formatHint: 'gltf'));
      final args = log.first.arguments as Map;
      expect(args['type'], 'memory');
      expect(args['bytes'], bytes);
      expect(args['formatHint'], 'gltf');
    });
  });

  // ---------------------------------------------------------------------------
  // loadModel errors
  // ---------------------------------------------------------------------------
  group('loadModel errors', () {
    test('MODEL_LOAD_ERROR maps to ModelLoadException', () {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_native_3d/scene_42'),
        (MethodCall call) async {
          throw PlatformException(code: 'MODEL_LOAD_ERROR', message: 'Parse failed');
        },
      );
      const source = ModelSource.file('/bad.glb');
      expect(
        () => platform.loadModel(source),
        throwsA(
          isA<ModelLoadException>()
              .having((e) => e.code, 'code', 'MODEL_LOAD_ERROR')
              .having((e) => e.source, 'source', source),
        ),
      );
    });

    test('ASSET_NOT_FOUND maps to AssetNotFoundException', () {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_native_3d/scene_42'),
        (MethodCall call) async {
          throw PlatformException(code: 'ASSET_NOT_FOUND', message: 'Asset not found: bad.glb');
        },
      );
      expect(
        () => platform.loadModel(const ModelSource.asset('bad.glb')),
        throwsA(isA<AssetNotFoundException>()),
      );
    });

    test('NETWORK_ERROR maps to NetworkException', () {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_native_3d/scene_42'),
        (MethodCall call) async {
          throw PlatformException(code: 'NETWORK_ERROR', message: 'HTTP 403');
        },
      );
      expect(
        () => platform.loadModel(const ModelSource.network('https://x.com/m.glb')),
        throwsA(isA<NetworkException>()),
      );
    });

    test('FORMAT_ERROR maps to FormatNotSupportedException', () {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_native_3d/scene_42'),
        (MethodCall call) async {
          throw PlatformException(code: 'FORMAT_ERROR', message: 'Unsupported: obj');
        },
      );
      expect(
        () => platform.loadModel(const ModelSource.file('/model.glb')),
        throwsA(isA<FormatNotSupportedException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Camera
  // ---------------------------------------------------------------------------
  test('resetCamera sends correct method', () async {
    await platform.resetCamera();
    expect(log.first.method, 'resetCamera');
  });

  test('setCameraOrbit sends theta, phi, radius', () async {
    await platform
        .setCameraOrbit(const CameraOrbit(theta: 45, phi: 30, radius: 5));
    expect(log.first.method, 'setCameraOrbit');
    expect(log.first.arguments, {'theta': 45.0, 'phi': 30.0, 'radius': 5.0});
  });

  // ---------------------------------------------------------------------------
  // Animations
  // ---------------------------------------------------------------------------
  test('getAnimationNames returns list', () async {
    final names = await platform.getAnimationNames();
    expect(names, ['Walk', 'Run']);
  });

  test('playAnimation sends name and loop', () async {
    await platform.playAnimation(name: 'Walk', loop: false);
    expect(log.first.method, 'playAnimation');
    expect(log.first.arguments, {'name': 'Walk', 'loop': false});
  });

  test('playAnimationByIndex sends index and loop', () async {
    await platform.playAnimationByIndex(index: 1, loop: false);
    expect(log.first.method, 'playAnimationByIndex');
    expect(log.first.arguments, {'index': 1, 'loop': false});
  });

  test('pauseAnimation sends correct method', () async {
    await platform.pauseAnimation();
    expect(log.first.method, 'pauseAnimation');
  });

  test('stopAnimation sends correct method', () async {
    await platform.stopAnimation();
    expect(log.first.method, 'stopAnimation');
  });

  // ---------------------------------------------------------------------------
  // Appearance
  // ---------------------------------------------------------------------------
  test('setBackgroundColor sends ARGB int', () async {
    await platform.setBackgroundColor(const Color(0xFFFF0000));
    expect(log.first.method, 'setBackgroundColor');
    expect(log.first.arguments, {'color': 0xFFFF0000});
  });

  test('setLighting sends preset name', () async {
    await platform.setLighting(SceneLighting.dramatic);
    expect(log.first.method, 'setLighting');
    expect(log.first.arguments, {'preset': 'dramatic'});
  });

  test('setGesturesEnabled sends boolean', () async {
    await platform.setGesturesEnabled(false);
    expect(log.first.method, 'setGesturesEnabled');
    expect(log.first.arguments, {'enabled': false});
  });

  test('setAutoRotate sends boolean', () async {
    await platform.setAutoRotate(true);
    expect(log.first.method, 'setAutoRotate');
    expect(log.first.arguments, {'enabled': true});
  });

  test('setFitMode sends enum name', () async {
    await platform.setFitMode(ModelFit.cover);
    expect(log.first.method, 'setFitMode');
    expect(log.first.arguments, {'mode': 'cover'});
  });

  // ---------------------------------------------------------------------------
  // Events from native
  // ---------------------------------------------------------------------------
  group('native events', () {
    test('sceneReady event is forwarded', () async {
      final events = <SceneEvent>[];
      platform.events.listen(events.add);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'flutter_native_3d/scene_42',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onEvent', {'type': 'sceneReady'}),
        ),
        (_) {},
      );

      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.first, isA<SceneReadyEvent>());
    });

    test('loadProgress event is forwarded', () async {
      final events = <SceneEvent>[];
      platform.events.listen(events.add);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'flutter_native_3d/scene_42',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onEvent', {
            'type': 'loadProgress',
            'progress': 0.5,
          }),
        ),
        (_) {},
      );

      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.first, isA<ModelLoadProgressEvent>());
      expect((events.first as ModelLoadProgressEvent).progress, 0.5);
    });

    test('animationCompleted event is forwarded', () async {
      final events = <SceneEvent>[];
      platform.events.listen(events.add);

      // Simulate native sending an event
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'flutter_native_3d/scene_42',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onEvent', {
            'type': 'animationCompleted',
            'name': 'Jump',
          }),
        ),
        (_) {},
      );

      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(
          (events.first as AnimationCompletedEvent).animationName, 'Jump');
    });

    test('error event is forwarded', () async {
      final events = <SceneEvent>[];
      platform.events.listen(events.add);

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'flutter_native_3d/scene_42',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('onEvent', {
            'type': 'error',
            'message': 'GPU lost',
            'code': 'GPU_ERROR',
          }),
        ),
        (_) {},
      );

      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      final err = (events.first as SceneErrorEvent).exception;
      expect(err.message, 'GPU lost');
      expect(err.code, 'GPU_ERROR');
    });
  });
}
