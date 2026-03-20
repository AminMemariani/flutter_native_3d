import Flutter
import UIKit

public class FlutterNative3dPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let factory = Native3DPlatformViewFactory(messenger: registrar.messenger())
        registrar.register(factory, withId: "flutter_native_3d/native3d_view")
    }
}
