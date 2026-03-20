import SceneKit

/// Manages the SceneKit scene, camera, lighting, animations, and model lifecycle.
///
/// Pure SceneKit -- no Flutter imports. All communication with Flutter
/// happens through Native3DPlatformView.
class SceneManager {
    private let scnView: SCNView
    private var animationKeys: [String] = []
    private var modelCenter = SCNVector3Zero
    private var modelRadius: Float = 1.0
    private var currentTheta: Float = 0
    private var currentPhi: Float = 20
    private var currentCameraRadius: Float = 3
    private var autoRotateTimer: Timer?
    private var disposed = false

    var view: UIView { scnView }

    init(frame: CGRect) {
        scnView = SCNView(frame: frame)
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = true
        scnView.antialiasingMode = .multisampling4X
        scnView.backgroundColor = .clear

        let scene = SCNScene()
        scnView.scene = scene

        setupDefaultCamera(scene: scene)
        setupDefaultLighting(scene: scene)
    }

    // MARK: - Model Loading

    /// Load a model from the given source descriptor.
    ///
    /// `source` keys: type (asset|file|network|memory), path, headers?, bytes?, formatHint?
    /// `completion` is called on the main thread.
    func loadModel(
        source: [String: Any],
        autoPlay: Bool,
        onProgress: ((Float) -> Void)? = nil,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        if disposed {
            completion(.failure(SceneError.disposed))
            return
        }

        guard let type = source["type"] as? String else {
            completion(.failure(SceneError.missingField("type")))
            return
        }

        clearModelNodes()

        ModelLoader.resolve(type: type, source: source, onProgress: onProgress) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self, !self.disposed else { return }
                switch result {
                case .success(let url):
                    do {
                        let loaded = try ModelLoader.loadGLTF(from: url)
                        guard let scene = self.scnView.scene else { return }

                        for child in loaded.nodes {
                            scene.rootNode.addChildNode(child)
                        }
                        self.animationKeys = loaded.animationKeys
                        self.computeModelBounds()
                        self.frameCameraToFitModel()

                        if autoPlay, let first = self.animationKeys.first {
                            _ = self.playAnimation(name: first, loop: true, onComplete: nil)
                        }

                        completion(.success(["animationNames": self.animationKeys]))
                    } catch {
                        completion(.failure(error))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Camera

    func resetCamera() {
        frameCameraToFitModel()
    }

    /// Position the camera using spherical coordinates around the model center.
    /// - theta: horizontal angle in degrees (0 = front, 90 = right)
    /// - phi: vertical angle in degrees (0 = eye level, clamped to -89..89)
    /// - radius: distance from model center
    func setCameraOrbit(theta: Float, phi: Float, radius: Float) {
        currentTheta = theta
        currentPhi = min(max(phi, -89), 89)
        currentCameraRadius = max(radius, 0.1)
        applyCameraOrbit()
    }

    // MARK: - Animations

    func getAnimationNames() -> [String] {
        return animationKeys
    }

    /// Play animation by name. Returns nil on success, error message on failure.
    func playAnimation(name: String, loop: Bool, onComplete: ((String) -> Void)?) -> String? {
        guard scnView.scene != nil else {
            return "No scene available"
        }
        guard animationKeys.contains(name) else {
            return "Animation '\(name)' not found. Available: \(animationKeys)"
        }
        playAnimationRecursive(node: scnView.scene!.rootNode, name: name, loop: loop, onComplete: onComplete)
        return nil
    }

    /// Play animation by index. Returns nil on success, error message on failure.
    func playAnimationByIndex(index: Int, loop: Bool, onComplete: ((String) -> Void)?) -> String? {
        guard index >= 0 && index < animationKeys.count else {
            return "Animation index \(index) out of range (0..\(animationKeys.count - 1))"
        }
        return playAnimation(name: animationKeys[index], loop: loop, onComplete: onComplete)
    }

    func pauseAnimation() {
        guard let scene = scnView.scene else { return }
        pauseAnimationsRecursive(node: scene.rootNode)
    }

    func stopAnimation() {
        guard let scene = scnView.scene else { return }
        stopAnimationsRecursive(node: scene.rootNode)
    }

    // MARK: - Appearance

    func setBackgroundColor(_ argb: Int) {
        let a = CGFloat((argb >> 24) & 0xFF) / 255.0
        let r = CGFloat((argb >> 16) & 0xFF) / 255.0
        let g = CGFloat((argb >> 8) & 0xFF) / 255.0
        let b = CGFloat(argb & 0xFF) / 255.0
        scnView.backgroundColor = UIColor(red: r, green: g, blue: b, alpha: a)
    }

    /// Apply a lighting preset by configuring the ambient and directional lights.
    func setLighting(_ preset: String) {
        guard let scene = scnView.scene else { return }
        let ambient = scene.rootNode.childNode(withName: "__native3d_ambient_light", recursively: false)
        let directional = scene.rootNode.childNode(withName: "__native3d_directional_light", recursively: false)

        switch preset {
        case "studio":
            ambient?.light?.intensity = 500
            ambient?.light?.color = UIColor.white
            directional?.light?.intensity = 1000
            directional?.light?.color = UIColor.white
        case "natural":
            ambient?.light?.intensity = 600
            ambient?.light?.color = UIColor(red: 1.0, green: 0.97, blue: 0.94, alpha: 1.0)
            directional?.light?.intensity = 800
            directional?.light?.color = UIColor(red: 1.0, green: 0.97, blue: 0.94, alpha: 1.0)
        case "dramatic":
            ambient?.light?.intensity = 200
            ambient?.light?.color = UIColor(red: 0.3, green: 0.3, blue: 0.4, alpha: 1.0)
            directional?.light?.intensity = 1500
            directional?.light?.color = UIColor(red: 1.0, green: 0.94, blue: 0.86, alpha: 1.0)
        case "neutral":
            ambient?.light?.intensity = 800
            ambient?.light?.color = UIColor.white
            directional?.light?.intensity = 500
            directional?.light?.color = UIColor.white
        case "unlit":
            ambient?.light?.intensity = 0
            directional?.light?.intensity = 0
        default:
            NSLog("[flutter_native_3d] Unknown lighting preset: \(preset)")
        }
    }

    /// Toggle camera orbit/pan/zoom gestures.
    /// Note: only disables the built-in camera manipulation, not all touch
    /// (isUserInteractionEnabled stays true for future tap-on-node support).
    func setGesturesEnabled(_ enabled: Bool) {
        scnView.allowsCameraControl = enabled
    }

    /// Enable/disable continuous auto-rotation around the model's Y axis.
    /// Rotates at approximately 30 degrees/second.
    ///
    /// While auto-rotating, the built-in camera gestures are suspended to
    /// prevent the timer and user touches from fighting over the camera.
    /// Call `setAutoRotate(false)` to stop rotation and restore gestures.
    private var gesturesEnabledBeforeAutoRotate = true

    func setAutoRotate(_ enabled: Bool) {
        autoRotateTimer?.invalidate()
        autoRotateTimer = nil

        if !enabled {
            // Restore gesture state from before auto-rotate was enabled
            scnView.allowsCameraControl = gesturesEnabledBeforeAutoRotate
            return
        }

        // Save current gesture state and disable during rotation
        gesturesEnabledBeforeAutoRotate = scnView.allowsCameraControl
        scnView.allowsCameraControl = false

        autoRotateTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self, !self.disposed else { return }
            self.currentTheta += 0.5 // ~30 deg/sec at 60fps
            if self.currentTheta >= 360 { self.currentTheta -= 360 }
            self.applyCameraOrbit()
        }
    }

    /// Set how the model is scaled to fit the viewport.
    /// Modes: "contain" (default), "cover", "none"
    func setFitMode(_ mode: String) {
        switch mode {
        case "contain":
            frameCameraToFitModel()
        case "cover":
            let distance = modelRadius * 0.8
            currentCameraRadius = max(distance, 0.1)
            applyCameraOrbit()
        case "none":
            currentCameraRadius = 3.0
            applyCameraOrbit()
        default:
            NSLog("[flutter_native_3d] Unknown fit mode: \(mode)")
        }
    }

    // MARK: - Lifecycle

    func dispose() {
        guard !disposed else { return }
        disposed = true
        autoRotateTimer?.invalidate()
        autoRotateTimer = nil
        clearModelNodes()
        scnView.scene = nil
    }

    // MARK: - Private: Setup

    private func setupDefaultCamera(scene: SCNScene) {
        let cameraNode = SCNNode()
        cameraNode.name = "__native3d_camera"
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.position = SCNVector3(0, 1, 3)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode
    }

    private func setupDefaultLighting(scene: SCNScene) {
        let ambientNode = SCNNode()
        ambientNode.name = "__native3d_ambient_light"
        ambientNode.light = SCNLight()
        ambientNode.light?.type = .ambient
        ambientNode.light?.intensity = 500
        ambientNode.light?.color = UIColor.white
        scene.rootNode.addChildNode(ambientNode)

        let directionalNode = SCNNode()
        directionalNode.name = "__native3d_directional_light"
        directionalNode.light = SCNLight()
        directionalNode.light?.type = .directional
        directionalNode.light?.intensity = 1000
        directionalNode.light?.color = UIColor.white
        directionalNode.position = SCNVector3(5, 10, 5)
        directionalNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(directionalNode)
    }

    // MARK: - Private: Model Management

    private func clearModelNodes() {
        scnView.scene?.rootNode.childNodes
            .filter { !($0.name?.hasPrefix("__native3d_") ?? false) }
            .forEach { $0.removeFromParentNode() }
        animationKeys = []
    }

    /// Compute the axis-aligned bounding box center and radius from model nodes.
    private func computeModelBounds() {
        let modelNodes = scnView.scene?.rootNode.childNodes.filter {
            !($0.name?.hasPrefix("__native3d_") ?? false)
        } ?? []

        guard !modelNodes.isEmpty else {
            modelCenter = SCNVector3Zero
            modelRadius = 1.0
            return
        }

        var minB = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxB = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)

        for node in modelNodes {
            let (localMin, localMax) = node.boundingBox
            let worldMin = node.convertPosition(localMin, to: nil)
            let worldMax = node.convertPosition(localMax, to: nil)
            minB.x = min(minB.x, worldMin.x); minB.y = min(minB.y, worldMin.y); minB.z = min(minB.z, worldMin.z)
            maxB.x = max(maxB.x, worldMax.x); maxB.y = max(maxB.y, worldMax.y); maxB.z = max(maxB.z, worldMax.z)
        }

        modelCenter = SCNVector3(
            (minB.x + maxB.x) / 2,
            (minB.y + maxB.y) / 2,
            (minB.z + maxB.z) / 2
        )
        modelRadius = max(maxB.x - minB.x, max(maxB.y - minB.y, maxB.z - minB.z))
        if modelRadius < 0.01 { modelRadius = 1.0 }
    }

    // MARK: - Private: Camera

    private func frameCameraToFitModel() {
        currentCameraRadius = max(modelRadius * 1.5, 0.5)
        currentTheta = 0
        currentPhi = 20
        applyCameraOrbit()
    }

    /// Apply the current spherical coordinates to position the camera.
    /// Converts (theta, phi, radius) from degrees to Cartesian looking at modelCenter.
    private func applyCameraOrbit() {
        let thetaRad = currentTheta * .pi / 180
        let phiRad = currentPhi * .pi / 180

        let x = currentCameraRadius * cos(phiRad) * sin(thetaRad)
        let y = currentCameraRadius * sin(phiRad)
        let z = currentCameraRadius * cos(phiRad) * cos(thetaRad)

        guard let cameraNode = scnView.scene?.rootNode.childNode(
            withName: "__native3d_camera", recursively: false
        ) else { return }

        cameraNode.position = SCNVector3(
            modelCenter.x + x,
            modelCenter.y + y,
            modelCenter.z + z
        )
        cameraNode.look(at: modelCenter)
    }

    // MARK: - Private: Animations

    private func playAnimationRecursive(node: SCNNode, name: String, loop: Bool, onComplete: ((String) -> Void)?) {
        if let player = node.animationPlayer(forKey: name) {
            player.animation.isRemovedOnCompletion = !loop
            player.animation.repeatCount = loop ? .greatestFiniteMagnitude : 1
            if !loop, let onComplete = onComplete {
                player.animation.animationDidStop = { _, _, _ in
                    onComplete(name)
                }
            }
            player.play()
        }
        for child in node.childNodes {
            playAnimationRecursive(node: child, name: name, loop: loop, onComplete: onComplete)
        }
    }

    private func pauseAnimationsRecursive(node: SCNNode) {
        for key in node.animationKeys {
            node.animationPlayer(forKey: key)?.paused = true
        }
        for child in node.childNodes {
            pauseAnimationsRecursive(node: child)
        }
    }

    private func stopAnimationsRecursive(node: SCNNode) {
        for key in node.animationKeys {
            node.animationPlayer(forKey: key)?.stop()
        }
        for child in node.childNodes {
            stopAnimationsRecursive(node: child)
        }
    }
}

// MARK: - Errors

enum SceneError: LocalizedError {
    case disposed
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .disposed: return "SceneManager has been disposed"
        case .missingField(let field): return "Missing '\(field)' in source"
        }
    }
}
