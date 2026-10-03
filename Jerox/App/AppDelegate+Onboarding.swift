import AppKit
import SwiftUI

extension AppDelegate {
    /// First run shows onboarding instead of the old welcome alert; its last page carries the welcome line.
    func showWelcomeIfNeeded() {
        #if DEBUG
        // Dev check: JEROX_SNAPSHOT_ONBOARDING=<dir> renders every page to PNG and quits.
        if let dir = ProcessInfo.processInfo.environment["JEROX_SNAPSHOT_ONBOARDING"] {
            MainActor.assumeIsolated {
                for page in 0..<OnboardingView.pageCount {
                    let renderer = ImageRenderer(content: OnboardingView(onDone: {}, start: page, still: true))
                    renderer.scale = 2
                    if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("onboarding-\(page + 1).png"))
                    }
                }
            }
            NSApp.terminate(nil)
            return
        }
        #endif
        if ProcessInfo.processInfo.environment["JEROX_SKIP_WELCOME"] == "1" { return }
        guard !UserDefaults.standard.bool(forKey: "didShowWelcome") else { return }
        UserDefaults.standard.set(true, forKey: "didShowWelcome")
        showOnboarding()
    }

    func showOnboarding() {
        let window = onboardingWindow ?? {
            let host = NSHostingView(rootView: OnboardingView(onDone: { [weak self] in self?.onboardingWindow?.close() }))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 640),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to Jerox"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            onboardingWindow = window
            return window
        }()
        bringToFront(window)
    }
}
