import Flutter
import UIKit

/// Flutter platform view that bridges method channel calls to SceneManager.
///
/// This class handles only Flutter communication -- no rendering logic.
/// All 3D operations are delegated to SceneManager.
///
/// Channel: `flutter_native_3d/scene_$viewId`
class Native3DPlatformView: NSObject, FlutterPlatformView {
    private let sceneManager: SceneManager
    private let channel: FlutterMethodChannel
    private var disposed = false

    init(frame: CGRect, viewId: Int64, args: [String: Any], messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "flutter_native_3d/scene_\(viewId)",
            binaryMessenger: messenger
        )
        sceneManager = SceneManager(frame: frame)

        super.init()

        channel.setMethodCallHandler(handle)
        applyCreationParams(args)

        // Signal that the native scene is ready for commands
        DispatchQueue.main.async { [weak self] in
            self?.channel.invokeMethod("onEvent", arguments: ["type": "sceneReady"])
        }
    }

    func view() -> UIView {
        return sceneManager.view
    }

    /// Map a native error to a structured error code for the Dart side.
    private static func errorCode(for error: Error) -> String {
        if let loaderError = error as? LoaderError {
            return switch loaderError {
            case .assetNotFound: "ASSET_NOT_FOUND"
            case .fileNotFound, .fileNotReadable: "FILE_NOT_FOUND"
            case .invalidURL, .httpError, .downloadFailed: "NETWORK_ERROR"
            case .unsupportedFormat: "FORMAT_ERROR"
            case .unknownType, .missingField: "MODEL_LOAD_ERROR"
            }
        }
        return "MODEL_LOAD_ERROR"
    }

    // MARK: - Creation Params (applied once at native view init)

    private func applyCreationParams(_ params: [String: Any]) {
        if let bgColor = params["backgroundColor"] as? Int {
            sceneManager.setBackgroundColor(bgColor)
        }
        if let lighting = params["lighting"] as? String {
            sceneManager.setLighting(lighting)
        }
        if let fitMode = params["fitMode"] as? String {
            sceneManager.setFitMode(fitMode)
        }
        if let gesturesEnabled = params["gesturesEnabled"] as? Bool {
            sceneManager.setGesturesEnabled(gesturesEnabled)
        }
        if let autoRotate = params["autoRotate"] as? Bool {
            sceneManager.setAutoRotate(autoRotate)
        }
        if let orbit = params["initialCameraOrbit"] as? [String: Any] {
            let theta = (orbit["theta"] as? NSNumber)?.floatValue ?? 0
            let phi = (orbit["phi"] as? NSNumber)?.floatValue ?? 20
            let radius = (orbit["radius"] as? NSNumber)?.floatValue ?? 3
            sceneManager.setCameraOrbit(theta: theta, phi: phi, radius: radius)
        }

        // NOTE: We intentionally do NOT load the model here from creation params.
        // The Dart side sends loadModel via the method channel so it can receive
        // the Future<ModelInfo> result. Loading here too would cause a double load
        // (creation-params load is discarded, channel load clears and reloads).
    }

    // MARK: - Method Channel Dispatch

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if disposed {
            result(FlutterError(code: "DISPOSED", message: "Native view has been disposed", details: nil))
            return
        }

        switch call.method {
        case "loadModel":
            handleLoadModel(call, result: result)

        case "resetCamera":
            sceneManager.resetCamera()
            result(nil)

        case "setCameraOrbit":
            let args = call.arguments as? [String: Any] ?? [:]
            let theta = (args["theta"] as? NSNumber)?.floatValue ?? 0
            let phi = (args["phi"] as? NSNumber)?.floatValue ?? 20
            let radius = (args["radius"] as? NSNumber)?.floatValue ?? 3
            sceneManager.setCameraOrbit(theta: theta, phi: phi, radius: radius)
            result(nil)

        case "getAnimationNames":
            result(sceneManager.getAnimationNames())

        case "playAnimation":
            guard let args = call.arguments as? [String: Any],
                  let name = args["name"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Expected 'name' argument", details: nil))
                return
            }
            let loop = args["loop"] as? Bool ?? true
            let onComplete: (String) -> Void = { [weak self] completedName in
                guard let self = self, !self.disposed else { return }
                self.channel.invokeMethod("onEvent", arguments: [
                    "type": "animationCompleted",
                    "name": completedName,
                ])
            }
            if let error = sceneManager.playAnimation(name: name, loop: loop, onComplete: onComplete) {
                result(FlutterError(code: "ANIMATION_ERROR", message: error, details: nil))
            } else {
                result(nil)
            }

        case "playAnimationByIndex":
            guard let args = call.arguments as? [String: Any],
                  let index = args["index"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Expected 'index' argument", details: nil))
                return
            }
            let loop = args["loop"] as? Bool ?? true
            let onComplete: (String) -> Void = { [weak self] completedName in
                guard let self = self, !self.disposed else { return }
                self.channel.invokeMethod("onEvent", arguments: [
                    "type": "animationCompleted",
                    "name": completedName,
                ])
            }
            if let error = sceneManager.playAnimationByIndex(index: index, loop: loop, onComplete: onComplete) {
                result(FlutterError(code: "ANIMATION_ERROR", message: error, details: nil))
            } else {
                result(nil)
            }

        case "pauseAnimation":
            sceneManager.pauseAnimation()
            result(nil)

        case "stopAnimation":
            sceneManager.stopAnimation()
            result(nil)

        case "setBackgroundColor":
            guard let args = call.arguments as? [String: Any],
                  let color = args["color"] as? Int else {
                result(FlutterError(code: "INVALID_ARGS", message: "Expected 'color' argument", details: nil))
                return
            }
            sceneManager.setBackgroundColor(color)
            result(nil)

        case "setLighting":
            guard let args = call.arguments as? [String: Any],
                  let preset = args["preset"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Expected 'preset' argument", details: nil))
                return
            }
            sceneManager.setLighting(preset)
            result(nil)

        case "setGesturesEnabled":
            let args = call.arguments as? [String: Any] ?? [:]
            let enabled = args["enabled"] as? Bool ?? true
            sceneManager.setGesturesEnabled(enabled)
            result(nil)

        case "setAutoRotate":
            let args = call.arguments as? [String: Any] ?? [:]
            let enabled = args["enabled"] as? Bool ?? false
            sceneManager.setAutoRotate(enabled)
            result(nil)

        case "setFitMode":
            let args = call.arguments as? [String: Any] ?? [:]
            let mode = args["mode"] as? String ?? "contain"
            sceneManager.setFitMode(mode)
            result(nil)

        case "dispose":
            disposed = true
            channel.setMethodCallHandler(nil)
            sceneManager.dispose()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleLoadModel(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Expected map with 'type' and 'path'", details: nil))
            return
        }

        let onProgress: (Float) -> Void = { [weak self] progress in
            guard let self = self, !self.disposed else { return }
            self.channel.invokeMethod("onEvent", arguments: [
                "type": "loadProgress",
                "progress": Double(progress),
            ])
        }

        sceneManager.loadModel(source: args, autoPlay: false, onProgress: onProgress) { [weak self] loadResult in
            guard let self = self, !self.disposed else { return }
            switch loadResult {
            case .success(let info):
                result(info)
            case .failure(let error):
                result(FlutterError(
                    code: Self.errorCode(for: error),
                    message: error.localizedDescription,
                    details: String(describing: error)
                ))
            }
        }
    }
}
