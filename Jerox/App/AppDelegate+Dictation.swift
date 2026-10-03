import AppKit
import ApplicationServices
import AVFoundation
import Carbon
import Foundation
import Speech
import SwiftUI

extension AppDelegate {
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
            AVCaptureDevice.requestAccess(for: .audio) { ok in
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

    func beginDictation() {
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

    func armRecognition() {
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
    func previewWhisper() {
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
    func rollRecognition() {
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

    func stopDictation() {
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

    func finishDictation() {
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

    func endMic() {
        audioEngine?.stop()
        if micTap, let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
        }
        micTap = false
        audioEngine = nil
    }

    func armCancelKey() {
        disarmCancelKey()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4A455258), id: 5)
        let status = RegisterEventHotKey(UInt32(kVK_Escape), 0, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr { cancelHotKey = ref }
    }

    func disarmCancelKey() {
        if let cancelHotKey {
            UnregisterEventHotKey(cancelHotKey)
            self.cancelHotKey = nil
        }
    }

    func copyPCM(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
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

    func pasteDictated(_ text: String) {
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

    func hideDictatePanel() {
        dictateState.closing = false
        dictatePanelOpen = false
        dictatePanel?.orderOut(nil)
    }

    func shrinkDictatePanel() {
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

    func showDictatePanel() {
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
}
