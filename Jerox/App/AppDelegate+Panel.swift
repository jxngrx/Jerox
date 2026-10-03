import AppKit
import ApplicationServices
import Carbon
import Foundation
import SwiftUI

extension AppDelegate {
    func toggle(anchor: Anchor) {
        if let panel, panel.isVisible {
            let target = previousApp
            closePanel()
            target?.activate()
            return
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        model.history.setQuery("")
        model.reveal += 1
        let panel = ensurePanel()
        let size = panel.frame.size.width >= PickerMetrics.minWidth ? panel.frame.size : PickerMetrics.saved
        let origin = origin(for: anchor, size: size)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        installPanelMonitors()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func ensurePanel() -> KeyPanel {
        if let panel { return panel }
        let panel = KeyPanel(
            contentRect: NSRect(origin: .zero, size: PickerMetrics.saved),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.minSize = NSSize(width: PickerMetrics.minWidth, height: PickerMetrics.minHeight)
        panel.isMovable = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true
        let host = NSHostingView(rootView: PickerView(model: model, onPaste: { [weak self] clip, plain in
            self?.paste(clip, plain: plain)
        }))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.delegate = self
        self.panel = panel
        return panel
    }

    func origin(for anchor: Anchor, size: NSSize) -> NSPoint {
        switch anchor {
        case .cursor:
            let mouse = NSEvent.mouseLocation
            let preferred = NSPoint(x: mouse.x, y: mouse.y - size.height)
            return clamp(preferred, around: mouse, size: size)
        case .statusItem:
            guard let button = statusItem.button, let window = button.window else {
                return clamp(.zero, around: NSEvent.mouseLocation, size: size)
            }
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            let anchorPoint = NSPoint(x: rect.midX, y: rect.midY)
            let preferred = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 6)
            return clamp(preferred, around: anchorPoint, size: size)
        }
    }

    func clamp(_ preferred: NSPoint, around anchor: NSPoint, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        let x = min(max(preferred.x, visible.minX + 4), visible.maxX - size.width - 4)
        let y = min(max(preferred.y, visible.minY + 4), visible.maxY - size.height - 4)
        return NSPoint(x: x, y: y)
    }

    func installPanelMonitors() {
        removePanelMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            if self.promptPanel?.isVisible == true {
                self.cancelPrompt()
            } else {
                self.closePanel()
            }
        }
    }

    func removePanelMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    func handleKey(_ event: NSEvent) -> Bool {
        if promptPanel?.isVisible == true { return handlePromptKey(event) }
        let commandW = event.keyCode == UInt16(kVK_ANSI_W) && event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
        if event.keyCode == UInt16(kVK_Escape) || commandW {
            let target = previousApp
            closePanel()
            target?.activate()
            return true
        }
        if matches(event, codeKey: "hotkey.pin.code", modsKey: "hotkey.pin.mods", code: ShortcutDefaults.pinCode, mods: ShortcutDefaults.pinMods) {
            model.togglePinSelected()
            return true
        }
        if matches(event, codeKey: "hotkey.plain.code", modsKey: "hotkey.plain.mods", code: ShortcutDefaults.plainCode, mods: ShortcutDefaults.plainMods) {
            if let clip = model.history.selectedClip { paste(clip, plain: true) }
            return true
        }
        if matches(event, codeKey: "hotkey.paste.code", modsKey: "hotkey.paste.mods", code: ShortcutDefaults.pasteCode, mods: ShortcutDefaults.pasteMods) {
            if let clip = model.history.selectedClip { paste(clip, plain: false) }
            return true
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags.contains(.command) || flags.contains(.option) || flags.contains(.control) { return false }
        switch event.keyCode {
        case UInt16(kVK_DownArrow):
            model.history.moveSelection(1)
            return true
        case UInt16(kVK_UpArrow):
            model.history.moveSelection(-1)
            return true
        default:
            break
        }
        if !flags.contains(.shift),
           let raw = event.charactersIgnoringModifiers,
           raw.count == 1,
           let number = Int(raw),
           (1...9).contains(number) {
            if let clip = model.history.clip(number: number) { paste(clip, plain: false) }
            return true
        }
        return false
    }

    func matches(_ event: NSEvent, codeKey: String, modsKey: String, code: Int, mods: Int) -> Bool {
        let (wantCode, wantMods) = storedHotkey(codeKey: codeKey, modsKey: modsKey, code: code, mods: mods)
        let got = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return event.keyCode == wantCode && got == wantMods
    }

    func closePanel() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        removePanelMonitors()
    }

    func paste(_ clip: Clip, plain: Bool) {
        writeClipboard(clip, plain: plain)
        let target = previousApp
        closePanel()
        guard AXIsProcessTrusted() else {
            promptAccessibility()
            return
        }
        guard let target else { return }
        target.activate()
        // ponytail: 150ms so the target app is frontmost before ⌘V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            postCommandV()
        }
    }

    func promptAccessibility() {
        guard !didPromptAX else { return }
        didPromptAX = true
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
