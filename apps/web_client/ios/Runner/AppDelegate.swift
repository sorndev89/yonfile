import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, UIDocumentPickerDelegate {
  private var pendingSaveResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "la.yonfile/incoming_file",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "saveIncomingFile" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard let self,
              let args = call.arguments as? [String: Any],
              let path = args["path"] as? String,
              FileManager.default.fileExists(atPath: path),
              let presenter = self.window?.rootViewController else {
          result(FlutterError(code: "INVALID_FILE", message: "Temporary file is unavailable", details: nil))
          return
        }
        guard self.pendingSaveResult == nil else {
          result(FlutterError(code: "SAVE_BUSY", message: "A save dialog is already open", details: nil))
          return
        }
        self.pendingSaveResult = result
        let picker = UIDocumentPickerViewController(
          forExporting: [URL(fileURLWithPath: path)],
          asCopy: true
        )
        picker.delegate = self
        presenter.present(picker, animated: true)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    pendingSaveResult?(true)
    pendingSaveResult = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pendingSaveResult?(false)
    pendingSaveResult = nil
  }
}
