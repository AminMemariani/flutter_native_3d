import 'native_3d_exception.dart';

/// Events emitted by the native 3D scene.
///
/// Listen via [Native3DController.events] for advanced use,
/// or use the widget callbacks for common cases.
///
/// ## Event types
///
/// | Event | When | Widget callback |
/// |-------|------|-----------------|
/// | [SceneReadyEvent] | Native view initialized, ready for commands | [onSceneCreated] |
/// | [ModelLoadProgressEvent] | Network download progress (0.0-1.0) | [onModelLoadProgress] |
/// | [AnimationCompletedEvent] | Non-looping animation finished | via `controller.events` |
/// | [SceneErrorEvent] | Unexpected native error | [onError] |
sealed class SceneEvent {
  const SceneEvent();
}

/// The native scene is fully initialized and ready to receive commands.
///
/// Emitted once after the platform view is created and the rendering
/// engine (SceneKit/Filament) is set up. Commands sent before this event
/// are queued and executed when the scene becomes ready.
final class SceneReadyEvent extends SceneEvent {
  const SceneReadyEvent();
}

/// Progress update during model loading (0.0 to 1.0).
///
/// Emitted during network downloads when the server provides Content-Length.
/// Asset and file sources do not emit progress events.
final class ModelLoadProgressEvent extends SceneEvent {
  /// Value between 0.0 (started) and 1.0 (download complete, parsing next).
  final double progress;
  const ModelLoadProgressEvent(this.progress);
}

/// A non-looping animation finished playing.
final class AnimationCompletedEvent extends SceneEvent {
  final String animationName;
  const AnimationCompletedEvent(this.animationName);
}

/// An unexpected error occurred in the native scene.
///
/// The [exception] is typed based on the error code from native:
/// - [SceneException] for rendering/GPU errors
/// - [ModelLoadException] subtypes for loading issues
/// - [Native3DException] for unrecognized errors
final class SceneErrorEvent extends SceneEvent {
  final Native3DException exception;
  const SceneErrorEvent(this.exception);
}
