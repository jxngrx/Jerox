import AppKit
import Carbon
import CoreGraphics
import Foundation
import ScreenCaptureKit
import SwiftUI

extension AppDelegate {
    func readScreen() {
        if grabWindow != nil {
            cancelRead()
            return
        }
        closeOcr()
        beginSelection()
    }

    func beginSelection() {
        guard screenCaptureAllowed(), let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let view = GrabView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.autoresizingMask = [.width, .height]
        view.onDone = { [weak self] rect in self?.recognize(screen: screen, rect: rect) }
        view.onCancel = { [weak self] in self?.cancelRead() }
        let window = GrabWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.hidesOnDeactivate = false // an NSPanel hides itself while its app is inactive, and this app stays inactive on purpose
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = view
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        grabWindow = window
        watchGrabEscape()
    }

    func screenCaptureAllowed() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        requestScreen()
        flashDictation("Allow Screen Recording for Jerox, then try again.")
        return false
    }

    func recognize(screen: NSScreen, rect: NSRect) {
        grabWindow?.orderOut(nil)
        grabWindow = nil
        endGrabEscape()
        Task {
            guard let image = await screenImage(screen, crop: rect) else {
                await MainActor.run { self.flashDictation("Could not capture the screen. Check Screen Recording in Settings → Permissions.") }
                return
            }
            let text = readText(image)
            await MainActor.run { self.showOcr(text, above: rect, on: screen) }
        }
    }

    func screenImage(_ screen: NSScreen, crop: NSRect?) async -> CGImage? {
        guard let number = (screen.deviceDescription as NSDictionary)["NSScreenNumber"] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        // Leave Jerox's own overlay out of the picture, and ask for real pixels: SCDisplay.width is in points,
        // so a point-sized capture cropped with Retina pixel coordinates lands on the wrong part of the screen.
        let ours = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ours, exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(Double(display.width) * Double(filter.pointPixelScale))
        config.height = Int(Double(display.height) * Double(filter.pointPixelScale))
        config.showsCursor = false
        guard let full = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        guard let crop else { return full }
        let sx = CGFloat(full.width) / screen.frame.width
        let sy = CGFloat(full.height) / screen.frame.height
        let pixel = CGRect(
            x: (crop.minX - screen.frame.minX) * sx,
            y: (screen.frame.height - (crop.minY - screen.frame.minY) - crop.height) * sy,
            width: crop.width * sx,
            height: crop.height * sy
        ).integral.intersection(CGRect(x: 0, y: 0, width: CGFloat(full.width), height: CGFloat(full.height)))
        guard pixel.width > 2, pixel.height > 2 else { return nil }
        return full.cropping(to: pixel)
    }

    func showOcr(_ text: String, above rect: NSRect, on screen: NSScreen) {
        ocrState.text = text
        let shown = text.isEmpty ? "No text found." : text
        let frame = ocrCaptionFrame(anchor: rect, screen: screen.visibleFrame, text: shown)
        let panel = ocrPanel ?? {
            let host = NSHostingView(rootView: OcrMark(state: ocrState, onCopy: { [weak self] in
                guard let self, !self.ocrState.text.isEmpty else {
                    self?.closeOcr()
                    return
                }
                self.publish(self.ocrState.text)
            }))
            host.sizingOptions = []
            let panel = OcrWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.hidesOnDeactivate = false
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = host
            ocrPanel = panel
            return panel
        }()
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        watchOcrDismiss()
    }

    func closeOcr() {
        endOcrWatch()
        ocrPanel?.orderOut(nil)
    }

    func watchOcrDismiss() {
        endOcrWatch()
        ocrKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.closeOcr()
                return nil
            }
            return event
        }
        ocrOutside = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            DispatchQueue.main.async { self?.closeOcr() }
        }
    }

    func endOcrWatch() {
        if let ocrKeys { NSEvent.removeMonitor(ocrKeys) }
        if let ocrOutside { NSEvent.removeMonitor(ocrOutside) }
        ocrKeys = nil
        ocrOutside = nil
    }

    func cancelRead() {
        grabWindow?.orderOut(nil)
        grabWindow = nil
        endGrabEscape()
        closeOcr()
    }

    func watchGrabEscape() {
        endGrabEscape()
        grabMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.cancelRead()
                return nil
            }
            return event
        }
    }

    func endGrabEscape() {
        if let grabMonitor { NSEvent.removeMonitor(grabMonitor) }
        grabMonitor = nil
    }
}
