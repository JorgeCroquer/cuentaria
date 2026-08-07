import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let systemShareChannelName = "cuentaria/system_share"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: systemShareChannelName,
        binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "shareFile" else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.shareFile(call: call, from: controller, result: result)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Backs [SystemShare] (#192, ADR-0021 §5) via `UIActivityViewController`.
  /// `sourceRect`/`sourceView` are required on iPad, where the share sheet is
  /// a popover anchored to the tapped button — omitting them crashes only
  /// there, never on iPhone.
  private func shareFile(
    call: FlutterMethodCall, from controller: FlutterViewController,
    result: @escaping FlutterResult
  ) {
    guard let args = call.arguments as? [String: Any],
      let filename = args["filename"] as? String,
      let content = args["content"] as? String
    else {
      result(
        FlutterError(
          code: "invalid_args", message: "filename and content are required", details: nil))
      return
    }

    let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      "backup", isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: stagingDir, withIntermediateDirectories: true)
      let fileUrl = stagingDir.appendingPathComponent(filename)
      try content.write(to: fileUrl, atomically: true, encoding: .utf8)

      let activityController = UIActivityViewController(
        activityItems: [fileUrl], applicationActivities: nil)

      if let popover = activityController.popoverPresentationController {
        popover.sourceView = controller.view
        if let originX = args["originX"] as? Double,
          let originY = args["originY"] as? Double,
          let originWidth = args["originWidth"] as? Double,
          let originHeight = args["originHeight"] as? Double
        {
          popover.sourceRect = CGRect(
            x: originX, y: originY, width: originWidth, height: originHeight)
        } else {
          popover.sourceRect = CGRect(
            x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 0, height: 0)
        }
      }

      activityController.completionWithItemsHandler = { _, completed, _, _ in
        result(completed)
      }

      controller.present(activityController, animated: true)
    } catch {
      result(
        FlutterError(
          code: "share_failed", message: error.localizedDescription, details: nil))
    }
  }
}
