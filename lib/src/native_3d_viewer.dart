import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'native_3d_controller.dart';
import 'platform/model_source_serializer.dart';
import 'types/types.dart';

/// Renders a 3D model using the platform's native rendering engine.
///
/// SceneKit on iOS, Filament on Android.
///
/// ## Minimal usage
/// ```dart
/// Native3DViewer(
///   source: ModelSource.asset('assets/helmet.glb'),
/// )
/// ```
///
/// ## Full configuration
/// ```dart
/// Native3DViewer(
///   source: ModelSource.network(
///     'https://example.com/model.glb',
///     headers: {'Authorization': 'Bearer token'},
///   ),
///   backgroundColor: Colors.grey.shade100,
///   lighting: SceneLighting.studio,
///   fitMode: ModelFit.contain,
///   gesturesEnabled: true,
///   autoRotate: false,
///   autoPlay: true,
///   initialCameraOrbit: CameraOrbit(theta: 30, phi: 20, radius: 4),
///   onSceneCreated: (controller) => _ctrl = controller,
///   onModelLoaded: (info) => print('animations: ${info.animationNames}'),
///   onError: (e) => print('error: $e'),
/// )
/// ```
///
/// ## Rebuild behavior
///
/// The widget diffs each parameter individually on rebuild:
///
/// | Parameter           | On change                          |
/// |---------------------|------------------------------------|
/// | [source]            | Full model reload (expensive)      |
/// | [backgroundColor]   | `setBackgroundColor` (cheap)       |
/// | [lighting]          | `setLighting` (cheap)              |
/// | [fitMode]           | `setFitMode` (cheap)               |
/// | [gesturesEnabled]   | `setGesturesEnabled` (cheap)       |
/// | [autoRotate]        | `setAutoRotate` (cheap)            |
/// | [autoPlay]          | Creation-time only -- no runtime effect |
/// | [initialCameraOrbit]| Creation-time only -- use `controller.setCameraOrbit` |
class Native3DViewer extends StatefulWidget {
  // ---- Required ----

  /// The 3D model to display. Changing this triggers a full model reload.
  final ModelSource source;

  // ---- Scene appearance ----

  /// Background color of the 3D viewport. Defaults to transparent.
  final Color backgroundColor;

  /// Lighting preset for the scene. Defaults to [SceneLighting.studio].
  final SceneLighting lighting;

  /// How the model is scaled to fit within the viewport.
  /// Defaults to [ModelFit.contain].
  final ModelFit fitMode;

  // ---- Interaction ----

  /// Whether touch gestures (orbit, pan, zoom) are enabled.
  /// Defaults to true.
  final bool gesturesEnabled;

  /// Whether the model automatically rotates when the user is not interacting.
  /// Defaults to false.
  final bool autoRotate;

  /// Whether to play the first animation automatically after loading.
  /// Creation-time only -- changing this on rebuild has no effect.
  final bool autoPlay;

  /// Initial camera position. If null, the camera auto-frames to fit the model.
  /// Creation-time only -- use [Native3DController.setCameraOrbit] for runtime changes.
  final CameraOrbit? initialCameraOrbit;

  // ---- Callbacks ----

  /// Called once when the native view is ready and the [Native3DController]
  /// is available. The controller remains valid until the widget is disposed.
  final ValueChanged<Native3DController>? onSceneCreated;

  /// Called when a model finishes loading (initial load or source change).
  final ValueChanged<ModelInfo>? onModelLoaded;

  /// Called during network model downloads with progress (0.0 to 1.0).
  /// Not fired for asset or file sources.
  final ValueChanged<double>? onModelLoadProgress;

  /// Called when loading fails or a native error occurs.
  final ValueChanged<Native3DException>? onError;

  const Native3DViewer({
    super.key,
    required this.source,
    this.backgroundColor = const Color(0x00000000),
    this.lighting = SceneLighting.studio,
    this.fitMode = ModelFit.contain,
    this.gesturesEnabled = true,
    this.autoRotate = false,
    this.autoPlay = false,
    this.initialCameraOrbit,
    this.onSceneCreated,
    this.onModelLoaded,
    this.onModelLoadProgress,
    this.onError,
  });

  @override
  State<Native3DViewer> createState() => _Native3DViewerState();
}

class _Native3DViewerState extends State<Native3DViewer> {
  Native3DController? _controller;
  StreamSubscription<SceneEvent>? _eventSubscription;
  late final Map<String, dynamic> _cachedCreationParams = _buildCreationParams();

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void didUpdateWidget(Native3DViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (controller == null) return;

    // Source change triggers a full model reload.
    // All other params are cheap setting updates.
    if (widget.source != oldWidget.source) {
      _loadModel(controller, widget.source);
    }

    if (widget.backgroundColor != oldWidget.backgroundColor) {
      controller.setBackgroundColor(widget.backgroundColor);
    }

    if (widget.lighting != oldWidget.lighting) {
      controller.setLighting(widget.lighting);
    }

    if (widget.fitMode != oldWidget.fitMode) {
      controller.setFitMode(widget.fitMode);
    }

    if (widget.gesturesEnabled != oldWidget.gesturesEnabled) {
      controller.setGesturesEnabled(widget.gesturesEnabled);
    }

    if (widget.autoRotate != oldWidget.autoRotate) {
      controller.setAutoRotate(widget.autoRotate);
    }

    // autoPlay and initialCameraOrbit are creation-time only.
    // Changing them on rebuild is intentionally ignored.
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Platform view created
  // ---------------------------------------------------------------------------

  void _onPlatformViewCreated(int id) {
    final controller = Native3DController.fromViewId(id);
    _controller = controller;

    // Forward native events to the appropriate widget callbacks.
    _eventSubscription = controller.events.listen((event) {
      if (!mounted) return;
      switch (event) {
        case SceneReadyEvent():
          break; // Scene ready is signaled via onSceneCreated callback
        case ModelLoadProgressEvent(:final progress):
          widget.onModelLoadProgress?.call(progress);
        case SceneErrorEvent(:final exception):
          widget.onError?.call(exception);
        case AnimationCompletedEvent():
          break; // Handled by user via controller.events directly
      }
    });

    widget.onSceneCreated?.call(controller);
  }

  // ---------------------------------------------------------------------------
  // Model loading with stale-guard
  // ---------------------------------------------------------------------------

  Future<void> _loadModel(
    Native3DController controller,
    ModelSource source,
  ) async {
    try {
      final info = await controller.loadModel(source);
      // Guard: source may have changed while the load was in flight.
      if (mounted && widget.source == source) {
        widget.onModelLoaded?.call(info);
      }
    } on LoadSupersededException {
      // A newer load was started -- this one was cancelled. Not an error.
    } on ModelLoadException catch (e) {
      if (mounted && widget.source == source) {
        widget.onError?.call(e);
      }
    } on StateError {
      // Controller disposed during load -- widget is unmounting.
    }
  }

  // ---------------------------------------------------------------------------
  // Creation params (sent once when the native view is instantiated)
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _buildCreationParams() {
    final lightingValue = switch (widget.lighting) {
      PresetLighting(:final name) => name,
    };
    return {
      'source': serializeModelSource(widget.source),
      'backgroundColor': widget.backgroundColor.toARGB32(),
      'lighting': lightingValue,
      'fitMode': widget.fitMode.name,
      'gesturesEnabled': widget.gesturesEnabled,
      'autoRotate': widget.autoRotate,
      'autoPlay': widget.autoPlay,
      if (widget.initialCameraOrbit case final orbit?) ...{
        'initialCameraOrbit': {
          'theta': orbit.theta,
          'phi': orbit.phi,
          'radius': orbit.radius,
        },
      },
    };
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    const viewType = 'flutter_native_3d/native3d_view';
    final creationParams = _cachedCreationParams;
    const codec = StandardMessageCodec();

    // Always claim touch events so the native view receives them.
    // The native side decides whether to act on them based on gesturesEnabled.
    // We must always register recognizers because platform views that don't
    // register any will never receive touch events on iOS (UiKitView behavior).
    final gestureRecognizers = <Factory<OneSequenceGestureRecognizer>>{
      Factory<EagerGestureRecognizer>(() => EagerGestureRecognizer()),
    };

    if (Platform.isIOS) {
      return UiKitView(
        viewType: viewType,
        onPlatformViewCreated: _onPlatformViewCreated,
        creationParams: creationParams,
        creationParamsCodec: codec,
        gestureRecognizers: gestureRecognizers,
      );
    }

    if (Platform.isAndroid) {
      return AndroidView(
        viewType: viewType,
        onPlatformViewCreated: _onPlatformViewCreated,
        creationParams: creationParams,
        creationParamsCodec: codec,
        gestureRecognizers: gestureRecognizers,
      );
    }

    return const Center(
      child: Text('Native3DViewer: Unsupported platform'),
    );
  }
}
