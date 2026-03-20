import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_native_3d/flutter_native_3d.dart';
import 'package:flutter_native_3d/src/platform/native_3d_platform.dart';

/// Mock platform that records calls and lets tests control responses.
class MockNative3DPlatform implements Native3DPlatform {
  final List<String> calls = [];
  final StreamController<SceneEvent> _events =
      StreamController<SceneEvent>.broadcast();

  /// Controls how long loadModel takes. Set to non-null to simulate async loading.
  Completer<ModelInfo>? loadCompleter;

  /// Default model info returned by loadModel when no completer is set.
  ModelInfo defaultModelInfo =
      const ModelInfo(animationNames: ['Walk', 'Run']);

  /// If set, loadModel throws this exception.
  Exception? loadError;

  @override
  Future<ModelInfo> loadModel(ModelSource source) async {
    calls.add('loadModel');
    if (loadError != null) throw loadError!;
    if (loadCompleter != null) return loadCompleter!.future;
    return defaultModelInfo;
  }

  @override
  Future<void> resetCamera() async => calls.add('resetCamera');

  @override
  Future<void> setCameraOrbit(CameraOrbit orbit) async =>
      calls.add('setCameraOrbit(${orbit.theta},${orbit.phi},${orbit.radius})');

  @override
  Future<List<String>> getAnimationNames() async {
    calls.add('getAnimationNames');
    return defaultModelInfo.animationNames;
  }

  @override
  Future<void> playAnimation({required String name, bool loop = true}) async =>
      calls.add('playAnimation($name,$loop)');

  @override
  Future<void> playAnimationByIndex({required int index, bool loop = true}) async =>
      calls.add('playAnimationByIndex($index,$loop)');

  @override
  Future<void> pauseAnimation() async => calls.add('pauseAnimation');

  @override
  Future<void> stopAnimation() async => calls.add('stopAnimation');

  @override
  Future<void> setBackgroundColor(Color color) async =>
      calls.add('setBackgroundColor');

  @override
  Future<void> setLighting(SceneLighting lighting) async {
    final name = switch (lighting) { PresetLighting(:final name) => name };
    calls.add('setLighting($name)');
  }

  @override
  Future<void> setGesturesEnabled(bool enabled) async =>
      calls.add('setGesturesEnabled($enabled)');

  @override
  Future<void> setAutoRotate(bool enabled) async =>
      calls.add('setAutoRotate($enabled)');

  @override
  Future<void> setFitMode(ModelFit fit) async =>
      calls.add('setFitMode(${fit.name})');

  @override
  Stream<SceneEvent> get events => _events.stream;

  void emitEvent(SceneEvent event) => _events.add(event);

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    await _events.close();
  }
}

void main() {
  late MockNative3DPlatform mock;
  late Native3DController controller;

  setUp(() {
    mock = MockNative3DPlatform();
    controller = Native3DController.fromPlatform(mock);
  });

  // ---------------------------------------------------------------------------
  // Basic API
  // ---------------------------------------------------------------------------
  group('basic API', () {
    test('loadModel delegates to platform and returns ModelInfo', () async {
      final info =
          await controller.loadModel(const ModelSource.asset('test.glb'));
      expect(info.animationNames, ['Walk', 'Run']);
      expect(mock.calls, ['loadModel']);
    });

    test('resetCamera delegates to platform', () async {
      await controller.resetCamera();
      expect(mock.calls, ['resetCamera']);
    });

    test('setCameraOrbit delegates with correct values', () async {
      await controller
          .setCameraOrbit(const CameraOrbit(theta: 45, phi: 30, radius: 5));
      expect(mock.calls, ['setCameraOrbit(45.0,30.0,5.0)']);
    });

    test('getAnimationNames delegates to platform', () async {
      final names = await controller.getAnimationNames();
      expect(names, ['Walk', 'Run']);
    });

    test('playAnimation delegates with name and loop', () async {
      await controller.playAnimation(name: 'Walk', loop: false);
      expect(mock.calls, ['playAnimation(Walk,false)']);
    });

    test('playAnimationByIndex delegates with index and loop', () async {
      await controller.playAnimationByIndex(index: 0, loop: false);
      expect(mock.calls, ['playAnimationByIndex(0,false)']);
    });

    test('pauseAnimation delegates to platform', () async {
      await controller.pauseAnimation();
      expect(mock.calls, ['pauseAnimation']);
    });

    test('stopAnimation delegates to platform', () async {
      await controller.stopAnimation();
      expect(mock.calls, ['stopAnimation']);
    });

    test('setBackgroundColor delegates to platform', () async {
      await controller.setBackgroundColor(const Color(0xFFFF0000));
      expect(mock.calls, ['setBackgroundColor']);
    });

    test('setLighting delegates preset name', () async {
      await controller.setLighting(SceneLighting.dramatic);
      expect(mock.calls, ['setLighting(dramatic)']);
    });

    test('setGesturesEnabled delegates boolean', () async {
      await controller.setGesturesEnabled(false);
      expect(mock.calls, ['setGesturesEnabled(false)']);
    });

    test('setAutoRotate delegates boolean', () async {
      await controller.setAutoRotate(true);
      expect(mock.calls, ['setAutoRotate(true)']);
    });

    test('setFitMode delegates enum name', () async {
      await controller.setFitMode(ModelFit.cover);
      expect(mock.calls, ['setFitMode(cover)']);
    });
  });

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------
  group('events', () {
    test('events stream forwards platform events', () async {
      final events = <SceneEvent>[];
      controller.events.listen(events.add);

      mock.emitEvent(const AnimationCompletedEvent('Jump'));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first, isA<AnimationCompletedEvent>());
      expect(
          (events.first as AnimationCompletedEvent).animationName, 'Jump');
    });

    test('events stream delivers errors', () async {
      final events = <SceneEvent>[];
      controller.events.listen(events.add);

      mock.emitEvent(
          const SceneErrorEvent(Native3DException('test error', code: 'E1')));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      final error = (events.first as SceneErrorEvent).exception;
      expect(error.message, 'test error');
      expect(error.code, 'E1');
    });
  });

  // ---------------------------------------------------------------------------
  // Load sequencing (race condition prevention)
  // ---------------------------------------------------------------------------
  group('load sequencing', () {
    test('concurrent loads: first load gets LOAD_SUPERSEDED', () async {
      final completer1 = Completer<ModelInfo>();
      final completer2 = Completer<ModelInfo>();

      // Start first load (will be slow)
      mock.loadCompleter = completer1;
      final future1 =
          controller.loadModel(const ModelSource.asset('slow.glb'));

      // Start second load before first completes
      mock.loadCompleter = completer2;
      final future2 =
          controller.loadModel(const ModelSource.asset('fast.glb'));

      // Complete first load
      completer1
          .complete(const ModelInfo(animationNames: ['OldAnim']));

      // First load should throw LoadSupersededException
      await expectLater(
        future1,
        throwsA(isA<LoadSupersededException>()),
      );

      // Complete second load
      completer2
          .complete(const ModelInfo(animationNames: ['NewAnim']));
      final info2 = await future2;
      expect(info2.animationNames, ['NewAnim']);
    });

    test('sequential loads both succeed', () async {
      final info1 =
          await controller.loadModel(const ModelSource.asset('a.glb'));
      final info2 =
          await controller.loadModel(const ModelSource.asset('b.glb'));
      expect(info1.animationNames, ['Walk', 'Run']);
      expect(info2.animationNames, ['Walk', 'Run']);
      expect(mock.calls, ['loadModel', 'loadModel']);
    });
  });

  // ---------------------------------------------------------------------------
  // Error propagation
  // ---------------------------------------------------------------------------
  group('error propagation', () {
    test('loadModel propagates ModelLoadException', () async {
      mock.loadError = const ModelLoadException('not found', code: 'E404');

      await expectLater(
        controller.loadModel(const ModelSource.file('/bad.glb')),
        throwsA(isA<ModelLoadException>()),
      );
    });

    test('loadModel wraps unexpected exceptions in ModelLoadException',
        () async {
      mock.loadError = Exception('disk full');

      await expectLater(
        controller.loadModel(const ModelSource.asset('x.glb')),
        throwsA(
          isA<ModelLoadException>()
              .having((e) => e.message, 'message', contains('disk full')),
        ),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Lifecycle safety
  // ---------------------------------------------------------------------------
  group('lifecycle', () {
    test('isDisposed is false initially', () {
      expect(controller.isDisposed, isFalse);
    });

    test('isDisposed is true after dispose', () async {
      await controller.dispose();
      expect(controller.isDisposed, isTrue);
      expect(mock.calls, ['dispose']);
    });

    test('double dispose is safe', () async {
      await controller.dispose();
      await controller.dispose(); // should not throw or call platform twice
      expect(mock.calls.where((c) => c == 'dispose').length, 1);
    });

    test('loadModel throws StateError after dispose', () async {
      await controller.dispose();
      expect(
        () => controller.loadModel(const ModelSource.asset('x.glb')),
        throwsStateError,
      );
    });

    test('getAnimationNames throws StateError after dispose', () async {
      await controller.dispose();
      expect(() => controller.getAnimationNames(), throwsStateError);
    });

    test('events throws StateError after dispose', () async {
      await controller.dispose();
      expect(() => controller.events, throwsStateError);
    });

    test('void methods silently no-op after dispose', () async {
      await controller.dispose();

      // These should all complete without error:
      await controller.resetCamera();
      await controller.setCameraOrbit(CameraOrbit.defaultOrbit);
      await controller.playAnimation(name: 'Walk');
      await controller.playAnimationByIndex(index: 0);
      await controller.pauseAnimation();
      await controller.stopAnimation();
      await controller.setBackgroundColor(const Color(0xFFFF0000));
      await controller.setLighting(SceneLighting.studio);
      await controller.setGesturesEnabled(false);
      await controller.setAutoRotate(true);
      await controller.setFitMode(ModelFit.cover);

      // None of these should have been forwarded to the platform
      expect(mock.calls, ['dispose']);
    });

    test('dispose during in-flight load: load gets LOAD_SUPERSEDED',
        () async {
      final completer = Completer<ModelInfo>();
      mock.loadCompleter = completer;

      final loadFuture =
          controller.loadModel(const ModelSource.asset('test.glb'));

      await controller.dispose();
      completer.complete(const ModelInfo(animationNames: []));

      await expectLater(
        loadFuture,
        throwsA(isA<LoadSupersededException>()),
      );
    });
  });
}
