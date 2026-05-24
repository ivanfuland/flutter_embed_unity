import Foundation

class LifecycleEventEmitter {
    static func runtimeLoaded() {
        emit(method: "runtimeLoaded")
    }

    static func firstFrameSeen(viewId: Int64) {
        emit(method: "firstFrameSeen", payload: ["viewId": viewId])
    }

    static func foregroundActive(_ active: Bool, viewId: Int64? = nil) {
        var payload: [String: Any] = ["active": active]
        if let viewId = viewId {
            payload["viewId"] = viewId
        }
        emit(method: "foregroundActive", payload: payload)
    }

    private static func emit(method: String, payload: [String: Any]? = nil) {
        var envelope: [String: Any] = [
            "v": 1,
            "type": "evt",
            "msgId": "ios-\(UUID().uuidString)",
            "method": method,
            "ts": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if let payload = payload {
            envelope["payload"] = payload
        }

        guard JSONSerialization.isValidJSONObject(envelope),
              let data = try? JSONSerialization.data(withJSONObject: envelope),
              let json = String(data: data, encoding: .utf8) else {
            debugPrint("Couldn't emit lifecycle event \(method): invalid envelope")
            return
        }

        SendToFlutter.sendToFlutter(json)
    }
}
