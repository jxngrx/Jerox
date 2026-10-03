import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import ServiceManagement
import Speech
import SwiftUI

struct SettingsView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case general, history, models, permissions, advanced
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: "General"
            case .history: "History"
            case .models: "Models"
            case .permissions: "Permissions"
            case .advanced: "Advanced"
            }
        }
        var symbol: String {
            switch self {
            case .general: "waveform"
            case .history: "clock"
            case .models: "cpu"
            case .permissions: "lock.shield"
            case .advanced: "gearshape"
            }
        }
    }

    var onRetention: () -> Void
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "Version \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
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
    @AppStorage("localModel") private var localModel = ""
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
    @State private var permissionsTick = 0
    @State private var testing = false
    @State private var testOK = false
    @State private var testNote = ""
    private let updater = JeroxUpdater.shared

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
                if let version = updater.availableVersion {
                    Button("Update to \(version)") { updater.checkForUpdates(nil) }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(JeroxInk.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
                Text(appVersion)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .textSelection(.enabled)
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
        .frame(minWidth: 640, minHeight: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .onChange(of: page) { _, _ in permissionsTick += 1 }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionsTick += 1
        }
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

    /// Hindi's locale handles Hinglish (code-mixed Hindi/English) speech well, so label it
    /// that way and, for a user in India, put it (then English-India) ahead of the rest.
    private var speechLocales: [Locale] {
        let all = SFSpeechRecognizer.supportedLocales().sorted { $0.identifier < $1.identifier }
        guard Locale.current.region?.identifier == "IN" else { return all }
        let priority = ["hi_IN", "en_IN"]
        let first = priority.compactMap { id in all.first { $0.identifier == id } }
        let rest = all.filter { !priority.contains($0.identifier) }
        return first + rest
    }

    private func speechLocaleLabel(_ locale: Locale) -> String {
        if locale.identifier == "hi_IN" { return "Hinglish (Hindi + English)" }
        return locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
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
            group("Rephrase", hint: "Pick an offline model below, or bring your own key. OpenRouter defaults to a free model.") {
                row("Rephrase after dictate") { switchToggle($dictateRephrase) }
                ForEach(AIService.allCases.filter { $0 != .local }, id: \.self) { service in
                    choice(service.title, detail: service == .openrouter ? "Online · free model by default" : "Online · API key", selected: providerRaw == service.rawValue) {
                        selectProvider(service)
                    }
                }
                if providerRaw != AIService.local.rawValue {
                    line { field("API key", text: $apiKey, secure: true) }
                    line { field("Model", text: $modelName, secure: false) }
                }
                line {
                    HStack(spacing: 10) {
                        Button("Test rephrase", action: testRephrase)
                            .controlSize(.small)
                            .disabled(testing)
                        if testing { ProgressView().controlSize(.small) }
                        Text(testNote)
                            .font(.caption)
                            .foregroundStyle(testOK ? JeroxInk.accent : JeroxInk.danger)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            group("Offline rephrase", hint: "Qwen runs on this Mac. After the download there is no key and no network. Tap the circle to use one.") {
                ForEach(SpeechCatalog.rephraseModels) { model in speechModelRow(model) }
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
        case .permissions:
            let _ = permissionsTick
            group("macOS permissions", hint: "Jerox checks these live. Flip one on in System Settings, then come back here.") {
                permissionRow(
                    "Accessibility", detail: "Pasting back into the previous app",
                    granted: AppDelegate.shared?.accessibilityGranted() ?? false
                ) { AppDelegate.shared?.requestAccessibility() }
                permissionRow(
                    "Microphone", detail: "Dictation",
                    granted: AppDelegate.shared?.micGranted() ?? false
                ) { AppDelegate.shared?.requestMic { _ in permissionsTick += 1 } }
                permissionRow(
                    "Speech Recognition", detail: "Dictation",
                    granted: AppDelegate.shared?.speechGranted() ?? false
                ) { AppDelegate.shared?.requestSpeech { _ in permissionsTick += 1 } }
                permissionRow(
                    "Screen Recording", detail: "Reading text off the screen",
                    granted: AppDelegate.shared?.screenGranted() ?? false
                ) { AppDelegate.shared?.requestScreen() }
            }
            group("Still showing Allow?", hint: "If Jerox is already switched on in System Settings, macOS may be holding a grant from an older build. Reset clears it so the dialogs can ask again. Screen Recording also needs a restart after you switch it on.") {
                row("Reset Jerox permissions") {
                    Button("Reset") {
                        AppDelegate.shared?.resetPermissions { ok in
                            permissionsTick += 1
                            AppDelegate.shared?.showToast(ok ? "Permissions reset. Click Allow on each one." : "Could not reset. Remove Jerox in System Settings → Privacy, then click Allow.")
                        }
                    }
                    .controlSize(.small)
                }
                row("Restart Jerox") {
                    Button("Restart") { AppDelegate.shared?.relaunch() }
                        .controlSize(.small)
                }
            }
        case .advanced:
            group("Updates", hint: "Sparkle checks GitHub Releases, verifies the EdDSA signature, then installs and relaunches.") {
                if let version = updater.availableVersion {
                    row("Update available") {
                        Button("Update Now") { updater.checkForUpdates(nil) }
                            .controlSize(.small)
                    }
                    line { Text("Version \(version) is on GitHub.").foregroundStyle(.secondary) }
                } else {
                    row("Jerox") {
                        Button("Check for Updates…") { updater.checkForUpdates(nil) }
                            .controlSize(.small)
                    }
                }
                if !updater.note.isEmpty {
                    line { Text(updater.note).foregroundStyle(JeroxInk.danger) }
                }
            }
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
            #if DEBUG
            group("Developer", hint: "Debug builds only. Not shipped.") {
                row("__dev__ Onboarding") {
                    Button("Open") { AppDelegate.shared?.showOnboarding() }
                        .controlSize(.small)
                }
            }
            #endif
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
                            Text(speechLocaleLabel(locale)).tag(locale.identifier)
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

    private func permissionRow(_ title: String, detail: String, granted: Bool, request: @escaping () -> Void) -> some View {
        line {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if granted {
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Button("Allow…", action: request)
                    .controlSize(.small)
                }
            }
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

    private func isChosen(_ model: SpeechModel) -> Bool {
        model.rephrase ? providerRaw == AIService.local.rawValue && localModel == model.id : speechEngine == model.id
    }

    private func choose(_ model: SpeechModel) {
        guard model.rephrase else {
            speechEngine = model.id
            return
        }
        localModel = model.id
        providerRaw = AIService.local.rawValue
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
                    .onTapGesture { if phase == .ready { choose(model) } }
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
                    Button { choose(model) } label: { radio(isChosen(model)) }
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

    private func testRephrase() {
        testing = true
        testNote = ""
        Task { @MainActor in
            do {
                _ = try await requestAI(instruction: "Repeat the text exactly.", text: "Hello")
                testOK = true
                testNote = "Rephrase works."
            } catch {
                testOK = false
                testNote = error.localizedDescription
            }
            testing = false
        }
    }

    private func loadProvider() {
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
