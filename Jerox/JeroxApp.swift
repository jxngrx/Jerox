import AppKit
import ApplicationServices
import AVFoundation
import Carbon
import CoreAudio
import CryptoKit
import os
import FoundationModels
import Security
import ServiceManagement
import ScreenCaptureKit
import Speech
import SwiftUI
import Vision

private let log = Logger(subsystem: "com.jxngrx.jerox", category: "app")

enum ShortcutDefaults {
    static let showCode = Int(kVK_ANSI_V)
    static let showMods = Int(NSEvent.ModifierFlags([.command, .option, .control]).rawValue)
    static let pasteCode = Int(kVK_Return)
    static let pasteMods = 0
    static let plainCode = Int(kVK_Return)
    static let plainMods = Int(NSEvent.ModifierFlags.shift.rawValue)
    static let pinCode = Int(kVK_ANSI_P)
    static let pinMods = Int(NSEvent.ModifierFlags.command.rawValue)
    static let rephraseCode = Int(kVK_ANSI_R)
    static let rephraseMods = Int(NSEvent.ModifierFlags([.command, .shift]).rawValue)
    static let dictateCode = Int(kVK_ANSI_D)
    static let dictateMods = Int(NSEvent.ModifierFlags([.command, .option, .control]).rawValue)
    static let readCode = Int(kVK_ANSI_T)
    static let readMods = Int(NSEvent.ModifierFlags([.command, .option, .control]).rawValue)
}

struct AIError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

enum APIKey {
    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.jxngrx.jerox",
            kSecAttrAccount as String: account,
        ]
    }

    static func read(_ account: String) -> String {
        var lookup = query(account)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return "" }
        return key
    }

    static func write(_ account: String, _ value: String) {
        let query = query(account)
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }
}
private let appDelegate = AppDelegate()

@main
enum JeroxMain {
    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

private func jeroxHotKeyHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    _: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    if let event {
        GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
    }
    let id = hotKeyID.id
    DispatchQueue.main.async {
        if id == 2 {
            AppDelegate.shared?.rephraseSelection()
        } else if id == 3 {
            AppDelegate.shared?.toggleDictation()
        } else if id == 4 {
            AppDelegate.shared?.readScreen()
        } else if id == 5 {
            AppDelegate.shared?.cancelDictation()
        } else {
            AppDelegate.shared?.toggle(anchor: .cursor)
        }
    }
    return noErr
}

enum PickerMetrics {
    static let width: CGFloat = 360
    static let height: CGFloat = 380
    static var size: NSSize { NSSize(width: width, height: height) }
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?

    enum Anchor {
        case cursor
        case statusItem
    }

    let model = AppModel()
    private var statusItem: NSStatusItem!
    private var panel: KeyPanel?
    private var previousApp: NSRunningApplication?
    private var hotKey: EventHotKeyRef?
    private var rephraseHotKey: EventHotKeyRef?
    private var dictateHotKey: EventHotKeyRef?
    private var readHotKey: EventHotKeyRef?
    private var cancelHotKey: EventHotKeyRef?
    private var grabWindow: NSWindow?
    private var grabMonitor: Any?
    private var ocrPanel: NSWindow?
    private var ocrKeys: Any?
    private var ocrOutside: Any?
    private let ocrState = OcrState()
    private var dictatePanel: NSPanel?
    private let dictateState = DictateState()
    private var lastBarUpdate = Date.distantPast
    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioLock = NSLock()
    private var heldAudio: [AVAudioPCMBuffer] = []
    // Downloaded-model dictation: 16 kHz audio collected under audioLock, transcribed on stop.
    private var resampler: Resampler16k?
    private var whisperSamples: [Float] = []
    private var dictateWhisper: SpeechModel?
    private var whisperPreview: Timer?
    private var whisperPreviewBusy = false
    private var micTap = false
    private var dictatePaste = 0
    private var recognitionGeneration = 0
    private var dictateText = ""
    private var dictateCommitted = ""
    private var dictateTentative = ""
    private var dictateListening = false
    private var dictateStarting = false
    private var dictateStopRequested = false
    private var dictateStarted = Date()
    private var dictateClock: Timer?
    private var dictatePanelOpen = false
    private var recognitionRolled = Date.distantPast
    private var hotKeyHandler: EventHandlerRef?
    private var loaderPanel: NSPanel?
    private var toastPanel: NSPanel?
    private var toastHide: DispatchWorkItem?
    private let loaderState = LoaderState()
    private var promptPanel: KeyPanel?
    private let promptState = PromptChoice()
    private var promptCaptureInFlight = false
    private var didCaptureSelection = false
    private var clipboardBeforeRephrase: String?
    // ponytail: ignores the clipboard while a global rephrase copies the selection and pastes the result.
    private var ignoreClipboard = false
    private var pollTimer: Timer?
    private var readWork: DispatchWorkItem?
    private var lastChangeCount = 0
    // ponytail: 0.5s echo window so pasting does not reshuffle the row we just wrote.
    private var ownWrite: (text: String, hash: String?, until: Date)?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var didPromptAX = false
    private var settingsWindow: NSWindow?
    private var shotWatch: DispatchSourceFileSystemObject?
    private var watchedShotDir: String?
    private var knownShots: Set<String> = []

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        ClipboardHistory.selfCheck()
        ModelsSelfCheck.run()
        #endif
        model.loadFromDisk()
        applyTheme(UserDefaults.standard.string(forKey: "theme") ?? "system")
        applyAppIcon()
        installEditMenu()
        setupStatusItem()
        installHotkey()
        startPolling()
        watchScreenshotDirectoryIfNeeded()
        DispatchQueue.main.async { self.showWelcomeIfNeeded() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        WhisperEngine.shared.shutdown()
    }

    private func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let app = NSMenu(title: "Jerox")
        app.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Jerox", action: #selector(quit(_:)), keyEquivalent: "q").target = self
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let main = NSMenu()
        for menu in [app, edit, window] {
            let item = NSMenuItem()
            item.submenu = menu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        if let url = Bundle.main.url(forResource: "jerox-icon-menu", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            button.image = image
        }
        button.toolTip = "Jerox"
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusMenu()
        } else {
            toggle(anchor: .statusItem)
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let item = NSMenuItem(title: "Quit Jerox", action: #selector(quit(_:)), keyEquivalent: "q")
        item.target = self
        menu.addItem(item)
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    @objc private func showSettings(_ sender: Any?) {
        closePanel()
        let window = settingsWindow ?? {
            let host = NSHostingView(rootView: SettingsView(
                onRetention: { [weak self] in self?.model.applyRetention() },
                onHotkey: { [weak self] in self?.registerHotkey() }
            ))
            host.sizingOptions = []
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Jerox Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = .windowBackgroundColor
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
            return window
        }()
        window.setContentSize(NSSize(width: 760, height: 540))
        NSApp.setActivationPolicy(.regular)
        applyAppIcon()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { self.applyAppIcon() }
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    private func applyAppIcon() {
        let url = Bundle.main.url(forResource: "jerox-icon", withExtension: "icns")
            ?? Bundle.main.url(forResource: "jerox-icon", withExtension: "png")
        guard let url, let image = NSImage(contentsOf: url) else { return }
        NSApp.applicationIconImage = image
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    private func installHotkey() {
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            jeroxHotKeyHandler,
            1,
            &spec,
            nil,
            &hotKeyHandler
        )
        guard installed == noErr else {
            log.error("InstallEventHandler failed (\(installed))")
            return
        }
        registerHotkey()
    }

    func registerHotkey() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let rephraseHotKey {
            UnregisterEventHotKey(rephraseHotKey)
            self.rephraseHotKey = nil
        }
        if let dictateHotKey {
            UnregisterEventHotKey(dictateHotKey)
            self.dictateHotKey = nil
        }
        if let readHotKey {
            UnregisterEventHotKey(readHotKey)
            self.readHotKey = nil
        }
        registerOne(
            codeKey: "hotkey.show.code",
            modsKey: "hotkey.show.mods",
            code: ShortcutDefaults.showCode,
            mods: ShortcutDefaults.showMods,
            id: 1,
            hotKey: &hotKey
        )
        registerOne(
            codeKey: "hotkey.rephrase.code",
            modsKey: "hotkey.rephrase.mods",
            code: ShortcutDefaults.rephraseCode,
            mods: ShortcutDefaults.rephraseMods,
            id: 2,
            hotKey: &rephraseHotKey
        )
        registerOne(
            codeKey: "hotkey.dictate.code",
            modsKey: "hotkey.dictate.mods",
            code: ShortcutDefaults.dictateCode,
            mods: ShortcutDefaults.dictateMods,
            id: 3,
            hotKey: &dictateHotKey
        )
        registerOne(
            codeKey: "hotkey.read.code",
            modsKey: "hotkey.read.mods",
            code: ShortcutDefaults.readCode,
            mods: ShortcutDefaults.readMods,
            id: 4,
            hotKey: &readHotKey
        )
    }

    private func registerOne(
        codeKey: String,
        modsKey: String,
        code: Int,
        mods: Int,
        id: UInt32,
        hotKey: inout EventHotKeyRef?
    ) {
        let (keyCode, flags) = storedHotkey(codeKey: codeKey, modsKey: modsKey, code: code, mods: mods)
        let carbon = carbonModifierMask(
            command: flags.contains(.command),
            option: flags.contains(.option),
            control: flags.contains(.control),
            shift: flags.contains(.shift)
        )
        let hotKeyID = EventHotKeyID(signature: OSType(0x4A455258), id: id)
        let registered = RegisterEventHotKey(UInt32(keyCode), carbon, hotKeyID, GetApplicationEventTarget(), 0, &hotKey)
        if registered != noErr {
            log.error("RegisterEventHotKey failed (\(registered))")
        }
    }

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

    private func readSelectionForPrompt(before: Int, attempt: Int) {
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

    private func showPromptPanel(target: UUID?, captured: Bool, text: String?) {
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

    private func ensurePromptPanel() -> KeyPanel {
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

    private func handlePromptKey(_ event: NSEvent) -> Bool {
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

    private func pickPrompt(_ prompt: RephrasePrompt) {
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
                self.loaderState.label = self.model.aiNote.isEmpty ? "Rephrase failed" : self.model.aiNote
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { self.hideLoader() }
                self.ignoreClipboard = false
            }
        }
    }

    private func cancelPrompt() {
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

    private func restoreClipboard(_ text: String?) {
        let board = NSPasteboard.general
        board.clearContents()
        if let text, !text.isEmpty { board.setString(text, forType: .string) }
        lastChangeCount = board.changeCount
    }

    private func closePromptPanel() {
        guard let promptPanel, promptPanel.isVisible else { return }
        promptPanel.orderOut(nil)
        if panel?.isVisible != true { removePanelMonitors() }
    }

    private func showLoader(at point: NSPoint) {
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

    private func hideLoader() {
        loaderPanel?.orderOut(nil)
        loaderState.label = ""
    }

    func toggleDictation() {
        if dictateListening {
            stopDictation()
            return
        }
        if dictateStarting { return }
        dictateStarting = true
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        let askMic = {
            AVAudioApplication.requestRecordPermission { ok in
                DispatchQueue.main.async {
                    self.dictateStarting = false
                    guard ok else {
                        self.flashDictation("Allow the microphone for Jerox in System Settings.")
                        return
                    }
                    self.beginDictation()
                }
            }
        }
        if SpeechCatalog.active != nil {
            askMic()
            return
        }
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.dictateStarting = false
                    self.flashDictation("Allow speech recognition for Jerox in System Settings.")
                    return
                }
                askMic()
            }
        }
    }

    private func beginDictation() {
        let whisper = SpeechCatalog.active
        var recognizer: SFSpeechRecognizer?
        if whisper == nil {
            let localeID = UserDefaults.standard.string(forKey: "speechLocale") ?? ""
            recognizer = localeID.isEmpty ? SFSpeechRecognizer() : SFSpeechRecognizer(locale: Locale(identifier: localeID))
            guard let recognizer, recognizer.isAvailable else {
                flashDictation("Speech recognition is unavailable.")
                return
            }
            guard recognizer.supportsOnDeviceRecognition else {
                flashDictation("On-device speech is not available for this language.")
                return
            }
        }
        guard !micDevices().isEmpty else {
            showToast("Error: no microphone detected")
            return
        }
        let engine = AVAudioEngine()
        applyMic(uid: UserDefaults.standard.string(forKey: "micUID") ?? "", to: engine)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            showToast("Error: no microphone detected")
            return
        }
        let resampler = whisper == nil ? nil : Resampler16k(from: format)
        if whisper != nil, resampler == nil {
            showToast("Error: this microphone format is not supported")
            return
        }
        audioLock.lock()
        self.resampler = resampler
        whisperSamples.removeAll()
        audioLock.unlock()
        dictateWhisper = whisper
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.audioLock.lock()
            if let resampler = self.resampler { self.whisperSamples += resampler.convert(buffer) }
            let request = self.recognitionRequest
            let pending = request == nil ? [] : self.heldAudio
            if request != nil { self.heldAudio.removeAll() }
            else if self.resampler == nil, let copy = self.copyPCM(buffer) {
                self.heldAudio.append(copy)
                if self.heldAudio.count > 150 { self.heldAudio.removeFirst(self.heldAudio.count - 150) }
            }
            self.audioLock.unlock()
            if let request {
                for copy in pending { request.append(copy) }
                request.append(buffer)
            }
            let now = Date()
            guard now.timeIntervalSince(self.lastBarUpdate) > 0.05 else { return }
            self.lastBarUpdate = now
            guard let channel = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: frames))
            let bars = waveBars(samples, count: 9)
            DispatchQueue.main.async { self.dictateState.bars = bars }
        }
        micTap = true
        audioEngine = engine
        engine.prepare()
        do {
            try engine.start()
        } catch {
            endMic()
            flashDictation("Could not start the microphone.")
            return
        }
        audioLock.lock()
        heldAudio.removeAll()
        audioLock.unlock()
        speechRecognizer = recognizer
        dictateText = ""
        dictateCommitted = ""
        dictateTentative = ""
        recognitionRolled = .distantPast
        dictatePanelOpen = false
        dictateState.text = ""
        dictateState.elapsed = 0
        dictateState.closing = false
        dictateState.bars = Array(repeating: 0.15, count: 9)
        dictateListening = true
        dictateStopRequested = false
        dictateStarted = Date()
        dictateClock?.invalidate()
        dictateClock = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.dictateState.elapsed = Date().timeIntervalSince(self.dictateStarted)
        }
        armRecognition()
        if whisper != nil {
            whisperPreview?.invalidate()
            whisperPreview = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.previewWhisper()
            }
        }
        armCancelKey()
        showDictatePanel()
    }

    private func armRecognition() {
        guard dictateListening, let recognizer = speechRecognizer else { return }
        recognitionGeneration += 1
        let generation = recognitionGeneration
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        audioLock.lock()
        recognitionRequest = request
        audioLock.unlock()
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, generation == self.recognitionGeneration else { return }
                if let result {
                    let next = dictateUpdate(locked: self.dictateCommitted, tentative: self.dictateTentative, latest: result.bestTranscription.formattedString, final: result.isFinal)
                    self.dictateCommitted = next.locked
                    self.dictateTentative = next.tentative
                    self.dictateText = next.shown
                    self.dictateState.text = next.shown
                    if !next.shown.isEmpty { self.showDictatePanel() }
                }
                let ended = result?.isFinal == true || error != nil
                guard ended, !self.dictateStopRequested else {
                    if self.dictateStopRequested, ended { self.finishDictation() }
                    return
                }
                if result?.isFinal != true {
                    let next = dictateUpdate(locked: self.dictateCommitted, tentative: self.dictateTentative, latest: "", final: true)
                    self.dictateCommitted = next.locked
                    self.dictateTentative = next.tentative
                    self.dictateText = next.shown
                    self.dictateState.text = next.shown
                }
                self.rollRecognition()
            }
        }
    }

    // ponytail: re-transcribes everything heard so far, one pass at a time. Window the tail if long dictations lag.
    private func previewWhisper() {
        guard let model = dictateWhisper, !whisperPreviewBusy, dictateListening, !dictateStopRequested else { return }
        audioLock.lock()
        let samples = whisperSamples
        audioLock.unlock()
        guard samples.count >= 16_000 else { return }
        whisperPreviewBusy = true
        let paste = dictatePaste
        WhisperEngine.shared.transcribe(samples, model: model) { [weak self] text in
            guard let self else { return }
            self.whisperPreviewBusy = false
            guard paste == self.dictatePaste, self.dictateListening, !self.dictateStopRequested,
                  let text, !text.isEmpty else { return }
            self.dictateText = text
            self.dictateState.text = text
            self.showDictatePanel()
        }
    }

    // ponytail: the on-device recognizer ends a request on a pause. The paragraph stays; only the request is replaced. The session ends when the shortcut or X says so.
    private func rollRecognition() {
        guard dictateListening, !dictateStopRequested else { return }
        let wait: TimeInterval = Date().timeIntervalSince(recognitionRolled) < 0.3 ? 0.3 : 0
        recognitionRolled = Date()
        recognitionGeneration += 1
        recognitionTask?.cancel()
        recognitionTask = nil
        audioLock.lock()
        let request = recognitionRequest
        recognitionRequest = nil
        audioLock.unlock()
        request?.endAudio()
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, self.dictateListening, !self.dictateStopRequested else { return }
            self.armRecognition()
        }
    }

    private func stopDictation() {
        guard dictateListening else { return }
        dictateStopRequested = true
        dictateState.closing = true
        shrinkDictatePanel()
        if let model = dictateWhisper {
            whisperPreview?.invalidate()
            whisperPreview = nil
            endMic()
            audioLock.lock()
            let samples = whisperSamples
            whisperSamples = []
            resampler = nil
            audioLock.unlock()
            dictateWhisper = nil
            let paste = dictatePaste
            WhisperEngine.shared.transcribe(samples, model: model) { [weak self] text in
                guard let self, paste == self.dictatePaste, self.dictateStopRequested else { return }
                guard let text else {
                    self.cancelDictation()
                    self.showToast("Error: \(model.name) could not transcribe")
                    return
                }
                self.dictateText = text
                self.finishDictation()
            }
            return
        }
        audioLock.lock()
        let request = recognitionRequest
        recognitionRequest = nil
        heldAudio.removeAll()
        audioLock.unlock()
        request?.endAudio()
        endMic()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.dictateStopRequested else { return }
            self.finishDictation()
        }
    }

    private func finishDictation() {
        guard dictateListening || dictateStopRequested else { return }
        dictateListening = false
        dictateStopRequested = false
        recognitionGeneration += 1
        dictatePanelOpen = false
        dictateClock?.invalidate()
        dictateClock = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        let text = spokenList(stripDictationFillers(dictateText.trimmingCharacters(in: .whitespacesAndNewlines)))
        let saved = rememberDictation(text, notes: decodeDictateNotes(Data((UserDefaults.standard.string(forKey: "dictateNotes") ?? "").utf8)))
        UserDefaults.standard.set(String(data: encodeDictateNotes(saved), encoding: .utf8), forKey: "dictateNotes")
        dictateText = ""
        dictateCommitted = ""
        dictateTentative = ""
        guard !text.isEmpty else {
            disarmCancelKey()
            hideDictatePanel()
            return
        }
        ignoreClipboard = true
        let paste = dictatePaste
        if UserDefaults.standard.object(forKey: "dictateRephrase") == nil || UserDefaults.standard.bool(forKey: "dictateRephrase") {
            let id = UserDefaults.standard.string(forKey: "dictateRephrasePrompt") ?? "friendly"
            let prompts = rephrasePromptList(custom: RephrasePromptStore.load())
            let instruction = prompts.first { $0.id == id }?.instruction ?? builtInRephrasePrompts[0].instruction
            Task { @MainActor in
                let rewritten = spokenList((try? await requestAI(instruction: instruction, text: text)) ?? text)
                guard paste == self.dictatePaste else { return }
                self.disarmCancelKey()
                self.pasteDictated(rewritten.isEmpty ? text : rewritten)
            }
            return
        }
        disarmCancelKey()
        pasteDictated(text)
    }

    func cancelDictation() {
        let live = dictateListening || dictateStopRequested || dictatePanel?.isVisible == true
        guard live else { return }
        dictatePaste += 1
        dictateListening = false
        dictateStopRequested = false
        recognitionGeneration += 1
        disarmCancelKey()
        dictateClock?.invalidate()
        dictateClock = nil
        audioLock.lock()
        let request = recognitionRequest
        recognitionRequest = nil
        heldAudio.removeAll()
        whisperSamples = []
        resampler = nil
        audioLock.unlock()
        dictateWhisper = nil
        whisperPreview?.invalidate()
        whisperPreview = nil
        request?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        endMic()
        dictateText = ""
        dictateCommitted = ""
        dictateTentative = ""
        dictateState.text = ""
        ignoreClipboard = false
        hideLoader()
        hideDictatePanel()
    }

    private func endMic() {
        audioEngine?.stop()
        if micTap, let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
        }
        micTap = false
        audioEngine = nil
    }

    private func armCancelKey() {
        disarmCancelKey()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4A455258), id: 5)
        let status = RegisterEventHotKey(UInt32(kVK_Escape), 0, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr { cancelHotKey = ref }
    }

    private func disarmCancelKey() {
        if let cancelHotKey {
            UnregisterEventHotKey(cancelHotKey)
            self.cancelHotKey = nil
        }
    }

    private func copyPCM(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
    copy.frameLength = buffer.frameLength
    let frames = Int(buffer.frameLength)
    let channels = Int(buffer.format.channelCount)
    if let source = buffer.floatChannelData, let dest = copy.floatChannelData {
        for channel in 0..<channels { dest[channel].update(from: source[channel], count: frames) }
        return copy
    }
    if let source = buffer.int16ChannelData, let dest = copy.int16ChannelData {
        for channel in 0..<channels { dest[channel].update(from: source[channel], count: frames) }
        return copy
    }
    return nil
}

    private func pasteDictated(_ text: String) {
        publish(text)
        model.add(Captured(clip: Clip(text, kind: classifyText(text))))
        guard AXIsProcessTrusted(), let target = previousApp else {
            ignoreClipboard = false
            hideLoader()
            hideDictatePanel()
            if !AXIsProcessTrusted() { promptAccessibility() }
            return
        }
        target.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            postCommandV()
            self.hideLoader()
            self.hideDictatePanel()
            self.ignoreClipboard = false
        }
    }

    private func hideDictatePanel() {
        dictateState.closing = false
        dictatePanelOpen = false
        dictatePanel?.orderOut(nil)
    }

    private func shrinkDictatePanel() {
        guard let panel = dictatePanel else { return }
        let size = NSSize(width: 36, height: 28)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? panel.frame
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 10)
        panel.contentView?.wantsLayer = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(NSRect(origin: origin, size: size), display: true)
        }
    }

    private func showDictatePanel() {
        if dictateState.closing { return }
        if UserDefaults.standard.object(forKey: "showDictateOverlay") != nil,
           !UserDefaults.standard.bool(forKey: "showDictateOverlay") { return }
        let box = dictateBox(text: dictateState.text)
        let size = NSSize(width: box.width, height: box.height)
        let panel = dictatePanel ?? {
            let host = NSHostingView(rootView: DictateMark(state: dictateState, onStop: { [weak self] in
                self?.stopDictation()
            }))
            host.sizingOptions = []
            host.autoresizingMask = [.width, .height]
            host.clipsToBounds = true
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .statusBar
            panel.isFloatingPanel = true
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = host
            dictatePanel = panel
            return panel
        }()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: size.width, height: size.height)
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 10)
        let frame = NSRect(origin: origin, size: size)
        if panel.isVisible, abs(panel.frame.width - size.width) < 1, abs(panel.frame.height - size.height) < 1 { return }
        dictatePanelOpen = !dictateState.text.isEmpty
        if panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        panel.orderFrontRegardless()
    }

    func readScreen() {
        if grabWindow != nil {
            cancelRead()
            return
        }
        closeOcr()
        beginSelection()
    }

    private func beginSelection() {
        guard screenCaptureAllowed(), let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let view = GrabView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.autoresizingMask = [.width, .height]
        view.onDone = { [weak self] rect in self?.recognize(screen: screen, rect: rect) }
        view.onCancel = { [weak self] in self?.cancelRead() }
        let window = GrabWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = view
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        grabWindow = window
        watchGrabEscape()
    }

    private func screenCaptureAllowed() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess()
        flashDictation("Allow Screen Recording for Jerox in System Settings, then try again.")
        return false
    }

    private func recognize(screen: NSScreen, rect: NSRect) {
        grabWindow?.orderOut(nil)
        grabWindow = nil
        endGrabEscape()
        Task {
            guard let image = await screenImage(screen, crop: rect) else {
                await MainActor.run { self.flashDictation("Could not capture the screen.") }
                return
            }
            let text = readText(image)
            await MainActor.run { self.showOcr(text, above: rect, on: screen) }
        }
    }

    private func screenImage(_ screen: NSScreen, crop: NSRect?) async -> CGImage? {
        guard let number = (screen.deviceDescription as NSDictionary)["NSScreenNumber"] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID }) else { return nil }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = false
        guard let full = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) else { return nil }
        guard let crop else { return full }
        let scale = screen.backingScaleFactor
        let pixel = CGRect(
            x: (crop.minX - screen.frame.minX) * scale,
            y: (screen.frame.height - (crop.minY - screen.frame.minY) - crop.height) * scale,
            width: crop.width * scale,
            height: crop.height * scale
        ).integral.intersection(CGRect(x: 0, y: 0, width: CGFloat(full.width), height: CGFloat(full.height)))
        guard pixel.width > 2, pixel.height > 2 else { return nil }
        return full.cropping(to: pixel)
    }

    private func showOcr(_ text: String, above rect: NSRect, on screen: NSScreen) {
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
            let panel = OcrWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
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

    private func closeOcr() {
        endOcrWatch()
        ocrPanel?.orderOut(nil)
    }

    private func watchOcrDismiss() {
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

    private func endOcrWatch() {
        if let ocrKeys { NSEvent.removeMonitor(ocrKeys) }
        if let ocrOutside { NSEvent.removeMonitor(ocrOutside) }
        ocrKeys = nil
        ocrOutside = nil
    }

    private func cancelRead() {
        grabWindow?.orderOut(nil)
        grabWindow = nil
        endGrabEscape()
        closeOcr()
    }

    private func watchGrabEscape() {
        endGrabEscape()
        grabMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == UInt16(kVK_Escape) {
                self?.cancelRead()
                return nil
            }
            return event
        }
    }

    private func endGrabEscape() {
        if let grabMonitor { NSEvent.removeMonitor(grabMonitor) }
        grabMonitor = nil
    }

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

    private func flashDictation(_ message: String) {
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

    private func startPolling() {
        lastChangeCount = NSPasteboard.general.changeCount
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func watchScreenshotDirectoryIfNeeded() {
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

    private func ingestScreenshots() {
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

    private func pollPasteboard() {
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
    private func replacePrettyJSON() -> Bool {
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

    private func captureClipboard() {
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

    private func writeClipboard(_ clip: Clip, plain: Bool) {
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
        let size = PickerMetrics.size
        let origin = origin(for: anchor, size: size)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        installPanelMonitors()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func ensurePanel() -> KeyPanel {
        if let panel { return panel }
        let panel = KeyPanel(
            contentRect: NSRect(origin: .zero, size: PickerMetrics.size),
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
        let host = NSHostingView(rootView: PickerView(model: model, onPaste: { [weak self] clip, plain in
            self?.paste(clip, plain: plain)
        }))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private func origin(for anchor: Anchor, size: NSSize) -> NSPoint {
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

    private func clamp(_ preferred: NSPoint, around anchor: NSPoint, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        let x = min(max(preferred.x, visible.minX + 4), visible.maxX - size.width - 4)
        let y = min(max(preferred.y, visible.minY + 4), visible.maxY - size.height - 4)
        return NSPoint(x: x, y: y)
    }

    private func installPanelMonitors() {
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

    private func removePanelMonitors() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        keyMonitor = nil
        clickMonitor = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
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

    private func matches(_ event: NSEvent, codeKey: String, modsKey: String, code: Int, mods: Int) -> Bool {
        let (wantCode, wantMods) = storedHotkey(codeKey: codeKey, modsKey: modsKey, code: code, mods: mods)
        let got = event.modifierFlags.intersection([.command, .shift, .option, .control])
        return event.keyCode == wantCode && got == wantMods
    }

    private func closePanel() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        removePanelMonitors()
    }

    private func paste(_ clip: Clip, plain: Bool) {
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

    private func promptAccessibility() {
        guard !didPromptAX else { return }
        didPromptAX = true
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func showWelcomeIfNeeded() {
        if ProcessInfo.processInfo.environment["JEROX_SKIP_WELCOME"] == "1" { return }
        let key = "didShowWelcome"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let sentence = "🙏 Namaste, Welcome to Jerox Family \u{2014} this is developed by jxngrx.com 🎉💚"
        let alert = NSAlert()
        alert.messageText = sentence
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.layout()
        styleWelcome(sentence, window: alert.window)
        alert.runModal()
    }

    private func styleWelcome(_ sentence: String, window: NSWindow) {
        let attr = NSMutableAttributedString(string: sentence)
        let full = NSRange(location: 0, length: attr.length)
        attr.addAttribute(.font, value: NSFont.systemFont(ofSize: 13), range: full)
        attr.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        let ns = sentence as NSString
        let name = ns.range(of: "Jerox")
        if name.location != NSNotFound {
            attr.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 13), range: name)
        }
        let link = ns.range(of: "jxngrx.com")
        if link.location != NSNotFound, let url = URL(string: "http://jxngrx.com") {
            attr.addAttribute(.link, value: url, range: link)
            attr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: link)
            attr.addAttribute(.foregroundColor, value: NSColor.linkColor, range: link)
        }
        func walk(_ view: NSView) {
            if let field = view as? NSTextField, field.stringValue.contains("Namaste") {
                field.allowsEditingTextAttributes = true
                field.isSelectable = true
                field.attributedStringValue = attr
            }
            view.subviews.forEach(walk)
        }
        if let content = window.contentView { walk(content) }
    }
}

private func postCommandV() {
    postCommand(CGKeyCode(kVK_ANSI_V))
}

private func postCommand(_ key: CGKeyCode) {
    let source = CGEventSource(stateID: .hidSystemState)
    source?.localEventsSuppressionInterval = 0
    let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
    down?.flags = .maskCommand
    up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

@Observable
final class LoaderState {
    var label = ""
}

struct DictateMark: View {
    var state: DictateState
    var onStop: () -> Void

    private var clock: String {
        let seconds = Int(state.elapsed)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        let radius: CGFloat = state.closing ? 14 : (state.text.isEmpty ? 20 : 16)
        if state.closing {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(JeroxInk.graphite, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
        VStack(spacing: 0) {
            if !state.text.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(state.text)
                            .font(.system(size: 14))
                            .italic()
                            .foregroundStyle(Color.white.opacity(0.92))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("tail")
                    }
                    .scrollIndicators(.hidden)
                    .defaultScrollAnchor(.bottom)
                    .frame(height: dictateBox(text: state.text).textHeight)
                    .padding(.horizontal, 14)
                    .padding(.top, 4)
                    .mask(
                        LinearGradient(
                            stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22), .init(color: .black, location: 1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .onChange(of: state.text) { _, _ in
                        proxy.scrollTo("tail", anchor: .bottom)
                    }
                }
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(red: 0.98, green: 0.33, blue: 0.42))
                    .frame(width: 7, height: 7)
                    .padding(.leading, 4)
                Spacer(minLength: 0)
                if !state.text.isEmpty {
                    Text(clock)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .monospacedDigit()
                }
                Button(action: onStop) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .frame(width: 22, height: 22)
                        .background(Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .frame(height: 40)
            .overlay {
                HStack(alignment: .center, spacing: 3) {
                    ForEach(Array(state.bars.enumerated()), id: \.offset) { _, level in
                        Capsule()
                            .fill(JeroxInk.silver)
                            .frame(width: 4, height: max(3, 16 * level))
                    }
                }
                .frame(height: 18)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(JeroxInk.graphite, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
    }
}

struct LoaderMark: View {
    var state: LoaderState

    var body: some View {
        Group {
            if state.label.isEmpty {
                ProgressView().controlSize(.small)
            } else {
                Text(state.label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(3)
                    .padding(.horizontal, 10)
            }
        }
        .tint(JeroxInk.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .jeroxPanel(radius: 9)
    }
}

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

struct PromptPickerView: View {
    static let width: CGFloat = 300
    static let rowPitch: CGFloat = 32
    // header 36 + dividers 2 + list padding 12 + footer 32, less the last row gap.
    static let chrome: CGFloat = 80
    var state: PromptChoice
    var onPick: (RephrasePrompt) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundStyle(JeroxInk.accent)
                Text("Rephrase with").foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14)
            .frame(height: 36)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(state.prompts.enumerated()), id: \.element.id) { index, prompt in
                            Button {
                                onPick(prompt)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(index < 9 ? "\(index + 1)" : "")
                                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 12, alignment: .trailing)
                                    Text(prompt.name)
                                        .font(.system(size: 13))
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if index == state.selection {
                                        Image(systemName: "return")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(JeroxInk.accent)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .frame(height: Self.rowPitch - 2)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(
                                index == state.selection ? JeroxInk.accent.opacity(0.16) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .id(prompt.id)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: state.selection) { _, _ in
                    guard state.prompts.indices.contains(state.selection) else { return }
                    proxy.scrollTo(state.prompts[state.selection].id, anchor: .center)
                }
            }
            Divider()
            HStack(spacing: 14) {
                hint("↩", "apply")
                hint("Esc", "cancel")
                Spacer(minLength: 0)
                Text("1–9").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .jeroxPanel()
    }

    private func hint(_ key: String, _ name: String) -> some View {
        HStack(spacing: 4) {
            KeyCap(text: key)
            Text(name).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

extension View {
    /// Shared chrome for every floating Jerox panel.
    func jeroxPanel(radius: CGFloat = 12) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct PickerView: View {
    var model: AppModel
    var onPaste: (Clip, Bool) -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                JeroxLogo(size: 22)
                TextField("Search history", text: Binding(
                    get: { model.history.query },
                    set: { model.history.setQuery($0) }
                ))
                .textFieldStyle(.plain)
                .focused($searchFocused)
            }
            .padding(.leading, 5)
            .padding(.trailing, 10)
            .frame(height: 32)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 1))
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    rows
                }
                .onChange(of: model.history.selection) { _, _ in scroll(proxy) }
                .onChange(of: model.history.query) { _, _ in scroll(proxy) }
            }
            if let clip = model.history.selectedClip, !clip.text.isEmpty {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(rephrasePromptList(custom: RephrasePromptStore.load())) { prompt in
                            Button(prompt.name) { model.rewrite(clip, instruction: prompt.instruction) }
                        }
                    } label: {
                        Label("Rephrase", systemImage: "sparkles")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .tint(JeroxInk.accent)
                    .disabled(model.aiBusy)
                    .fixedSize()
                    Spacer(minLength: 0)
                    if !model.aiNote.isEmpty {
                        Text(model.aiNote)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            Divider()
                .padding(.horizontal, 10)
            CommandHints()
                .padding(.top, 7)
                .padding(.bottom, 11)
        }
        .frame(width: PickerMetrics.width, height: PickerMetrics.height)
        .jeroxPanel()
        .onAppear { searchFocused = true }
        .onChange(of: model.reveal) { _, _ in searchFocused = true }
    }

    private var rows: some View {
        let visible = model.history.visible
        return Group {
            if model.history.items.isEmpty {
                Text("Nothing copied yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else if visible.isEmpty {
                Text("No matches")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, clip in
                        if index == 0, clip.pinned {
                            sectionLabel("Pinned")
                        } else if index > 0, !clip.pinned, visible[index - 1].pinned {
                            sectionLabel("History")
                        }
                        row(index: index, clip: clip)
                    }
                }
                .padding(6)
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        let visible = model.history.visible
        guard visible.indices.contains(model.history.selection) else { return }
        proxy.scrollTo(visible[model.history.selection].id, anchor: .center)
    }

    private func row(index: Int, clip: Clip) -> some View {
        let selected = index == model.history.selection
        let busy = model.aiBusy && model.aiTarget == clip.id
        return HStack(spacing: 8) {
            Text(index < 9 ? "\(index + 1)" : "")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 12, alignment: .trailing)
            clipLeading(clip)
            Button {
                onPaste(clip, false)
            } label: {
                clipTitle(clip)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if busy {
                ProgressView().controlSize(.small)
            } else if selected {
                rowAction("doc.plaintext", help: "Paste as Plain Text") { onPaste(clip, true) }
                rowAction(clip.pinned ? "pin.fill" : "pin", help: clip.pinned ? "Unpin" : "Pin") { model.togglePin(id: clip.id) }
            } else if clip.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(width: 22)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 30)
        .background(
            selected ? JeroxInk.accent.opacity(0.16) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .id(clip.id)
    }

    private func rowAction(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(IconButtonStyle())
        .help(help)
    }

}

struct BlobThumb: View {
    var clip: Clip
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "photo")
            }
        }
        .frame(width: 20, height: 20)
        .task(id: clip.id) {
            let dir = ClipboardHistory.blobsURL
            let thumb = dir.appendingPathComponent("\(clip.id.uuidString).thumb.png")
            if let image = NSImage(contentsOf: thumb) {
                self.image = image
                return
            }
            if let ext = clip.blobExt {
                self.image = NSImage(contentsOf: dir.appendingPathComponent("\(clip.id.uuidString).\(ext)"))
            }
        }
    }
}

@ViewBuilder
func clipLeading(_ clip: Clip) -> some View {
    Group {
        switch clip.kind {
        case .image:
            BlobThumb(clip: clip).clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        case .color:
            if let rgba = parseColor(clip.text) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: NSColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Color.primary.opacity(0.15), lineWidth: 1))
                    .padding(3)
            }
        default:
            Image(systemName: kindSymbol(clip.kind))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
    .frame(width: 20, height: 20)
}

func kindSymbol(_ kind: ClipKind) -> String {
    switch kind {
    case .text: "text.alignleft"
    case .richText: "textformat"
    case .image: "photo"
    case .file: "doc"
    case .link: "link"
    case .color: "paintpalette"
    case .code: "chevron.left.forwardslash.chevron.right"
    }
}

@ViewBuilder
func clipTitle(_ clip: Clip) -> some View {
    if clip.kind == .code {
        Text(highlightedLine(clip.text)).lineLimit(1)
    } else {
        Text(displayTitle(clip)).lineLimit(1)
    }
}

func displayTitle(_ clip: Clip) -> String {
    switch clip.kind {
    case .image where clip.text.isEmpty:
        return "Image"
    case .file:
        let parts = clip.text.split(separator: "\n").map(String.init)
        let name = URL(fileURLWithPath: parts.first ?? clip.text).lastPathComponent
        let extra = parts.count - 1
        return extra > 0 ? "\(name) +\(extra)" : name
    default:
        return clip.text.replacingOccurrences(of: "\n", with: " ")
    }
}

func highlightedLine(_ text: String) -> AttributedString {
    let line = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? text
    var result = AttributedString()
    for token in codeTokens(line) {
        var piece = AttributedString(token.text)
        switch token.kind {
        case .keyword: piece.foregroundColor = .purple
        case .string: piece.foregroundColor = .red
        case .number: piece.foregroundColor = .blue
        case .comment: piece.foregroundColor = .secondary
        case .plain: break
        }
        result += piece
    }
    return result
}

func readPasteboard(_ board: NSPasteboard) -> Captured? {
    if let files = fileURLs(on: board), !files.isEmpty {
        if files.count == 1, let captured = capturedImageFile(files[0]) { return captured }
        let paths = files.map(\.path).joined(separator: "\n")
        let hash = files.map(fileIdentity).joined(separator: "|")
        return Captured(clip: Clip(paths, kind: .file, hash: hash), payload: nil, thumb: nil)
    }
    if let url = webURL(on: board) {
        return Captured(clip: Clip(url.absoluteString, kind: .link), payload: nil, thumb: nil)
    }
    if let color = (board.readObjects(forClasses: [NSColor.self], options: nil) as? [NSColor])?.first {
        return Captured(clip: Clip(hexString(color), kind: .color), payload: nil, thumb: nil)
    }
    if let text = board.string(forType: .string) {
        let kind = classifyText(text)
        if kind == .color || kind == .link {
            let stored = kind == .color ? canonicalColor(text) : text.trimmingCharacters(in: .whitespacesAndNewlines)
            return Captured(clip: Clip(stored, kind: kind), payload: nil, thumb: nil)
        }
    }
    // RTF wins over a TIFF preview. HTML does not, so a copied picture stays an image.
    if let rich = richData(on: board, html: false) {
        return capturedRich(rich, board: board)
    }
    if let image = imageData(on: board) {
        let plain = board.string(forType: .string) ?? ""
        return Captured(
            clip: Clip(plain, kind: .image, blobExt: image.ext, hash: sha256Hex(image.data)),
            payload: image.data,
            thumb: thumbnailPNG(image.data)
        )
    }
    if let rich = richData(on: board, html: true) {
        return capturedRich(rich, board: board)
    }
    guard let text = board.string(forType: .string), !text.isEmpty else { return nil }
    let kind = classifyText(text)
    let stored = kind == .color ? canonicalColor(text) : text
    return Captured(clip: Clip(stored, kind: kind), payload: nil, thumb: nil)
}

func writeOriginal(_ clip: Clip, board: NSPasteboard) {
    switch clip.kind {
    case .image:
        if let data = blobData(clip) {
            let type: NSPasteboard.PasteboardType
            switch clip.blobExt {
            case "tiff": type = .tiff
            case "jpg", "jpeg": type = NSPasteboard.PasteboardType("public.jpeg")
            default: type = .png
            }
            board.declareTypes([type], owner: nil)
            board.setData(data, forType: type)
            return
        }
    case .richText:
        if let data = blobData(clip) {
            let type: NSPasteboard.PasteboardType
            switch clip.blobExt {
            case "html": type = .html
            case "rtfd": type = .rtfd
            default: type = .rtf
            }
            var types: [NSPasteboard.PasteboardType] = [type]
            if !clip.text.isEmpty { types.append(.string) }
            board.declareTypes(types, owner: nil)
            board.setData(data, forType: type)
            if !clip.text.isEmpty { board.setString(clip.text, forType: .string) }
            return
        }
    case .file:
        let urls = clip.text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
        if !urls.isEmpty {
            board.writeObjects(urls as [NSURL])
            return
        }
    case .link:
        let item = NSPasteboardItem()
        item.setString(clip.text, forType: .string)
        if URL(string: clip.text) != nil {
            item.setString(clip.text, forType: .URL)
        }
        board.writeObjects([item])
        return
    case .color:
        if let rgba = parseColor(clip.text) {
            let color = NSColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
            let item = NSPasteboardItem()
            item.setString(clip.text, forType: .string)
            if let list = color.pasteboardPropertyList(forType: .color) {
                item.setPropertyList(list, forType: .color)
            }
            board.writeObjects([item])
            return
        }
    case .text, .code:
        break
    }
    if !clip.text.isEmpty { board.setString(clip.text, forType: .string) }
}

func webURL(on board: NSPasteboard) -> URL? {
    let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
    return urls?.first { url in
        guard !url.isFileURL, let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
    }
}

// ponytail: image files over 8MB stay as paths. The bytes are what still paste after the file moves.
func capturedImageFile(_ url: URL) -> Captured? {
    let ext = url.pathExtension.lowercased()
    guard ["png", "jpg", "jpeg", "gif", "tif", "tiff", "heic", "webp", "bmp"].contains(ext) else { return nil }
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    if size > 8 * 1024 * 1024 { return nil }
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
    let stored: (Data, String)
    switch ext {
    case "png": stored = (data, "png")
    case "tif", "tiff": stored = (data, "tiff")
    case "jpg", "jpeg": stored = (data, "jpg")
    default:
        guard let png = pngBytes(data) else { return nil }
        stored = (png, "png")
    }
    return Captured(
        clip: Clip(url.lastPathComponent, kind: .image, blobExt: stored.1, hash: sha256Hex(stored.0)),
        payload: stored.0,
        thumb: thumbnailPNG(stored.0)
    )
}

func fileURLs(on board: NSPasteboard) -> [URL]? {
    board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
}

func imageData(on board: NSPasteboard) -> (data: Data, ext: String)? {
    if let data = board.data(forType: .png), !data.isEmpty { return (data, "png") }
    if let data = board.data(forType: .tiff), !data.isEmpty { return (data, "tiff") }
    return nil
}

func richData(on board: NSPasteboard, html: Bool) -> (data: Data, ext: String)? {
    if !html {
        if let data = board.data(forType: .rtf), !data.isEmpty { return (data, "rtf") }
        if let data = board.data(forType: .rtfd), !data.isEmpty { return (data, "rtfd") }
        return nil
    }
    if let data = board.data(forType: .html), !data.isEmpty { return (data, "html") }
    return nil
}

func capturedRich(_ rich: (data: Data, ext: String), board: NSPasteboard) -> Captured? {
    let plain = board.string(forType: .string) ?? plainString(rich: rich.data, ext: rich.ext)
    guard !plain.isEmpty else { return nil }
    return Captured(clip: Clip(plain, kind: .richText, blobExt: rich.ext), payload: rich.data, thumb: nil)
}

func plainString(rich data: Data, ext: String) -> String {
    if ext == "html", let html = String(data: data, encoding: .utf8) {
        // ponytail: tag strip for the preview line. The blob is what pastes.
        return html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let text = NSAttributedString(rtf: data, documentAttributes: nil)?.string, !text.isEmpty {
        return text
    }
    return ""
}

func hexString(_ color: NSColor) -> String {
    let converted = color.usingColorSpace(.sRGB) ?? color
    func byte(_ value: CGFloat) -> Int { Int((value * 255).rounded()) }
    let hex = String(
        format: "#%02x%02x%02x%02x",
        byte(converted.redComponent),
        byte(converted.greenComponent),
        byte(converted.blueComponent),
        byte(converted.alphaComponent)
    )
    return canonicalColor(hex)
}

func pngBytes(_ data: Data) -> Data? {
    guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
    return thumbnailPNG(data, maxSide: min(2048, max(image.size.width, image.size.height)))
}

func thumbnailPNG(_ data: Data, maxSide limit: CGFloat = 64) -> Data? {
    guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
    let maxSide = limit
    let scale = min(1, maxSide / max(image.size.width, image.size.height))
    let newSize = NSSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(newSize.width),
        pixelsHigh: Int(newSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(origin: .zero, size: newSize))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// ponytail: files over 8MB match on size, mtime, and path so a copy doesn't read the whole disk
func fileIdentity(_ url: URL) -> String {
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
        return "dir:\(url.path)"
    }
    let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    let size = values?.fileSize ?? -1
    if size > 8 * 1024 * 1024 {
        let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "meta:\(size):\(mtime):\(url.path)"
    }
    return fileSHA256(url) ?? "path:\(url.path)"
}

func screenshotDirectory() -> URL {
    let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
    guard let raw = CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String,
          !raw.isEmpty else { return desktop }
    let path = (raw as NSString).expandingTildeInPath
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return desktop }
    return URL(fileURLWithPath: path, isDirectory: true)
}

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func storeBlob(id: UUID, ext: String?, payload: Data?, thumb: Data?) {
    let dir = ClipboardHistory.blobsURL
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        deleteBlobFiles(id: id)
        if let ext, let payload {
            try payload.write(to: dir.appendingPathComponent("\(id.uuidString).\(ext)"), options: .atomic)
        }
        if let thumb {
            try thumb.write(to: dir.appendingPathComponent("\(id.uuidString).thumb.png"), options: .atomic)
        }
    } catch {
        log.error("blob write failed: \(error.localizedDescription, privacy: .public)")
    }
}

func deleteBlobs(_ clips: [Clip]) {
    for clip in clips { deleteBlobFiles(id: clip.id) }
}

func deleteBlobFiles(id: UUID) {
    let dir = ClipboardHistory.blobsURL
    guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
    let prefix = id.uuidString
    for file in files where file.lastPathComponent.hasPrefix(prefix) {
        try? FileManager.default.removeItem(at: file)
    }
}

func storedHotkey(codeKey: String, modsKey: String, code: Int, mods: Int) -> (UInt16, NSEvent.ModifierFlags) {
    let storedCode = (UserDefaults.standard.object(forKey: codeKey) as? Int) ?? code
    let storedMods = (UserDefaults.standard.object(forKey: modsKey) as? Int) ?? mods
    let flags = NSEvent.ModifierFlags(rawValue: UInt(storedMods)).intersection([.command, .shift, .option, .control])
    return (UInt16(storedCode), flags)
}

func appleIntelligenceReady() -> Bool {
    guard #available(macOS 26, *) else { return false }
    return SystemLanguageModel.default.isAvailable
}

func appleRewrite(instruction: String, text: String) async throws -> String {
    guard #available(macOS 26, *) else { throw AIError(message: "Apple Intelligence needs macOS 26.") }
    guard SystemLanguageModel.default.isAvailable else {
        throw AIError(message: "Turn on Apple Intelligence in System Settings.")
    }
    let session = LanguageModelSession(instructions: instruction)
    let cleaned = try await session.respond(to: text).content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { throw AIError(message: "Apple Intelligence returned nothing.") }
    return cleaned
}

func requestAI(instruction: String, text: String) async throws -> String {
    let service = UserDefaults.standard.string(forKey: "aiProvider") ?? AIService.openrouter.rawValue
    if service == AIService.apple.rawValue {
        guard text.count <= 20_000 else { throw AIError(message: "Text is too long.") }
        return try await appleRewrite(instruction: instruction, text: text)
    }
    let title = AIService(rawValue: service)?.title ?? "AI"
    let key = APIKey.read(service)
    guard !key.isEmpty else { throw AIError(message: "Add a \(title) key in Settings.") }
    guard text.count <= 20_000 else { throw AIError(message: "Text is too long.") }
    guard let call = aiCall(service: service, model: savedAIModel(service: service), key: key, instruction: instruction, text: text),
          let url = URL(string: call.url) else {
        throw AIError(message: "Could not build the request.")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 45
    for (field, value) in call.headers { request.setValue(value, forHTTPHeaderField: field) }
    request.httpBody = call.body
    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else { throw AIError(message: aiErrorMessage(data: data, status: status, service: service)) }
    guard let reply = aiReply(service: service, data: data) else {
        throw AIError(message: "\(title) returned nothing.")
    }
    return reply
}

func blobData(_ clip: Clip) -> Data? {
    guard let ext = clip.blobExt else { return nil }
    return try? Data(contentsOf: ClipboardHistory.blobsURL.appendingPathComponent("\(clip.id.uuidString).\(ext)"))
}

struct KeyCap: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, 4)
            .frame(minWidth: 16)
            .padding(.vertical, 2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(.separator, lineWidth: 0.5)
            )
    }
}

func shortcutParts(code: Int, mods: Int) -> [String] {
    let flags = NSEvent.ModifierFlags(rawValue: UInt(mods))
    var parts: [String] = []
    if flags.contains(.control) { parts.append("⌃") }
    if flags.contains(.option) { parts.append("⌥") }
    if flags.contains(.shift) { parts.append("⇧") }
    if flags.contains(.command) { parts.append("⌘") }
    parts.append(keyGlyph(UInt16(code)))
    return parts
}

// ponytail: ANSI key labels. Use UCKeyTranslate if a non-US layout shows the wrong glyph.
func keyGlyph(_ keyCode: UInt16) -> String {
    switch Int(keyCode) {
    case kVK_Return, kVK_ANSI_KeypadEnter: return "↩"
    case kVK_Space: return "Space"
    case kVK_Tab: return "⇥"
    case kVK_Delete: return "⌫"
    case kVK_Escape: return "Esc"
    case kVK_LeftArrow: return "←"
    case kVK_RightArrow: return "→"
    case kVK_UpArrow: return "↑"
    case kVK_DownArrow: return "↓"
    default: break
    }
    let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
    ]
    return names[keyCode] ?? "Key \(keyCode)"
}

struct CommandHints: View {
    @AppStorage("hotkey.paste.code") private var pasteCode = ShortcutDefaults.pasteCode
    @AppStorage("hotkey.paste.mods") private var pasteMods = ShortcutDefaults.pasteMods
    @AppStorage("hotkey.plain.code") private var plainCode = ShortcutDefaults.plainCode
    @AppStorage("hotkey.plain.mods") private var plainMods = ShortcutDefaults.plainMods
    @AppStorage("hotkey.pin.code") private var pinCode = ShortcutDefaults.pinCode
    @AppStorage("hotkey.pin.mods") private var pinMods = ShortcutDefaults.pinMods

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            hint(pasteCode, pasteMods, "paste")
            hint(plainCode, plainMods, "plain")
            hint(pinCode, pinMods, "pin")
            Text("1–9")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
    }

    private func hint(_ code: Int, _ mods: Int, _ name: String) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(Array(shortcutParts(code: code, mods: mods).enumerated()), id: \.offset) { _, part in
                    KeyCap(text: part)
                }
            }
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct ShortcutRecorder: View {
    var title: String
    var requiresModifier = false
    @Binding var code: Int
    @Binding var mods: Int
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                recording ? stop() : start()
            } label: {
                Group {
                    if recording {
                        Text("Press keys…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(JeroxInk.accent)
                    } else {
                        HStack(spacing: 3) {
                            ForEach(Array(shortcutParts(code: code, mods: mods).enumerated()), id: \.offset) { _, part in
                                KeyCap(text: part)
                            }
                        }
                    }
                }
                .frame(width: 112, height: 26)
                .background(
                    recording ? JeroxInk.accent.opacity(0.12) : Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(recording ? JeroxInk.accent : Color.primary.opacity(0.12), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(recording ? "Esc cancels" : "Click to change")
        }
        .onDisappear { stop() }
    }

    private func start() {
        stop()
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let key = event.keyCode
            if key == UInt16(kVK_Escape) {
                DispatchQueue.main.async { self.stop() }
                return nil
            }
            if [54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(key) { return nil }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if requiresModifier && flags.isEmpty { return nil }
            DispatchQueue.main.async {
                self.code = Int(key)
                self.mods = Int(flags.rawValue)
                self.stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

func applyTheme(_ name: String) {
    switch name {
    case "light": NSApp.appearance = NSAppearance(named: .aqua)
    case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
    default: NSApp.appearance = nil
    }
}

struct MicDevice {
    var id: AudioDeviceID
    var uid: String
    var name: String
}

func micDevices() -> [MicDevice] {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = Array(repeating: AudioDeviceID(0), count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.compactMap { id in
        var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var streamSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
        let uid = audioString(id, kAudioDevicePropertyDeviceUID)
        guard !uid.isEmpty else { return nil }
        let name = audioString(id, kAudioObjectPropertyName)
        return MicDevice(id: id, uid: uid, name: name.isEmpty ? uid : name)
    }
}

func applyMic(uid: String, to engine: AVAudioEngine) {
    guard let device = micDevices().first(where: { $0.uid == uid }), let audioUnit = engine.inputNode.audioUnit else { return }
    var id = device.id
    AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size))
}

func audioString(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return "" }
    return value as String
}

struct SettingsView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case general, history, models, advanced
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: "General"
            case .history: "History"
            case .models: "Models"
            case .advanced: "Advanced"
            }
        }
        var symbol: String {
            switch self {
            case .general: "waveform"
            case .history: "clock"
            case .models: "cpu"
            case .advanced: "gearshape"
            }
        }
    }

    var onRetention: () -> Void
    var onHotkey: () -> Void
    @State private var page: Page? = .general
    @AppStorage("micUID") private var micUID = ""
    @AppStorage("speechLocale") private var speechLocale = ""
    @AppStorage("showDictateOverlay") private var showOverlay = true
    @AppStorage("theme") private var theme = "system"
    @AppStorage("loginItem") private var loginItem = false
    @AppStorage("dictateNotes") private var notesJSON = "[]"
    @State private var mics: [(uid: String, name: String)] = []
    @AppStorage("prettyJSON") private var prettyJSON = false
    @AppStorage("historyLimit") private var limit = 200
    @AppStorage("historyDays") private var days = 14
    @AppStorage("hotkey.show.code") private var showCode = ShortcutDefaults.showCode
    @AppStorage("hotkey.show.mods") private var showMods = ShortcutDefaults.showMods
    @AppStorage("hotkey.paste.code") private var pasteCode = ShortcutDefaults.pasteCode
    @AppStorage("hotkey.paste.mods") private var pasteMods = ShortcutDefaults.pasteMods
    @AppStorage("hotkey.plain.code") private var plainCode = ShortcutDefaults.plainCode
    @AppStorage("hotkey.plain.mods") private var plainMods = ShortcutDefaults.plainMods
    @AppStorage("hotkey.pin.code") private var pinCode = ShortcutDefaults.pinCode
    @AppStorage("hotkey.pin.mods") private var pinMods = ShortcutDefaults.pinMods
    @AppStorage("hotkey.rephrase.code") private var rephraseCode = ShortcutDefaults.rephraseCode
    @AppStorage("hotkey.rephrase.mods") private var rephraseMods = ShortcutDefaults.rephraseMods
    @AppStorage("hotkey.dictate.code") private var dictateCode = ShortcutDefaults.dictateCode
    @AppStorage("hotkey.dictate.mods") private var dictateMods = ShortcutDefaults.dictateMods
    @AppStorage("hotkey.read.code") private var readCode = ShortcutDefaults.readCode
    @AppStorage("hotkey.read.mods") private var readMods = ShortcutDefaults.readMods
    @AppStorage("speechEngine") private var speechEngine = SpeechCatalog.apple
    private let modelStore = ModelStore.shared
    @AppStorage("aiProvider") private var providerRaw = AIService.openrouter.rawValue
    @AppStorage("dictateRephrase") private var dictateRephrase = true
    @AppStorage("dictateRephrasePrompt") private var dictateRephrasePrompt = "friendly"
    @State private var customPrompts = RephrasePromptStore.load()
    @State private var promptName = ""
    @State private var promptInstruction = ""
    @State private var editingPrompt: String?
    @State private var apiKey = ""
    @State private var modelName = ""
    @State private var keyReady = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                mascot
                    .padding(.bottom, 8)
                ForEach(Page.allCases) { item in
                    Button {
                        page = item
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 7)
                            .foregroundStyle(page == item ? JeroxInk.accent : .primary.opacity(0.85))
                            .background(page == item ? JeroxInk.accent.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 28)
            .padding(.bottom, 12)
            .frame(width: 168)
            .background(JeroxInk.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(page?.title ?? "")
                        .font(.system(size: 22, weight: .bold))
                        .padding(.horizontal, 4)
                    pageBody
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 24)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 760, height: 540)
        .background(JeroxInk.canvas)
        .tint(JeroxInk.accent)
        .onAppear {
            loadProvider()
            applyTheme(theme)
            mics = micDevices().map { ($0.uid, $0.name) }
        }
        .onChange(of: theme) { _, value in applyTheme(value) }
        .onChange(of: loginItem) { _, value in setOpenAtLogin(value) }
        .onChange(of: apiKey) { _, value in
            if keyReady { APIKey.write(providerRaw, value) }
        }
        .onChange(of: modelName) { _, value in
            UserDefaults.standard.set(value, forKey: "aiModel.\(providerRaw)")
        }
        .onChange(of: limit) { _, _ in onRetention() }
        .onChange(of: days) { _, _ in onRetention() }
        .onChange(of: hotkeyToken) { _, _ in onHotkey() }
    }

    private var hotkeyToken: String {
        [showCode, showMods, rephraseCode, rephraseMods, dictateCode, dictateMods, readCode, readMods]
            .map(String.init).joined(separator: ",")
    }

    private var mascot: some View {
        HStack(spacing: 8) {
            JeroxLogo(size: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text("Jerox").font(.system(size: 15, weight: .semibold))
                Text("Settings").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
    }

    private var dictateNotes: [DictateNote] {
        decodeDictateNotes(Data(notesJSON.utf8))
    }

    private var speechLocales: [Locale] {
        SFSpeechRecognizer.supportedLocales().sorted { $0.identifier < $1.identifier }
    }

    @ViewBuilder private var pageBody: some View {
        switch page {
        case .history:
            group("Transcriptions", hint: "The last 50 dictations. Copy puts one back on the clipboard.") {
                if dictateNotes.isEmpty {
                    line { Text("No transcriptions yet.").foregroundStyle(.secondary) }
                }
                ForEach(dictateNotes) { note in
                    line {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(note.text).lineLimit(2)
                                Text(note.at.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            iconButton("doc.on.doc", help: "Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(note.text, forType: .string)
                            }
                            iconButton("trash", help: "Delete", role: .destructive) {
                                let left = dictateNotes.filter { $0.id != note.id }
                                notesJSON = String(data: encodeDictateNotes(left), encoding: .utf8) ?? "[]"
                            }
                        }
                    }
                }
            }
        case .models:
            group("Speech to text", hint: "Apple Speech shows live text as you talk. A downloaded model runs fully offline and types when you stop.") {
                choice("Apple Speech", detail: "Built in · live text", selected: speechEngine == SpeechCatalog.apple || SpeechCatalog.active == nil) {
                    speechEngine = SpeechCatalog.apple
                }
                ForEach(SpeechCatalog.models) { model in speechModelRow(model) }
            }
            group("Rephrase", hint: "Apple Intelligence runs on this Mac with no key. Online services use your key, kept in the Keychain.") {
                row("Rephrase after dictate") { switchToggle($dictateRephrase) }
                if appleIntelligenceReady() {
                    choice("Apple Intelligence", detail: "On this Mac · no key", selected: providerRaw == AIService.apple.rawValue) {
                        selectProvider(.apple)
                    }
                }
                ForEach(AIService.allCases.filter { $0 != .apple }, id: \.self) { service in
                    choice(service.title, detail: "Online · API key", selected: providerRaw == service.rawValue) {
                        selectProvider(service)
                    }
                }
                if providerRaw == AIService.apple.rawValue {
                    line { Text("Rephrase runs on this Mac. No key.").foregroundStyle(.secondary) }
                } else {
                    line { field("API key", text: $apiKey, secure: true) }
                    line { field("Model", text: $modelName, secure: false) }
                }
            }
            group("After dictation", hint: "Friendly chat is the default.") {
                if dictateRephrase {
                    ForEach(rephrasePromptList(custom: customPrompts)) { prompt in
                        line {
                            Button { dictateRephrasePrompt = prompt.id } label: {
                                HStack {
                                    Text(prompt.name)
                                    Spacer()
                                    if dictateRephrasePrompt == prompt.id {
                                        Image(systemName: "checkmark").foregroundStyle(JeroxInk.accent)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    line { Text("Online rephrase is off.").foregroundStyle(.secondary) }
                }
            }
            group("Your prompts", hint: "Built-ins are 1–3. Yours start at 4.") {
                ForEach(customPrompts) { prompt in
                    line {
                        HStack {
                            Text(prompt.name).lineLimit(1)
                            Spacer()
                            iconButton("pencil", help: "Edit") {
                                editingPrompt = prompt.id
                                promptName = prompt.name
                                promptInstruction = prompt.instruction
                            }
                            iconButton("trash", help: "Delete", role: .destructive) {
                                customPrompts.removeAll { $0.id == prompt.id }
                                if editingPrompt == prompt.id {
                                    editingPrompt = nil
                                    promptName = ""
                                    promptInstruction = ""
                                }
                                RephrasePromptStore.save(customPrompts)
                            }
                        }
                    }
                }
                line { field("Name", text: $promptName, secure: false) }
                line {
                    ZStack(alignment: .topLeading) {
                        if promptInstruction.isEmpty {
                            Text("How to rewrite")
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $promptInstruction)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                    }
                    .frame(height: 72)
                }
                line {
                    Button(editingPrompt == nil ? "Add prompt" : "Save prompt", action: savePrompt)
                        .buttonStyle(.plain)
                        .foregroundStyle(JeroxInk.accent)
                }
            }
        case .advanced:
            group("App") {
                row("Open at login") { switchToggle($loginItem) }
                row("Show the dictation bar") { switchToggle($showOverlay) }
                row("Theme") {
                    Picker("", selection: $theme) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            group("Clipboard", hint: "Pins stay until you unpin them.") {
                row("JSON pretty-print") { switchToggle($prettyJSON) }
                row("Items to keep") { stepper($limit, in: 1...5000) }
                row("Days to keep") { stepper($days, in: 1...3650) }
            }
            group("Shortcuts", hint: "Edit, then press the keys. Esc cancels.") {
                line { ShortcutRecorder(title: "Show Jerox", requiresModifier: true, code: $showCode, mods: $showMods) }
                line { ShortcutRecorder(title: "Paste", code: $pasteCode, mods: $pasteMods) }
                line { ShortcutRecorder(title: "Paste plain", code: $plainCode, mods: $plainMods) }
                line { ShortcutRecorder(title: "Pin", code: $pinCode, mods: $pinMods) }
                line { ShortcutRecorder(title: "Rephrase", requiresModifier: true, code: $rephraseCode, mods: $rephraseMods) }
            }
        default:
            group("Dictation") {
                line { ShortcutRecorder(title: "Shortcut", requiresModifier: true, code: $dictateCode, mods: $dictateMods) }
                line { ShortcutRecorder(title: "Read screen", requiresModifier: true, code: $readCode, mods: $readMods) }
                row("Microphone") {
                    Picker("", selection: $micUID) {
                        Text("System default").tag("")
                        ForEach(mics, id: \.uid) { mic in
                            Text(mic.name).tag(mic.uid)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                row("Language") {
                    Picker("", selection: $speechLocale) {
                        Text("System").tag("")
                        ForEach(speechLocales, id: \.identifier) { locale in
                            Text(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier).tag(locale.identifier)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
    }

    private func group<Content: View>(_ title: String, hint: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.horizontal, 4)
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }
            Color.clear.frame(height: 4)
            VStack(spacing: 0) { content() }
                .padding(.bottom, -1)
                .padding(.top, 2)
                .background(JeroxInk.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    /// Label leading, control trailing: every settings row shares this grid.
    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        line {
            HStack(spacing: 12) {
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
                control()
            }
        }
    }

    private func iconButton(_ symbol: String, help: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(IconButtonStyle(destructive: role == .destructive))
        .help(help)
    }

    /// A selectable row: title and detail leading, radio trailing.
    private func choice(_ title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        line {
            Button(action: action) {
                HStack(spacing: 12) {
                    titled(title, detail: Text(detail).foregroundStyle(.secondary))
                    radio(selected)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func titled(_ title: String, badge: Bool = false, detail: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                if badge {
                    Text("Recommended")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(JeroxInk.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(JeroxInk.accent.opacity(0.14), in: Capsule())
                }
            }
            detail.font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func radio(_ on: Bool) -> some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 15))
            .foregroundStyle(on ? AnyShapeStyle(JeroxInk.accent) : AnyShapeStyle(.tertiary))
            .frame(width: 26)
    }

    private func speechModelRow(_ model: SpeechModel) -> some View {
        let phase = modelStore.phase(model)
        let size = ByteCountFormatter.string(fromByteCount: model.bytes, countStyle: .file)
        var caption = Text("\(model.detail) · \(size)").foregroundStyle(.secondary)
        if case .failed(let message) = phase { caption = Text(message).foregroundStyle(JeroxInk.danger) }
        return line {
            HStack(spacing: 12) {
                titled(model.name, badge: model.recommended, detail: caption)
                    .contentShape(Rectangle())
                    .onTapGesture { if phase == .ready { speechEngine = model.id } }
                switch phase {
                case .idle, .failed:
                    Button { modelStore.download(model) } label: {
                        Label(phase == .idle ? "Download" : "Retry", systemImage: "arrow.down.circle")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(JeroxInk.accent)
                case .downloading(let done):
                    ProgressView(value: done).frame(width: 80)
                    Text("\(Int(done * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 32, alignment: .trailing)
                    iconButton("xmark", help: "Cancel") { modelStore.cancel(model) }
                case .verifying:
                    ProgressView().controlSize(.small)
                    Text("Verifying").font(.caption).foregroundStyle(.secondary)
                case .ready:
                    iconButton("trash", help: "Delete", role: .destructive) { modelStore.delete(model) }
                    Button { speechEngine = model.id } label: { radio(speechEngine == model.id) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func switchToggle(_ isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.mini)
    }

    private func stepper(_ value: Binding<Int>, in range: ClosedRange<Int>) -> some View {
        HStack(spacing: 8) {
            Text("\(value.wrappedValue)").monospacedDigit().foregroundStyle(.secondary)
            Stepper("", value: value, in: range).labelsHidden()
        }
    }

    private func line<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.horizontal, 14)
            }
    }

    private func field(_ title: String, text: Binding<String>, secure: Bool) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 64, alignment: .leading)
                .foregroundStyle(.secondary)
            Group {
                if secure {
                    SecureField("", text: text, prompt: Text(title).foregroundStyle(.tertiary))
                } else {
                    TextField("", text: text, prompt: Text(title).foregroundStyle(.tertiary))
                }
            }
            .textFieldStyle(.plain)
            .foregroundStyle(.primary)
            .tint(JeroxInk.accent)
        }
    }

    private func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            loginItem = false
        }
    }

    private func loadProvider() {
        if providerRaw == AIService.apple.rawValue, !appleIntelligenceReady() {
            providerRaw = AIService.openrouter.rawValue
        }
        keyReady = false
        apiKey = APIKey.read(providerRaw)
        modelName = savedAIModel(service: providerRaw)
        keyReady = true
    }

    private func selectProvider(_ service: AIService) {
        keyReady = false
        providerRaw = service.rawValue
        apiKey = APIKey.read(service.rawValue)
        modelName = savedAIModel(service: service.rawValue)
        keyReady = true
    }

    private func savePrompt() {
        let name = promptName.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = promptInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !instruction.isEmpty else { return }
        if let editingPrompt, let index = customPrompts.firstIndex(where: { $0.id == editingPrompt }) {
            customPrompts[index].name = name
            customPrompts[index].instruction = instruction
        } else {
            customPrompts.append(RephrasePrompt(id: UUID().uuidString, name: name, instruction: instruction))
        }
        RephrasePromptStore.save(customPrompts)
        promptName = ""
        promptInstruction = ""
        editingPrompt = nil
    }
}

private enum JeroxInk {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let field = Color(nsColor: .textBackgroundColor)
    // systemBlue adapts its shade for light and dark, so contrast holds in both.
    static let accent = Color(nsColor: .systemBlue)
    static let graphite = Color(red: 0.13, green: 0.14, blue: 0.17)
    static let silver = LinearGradient(
        colors: [Color(red: 0.93, green: 0.94, blue: 0.96), Color(red: 0.62, green: 0.65, blue: 0.71)],
        startPoint: .top, endPoint: .bottom
    )
    static let danger = Color.red
    static let ink = Color.primary
}

/// The Jerox mark, from the bundled app icon.
struct JeroxLogo: View {
    var size: CGFloat

    var body: some View {
        if let image = NSImage(named: "jerox-icon") {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
        }
    }
}


struct IconButtonStyle: ButtonStyle {
    var destructive = false
    @State private var hover = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hover ? (destructive ? JeroxInk.danger : JeroxInk.accent) : Color.secondary)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.12 : hover ? 0.06 : 0),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .onHover { hover = $0 }
    }
}

struct ToastView: View {
    var message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(JeroxInk.danger)
            Text(message).font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .jeroxPanel(radius: 20)
        .fixedSize()
    }
}
