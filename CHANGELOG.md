## 0.1.0

Initial release.

### Rendering
- Native 3D model rendering: SceneKit (Metal) on iOS, Filament on Android
- glTF (.gltf) and GLB (.glb) format support via GLTFKit2 (iOS) and SceneView (Android)
- PBR material rendering with physically-based shading

### Model Loading
- Load from Flutter assets, local files, network URLs, or raw bytes
- Network downloads with HTTP header support (authentication, API keys)
- Download progress reporting via `onModelLoadProgress`
- SHA-1 content-addressed caching to prevent filename collisions
- Format validation before native load attempt

### Animation
- Detect available animations on model load (`ModelInfo.animationNames`)
- Play by name or index, with loop control
- Pause at current frame, stop and reset to first frame
- Auto-play first animation on load via `autoPlay` parameter

### Camera & Interaction
- Touch gestures: orbit, pan, zoom (enable/disable at runtime)
- Programmatic camera orbit via `setCameraOrbit(theta, phi, radius)`
- Auto-frame camera to fit model bounding box
- Auto-rotate turntable mode
- Model fit modes: contain, cover, none

### Scene
- 5 lighting presets: studio, natural, dramatic, neutral, unlit
- Configurable background color
- Runtime switching of all scene properties

### API
- Controller pattern (`Native3DController`) for imperative scene control
- Typed error hierarchy: `AssetNotFoundException`, `NetworkException`, `FormatNotSupportedException`, `AnimationException`, `LoadSupersededException`
- Event stream: `SceneReadyEvent`, `ModelLoadProgressEvent`, `AnimationCompletedEvent`, `SceneErrorEvent`
- Load sequencing with automatic stale-load cancellation
- Lifecycle-safe dispose with graceful degradation

### Platform Support
- iOS 15.0+ (SceneKit + GLTFKit2)
- Android API 24+ (Filament via SceneView)
