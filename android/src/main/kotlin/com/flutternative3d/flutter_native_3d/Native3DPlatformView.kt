package com.flutternative3d.flutter_native_3d

import android.content.Context
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

/**
 * Flutter platform view that bridges method channel calls to [SceneManager].
 *
 * This class handles only Flutter communication -- no rendering logic.
 * All 3D operations are delegated to SceneManager.
 *
 * Channel: `flutter_native_3d/scene_$viewId`
 */
class Native3DPlatformView(
    context: Context,
    viewId: Int,
    creationParams: Map<String, Any>,
    messenger: BinaryMessenger
) : PlatformView, MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "flutter_native_3d/scene_$viewId")
    private val sceneManager = SceneManager(context)
    private var disposed = false

    init {
        channel.setMethodCallHandler(this)
        applyCreationParams(creationParams)

        // Signal that the native scene is ready for commands
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            if (!disposed) {
                channel.invokeMethod("onEvent", mapOf("type" to "sceneReady"))
            }
        }
    }

    override fun getView(): View = sceneManager.view

    override fun dispose() {
        if (disposed) return
        disposed = true
        channel.setMethodCallHandler(null)
        sceneManager.dispose()
    }

    // -------------------------------------------------------------------------
    // Creation params (applied once at native view init)
    // -------------------------------------------------------------------------

    private fun applyCreationParams(params: Map<String, Any>) {
        (params["backgroundColor"] as? Int)?.let {
            sceneManager.setBackgroundColor(it)
        }
        (params["lighting"] as? String)?.let {
            sceneManager.setLighting(it)
        }
        (params["fitMode"] as? String)?.let {
            sceneManager.setFitMode(it)
        }
        (params["gesturesEnabled"] as? Boolean)?.let {
            sceneManager.setGesturesEnabled(it)
        }
        (params["autoRotate"] as? Boolean)?.let {
            sceneManager.setAutoRotate(it)
        }
        @Suppress("UNCHECKED_CAST")
        (params["initialCameraOrbit"] as? Map<String, Any>)?.let { orbit ->
            val theta = (orbit["theta"] as? Number)?.toFloat() ?: 0f
            val phi = (orbit["phi"] as? Number)?.toFloat() ?: 20f
            val radius = (orbit["radius"] as? Number)?.toFloat() ?: 3f
            sceneManager.setCameraOrbit(theta, phi, radius)
        }

        // NOTE: We intentionally do NOT load the model here from creation params.
        // The Dart side sends loadModel via the method channel so it can receive
        // the Future<ModelInfo> result. Loading here too would cause a double load.
    }

    // -------------------------------------------------------------------------
    // Method channel dispatch
    // -------------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            result.error("DISPOSED", "Native view has been disposed", null)
            return
        }

        when (call.method) {
            "loadModel" -> handleLoadModel(call, result)
            "resetCamera" -> {
                sceneManager.resetCamera()
                result.success(null)
            }
            "setCameraOrbit" -> {
                val theta = call.argument<Number>("theta")?.toFloat() ?: 0f
                val phi = call.argument<Number>("phi")?.toFloat() ?: 20f
                val radius = call.argument<Number>("radius")?.toFloat() ?: 3f
                sceneManager.setCameraOrbit(theta, phi, radius)
                result.success(null)
            }
            "getAnimationNames" -> {
                result.success(sceneManager.getAnimationNames())
            }
            "playAnimation" -> {
                val name = call.argument<String>("name")
                if (name == null) {
                    result.error("INVALID_ARGS", "Expected 'name' argument", null)
                    return
                }
                val loop = call.argument<Boolean>("loop") ?: true
                val error = sceneManager.playAnimation(name, loop) { completedName ->
                    if (!disposed) {
                        channel.invokeMethod("onEvent", mapOf(
                            "type" to "animationCompleted",
                            "name" to completedName,
                        ))
                    }
                }
                if (error != null) {
                    result.error("ANIMATION_ERROR", error, null)
                } else {
                    result.success(null)
                }
            }
            "playAnimationByIndex" -> {
                val index = call.argument<Int>("index")
                if (index == null) {
                    result.error("INVALID_ARGS", "Expected 'index' argument", null)
                    return
                }
                val loop = call.argument<Boolean>("loop") ?: true
                val error = sceneManager.playAnimationByIndex(index, loop) { completedName ->
                    if (!disposed) {
                        channel.invokeMethod("onEvent", mapOf(
                            "type" to "animationCompleted",
                            "name" to completedName,
                        ))
                    }
                }
                if (error != null) {
                    result.error("ANIMATION_ERROR", error, null)
                } else {
                    result.success(null)
                }
            }
            "pauseAnimation" -> {
                sceneManager.pauseAnimation()
                result.success(null)
            }
            "stopAnimation" -> {
                sceneManager.stopAnimation()
                result.success(null)
            }
            "setBackgroundColor" -> {
                val color = call.argument<Int>("color")
                if (color == null) {
                    result.error("INVALID_ARGS", "Expected 'color' argument", null)
                    return
                }
                sceneManager.setBackgroundColor(color)
                result.success(null)
            }
            "setLighting" -> {
                val preset = call.argument<String>("preset")
                if (preset == null) {
                    result.error("INVALID_ARGS", "Expected 'preset' argument", null)
                    return
                }
                sceneManager.setLighting(preset)
                result.success(null)
            }
            "setGesturesEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                sceneManager.setGesturesEnabled(enabled)
                result.success(null)
            }
            "setAutoRotate" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                sceneManager.setAutoRotate(enabled)
                result.success(null)
            }
            "setFitMode" -> {
                val mode = call.argument<String>("mode") ?: "contain"
                sceneManager.setFitMode(mode)
                result.success(null)
            }
            "dispose" -> {
                dispose()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun handleLoadModel(call: MethodCall, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val args = call.arguments as? Map<String, Any>
        if (args == null) {
            result.error("INVALID_ARGS", "Expected map with 'type' and 'path'", null)
            return
        }

        val onProgress: (Float) -> Unit = { progress ->
            if (!disposed) {
                channel.invokeMethod("onEvent", mapOf(
                    "type" to "loadProgress",
                    "progress" to progress.toDouble(),
                ))
            }
        }

        sceneManager.loadModel(args, autoPlay = false, onProgress = onProgress) { loadResult ->
            if (disposed) return@loadModel
            loadResult.fold(
                onSuccess = { info -> result.success(info) },
                onFailure = { error ->
                    result.error(
                        errorCode(error),
                        error.message ?: "Unknown error loading model",
                        error.stackTraceToString()
                    )
                }
            )
        }
    }

    /// Map a native error to a structured error code for the Dart side.
    private fun errorCode(error: Throwable): String {
        val message = error.message?.lowercase() ?: ""
        return when {
            message.contains("asset not found") || message.contains("not found in assets") -> "ASSET_NOT_FOUND"
            message.contains("file not found") -> "FILE_NOT_FOUND"
            message.contains("file not readable") -> "FILE_NOT_FOUND"
            message.contains("http ") || message.contains("download") || message.contains("connect") -> "NETWORK_ERROR"
            message.contains("unsupported file format") || message.contains("unsupported") -> "FORMAT_ERROR"
            else -> "MODEL_LOAD_ERROR"
        }
    }
}
