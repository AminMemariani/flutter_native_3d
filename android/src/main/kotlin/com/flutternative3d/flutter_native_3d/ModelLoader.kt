package com.flutternative3d.flutter_native_3d

import android.content.Context
import android.util.Log
import io.flutter.FlutterInjector
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * Stateless utility for resolving model source descriptors to local file paths
 * that SceneView's ModelLoader can consume.
 *
 * Supports: asset, file, network (with headers + progress), memory (bytes).
 *
 * All [completion] callbacks are delivered on [Dispatchers.Main].
 */
object ModelLoader {

    private const val TAG = "flutter_native_3d"
    private val SUPPORTED_EXTENSIONS = setOf("glb", "gltf")

    /**
     * Resolve a source descriptor to a file path or asset key.
     *
     * [onProgress] is called with values 0.0..1.0 during network downloads
     * (on Dispatchers.Main). Not called for asset/file/memory sources.
     */
    fun resolve(
        context: Context,
        type: String,
        source: Map<String, Any>,
        scope: CoroutineScope,
        onProgress: ((Float) -> Unit)? = null,
        completion: (Result<String>) -> Unit
    ) {
        when (type) {
            "asset" -> resolveAsset(source, completion)
            "file" -> resolveFile(source, completion)
            "network" -> resolveNetwork(context, source, scope, onProgress, completion)
            "memory" -> resolveMemory(context, source, scope, completion)
            else -> completion(Result.failure(
                IllegalArgumentException("Unknown source type: '$type'")
            ))
        }
    }

    // -------------------------------------------------------------------------
    // Asset
    // -------------------------------------------------------------------------

    private fun resolveAsset(source: Map<String, Any>, completion: (Result<String>) -> Unit) {
        val path = source["path"] as? String ?: run {
            completion(Result.failure(IllegalArgumentException("Missing 'path' for asset source")))
            return
        }

        if (!hasValidExtension(path)) {
            completion(Result.failure(IllegalArgumentException(
                "Unsupported file format: '${extensionOf(path)}'. Supported: $SUPPORTED_EXTENSIONS"
            )))
            return
        }

        val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(path)
        completion(Result.success(key))
    }

    // -------------------------------------------------------------------------
    // File
    // -------------------------------------------------------------------------

    private fun resolveFile(source: Map<String, Any>, completion: (Result<String>) -> Unit) {
        val path = source["path"] as? String ?: run {
            completion(Result.failure(IllegalArgumentException("Missing 'path' for file source")))
            return
        }

        if (!hasValidExtension(path)) {
            completion(Result.failure(IllegalArgumentException(
                "Unsupported file format: '${extensionOf(path)}'. Supported: $SUPPORTED_EXTENSIONS"
            )))
            return
        }

        val file = File(path)
        if (!file.exists()) {
            completion(Result.failure(IllegalArgumentException("File not found: $path")))
        } else if (!file.canRead()) {
            completion(Result.failure(IllegalArgumentException("File not readable: $path")))
        } else {
            completion(Result.success(file.absolutePath))
        }
    }

    // -------------------------------------------------------------------------
    // Network (with headers + progress)
    // -------------------------------------------------------------------------

    @Suppress("UNCHECKED_CAST")
    private fun resolveNetwork(
        context: Context,
        source: Map<String, Any>,
        scope: CoroutineScope,
        onProgress: ((Float) -> Unit)?,
        completion: (Result<String>) -> Unit
    ) {
        val urlString = source["path"] as? String ?: run {
            completion(Result.failure(IllegalArgumentException("Missing 'path' for network source")))
            return
        }
        val headers = source["headers"] as? Map<String, String> ?: emptyMap()

        scope.launch(Dispatchers.IO) {
            try {
                val url = URL(urlString)
                val connection = url.openConnection() as HttpURLConnection
                try {
                    connection.requestMethod = "GET"
                    connection.connectTimeout = 30_000
                    connection.readTimeout = 60_000
                    headers.forEach { (key, value) ->
                        connection.setRequestProperty(key, value)
                    }

                    val responseCode = connection.responseCode
                    if (responseCode !in 200..299) {
                        throw IllegalStateException(
                            "HTTP $responseCode downloading $urlString"
                        )
                    }

                    // Determine filename: URL-hash + extension to avoid collisions
                    val ext = sanitizedExtension(url.path)
                    val hash = sha1(urlString).take(12)
                    val fileName = "${hash}.$ext"

                    val cacheDir = cacheDirectory(context)
                    val tempFile = File(cacheDir, fileName)

                    // Download with throttled progress (max 1 callback per 100ms)
                    val contentLength = connection.contentLength.toLong()
                    var bytesWritten = 0L
                    var lastProgressTime = 0L

                    connection.inputStream.use { input ->
                        FileOutputStream(tempFile).use { output ->
                            val buffer = ByteArray(32768)
                            var read: Int
                            while (input.read(buffer).also { read = it } != -1) {
                                output.write(buffer, 0, read)
                                bytesWritten += read
                                if (contentLength > 0 && onProgress != null) {
                                    val now = System.currentTimeMillis()
                                    if (now - lastProgressTime >= 100) {
                                        lastProgressTime = now
                                        val progress = (bytesWritten.toFloat() / contentLength)
                                            .coerceIn(0f, 1f)
                                        scope.launch(Dispatchers.Main) {
                                            onProgress(progress)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    scope.launch(Dispatchers.Main) {
                        completion(Result.success(tempFile.absolutePath))
                    }
                } finally {
                    connection.disconnect()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to download model: $urlString", e)
                scope.launch(Dispatchers.Main) {
                    completion(Result.failure(e))
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Memory (bytes -> temp file with unique name)
    // -------------------------------------------------------------------------

    private fun resolveMemory(
        context: Context,
        source: Map<String, Any>,
        scope: CoroutineScope,
        completion: (Result<String>) -> Unit
    ) {
        val bytes = source["bytes"] as? ByteArray ?: run {
            completion(Result.failure(
                IllegalArgumentException("Missing 'bytes' for memory source")
            ))
            return
        }
        val formatHint = source["formatHint"] as? String ?: "glb"

        // Use content hash for filename to avoid collisions
        val hash = sha1(bytes).take(12)
        val fileName = "mem_$hash.$formatHint"

        scope.launch(Dispatchers.IO) {
            try {
                val cacheDir = cacheDirectory(context)
                val tempFile = File(cacheDir, fileName)

                FileOutputStream(tempFile).use { output ->
                    output.write(bytes)
                }

                scope.launch(Dispatchers.Main) {
                    completion(Result.success(tempFile.absolutePath))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to write memory model to temp file", e)
                scope.launch(Dispatchers.Main) {
                    completion(Result.failure(e))
                }
            }
        }
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private fun cacheDirectory(context: Context): File {
        val dir = File(context.cacheDir, "flutter_native_3d")
        dir.mkdirs()
        return dir
    }

    private fun extensionOf(path: String): String {
        return path.substringAfterLast('.', "").lowercase()
    }

    private fun hasValidExtension(path: String): Boolean {
        val ext = extensionOf(path)
        return ext in SUPPORTED_EXTENSIONS
    }

    /** Extract extension from a URL path, stripping query params. */
    private fun sanitizedExtension(urlPath: String): String {
        val pathOnly = urlPath.substringBefore('?').substringBefore('#')
        val ext = pathOnly.substringAfterLast('.', "").lowercase()
        return if (ext in SUPPORTED_EXTENSIONS) ext else "glb"
    }

    private fun sha1(input: String): String {
        val digest = MessageDigest.getInstance("SHA-1")
        return digest.digest(input.toByteArray())
            .joinToString("") { "%02x".format(it) }
    }

    private fun sha1(input: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-1")
        return digest.digest(input)
            .joinToString("") { "%02x".format(it) }
    }
}
