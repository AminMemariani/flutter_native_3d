import Foundation
import SceneKit
import GLTFKit2
import CommonCrypto
import QuartzCore

/// Result of loading a glTF/GLB model.
struct LoadedModel {
    let nodes: [SCNNode]
    let animationKeys: [String]
}

/// Stateless utility for resolving model source descriptors to local file URLs
/// and loading them via GLTFKit2.
///
/// Supports: asset, file, network (with headers + progress), memory (bytes).
enum ModelLoader {

    private static let supportedExtensions: Set<String> = ["glb", "gltf"]

    // MARK: - Public API

    /// Resolve a source descriptor to a local file URL.
    ///
    /// [onProgress] is called with 0.0..1.0 during network downloads.
    /// Not called for asset/file/memory sources.
    static func resolve(
        type: String,
        source: [String: Any],
        onProgress: ((Float) -> Void)? = nil,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        switch type {
        case "asset":
            resolveAsset(source: source, completion: completion)
        case "file":
            resolveFile(source: source, completion: completion)
        case "network":
            resolveNetwork(source: source, onProgress: onProgress, completion: completion)
        case "memory":
            resolveMemory(source: source, completion: completion)
        default:
            completion(.failure(LoaderError.unknownType(type)))
        }
    }

    /// Load a glTF/GLB file from a local URL and return SceneKit nodes.
    static func loadGLTF(from url: URL) throws -> LoadedModel {
        let asset = try GLTFAsset.load(from: url)
        let scnScene = try SCNScene.scene(from: asset)

        let nodes = scnScene.rootNode.childNodes.map { node -> SCNNode in
            node.name = node.name ?? "__native3d_model_\(node.hash)"
            return node
        }

        var keys: [String] = []
        collectAnimationKeys(node: scnScene.rootNode, keys: &keys)

        return LoadedModel(nodes: nodes, animationKeys: keys)
    }

    // MARK: - Asset

    private static func resolveAsset(
        source: [String: Any],
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let path = source["path"] as? String else {
            completion(.failure(LoaderError.missingField("path", sourceType: "asset")))
            return
        }

        if !hasValidExtension(path) {
            completion(.failure(LoaderError.unsupportedFormat(extensionOf(path))))
            return
        }

        let key = FlutterDartProject.lookupKey(forAsset: path)
        guard let bundlePath = Bundle.main.path(forResource: key, ofType: nil) else {
            completion(.failure(LoaderError.assetNotFound(path)))
            return
        }
        completion(.success(URL(fileURLWithPath: bundlePath)))
    }

    // MARK: - File

    private static func resolveFile(
        source: [String: Any],
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let path = source["path"] as? String else {
            completion(.failure(LoaderError.missingField("path", sourceType: "file")))
            return
        }

        if !hasValidExtension(path) {
            completion(.failure(LoaderError.unsupportedFormat(extensionOf(path))))
            return
        }

        guard FileManager.default.fileExists(atPath: path) else {
            completion(.failure(LoaderError.fileNotFound(path)))
            return
        }
        guard FileManager.default.isReadableFile(atPath: path) else {
            completion(.failure(LoaderError.fileNotReadable(path)))
            return
        }
        completion(.success(URL(fileURLWithPath: path)))
    }

    // MARK: - Network (with headers + progress)

    private static func resolveNetwork(
        source: [String: Any],
        onProgress: ((Float) -> Void)?,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        guard let urlString = source["path"] as? String else {
            completion(.failure(LoaderError.missingField("path", sourceType: "network")))
            return
        }
        guard let url = URL(string: urlString) else {
            completion(.failure(LoaderError.invalidURL(urlString)))
            return
        }

        let headers = source["headers"] as? [String: String] ?? [:]

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 60
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Use a delegate-based session for progress reporting
        let delegate = DownloadDelegate(
            url: url,
            onProgress: onProgress,
            completion: completion
        )
        let session = URLSession(
            configuration: .default,
            delegate: delegate,
            delegateQueue: nil
        )
        let task = session.downloadTask(with: request)
        // Store delegate reference to prevent premature deallocation.
        // URLSession retains its delegate, so this is safe.
        task.resume()
    }

    // MARK: - Memory (bytes -> temp file with unique name)

    private static func resolveMemory(
        source: [String: Any],
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let data: Data
        if let typedData = source["bytes"] as? FlutterStandardTypedData {
            data = typedData.data
        } else if let rawData = source["bytes"] as? Data {
            data = rawData
        } else {
            completion(.failure(LoaderError.missingField("bytes", sourceType: "memory")))
            return
        }

        let formatHint = source["formatHint"] as? String ?? "glb"

        // Use content hash to avoid filename collisions
        let hash = String(sha1(data).prefix(12))
        let fileName = "mem_\(hash).\(formatHint)"

        DispatchQueue.global(qos: .userInitiated).async {
            let cacheDir = self.cacheDirectory()

            let destURL = cacheDir.appendingPathComponent(fileName)

            do {
                try data.write(to: destURL, options: .atomic)
                completion(.success(destURL))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Helpers

    private static func cacheDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("flutter_native_3d", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func extensionOf(_ path: String) -> String {
        return (path as NSString).pathExtension.lowercased()
    }

    private static func hasValidExtension(_ path: String) -> Bool {
        return supportedExtensions.contains(extensionOf(path))
    }

    /// Extract extension from a URL path, stripping query params.
    private static func sanitizedExtension(_ urlPath: String) -> String {
        let pathOnly = urlPath.components(separatedBy: "?").first ?? urlPath
        let ext = (pathOnly as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext) ? ext : "glb"
    }

    private static func sha1(_ string: String) -> String {
        return sha1(Data(string.utf8))
    }

    private static func sha1(_ data: Data) -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func collectAnimationKeys(node: SCNNode, keys: inout [String]) {
        for key in node.animationKeys where !keys.contains(key) {
            keys.append(key)
        }
        for child in node.childNodes {
            collectAnimationKeys(node: child, keys: &keys)
        }
    }
}

// MARK: - Download Delegate (progress reporting)

/// URLSession delegate that reports download progress and moves the
/// completed file to the plugin's cache directory.
private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let sourceURL: URL
    private let onProgress: ((Float) -> Void)?
    private let completion: (Result<URL, Error>) -> Void
    private var completed = false
    private var lastProgressTime: CFTimeInterval = 0

    init(
        url: URL,
        onProgress: ((Float) -> Void)?,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.sourceURL = url
        self.onProgress = onProgress
        self.completion = completion
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        // Throttle: max 1 callback per 100ms to avoid flooding the main thread
        let now = CACurrentMediaTime()
        guard now - lastProgressTime >= 0.1 else { return }
        lastProgressTime = now
        let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
        DispatchQueue.main.async { [weak self] in
            self?.onProgress?(progress.clamped(to: 0...1))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard !completed else { return }

        // Validate HTTP status
        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            finish(.failure(LoaderError.httpError(
                httpResponse.statusCode, sourceURL.absoluteString
            )))
            return
        }

        let ext = ModelLoader.sanitizedExtension(sourceURL.path)
        let hash = String(ModelLoader.sha1(sourceURL.absoluteString).prefix(12))
        let fileName = "\(hash).\(ext)"

        let cacheDir = ModelLoader.cacheDirectory()
        let destURL = cacheDir.appendingPathComponent(fileName)

        try? FileManager.default.removeItem(at: destURL)
        do {
            try FileManager.default.moveItem(at: location, to: destURL)
            finish(.success(destURL))
        } catch {
            finish(.failure(error))
        }

        session.finishTasksAndInvalidate()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            finish(.failure(error))
            session.finishTasksAndInvalidate()
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !completed else { return }
        completed = true
        completion(result)
    }
}

// Make helper methods accessible to DownloadDelegate
extension ModelLoader {
    fileprivate static func sanitizedExtension(_ urlPath: String) -> String {
        let pathOnly = urlPath.components(separatedBy: "?").first ?? urlPath
        let ext = (pathOnly as NSString).pathExtension.lowercased()
        return supportedExtensions.contains(ext) ? ext : "glb"
    }

    fileprivate static func sha1(_ string: String) -> String {
        return sha1(Data(string.utf8))
    }

    fileprivate static func cacheDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("flutter_native_3d", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

// MARK: - Float clamping helper

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Errors

enum LoaderError: LocalizedError {
    case assetNotFound(String)
    case fileNotFound(String)
    case fileNotReadable(String)
    case invalidURL(String)
    case httpError(Int, String)
    case downloadFailed(String)
    case unknownType(String)
    case unsupportedFormat(String)
    case missingField(String, sourceType: String)

    var errorDescription: String? {
        switch self {
        case .assetNotFound(let path):
            return "Asset not found: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .fileNotReadable(let path):
            return "File not readable: \(path)"
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .httpError(let code, let url):
            return "HTTP \(code) downloading \(url)"
        case .downloadFailed(let url):
            return "Download failed: \(url)"
        case .unknownType(let type):
            return "Unknown source type: \(type)"
        case .unsupportedFormat(let ext):
            return "Unsupported file format: '\(ext)'. Supported: glb, gltf"
        case .missingField(let field, let sourceType):
            return "Missing '\(field)' for \(sourceType) source"
        }
    }
}
