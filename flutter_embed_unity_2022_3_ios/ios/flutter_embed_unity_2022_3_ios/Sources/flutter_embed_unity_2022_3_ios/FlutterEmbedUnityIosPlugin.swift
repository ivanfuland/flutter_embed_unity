import Flutter
import UIKit

public class FlutterEmbedUnityIosPlugin: NSObject, FlutterPlugin {
    
    private let viewStack = UnityViewStack()
    private lazy var sendToUnity = SendToUnity(viewStack: viewStack)
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        // Register the method call handler
        let channel = FlutterMethodChannel(
            name: FlutterEmbedConstants.uniqueIdentifier,
            binaryMessenger: registrar.messenger())
        let instance = FlutterEmbedUnityIosPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        // Register channel with SendToFlutter so it can send messages back to Flutter
        SendToFlutter.methodChannel = channel
        
        // Register a view factory
        // On the Flutter side, when we create a PlatformView with our unique identifier:
        // UiKitView(
        //    viewType: Constants.uniqueViewIdentifier,
        // )
        // the UnityViewFactory will be invoked to create a UnityPlatformView:
        let platformViewFactory = UnityViewFactory(
            messenger: registrar.messenger(),
            viewStack: instance.viewStack)
        registrar.register(
            platformViewFactory,
            withId: FlutterEmbedConstants.uniqueIdentifier,
            gestureRecognizersBlockingPolicy: FlutterPlatformViewGestureRecognizersBlockingPolicyWaitUntilTouchesEnded)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        sendToUnity.handle(call, result: result)
    }
}
