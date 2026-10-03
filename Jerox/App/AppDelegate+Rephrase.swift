import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation
import SwiftUI

extension AppDelegate {
    func rephraseSelection() {
        if promptPanel?.isVisible == true {
            cancelPrompt()
            return
        }
        if promptCaptureInFlight { return }
        if panel?.isKeyWindow == true {
            guard let clip = model.history.selectedClip, !clip.text.isEmpty else { return }
            showPromptPanel(target: clip.id, captured: false, text: nil)
            return
        }
        guard !model.aiBusy else { return }
        guard AXIsProcessTrusted() else {
            promptAccessibility()
            return
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        promptCaptureInFlight = true
        ignoreClipboard = true
        clipboardBeforeRephrase = NSPasteboard.general.string(forType: .string)
        let before = NSPasteboard.general.changeCount
        postCommand(CGKeyCode(kVK_ANSI_C))
        readSelectionForPrompt(before: before, attempt: 0)
    }

    func readSelectionForPrompt(before: Int, attempt: Int) {
        let board = NSPasteboard.general
        if board.changeCount != before, let text = board.string(forType: .string), !text.isEmpty {
            lastChangeCount = board.changeCount
            promptCaptureInFlight = false
            showPromptPanel(target: nil, captured: true, text: text)
            return
        }
        if attempt >= 8 {
            promptCaptureInFlight = false
            ignoreClipboard = false
            clipboardBeforeRephrase = nil
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.readSelectionForPrompt(before: before, attempt: attempt + 1)
        }
    }

    func showPromptPanel(target: UUID?, captured: Bool, text: String?) {
        didCaptureSelection = captured
        promptState.target = target
        promptState.capturedText = text
        promptState.prompts = rephrasePromptList(custom: RephrasePromptStore.load())
        promptState.selection = 0
        let height = min(PickerMetrics.height, PromptPickerView.chrome + CGFloat(max(promptState.prompts.count, 1)) * PromptPickerView.rowPitch)
        let size = NSSize(width: PromptPickerView.width, height: height)
        let panel = ensurePromptPanel()
        panel.setFrame(NSRect(origin: origin(for: .cursor, size: size), size: size), display: true)
        panel.contentView?.setFrameSize(size)
        if keyMonitor == nil { installPanelMonitors() }
        panel.makeKeyAndOrderFront(nil)
        if captured { NSApp.activate() }
    }

    func ensurePromptPanel() -> KeyPanel {
        if let promptPanel { return promptPanel }
        let panel = KeyPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: PickerMetrics.width, height: 160)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.isExcludedFromWindowsMenu = true
        let host = NSHostingView(rootView: PromptPickerView(state: promptState, onPick: { [weak self] prompt in
            self?.pickPrompt(prompt)
        }))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        promptPanel = panel
        return panel
    }

    func handlePromptKey(_ event: NSEvent) -> Bool {
        let prompts = promptState.prompts
        if event.keyCode == UInt16(kVK_Escape) {
            cancelPrompt()
            return true
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags.contains(.command) || flags.contains(.option) || flags.contains(.control) { return false }
        switch event.keyCode {
        case UInt16(kVK_DownArrow):
            promptState.selection = min(promptState.selection + 1, max(prompts.count - 1, 0))
            return true
        case UInt16(kVK_UpArrow):
            promptState.selection = max(promptState.selection - 1, 0)
            return true
        case UInt16(kVK_Return):
            if prompts.indices.contains(promptState.selection) { pickPrompt(prompts[promptState.selection]) }
            return true
        default:
            break
        }
        if !flags.contains(.shift),
           let raw = event.charactersIgnoringModifiers,
           raw.count == 1,
           let number = Int(raw),
           let prompt = rephrasePrompt(number: number, in: prompts) {
            pickPrompt(prompt)
            return true
        }
        return false
    }

    func pickPrompt(_ prompt: RephrasePrompt) {
        let target = promptState.target
        let text = promptState.capturedText
        let saved = clipboardBeforeRephrase
        didCaptureSelection = false
        clipboardBeforeRephrase = nil
        closePromptPanel()
        if let target, let clip = model.history.items.first(where: { $0.id == target }), !clip.text.isEmpty {
            model.rewrite(clip, instruction: prompt.instruction)
            return
        }
        guard let text, !text.isEmpty else {
            ignoreClipboard = false
            return
        }
        showLoader(at: NSEvent.mouseLocation)
        model.rephraseLive(text, instruction: prompt.instruction) { [weak self] result in
            guard let self else { return }
            if let result {
                self.publish(result)
                self.model.add(Captured(clip: Clip(result, kind: classifyText(result))))
                self.previousApp?.activate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    postCommandV()
                    self.hideLoader()
                    self.ignoreClipboard = false
                }
            } else {
                self.restoreClipboard(saved)
                self.flashDictation(self.model.aiNote.isEmpty ? "Rephrase failed." : self.model.aiNote)
                self.ignoreClipboard = false
            }
        }
    }

    func cancelPrompt() {
        let captured = didCaptureSelection
        let saved = clipboardBeforeRephrase
        didCaptureSelection = false
        clipboardBeforeRephrase = nil
        closePromptPanel()
        guard captured else { return }
        restoreClipboard(saved)
        ignoreClipboard = false
        if panel?.isVisible != true { previousApp?.activate() }
    }

    func restoreClipboard(_ text: String?) {
        let board = NSPasteboard.general
        board.clearContents()
        if let text, !text.isEmpty { board.setString(text, forType: .string) }
        lastChangeCount = board.changeCount
    }

    func closePromptPanel() {
        guard let promptPanel, promptPanel.isVisible else { return }
        promptPanel.orderOut(nil)
        if panel?.isVisible != true { removePanelMonitors() }
    }

    func showLoader(at point: NSPoint) {
        loaderState.label = ""
        let panel = loaderPanel ?? {
            let host = NSHostingView(rootView: LoaderMark(state: loaderState))
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 36, height: 28),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .statusBar
            panel.isFloatingPanel = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.contentView = host
            loaderPanel = panel
            return panel
        }()
        let wide = !loaderState.label.isEmpty
        let width: CGFloat = wide ? min(240, max(120, CGFloat(loaderState.label.count) * 7)) : 36
        let height: CGFloat = wide ? 36 : 28
        panel.setFrame(NSRect(x: point.x + 12, y: point.y + 12, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    func hideLoader() {
        loaderPanel?.orderOut(nil)
        loaderState.label = ""
    }
}
