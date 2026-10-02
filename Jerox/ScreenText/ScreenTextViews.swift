import AppKit
import Carbon
import CoreGraphics
import Foundation
import SwiftUI
import Vision

@Observable
final class OcrState {
    var text = ""
}

struct OcrMark: View {
    var state: OcrState
    var onCopy: () -> Void

    var body: some View {
        ScrollView {
            Text(state.text.isEmpty ? "No text found." : state.text)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .jeroxPanel(radius: 9)
        .onTapGesture(perform: onCopy)
            .help("Click to copy")
    }
}

final class OcrWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class GrabWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class GrabView: NSView {
    var start: NSPoint?
    var current: NSPoint?
    var onDone: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    private var selection: NSRect? {
        guard let start, let current else { return nil }
        return NSRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        guard let window, let local = selection, local.width > 8, local.height > 8 else {
            onCancel?()
            return
        }
        onDone?(window.convertToScreen(local))
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds)
        if let selection { path.appendRect(selection) }
        path.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.35).setFill()
        path.fill()
        if let selection {
            NSColor.white.setStroke()
            let stroke = NSBezierPath(rect: selection)
            stroke.lineWidth = 1
            stroke.stroke()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { onCancel?() }
        else { super.keyDown(with: event) }
    }
}

func readText(_ image: CGImage) -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    do {
        try VNImageRequestHandler(cgImage: image).perform([request])
    } catch {
        return ""
    }
    let lines = (request.results ?? []).compactMap { observation -> (text: String, y: CGFloat, x: CGFloat)? in
        guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
        return (text, observation.boundingBox.midY, observation.boundingBox.minX)
    }
    return ocrReadingOrder(lines)
}
