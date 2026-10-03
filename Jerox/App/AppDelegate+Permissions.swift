import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Speech

extension AppDelegate {
    func accessibilityGranted() -> Bool { AXIsProcessTrusted() }
    func micGranted() -> Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    func speechGranted() -> Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }
    func screenGranted() -> Bool { CGPreflightScreenCaptureAccess() }

    func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Shows the system dialog when the answer is still open. Only a past "Don't Allow"
    /// sends the person to System Settings, because that is the one place left to change it.
    func requestAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        if didPromptAX { openPrivacyPane("Privacy_Accessibility") } else { promptAccessibility() }
    }

    func requestMic(_ done: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            done(true)
        case .notDetermined:
            NSApp.activate()
            AVCaptureDevice.requestAccess(for: .audio) { ok in DispatchQueue.main.async { done(ok) } }
        default:
            openPrivacyPane("Privacy_Microphone")
            done(false)
        }
    }

    func requestSpeech(_ done: @escaping (Bool) -> Void) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            done(true)
        case .notDetermined:
            NSApp.activate()
            SFSpeechRecognizer.requestAuthorization { status in DispatchQueue.main.async { done(status == .authorized) } }
        default:
            openPrivacyPane("Privacy_SpeechRecognition")
            done(false)
        }
    }

    /// macOS has no "denied" state for Screen Recording, so remember that we already asked once.
    func requestScreen() {
        guard !CGPreflightScreenCaptureAccess() else { return }
        if UserDefaults.standard.bool(forKey: "askedScreenCapture") {
            openPrivacyPane("Privacy_ScreenCapture")
        } else {
            UserDefaults.standard.set(true, forKey: "askedScreenCapture")
            NSApp.activate()
            CGRequestScreenCaptureAccess()
        }
    }
}
