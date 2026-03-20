# flutter_native_3d

**Native 3D model rendering for Flutter.** No WebView. No JavaScript. Just Metal and Filament.

[![pub package](https://img.shields.io/pub/v/flutter_native_3d.svg)](https://pub.dev/packages/flutter_native_3d)
[![build](https://img.shields.io/github/actions/workflow/status/user/flutter_native_3d/ci.yml?branch=main)](https://github.com/user/flutter_native_3d/actions)
[![license](https://img.shields.io/github/license/user/flutter_native_3d)](LICENSE)

A Flutter plugin that renders glTF/GLB 3D models using the platform's native rendering engine -- **SceneKit** on iOS, **Filament** on Android. Touch to orbit, pinch to zoom, play animations, switch lighting -- all at native frame rates with zero web overhead.

<!-- Replace with actual screenshots/GIFs after building on-device -->
| iOS (SceneKit) | Android (Filament) |
|---|---|
| ![iOS demo](https://placehold.co/300x600/1a1a2e/eee?text=iOS+Demo+GIF) | ![Android demo](https://placehold.co/300x600/1a1a2e/eee?text=Android+Demo+GIF) |

## Features

- **Native rendering** -- SceneKit (Metal) on iOS, Filament on Android. 60fps on modern devices.
- **glTF & GLB** -- Industry-standard 3D format with PBR materials, skeletal animations, morph targets.
- **Load from anywhere** -- Flutter assets, local files, network URLs (with auth headers), raw bytes.
- **Animation playback** -- Play, pause, stop, loop. Auto-detect available animations on load.
- **Camera controls** -- Orbit, pan, zoom via touch gestures. Programmatic orbit via `setCameraOrbit`.
- **Lighting presets** -- Studio, natural, dramatic, neutral, unlit. Switch at runtime.
- **Auto-rotate** -- Turntable mode for product showcases.
- **Download progress** -- Progress callbacks during network model downloads.
- **Typed error handling** -- `AssetNotFoundException`, `NetworkException`, `FormatNotSupportedException`, etc.
- **Controller pattern** -- Familiar API modeled after `GoogleMapController` / `WebViewController`.
- **Lifecycle safe** -- Proper disposal, load sequencing, stale-load cancellation.

## Why Native-First?

Most Flutter 3D packages use a WebView with Three.js or `<model-viewer>` under the hood. That means:

| | WebView-based | flutter_native_3d |
|---|---|---|
| **Rendering** | JavaScript in a web view | Metal / Filament GPU pipeline |
| **Frame rate** | Limited by JS execution + compositing | Native 60fps |
| **Touch gestures** | Web touch events, then bridge to Flutter | Native gesture recognizers |
| **Memory** | WebView process + JS heap + GPU | Single GPU context |
| **Startup** | Load HTML + JS runtime + Three.js | Direct GPU init |
| **Binary size** | WebView is system (~0), Three.js ~500KB | iOS: ~200KB, Android: ~10MB |
| **Animations** | JS-driven requestAnimationFrame | Native animation pipeline |
| **Future AR path** | None (web AR is limited) | Direct ARKit/ARCore handoff |

The tradeoff: Android binary size is ~10MB larger (Filament native libraries). For apps that display 3D content, this is a worthwhile investment in quality.

## Installation

```yaml
dependencies:
  flutter_native_3d: ^0.1.0
```

### Platform requirements

| Platform | Minimum | Rendering engine | 3D dependency |
|---|---|---|---|
| iOS | 15.0 | SceneKit (Metal) | GLTFKit2 (~200KB) |
| Android | API 24 | Filament | SceneView (~10MB) |

### iOS

No additional setup. GLTFKit2 is pulled automatically via CocoaPods.

### Android

Ensure `minSdk` is at least 24 in `android/app/build.gradle.kts`:

```kotlin
defaultConfig {
    minSdk = 24
}
```

## Quick Start

### 1. Add a model to your assets

```yaml
# pubspec.yaml
flutter:
  assets:
    - assets/models/
```

### 2. Display it

```dart
import 'package:flutter_native_3d/flutter_native_3d.dart';

Native3DViewer(
  source: ModelSource.asset('assets/models/helmet.glb'),
)
```

That's it. The model renders with default lighting, auto-framed camera, and touch gestures enabled.

### 3. Add controls

```dart
Native3DViewer(
  source: ModelSource.network(
    'https://example.com/models/fox.glb',
    headers: {'Authorization': 'Bearer $token'},
  ),
  backgroundColor: Colors.grey.shade100,
  lighting: SceneLighting.dramatic,
  autoPlay: true,
  autoRotate: true,
  onSceneCreated: (controller) {
    _controller = controller;
  },
  onModelLoaded: (info) {
    print('Animations: ${info.animationNames}');
  },
  onModelLoadProgress: (progress) {
    print('Download: ${(progress * 100).toInt()}%');
  },
  onError: (error) {
    print('Failed: $error');
  },
)
```

### 4. Control the scene imperatively

```dart
// Camera
await controller.resetCamera();
await controller.setCameraOrbit(CameraOrbit(theta: 45, phi: 30, radius: 4));

// Animations
final info = await controller.loadModel(ModelSource.asset('fox.glb'));
if (info.hasAnimations) {
  await controller.playAnimation(name: info.animationNames.first);
  await controller.pauseAnimation();
  await controller.stopAnimation();
}

// Appearance
await controller.setLighting(SceneLighting.studio);
await controller.setGesturesEnabled(false);
await controller.setAutoRotate(true);
```

## API Overview

### Widget

```dart
Native3DViewer(
  // Required
  source: ModelSource,             // .asset(), .file(), .network(), .memory()

  // Appearance
  backgroundColor: Color,          // default: transparent
  lighting: SceneLighting,         // default: .studio
  fitMode: ModelFit,               // default: .contain

  // Interaction
  gesturesEnabled: bool,           // default: true (orbit, pan, zoom)
  autoRotate: bool,                // default: false (turntable mode)
  autoPlay: bool,                  // default: false (play first animation on load)
  initialCameraOrbit: CameraOrbit, // default: auto-frame to fit model

  // Callbacks
  onSceneCreated: (controller) {},
  onModelLoaded: (info) {},
  onModelLoadProgress: (progress) {},
  onError: (exception) {},
)
```

### Controller

| Method | Description |
|---|---|
| `loadModel(source)` | Load a model. Returns `Future<ModelInfo>`. |
| `resetCamera()` | Auto-frame camera to fit the model. |
| `setCameraOrbit(orbit)` | Position camera at specific theta/phi/radius. |
| `getAnimationNames()` | List available animations. |
| `playAnimation(name:, loop:)` | Play animation by name. |
| `playAnimationByIndex(index:, loop:)` | Play animation by index. |
| `pauseAnimation()` | Freeze at current frame. |
| `stopAnimation()` | Reset to first frame. |
| `setBackgroundColor(color)` | Change background at runtime. |
| `setLighting(preset)` | Switch lighting preset. |
| `setGesturesEnabled(enabled)` | Toggle touch gestures. |
| `setAutoRotate(enabled)` | Toggle turntable rotation. |
| `setFitMode(fit)` | Change model scaling (contain/cover/none). |
| `dispose()` | Release native resources. |

### Model Sources

```dart
// Flutter asset
ModelSource.asset('assets/models/chair.glb')

// Local file
ModelSource.file('/data/user/0/com.example/files/model.glb')

// Network URL with optional auth headers
ModelSource.network(
  'https://api.example.com/models/chair.glb',
  headers: {'Authorization': 'Bearer token123'},
)

// Raw bytes (e.g. after decryption)
ModelSource.memory(decryptedBytes, formatHint: 'glb')
```

### Error Handling

Errors are typed for precise catching:

```dart
try {
  await controller.loadModel(source);
} on AssetNotFoundException catch (e) {
  // Flutter asset path doesn't exist
} on NetworkException catch (e) {
  // HTTP error, timeout, DNS failure
} on FormatNotSupportedException catch (e) {
  // Not a .glb or .gltf file
} on AnimationException catch (e) {
  // Invalid animation name
} on LoadSupersededException {
  // A newer load replaced this one -- not a real error
} on ModelLoadException catch (e) {
  // Generic load failure (catch-all for loading)
} on Native3DException catch (e) {
  // Catch-all for any plugin error
}
```

### Events

```dart
controller.events.listen((event) {
  switch (event) {
    case SceneReadyEvent():
      // Native renderer is initialized
    case ModelLoadProgressEvent(:final progress):
      // Network download: 0.0 to 1.0
    case AnimationCompletedEvent(:final animationName):
      // Non-looping animation finished
    case SceneErrorEvent(:final exception):
      // Unexpected native error
  }
});
```

## Platform Limitations

### iOS

| Limitation | Detail |
|---|---|
| glTF only via GLTFKit2 | Apple's ModelIO does not support glTF natively |
| No Draco compression | GLTFKit2 does not decode Draco-compressed meshes |
| SceneKit is mature, not cutting-edge | Apple invests in RealityKit now, but SceneKit is stable and fully functional |

### Android

| Limitation | Detail |
|---|---|
| ~10MB binary size increase | Filament native .so libraries for arm64/armeabi/x86_64 |
| SceneView dependency | Community-maintained Filament wrapper; migration path to raw Filament exists |
| Animation completion callbacks | SceneView 2.x does not expose animation end events |

### Both platforms

| Limitation | Detail |
|---|---|
| Platform views compositing cost | Flutter composites native views with some overhead (minimal on modern devices) |
| No web/desktop support yet | Architecture supports future platform implementations |
| No USDZ (yet) | Planned for iOS in a future release via native SceneKit support |

## Performance Tips

- **Use GLB, not glTF** -- Single binary file, no external texture fetches.
- **Keep models under 200K triangles** for consistent 60fps on mobile.
- **Use KTX2/Basis Universal textures** in your GLB to reduce file size 5-10x.
- **Avoid rapid source changes** -- Each change triggers a full native reload. Debounce if driven by user input.
- **Dispose when off-screen** -- The renderer runs continuously. Dispose behind tabs or modals.
- **Network models under 5MB** -- Show progress for larger files via `onModelLoadProgress`.

## Roadmap

### v0.1.0 -- Core rendering (current)

Native glTF/GLB rendering on iOS (SceneKit) and Android (Filament). Asset/file/network/memory loading, animation playback, camera orbit, lighting presets, typed errors, download progress.

### v0.2.0 -- Camera, gestures, animations

- Per-gesture toggle (orbit, pan, zoom independently)
- Camera orbit read-back (get current position from native)
- Animation completion callbacks on Android
- Animation crossfade / blend
- Smooth camera transitions (animated orbit changes)
- Improved bounding box calculation on Android (real AABB)

### v0.3.0 -- Caching, events, performance

- LRU disk cache for network models (skip re-download)
- ETag / If-Modified-Since support for cache validation
- `controller.preload(source)` -- load into memory without displaying
- Background thread glTF parsing on iOS (currently main thread)
- IBL environment maps for realistic reflections (Android)

### v0.4.0 -- USDZ and AR

- USDZ format support on iOS (native SceneKit, no extra dependency)
- Auto-detect format from file extension (glTF vs USDZ)
- AR Quick Look handoff on iOS (pass model to ARKit viewer)
- ARCore Scene Viewer handoff on Android
- `controller.captureSnapshot()` -- render to PNG bytes

### v0.5.0 -- Scene interaction

- Tap-on-node hit testing (`onTapNode` callback with node name)
- Morph target / blend shape control
- Custom lighting (beyond presets: position, color, intensity per light)
- Node visibility toggle (show/hide parts of a model)
- macOS support (SceneKit -- most iOS code reusable)

See the [GitHub milestones](../../milestones) for detailed tracking.

## Contributing

Contributions are welcome. Please read the guidelines before submitting a PR.

### Setup

```bash
git clone https://github.com/user/flutter_native_3d.git
cd flutter_native_3d
flutter pub get
flutter test  # 76 tests should pass
```

### Structure

```
lib/src/
  native_3d_viewer.dart      # Widget
  native_3d_controller.dart   # Controller
  types/                      # ModelSource, events, errors, enums
  platform/                   # Method channel + platform interface

ios/Classes/
  FlutterNative3dPlugin.swift          # Registration
  Native3DPlatformView[Factory].swift  # Channel dispatch
  SceneManager.swift                   # SceneKit rendering
  ModelLoader.swift                    # glTF loading (GLTFKit2)

android/src/main/kotlin/.../
  FlutterNative3dPlugin.kt             # Registration
  Native3DPlatformView[Factory].kt     # Channel dispatch
  SceneManager.kt                      # Filament rendering
  ModelLoader.kt                       # glTF loading (SceneView)
```

### Guidelines

- **Dart changes**: Run `dart analyze lib/` and `flutter test` before submitting.
- **Native changes**: Ensure both iOS and Android handle the same channel methods with the same error codes.
- **New features**: Add to both platforms, update the platform interface, add tests.
- **Don't break the public API** without a compelling reason and a migration path.

## Comparison: flutter_native_3d vs Alternatives

| Feature | flutter_native_3d | model_viewer_plus | flutter_3d_controller | flutter_cube |
|---|---|---|---|---|
| Rendering | Native (Metal/Filament) | WebView (Three.js) | WebView (model-viewer) | Flutter Canvas (software) |
| glTF/GLB | Full PBR | Full PBR | Full PBR | Partial (OBJ) |
| Touch gestures | Native 60fps | Web touch events | Web touch events | Dart GestureDetector |
| Animations | Native playback | JS-driven | JS-driven | None |
| Camera control | Programmatic + touch | Limited | Limited | Manual |
| Lighting presets | 5 presets + custom (planned) | Via HTML attributes | Via HTML attributes | None |
| Binary size (Android) | +10MB (Filament) | ~0 (system WebView) | ~0 (system WebView) | ~0 |
| Binary size (iOS) | +200KB (GLTFKit2) | ~0 (system WKWebView) | ~0 (system WKWebView) | ~0 |
| AR-ready | Planned (ARKit/ARCore) | Via web AR (limited) | Via model-viewer AR | No |
| Error handling | Typed Dart exceptions | JS console errors | JS console errors | Dart exceptions |
| Startup latency | Fast (direct GPU init) | Slow (HTML + JS load) | Slow (HTML + JS load) | Fast (but software) |

**Choose flutter_native_3d when**: You need production-quality 3D rendering, native touch performance, animation control, or a path to AR. The binary size cost is justified by the quality.

**Choose a WebView-based package when**: You need the smallest possible binary and don't need native performance or animation control.

## Troubleshooting

### iOS: "No such module 'GLTFKit2'"

Run `pod install` in the `ios/` directory:

```bash
cd ios && pod install
```

If using newer Flutter with Swift Package Manager, add a Podfile to your app's `ios/` directory.

### Android: "minSdk 21 is too low"

This plugin requires `minSdk = 24` for Filament/SceneView support. Update your `android/app/build.gradle.kts`.

### Model doesn't appear / black screen

1. Check the asset path matches your `pubspec.yaml` exactly.
2. Ensure the file is `.glb` or `.gltf` (other formats are not supported).
3. Check the debug console for error messages -- all errors are logged with `[flutter_native_3d]` prefix.

### Network model doesn't load

1. Add `<uses-permission android:name="android.permission.INTERNET"/>` to your Android manifest (the plugin's manifest includes this, but verify).
2. On iOS, ensure `NSAppTransportSecurity` allows your domain (or use HTTPS).
3. Check `onError` callback for the specific error (HTTP status, timeout, etc.).

### Animations don't play

1. Not all glTF models contain animations. Check `ModelInfo.hasAnimations` after loading.
2. Use `getAnimationNames()` to see available animation names.
3. Ensure the animation name matches exactly (case-sensitive).

### Performance issues

1. Check triangle count -- models over 200K triangles may drop below 60fps on older devices.
2. Use profile mode (`flutter run --profile`) for accurate measurements -- debug mode has 10x overhead.
3. Large textures (4K+) consume GPU memory. Use compressed textures (KTX2) where possible.

## License

MIT License. See [LICENSE](LICENSE) for details.
