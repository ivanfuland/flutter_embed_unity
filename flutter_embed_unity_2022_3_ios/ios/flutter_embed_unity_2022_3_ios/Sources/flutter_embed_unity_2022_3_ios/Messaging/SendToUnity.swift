import Flutter

class SendToUnity {
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case FlutterEmbedConstants.methodNameSendToUnity:
            guard let message = parseSendToUnityArguments(call.arguments) else {
                result(invalidArgumentsError())
                return
            }
            guard UnityPlayerSingleton.isInitialised else {
                debugPrint("Dropped message to Unity: Unity is not loaded yet")
                result(FlutterError(
                    code: "UNITY_NOT_LOADED",
                    message: "Unity is not loaded yet.",
                    details: nil))
                return
            }

            UnityPlayerSingleton.getInstance().sendMessageToGO(
                withName: message.gameObjectName,
                functionName: message.methodName,
                message: message.data)
            result(nil)
        case FlutterEmbedConstants.methodNamePauseUnity:
            guard UnityPlayerSingleton.isInitialised else {
                debugPrint("Didn't pause Unity: Unity is not loaded yet")
                result(FlutterError(
                    code: "UNITY_NOT_LOADED",
                    message: "Unity is not loaded yet.",
                    details: nil))
                return
            }
            UnityPlayerSingleton.getInstance().pause(true)
            result(nil)
        case FlutterEmbedConstants.methodNameResumeUnity:
            guard UnityPlayerSingleton.isInitialised else {
                debugPrint("Didn't resume Unity: Unity is not loaded yet")
                result(FlutterError(
                    code: "UNITY_NOT_LOADED",
                    message: "Unity is not loaded yet.",
                    details: nil))
                return
            }
            UnityPlayerSingleton.getInstance().pause(false)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func parseSendToUnityArguments(_ arguments: Any?) -> SendToUnityMessage? {
        guard let values = arguments as? [Any], values.count == 3 else {
            return nil
        }
        guard
            let gameObjectName = values[0] as? String,
            let methodName = values[1] as? String,
            let data = values[2] as? String,
            !gameObjectName.isEmpty,
            !methodName.isEmpty
        else {
            return nil
        }
        return SendToUnityMessage(
            gameObjectName: gameObjectName,
            methodName: methodName,
            data: data)
    }

    private func invalidArgumentsError() -> FlutterError {
        return FlutterError(
            code: "INVALID_ARGUMENTS",
            message: "sendToUnity expects [gameObjectName, methodName, data] string arguments.",
            details: nil)
    }
}

private struct SendToUnityMessage {
    let gameObjectName: String
    let methodName: String
    let data: String
}
