import 'dart:async';

import 'package:flutter/services.dart';

import '../types/types.dart';
import 'model_source_serializer.dart';
import 'native_3d_platform.dart';

/// Method channel implementation of [Native3DPlatform].
///
/// Each instance corresponds to one native platform view identified by [viewId].
/// The channel name is `flutter_native_3d/scene_$viewId`.
class MethodChannelNative3D implements Native3DPlatform {
  final MethodChannel _channel;
  final StreamController<SceneEvent> _eventController =
      StreamController<SceneEvent>.broadcast();

  MethodChannelNative3D(int viewId)
      : _channel = MethodChannel('flutter_native_3d/scene_$viewId') {
    _channel.setMethodCallHandler(_handleNativeEvent);
  }

  Future<dynamic> _handleNativeEvent(MethodCall call) async {
    if (call.method != 'onEvent') return;
    final args = call.arguments as Map<Object?, Object?>;
    final type = args['type'] as String;

    switch (type) {
      case 'sceneReady':
        _eventController.add(const SceneReadyEvent());
      case 'loadProgress':
        final progress = (args['progress'] as num?)?.toDouble() ?? 0.0;
        _eventController.add(ModelLoadProgressEvent(progress));
      case 'animationCompleted':
        final name = args['name'] as String;
        _eventController.add(AnimationCompletedEvent(name));
      case 'error':
        _eventController.add(SceneErrorEvent(_mapNativeError(args)));
    }
  }

  /// Map a native error payload to a typed Dart exception.
  ///
  /// Native side sends: `{type: 'error', code: String?, message: String?}`
  /// The [code] determines which exception subtype we create.
  static Native3DException _mapNativeError(Map<Object?, Object?> args) {
    final message = args['message'] as String? ?? 'Unknown native error';
    final code = args['code'] as String?;
    final statusCode = args['statusCode'] as int?;

    return switch (code) {
      'ASSET_NOT_FOUND' => AssetNotFoundException(message),
      'FILE_NOT_FOUND' => FileNotFoundException(message),
      'NETWORK_ERROR' => NetworkException(message, statusCode: statusCode),
      'FORMAT_ERROR' => FormatNotSupportedException(message),
      'ANIMATION_ERROR' => AnimationException(message, code: code),
      'MODEL_LOAD_ERROR' => ModelLoadException(message, code: code),
      'SCENE_ERROR' => SceneException(message, code: code),
      _ => Native3DException(message, code: code),
    };
  }

  @override
  Future<ModelInfo> loadModel(ModelSource source) async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'loadModel',
        serializeModelSource(source),
      );
      final names =
          (result?['animationNames'] as List?)?.cast<String>() ?? [];
      return ModelInfo(animationNames: names);
    } on PlatformException catch (e) {
      throw _mapLoadError(e, source);
    }
  }

  /// Map a PlatformException from loadModel to a typed ModelLoadException.
  static ModelLoadException _mapLoadError(
    PlatformException e,
    ModelSource source,
  ) {
    final message = e.message ?? 'Failed to load model';
    return switch (e.code) {
      'ASSET_NOT_FOUND' => AssetNotFoundException(message, source: source),
      'FILE_NOT_FOUND' => FileNotFoundException(message, source: source),
      'NETWORK_ERROR' => NetworkException(message, source: source),
      'FORMAT_ERROR' => FormatNotSupportedException(message, source: source),
      _ => ModelLoadException(message, code: e.code, source: source),
    };
  }

  @override
  Future<void> resetCamera() => _channel.invokeMethod('resetCamera');

  @override
  Future<void> setCameraOrbit(CameraOrbit orbit) {
    return _channel.invokeMethod('setCameraOrbit', {
      'theta': orbit.theta,
      'phi': orbit.phi,
      'radius': orbit.radius,
    });
  }

  @override
  Future<List<String>> getAnimationNames() async {
    final result = await _channel.invokeMethod<List<Object?>>('getAnimationNames');
    return result?.cast<String>() ?? [];
  }

  @override
  Future<void> playAnimation({required String name, bool loop = true}) async {
    try {
      await _channel.invokeMethod('playAnimation', {
        'name': name,
        'loop': loop,
      });
    } on PlatformException catch (e) {
      throw AnimationException(
        e.message ?? 'Failed to play animation "$name"',
        code: e.code,
      );
    }
  }

  @override
  Future<void> playAnimationByIndex(
      {required int index, bool loop = true}) async {
    try {
      await _channel.invokeMethod('playAnimationByIndex', {
        'index': index,
        'loop': loop,
      });
    } on PlatformException catch (e) {
      throw AnimationException(
        e.message ?? 'Failed to play animation at index $index',
        code: e.code,
      );
    }
  }

  @override
  Future<void> pauseAnimation() => _channel.invokeMethod('pauseAnimation');

  @override
  Future<void> stopAnimation() => _channel.invokeMethod('stopAnimation');

  @override
  Future<void> setBackgroundColor(Color color) {
    return _channel.invokeMethod('setBackgroundColor', {
      'color': color.toARGB32(),
    });
  }

  @override
  Future<void> setLighting(SceneLighting lighting) {
    final value = switch (lighting) {
      PresetLighting(:final name) => name,
    };
    return _channel.invokeMethod('setLighting', {'preset': value});
  }

  @override
  Future<void> setGesturesEnabled(bool enabled) {
    return _channel.invokeMethod('setGesturesEnabled', {'enabled': enabled});
  }

  @override
  Future<void> setAutoRotate(bool enabled) {
    return _channel.invokeMethod('setAutoRotate', {'enabled': enabled});
  }

  @override
  Future<void> setFitMode(ModelFit fit) {
    return _channel.invokeMethod('setFitMode', {'mode': fit.name});
  }

  @override
  Stream<SceneEvent> get events => _eventController.stream;

  @override
  Future<void> dispose() async {
    // Detach handler first to prevent new events during teardown.
    _channel.setMethodCallHandler(null);
    try {
      // Best-effort: tell native to release resources.
      // May fail if the native view is already destroyed (hot restart, pop).
      await _channel.invokeMethod('dispose');
    } on PlatformException {
      // Native view gone -- expected during hot restart or rapid navigation.
    } on MissingPluginException {
      // Plugin not registered -- expected during tests or hot restart.
    } finally {
      await _eventController.close();
    }
  }
}
