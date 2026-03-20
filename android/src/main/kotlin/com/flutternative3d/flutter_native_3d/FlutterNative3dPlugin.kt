package com.flutternative3d.flutter_native_3d

import io.flutter.embedding.engine.plugins.FlutterPlugin

class FlutterNative3dPlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        binding.platformViewRegistry.registerViewFactory(
            "flutter_native_3d/native3d_view",
            Native3DPlatformViewFactory(binding.binaryMessenger)
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {}
}
