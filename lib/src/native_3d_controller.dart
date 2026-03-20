import 'dart:ui';

import 'platform/method_channel_native_3d.dart';
import 'platform/native_3d_platform.dart';
import 'types/types.dart';

/// Imperative controller for a [Native3DViewer] instance.
///
/// Obtained via [Native3DViewer.onSceneCreated]. Valid until the widget
/// disposes or [dispose] is called manually.
///
/// ## Load sequencing
///
/// If [loadModel] is called while a previous load is still in flight,
/// the previous load's future completes with a [ModelLoadException]
/// (code `LOAD_SUPERSEDED`). Only the most recent load wins.
///
/// ## Lifecycle safety
///
/// After [dispose], data-returning methods ([loadModel], [getAnimationNames])
/// throw [StateError]. Void methods silently no-op (matches Flutter's
/// [AnimationController] convention). Check [isDisposed] to avoid both.
class Native3DController {
  final Native3DPlatform _platform;
  bool _disposed = false;
  int _loadGeneration = 0;

  Native3DController._(this._platform);

  /// Creates a controller backed by method channels for the given view [id].
  factory Native3DController.fromViewId(int id) {
    return Native3DController._(MethodChannelNative3D(id));
  }

  /// Creates a controller from a custom platform implementation.
  /// Useful for testing.
  factory Native3DController.fromPlatform(Native3DPlatform platform) {
    return Native3DController._(platform);
  }

  /// Whether this controller has been disposed.
  bool get isDisposed => _disposed;

  // ---------------------------------------------------------------------------
  // Model loading
  // ---------------------------------------------------------------------------

  /// Load a 3D model, replacing any currently displayed model.
  ///
  /// Returns [ModelInfo] on success. Throws [ModelLoadException] on failure.
  /// If a newer [loadModel] call is made before this one completes, this
  /// future throws with code `LOAD_SUPERSEDED`.
  Future<ModelInfo> loadModel(ModelSource source) async {
    _throwIfDisposed();

    final myGeneration = ++_loadGeneration;

    final ModelInfo info;
    try {
      info = await _platform.loadModel(source);
    } on ModelLoadException {
      rethrow;
    } on Exception catch (e) {
      throw ModelLoadException(e.toString(), source: source);
    }

    if (_disposed || myGeneration != _loadGeneration) {
      throw LoadSupersededException(source: source);
    }

    return info;
  }

  // ---------------------------------------------------------------------------
  // Camera
  // ---------------------------------------------------------------------------

  /// Reset the camera to auto-frame the current model.
  Future<void> resetCamera() {
    if (_disposed) return Future.value();
    return _platform.resetCamera();
  }

  /// Move the camera to a specific orbit position around the model.
  Future<void> setCameraOrbit(CameraOrbit orbit) {
    if (_disposed) return Future.value();
    return _platform.setCameraOrbit(orbit);
  }

  // ---------------------------------------------------------------------------
  // Animations
  // ---------------------------------------------------------------------------

  /// Get the list of animation names in the current model.
  ///
  /// Returns an empty list if no model is loaded or it has no animations.
  /// Prefer using [ModelInfo.animationNames] from [loadModel] instead of
  /// calling this separately -- avoids an extra channel round-trip.
  Future<List<String>> getAnimationNames() {
    _throwIfDisposed();
    return _platform.getAnimationNames();
  }

  /// Play an animation by [name].
  ///
  /// If [loop] is true (default), the animation repeats indefinitely.
  /// When a non-looping animation completes, an [AnimationCompletedEvent]
  /// is emitted on [events].
  ///
  /// Throws [AnimationException] if [name] is not found in the model.
  /// Call [getAnimationNames] or check [ModelInfo.animationNames] first.
  Future<void> playAnimation({required String name, bool loop = true}) {
    if (_disposed) return Future.value();
    return _platform.playAnimation(name: name, loop: loop);
  }

  /// Play an animation by its [index] in the animation list.
  ///
  /// Indices correspond to [ModelInfo.animationNames] order.
  /// Throws [AnimationException] if [index] is out of range.
  Future<void> playAnimationByIndex({required int index, bool loop = true}) {
    if (_disposed) return Future.value();
    return _platform.playAnimationByIndex(index: index, loop: loop);
  }

  /// Pause the currently playing animation at its current frame.
  ///
  /// Call [playAnimation] or [playAnimationByIndex] to resume.
  /// Safe to call when no animation is playing (no-op).
  Future<void> pauseAnimation() {
    if (_disposed) return Future.value();
    return _platform.pauseAnimation();
  }

  /// Stop all animations and reset them to their initial frame.
  ///
  /// Safe to call when no animation is playing (no-op).
  Future<void> stopAnimation() {
    if (_disposed) return Future.value();
    return _platform.stopAnimation();
  }

  // ---------------------------------------------------------------------------
  // Scene appearance
  // ---------------------------------------------------------------------------

  /// Change the background color at runtime.
  Future<void> setBackgroundColor(Color color) {
    if (_disposed) return Future.value();
    return _platform.setBackgroundColor(color);
  }

  /// Change the lighting preset at runtime.
  Future<void> setLighting(SceneLighting lighting) {
    if (_disposed) return Future.value();
    return _platform.setLighting(lighting);
  }

  /// Enable or disable touch gestures (orbit, pan, zoom).
  Future<void> setGesturesEnabled(bool enabled) {
    if (_disposed) return Future.value();
    return _platform.setGesturesEnabled(enabled);
  }

  /// Enable or disable automatic rotation when idle.
  Future<void> setAutoRotate(bool enabled) {
    if (_disposed) return Future.value();
    return _platform.setAutoRotate(enabled);
  }

  /// Change how the model is scaled to fit the viewport.
  Future<void> setFitMode(ModelFit fit) {
    if (_disposed) return Future.value();
    return _platform.setFitMode(fit);
  }

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------

  /// Stream of events from the native scene.
  ///
  /// Emits [AnimationCompletedEvent] when a non-looping animation finishes,
  /// and [SceneErrorEvent] for unexpected native errors.
  Stream<SceneEvent> get events {
    _throwIfDisposed();
    return _platform.events;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Release native resources.
  ///
  /// Called automatically when the [Native3DViewer] widget is disposed.
  Future<void> dispose() {
    if (_disposed) return Future.value();
    _disposed = true;
    return _platform.dispose();
  }

  void _throwIfDisposed() {
    if (_disposed) {
      throw StateError(
        'Native3DController used after dispose. '
        'Check isDisposed before calling methods that return data.',
      );
    }
  }
}
