import AppKit
import AVFoundation
import Carbon
import Foundation
import os
import Speech
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static weak var shared: AppDelegate?

    enum Anchor {
        case cursor
        case statusItem
    }

    let model = AppModel()
    var statusItem: NSStatusItem!
    var panel: KeyPanel?
    var previousApp: NSRunningApplication?
    var hotKey: EventHotKeyRef?
    var rephraseHotKey: EventHotKeyRef?
    var dictateHotKey: EventHotKeyRef?
    var readHotKey: EventHotKeyRef?
    var cancelHotKey: EventHotKeyRef?
    var grabWindow: NSWindow?
    var grabMonitor: Any?
    var ocrPanel: NSWindow?
    var ocrKeys: Any?
    var ocrOutside: Any?
    let ocrState = OcrState()
    var dictatePanel: NSPanel?
    let dictateState = DictateState()
    var lastBarUpdate = Date.distantPast
    var audioEngine: AVAudioEngine?
    var speechRecognizer: SFSpeechRecognizer?
    var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    var recognitionTask: SFSpeechRecognitionTask?
    let audioLock = NSLock()
    var heldAudio: [AVAudioPCMBuffer] = []
    // Downloaded-model dictation: 16 kHz audio collected under audioLock, transcribed on stop.
    var resampler: Resampler16k?
    var whisperSamples: [Float] = []
    var dictateWhisper: SpeechModel?
    var whisperPreview: Timer?
    var whisperPreviewBusy = false
    var micTap = false
    var dictatePaste = 0
    var recognitionGeneration = 0
    var dictateText = ""
    var dictateCommitted = ""
    var dictateTentative = ""
    var dictateListening = false
    var dictateStarting = false
    var dictateStopRequested = false
    var dictateStarted = Date()
    var dictateClock: Timer?
    var dictatePanelOpen = false
    var recognitionRolled = Date.distantPast
    var hotKeyHandler: EventHandlerRef?
    var loaderPanel: NSPanel?
    var toastPanel: NSPanel?
    var toastHide: DispatchWorkItem?
    let loaderState = LoaderState()
    var promptPanel: KeyPanel?
    let promptState = PromptChoice()
    var promptCaptureInFlight = false
    var didCaptureSelection = false
    var clipboardBeforeRephrase: String?
    // ponytail: ignores the clipboard while a global rephrase copies the selection and pastes the result.
    var ignoreClipboard = false
    var pollTimer: Timer?
    var readWork: DispatchWorkItem?
    var lastChangeCount = 0
    // ponytail: 0.5s echo window so pasting does not reshuffle the row we just wrote.
    var ownWrite: (text: String, hash: String?, until: Date)?
    var keyMonitor: Any?
    var clickMonitor: Any?
    var didPromptAX = false
    var settingsWindow: NSWindow?
    var shotWatch: DispatchSourceFileSystemObject?
    var watchedShotDir: String?
    var knownShots: Set<String> = []

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

    func installEditMenu() {
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

    func setupStatusItem() {
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

    @objc func statusClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusMenu()
        } else {
            toggle(anchor: .statusItem)
        }
    }

    func showStatusMenu() {
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

    @objc func showSettings(_ sender: Any?) {
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

    func applyAppIcon() {
        let url = Bundle.main.url(forResource: "jerox-icon", withExtension: "icns")
            ?? Bundle.main.url(forResource: "jerox-icon", withExtension: "png")
        guard let url, let image = NSImage(contentsOf: url) else { return }
        NSApp.applicationIconImage = image
    }

    @objc func quit(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    func installHotkey() {
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

    func registerOne(
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
}
