import Cocoa
import FlutterMacOS

/// Handles `com.dupora/trash`, moving files to the Trash via
/// `FileManager.trashItem(at:resultingItemURL:)` - the standard,
/// undo-capable macOS delete API (never `FileManager.removeItem`, which is
/// permanent).
///
/// NOTE: written against the documented Foundation API but has not been
/// exercised on real macOS hardware as part of this build (no macOS host
/// was available). See BUILD.md / KNOWN LIMITATIONS.
class TrashChannel: NSObject {
  static let channelName = "com.dupora/trash"

  static func register(with registrar: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "trash":
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String
        else {
          result(FlutterError(code: "BAD_ARGS", message: "path is required", details: nil))
          return
        }
        do {
          let url = URL(fileURLWithPath: path)
          try FileManager.default.trashItem(at: url, resultingItemURL: nil)
          result(true)
        } catch {
          result(FlutterError(code: "TRASH_FAILED", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
