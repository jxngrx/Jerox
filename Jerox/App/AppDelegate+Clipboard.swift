import AppKit
import Foundation
import SwiftUI

extension AppDelegate {
    /// Bottom-center toast on the screen with the pointer, like the dictation bar.
    func showToast(_ message: String) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let host = NSHostingView(rootView: ToastView(message: message))
        let size = host.fittingSize
        let panel = toastPanel ?? {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .statusBar
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            toastPanel = panel
            return panel
        }()
        panel.contentView = host
        panel.setFrame(NSRect(x: area.midX - size.width / 2, y: area.minY + 28, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        toastHide?.cancel()
        let hide = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        toastHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: hide)
    }

    func flashDictation(_ message: String) {
        loaderState.label = message
        showLoader(at: NSEvent.mouseLocation)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { self.hideLoader() }
    }

    func publish(_ text: String) {
        let board = NSPasteboard.general
        board.clearContents()
        if !text.isEmpty { board.setString(text, forType: .string) }
        lastChangeCount = board.changeCount
        ownWrite = (text, nil, Date().addingTimeInterval(0.5))
        readWork?.cancel()
    }

    func startPolling() {
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func watchScreenshotDirectoryIfNeeded() {
        let dir = screenshotDirectory()
        if dir.path == watchedShotDir { return }
        shotWatch?.cancel()
        shotWatch = nil
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedShotDir = dir.path
        knownShots = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.ingestScreenshots() }
        }
        source.setCancelHandler { close(fd) }
        shotWatch = source
        source.resume()
    }

    func ingestScreenshots() {
        guard let watchedShotDir else { return }
        let dir = URL(fileURLWithPath: watchedShotDir, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names where !knownShots.contains(name) && isScreenshotFile(name) {
            let url = dir.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { continue }
            knownShots.insert(name)
            let ext = url.pathExtension.lowercased() == "tif" ? "tiff" : url.pathExtension.lowercased()
            model.add(Captured(
                clip: Clip("", kind: .image, blobExt: ext, hash: sha256Hex(data)),
                payload: data,
                thumb: thumbnailPNG(data)
            ))
        }
    }

    func pollPasteboard() {
        watchScreenshotDirectoryIfNeeded()
        if ignoreClipboard {
            lastChangeCount = NSPasteboard.general.changeCount
            return
        }
        let count = NSPasteboard.general.changeCount
        guard count != lastChangeCount else { return }
        if replacePrettyJSON() { return }
        lastChangeCount = count
        readWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.captureClipboard()
        }
        readWork = work
        // ponytail: 200ms debounce, apps burst several pasteboard writes per copy
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// Runs on the pasteboard poll, before the 200ms debounce, so a JSON copy is rewritten immediately.
    @discardableResult
    func replacePrettyJSON() -> Bool {
        let board = NSPasteboard.general
        if board.data(forType: .png) != nil || board.data(forType: .tiff) != nil { return false }
        if fileURLs(on: board)?.isEmpty == false { return false }
        guard let text = board.string(forType: .string), let pretty = prettyJSONDocument(text) else { return false }
        board.clearContents()
        board.setString(pretty, forType: .string)
        lastChangeCount = board.changeCount
        ownWrite = (pretty, nil, Date().addingTimeInterval(0.5))
        readWork?.cancel()
        model.add(Captured(clip: Clip(pretty, kind: classifyText(pretty))))
        return true
    }

    func captureClipboard() {
        if replacePrettyJSON() { return }
        let board = NSPasteboard.general
        lastChangeCount = board.changeCount
        guard let captured = readPasteboard(board) else { return }
        if let own = ownWrite, Date() < own.until {
            if let hash = captured.clip.hash, hash == own.hash { return }
            if !captured.clip.text.isEmpty, captured.clip.text == own.text { return }
        }
        ownWrite = nil
        model.add(captured)
    }

    func writeClipboard(_ clip: Clip, plain: Bool) {
        let text = transformPaste(clip.text, PasteOptions.current())
        let board = NSPasteboard.general
        board.clearContents()
        if plain || text != clip.text {
            if !text.isEmpty { board.setString(text, forType: .string) }
        } else {
            writeOriginal(clip, board: board)
        }
        lastChangeCount = board.changeCount
        ownWrite = (text, text == clip.text ? clip.hash : nil, Date().addingTimeInterval(0.5))
        readWork?.cancel()
    }
}
