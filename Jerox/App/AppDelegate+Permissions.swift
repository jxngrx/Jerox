import ApplicationServices
import AVFoundation
import CoreGraphics
import Speech

extension AppDelegate {
    func accessibilityGranted() -> Bool { AXIsProcessTrusted() }
    func micGranted() -> Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    func speechGranted() -> Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }
    func screenGranted() -> Bool { CGPreflightScreenCaptureAccess() }

    func allPermissionsGranted() -> Bool {
        accessibilityGranted() && micGranted() && speechGranted() && screenGranted()
    }
}
