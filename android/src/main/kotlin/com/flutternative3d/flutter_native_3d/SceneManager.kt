package com.flutternative3d.flutter_native_3d

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Color
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import dev.romainguy.kotlin.math.Float3
import io.github.sceneview.SceneView
import io.github.sceneview.node.ModelNode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin

/**
 * Manages the SceneView scene, camera, lighting, animations, and model lifecycle.
 *
 * Pure Android/SceneView -- no Flutter imports. All communication with Flutter
 * happens through [Native3DPlatformView].
 */
class SceneManager(private val context: Context) {

    companion object {
        private const val TAG = "flutter_native_3d"
        private const val DEG_TO_RAD = Math.PI.toFloat() / 180f
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val container = FrameLayout(context)
    private val sceneView: SceneView
    private var currentModelNode: ModelNode? = null
    private var animationNames: List<String> = emptyList()
    private var modelCenter = Float3(0f, 0f, 0f)
    private var modelRadius = 1f
    private var autoRotateAnimator: ValueAnimator? = null
    private var currentTheta = 0f
    private var currentPhi = 20f
    private var currentCameraRadius = 3f
    private var disposed = false

    val view: View get() = container

    init {
        sceneView = SceneView(context).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }
        container.addView(sceneView)
    }

    // -------------------------------------------------------------------------
    // Model loading
    // -------------------------------------------------------------------------

    /**
     * Load a model from the given source descriptor.
     *
     * [source] keys: type (asset|file|network|memory), path, headers?, bytes?, formatHint?
     * [completion] is called on the main thread with the result.
     * The result map contains: { "animationNames": List<String> }
     */
    fun loadModel(
        source: Map<String, Any>,
        autoPlay: Boolean,
        onProgress: ((Float) -> Unit)? = null,
        completion: (Result<Map<String, Any>>) -> Unit
    ) {
        if (disposed) {
            completion(Result.failure(IllegalStateException("SceneManager is disposed")))
            return
        }

        val type = source["type"] as? String ?: run {
            completion(Result.failure(IllegalArgumentException("Missing 'type' in source")))
            return
        }

        clearModel()

        ModelLoader.resolve(context, type, source, scope, onProgress) { resolveResult ->
            resolveResult.fold(
                onSuccess = { location ->
                    scope.launch {
                        try {
                            val modelNode = ModelNode(
                                modelLoader = sceneView.modelLoader,
                                assetFileLocation = location
                            )
                            currentModelNode = modelNode
                            sceneView.addChildNode(modelNode)

                            collectAnimationNames(modelNode)
                            computeModelBounds(modelNode)
                            frameCameraToFitModel()

                            if (autoPlay && animationNames.isNotEmpty()) {
                                playAnimationByIndex(0, loop = true, onComplete = null)
                            }

                            completion(Result.success(
                                mapOf("animationNames" to animationNames)
                            ))
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to create ModelNode", e)
                            completion(Result.failure(e))
                        }
                    }
                },
                onFailure = { error ->
                    scope.launch(Dispatchers.Main) {
                        completion(Result.failure(error))
                    }
                }
            )
        }
    }

    // -------------------------------------------------------------------------
    // Camera
    // -------------------------------------------------------------------------

    fun resetCamera() {
        frameCameraToFitModel()
    }

    /**
     * Position the camera using spherical coordinates around the model center.
     * [theta]: horizontal angle in degrees (0 = front, 90 = right)
     * [phi]: vertical angle in degrees (0 = eye level, clamped to -89..89)
     * [radius]: distance from model center
     */
    fun setCameraOrbit(theta: Float, phi: Float, radius: Float) {
        currentTheta = theta
        currentPhi = phi.coerceIn(-89f, 89f)
        currentCameraRadius = radius.coerceAtLeast(0.1f)
        applyCameraOrbit()
    }

    // -------------------------------------------------------------------------
    // Animations
    // -------------------------------------------------------------------------

    fun getAnimationNames(): List<String> = animationNames

    /// Returns null on success, or an error message string on failure.
    fun playAnimation(name: String, loop: Boolean, onComplete: ((String) -> Unit)?): String? {
        val index = animationNames.indexOf(name)
        if (index < 0) {
            return "Animation '$name' not found. Available: $animationNames"
        }
        return playAnimationByIndex(index, loop, onComplete)
    }

    /// Returns null on success, or an error message string on failure.
    fun playAnimationByIndex(index: Int, loop: Boolean, onComplete: ((String) -> Unit)? = null): String? {
        val animator = currentModelNode?.animator
            ?: return "No model loaded or model has no animations"
        if (index < 0 || index >= animator.animationCount) {
            return "Animation index $index out of range (0..${animator.animationCount - 1})"
        }
        animator.playAnimation(index)
        // SceneView 2.x does not expose animation completion callbacks.
        // For non-looping animations, onComplete would need a frame-based
        // check against animator.getAnimationDuration(). Deferred to v0.2.
        return null
    }

    fun pauseAnimation() {
        val animator = currentModelNode?.animator ?: return
        for (i in 0 until animator.animationCount) {
            if (animator.getAnimationDuration(i) > 0) {
                animator.pauseAnimation(i)
            }
        }
    }

    fun stopAnimation() {
        val animator = currentModelNode?.animator ?: return
        for (i in 0 until animator.animationCount) {
            animator.pauseAnimation(i)
        }
        // Reset all animations to frame 0 by applying time 0
        for (i in 0 until animator.animationCount) {
            animator.applyAnimation(i, 0f)
        }
    }

    // -------------------------------------------------------------------------
    // Appearance
    // -------------------------------------------------------------------------

    fun setBackgroundColor(argb: Int) {
        val a = (argb shr 24) and 0xFF
        val r = (argb shr 16) and 0xFF
        val g = (argb shr 8) and 0xFF
        val b = argb and 0xFF
        container.setBackgroundColor(Color.argb(a, r, g, b))
    }

    /**
     * Apply a lighting preset. Each preset configures the main directional
     * light's intensity and color.
     *
     * Presets: studio, natural, dramatic, neutral, unlit
     */
    fun setLighting(preset: String) {
        val mainLight = sceneView.mainLightNode ?: return

        when (preset) {
            "studio" -> {
                mainLight.intensity = 100_000f
                mainLight.color = Color.WHITE
            }
            "natural" -> {
                mainLight.intensity = 80_000f
                mainLight.color = Color.rgb(255, 248, 240)
            }
            "dramatic" -> {
                mainLight.intensity = 150_000f
                mainLight.color = Color.rgb(255, 240, 220)
            }
            "neutral" -> {
                mainLight.intensity = 60_000f
                mainLight.color = Color.WHITE
            }
            "unlit" -> {
                mainLight.intensity = 0f
            }
            else -> Log.w(TAG, "Unknown lighting preset: $preset")
        }
    }

    /// Toggle camera orbit/pan/zoom gestures.
    /// Intercepts touch events at the container level rather than using
    /// View.isEnabled (which dims the view) or non-existent SceneView properties.
    private var cameraGesturesEnabled = true

    fun setGesturesEnabled(enabled: Boolean) {
        cameraGesturesEnabled = enabled
        if (!enabled) {
            // Block touches from reaching SceneView by adding an intercepting overlay
            container.setOnTouchListener { _, _ -> true }
        } else {
            container.setOnTouchListener(null)
        }
    }

    /**
     * Enable/disable continuous auto-rotation around the model's Y axis.
     * Rotates at 30 degrees/second.
     *
     * While auto-rotating, camera gestures are suspended to prevent the
     * animator and user touches from fighting over the camera.
     */
    private var gesturesEnabledBeforeAutoRotate = true

    fun setAutoRotate(enabled: Boolean) {
        autoRotateAnimator?.cancel()
        autoRotateAnimator = null

        if (!enabled) {
            setGesturesEnabled(gesturesEnabledBeforeAutoRotate)
            return
        }

        // Save and disable gestures during rotation
        gesturesEnabledBeforeAutoRotate = cameraGesturesEnabled
        setGesturesEnabled(false)

        autoRotateAnimator = ValueAnimator.ofFloat(0f, 360f).apply {
            duration = 12_000L // full rotation in 12 seconds (30 deg/s)
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.RESTART
            addUpdateListener { animator ->
                val fraction = animator.animatedValue as Float
                currentTheta = fraction
                applyCameraOrbit()
            }
            start()
        }
    }

    /**
     * Set how the model is scaled to fit the viewport.
     * Modes: "contain" (default), "cover", "none"
     */
    fun setFitMode(mode: String) {
        val node = currentModelNode ?: return

        when (mode) {
            "contain" -> frameCameraToFitModel()
            "cover" -> {
                // Move camera closer so model fills viewport
                val distance = modelRadius * 0.8f
                currentCameraRadius = distance.coerceAtLeast(0.1f)
                applyCameraOrbit()
            }
            "none" -> {
                // Reset model to original scale, camera at fixed distance
                node.scale = Float3(1f, 1f, 1f)
                currentCameraRadius = 3f
                applyCameraOrbit()
            }
            else -> Log.w(TAG, "Unknown fit mode: $mode")
        }
    }

    // -------------------------------------------------------------------------
    // Lifecycle
    // -------------------------------------------------------------------------

    fun dispose() {
        if (disposed) return
        disposed = true
        autoRotateAnimator?.cancel()
        autoRotateAnimator = null
        clearModel()
        scope.cancel()
        sceneView.destroy()
    }

    // -------------------------------------------------------------------------
    // Private: model management
    // -------------------------------------------------------------------------

    private fun clearModel() {
        currentModelNode?.let { node ->
            sceneView.removeChildNode(node)
            node.destroy()
        }
        currentModelNode = null
        animationNames = emptyList()
        modelCenter = Float3(0f, 0f, 0f)
        modelRadius = 1f
    }

    private fun collectAnimationNames(node: ModelNode) {
        animationNames = node.animator?.let { animator ->
            (0 until animator.animationCount).map { i ->
                animator.getAnimationName(i) ?: "animation_$i"
            }
        } ?: emptyList()
    }

    /**
     * Compute the axis-aligned bounding sphere of the model for camera framing.
     * Uses the model node's world position and a heuristic based on scale.
     */
    private fun computeModelBounds(node: ModelNode) {
        modelCenter = node.worldPosition

        // SceneView 2.x doesn't directly expose the AABB through a public API.
        // Use the model's scale as a heuristic for its extent. The model loader
        // typically normalizes models, so scale ~1 means ~1 meter extent.
        val scale = node.worldScale
        modelRadius = max(max(scale.x, scale.y), scale.z).coerceAtLeast(0.5f)
    }

    // -------------------------------------------------------------------------
    // Private: camera
    // -------------------------------------------------------------------------

    private fun frameCameraToFitModel() {
        val distance = modelRadius * 2.5f
        currentCameraRadius = distance.coerceAtLeast(0.5f)
        currentTheta = 0f
        currentPhi = 20f
        applyCameraOrbit()
    }

    /**
     * Apply the current spherical coordinates to position the camera.
     *
     * Converts (theta, phi, radius) from degrees to a Cartesian position
     * looking at [modelCenter].
     */
    private fun applyCameraOrbit() {
        val thetaRad = currentTheta * DEG_TO_RAD
        val phiRad = currentPhi * DEG_TO_RAD

        val x = currentCameraRadius * cos(phiRad) * sin(thetaRad)
        val y = currentCameraRadius * sin(phiRad)
        val z = currentCameraRadius * cos(phiRad) * cos(thetaRad)

        val cameraNode = sceneView.cameraNode
        cameraNode.position = Float3(
            modelCenter.x + x,
            modelCenter.y + y,
            modelCenter.z + z
        )
        cameraNode.lookAt(modelCenter)
    }

    // -------------------------------------------------------------------------
    // Private: animations (no private methods currently)
    // -------------------------------------------------------------------------
}
