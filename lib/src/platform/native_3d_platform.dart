import 'dart:ui';

import '../types/types.dart';

/// Internal abstraction between the Dart controller and native code.
///
/// Not exported in the public API. Tests can mock this to verify
/// controller behavior without a real native view.
abstract class Native3DPlatform {
  Future<ModelInfo> loadModel(ModelSource source);
  Future<void> resetCamera();
  Future<void> setCameraOrbit(CameraOrbit orbit);
  Future<List<String>> getAnimationNames();
  Future<void> playAnimation({required String name, bool loop = true});
  Future<void> playAnimationByIndex({required int index, bool loop = true});
  Future<void> pauseAnimation();
  Future<void> stopAnimation();
  Future<void> setBackgroundColor(Color color);
  Future<void> setLighting(SceneLighting lighting);
  Future<void> setGesturesEnabled(bool enabled);
  Future<void> setAutoRotate(bool enabled);
  Future<void> setFitMode(ModelFit fit);
  Stream<SceneEvent> get events;
  Future<void> dispose();
}
