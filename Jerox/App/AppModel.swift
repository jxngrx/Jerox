import AppKit
import CoreGraphics
import Foundation
import os
import SwiftUI

enum PickerMetrics {
    static let width: CGFloat = 360
    static let height: CGFloat = 380
    static let minWidth: CGFloat = 280
    static let minHeight: CGFloat = 260
    static var size: NSSize { NSSize(width: width, height: height) }
    static var saved: NSSize {
        let w = UserDefaults.standard.double(forKey: "picker.width")
        let h = UserDefaults.standard.double(forKey: "picker.height")
        guard w >= minWidth, h >= minHeight else { return size }
        return NSSize(width: w, height: h)
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@Observable
final class PromptChoice {
    var prompts: [RephrasePrompt] = []
    var selection = 0
    var target: UUID?
    var capturedText: String?
}

@Observable
final class DictateState {
    var bars: [Double] = Array(repeating: 0.15, count: 9)
    var text = ""
    var elapsed: TimeInterval = 0
    var closing = false
}

struct Captured {
    var clip: Clip
    var payload: Data?
    var thumb: Data?
}

@Observable
final class AppModel {
    var history = ClipboardHistory()
    var reveal = 0
    var aiBusy = false
    var aiTarget: UUID?
    var aiNote = ""

    func loadFromDisk() {
        let (loaded, removed) = ClipboardHistory.load(limit: Retention.limit(), maxAge: Retention.maxAge())
        history = loaded
        deleteBlobs(removed)
        if !removed.isEmpty { persist() }
    }

    func add(_ captured: Captured) {
        let (saved, removed) = history.add(captured.clip)
        if captured.payload != nil || captured.thumb != nil {
            storeBlob(id: saved.id, ext: saved.blobExt, payload: captured.payload, thumb: captured.thumb)
        }
        deleteBlobs(removed)
        persist()
    }

    func togglePin(id: UUID) {
        let removed = history.togglePin(id: id)
        deleteBlobs(removed)
        persist()
    }

    func togglePinSelected() {
        guard let id = history.selectedID else { return }
        togglePin(id: id)
    }

    func replaceClip(id: UUID, text: String) {
        guard history.replaceText(id: id, text: text) else { return }
        persist()
    }

    func rewrite(_ clip: Clip, instruction: String) {
        guard !aiBusy, !clip.text.isEmpty else { return }
        aiBusy = true
        aiTarget = clip.id
        aiNote = ""
        let id = clip.id
        let text = clip.text
        Task { @MainActor in
            defer {
                self.aiBusy = false
                self.aiTarget = nil
            }
            do {
                let result = try await requestAI(instruction: instruction, text: text)
                self.replaceClip(id: id, text: result)
                AppDelegate.shared?.publish(result)
            } catch {
                self.aiNote = error.localizedDescription
            }
        }
    }

    func rephraseLive(_ text: String, instruction: String, done: @escaping (String?) -> Void) {
        guard !aiBusy, !text.isEmpty else {
            done(nil)
            return
        }
        aiBusy = true
        aiNote = ""
        Task { @MainActor in
            defer { self.aiBusy = false }
            do {
                done(try await requestAI(instruction: instruction, text: text))
            } catch {
                self.aiNote = error.localizedDescription
                done(nil)
            }
        }
    }

    func applyRetention() {
        let removed = history.setRetention(limit: Retention.limit(), maxAge: Retention.maxAge())
        deleteBlobs(removed)
        if !removed.isEmpty { persist() }
    }

    private func persist() {
        do {
            try history.save()
        } catch {
            log.error("history save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
