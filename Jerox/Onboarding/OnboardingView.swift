import ApplicationServices
import AVFoundation
import CoreGraphics
import Speech
import SwiftUI

/// First-run walkthrough: one page per job, then the three permissions.
/// Return continues, Esc skips. Opened again from Settings → Advanced → Developer in Debug builds.
struct OnboardingView: View {
    var onDone: () -> Void

    private struct Page {
        let kicker, line1, line2, body: String
        let keys: (code: String, mods: String, code0: Int, mods0: Int)?
    }

    private let pages: [Page] = [
        Page(kicker: "HISTORY", line1: "Everything you copy.", line2: "Right at your cursor.",
             body: "Press the shortcut in any app. Type to filter, then Return pastes it back in its original format.",
             keys: ("hotkey.show.code", "hotkey.show.mods", ShortcutDefaults.showCode, ShortcutDefaults.showMods)),
        Page(kicker: "REWRITE", line1: "Select any text.", line2: "Pick a tone.",
             body: "Jerox rewrites the selection and pastes it back in place. Use Apple Intelligence on this Mac, or your own key.",
             keys: ("hotkey.rephrase.code", "hotkey.rephrase.mods", ShortcutDefaults.rephraseCode, ShortcutDefaults.rephraseMods)),
        Page(kicker: "DICTATE", line1: "Just speak.", line2: "It types for you.",
             body: "Apple Speech shows live text. Download a Whisper model in Settings to work fully offline.",
             keys: ("hotkey.dictate.code", "hotkey.dictate.mods", ShortcutDefaults.dictateCode, ShortcutDefaults.dictateMods)),
        Page(kicker: "READ", line1: "Text on screen.", line2: "Now it is text.",
             body: "Drag over an image, a video frame, or a locked PDF. Click the result to copy it.",
             keys: ("hotkey.read.code", "hotkey.read.mods", ShortcutDefaults.readCode, ShortcutDefaults.readMods)),
        Page(kicker: "SETUP", line1: "Three permissions.", line2: "Asked once.",
             body: "macOS keeps these switches. Jerox only uses each one for the job named beside it.", keys: nil),
    ]

    @State private var index: Int
    @State private var forward = true

    private let still: Bool

    /// `still` freezes the art on one frame (for rendering pages to images).
    init(onDone: @escaping () -> Void, start: Int = 0, still: Bool = false) {
        self.onDone = onDone
        self.still = still
        _index = State(initialValue: start)
    }

    static let pageCount = 5

    private var page: Page { pages[index] }
    private var last: Bool { index == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 12)
            content
                .id(index)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: forward ? 24 : -24)),
                    removal: .opacity.combined(with: .offset(x: forward ? -24 : 24))
                ))
            Spacer(minLength: 12)
            dots
            buttons.padding(.top, 18)
        }
        .padding(EdgeInsets(top: 22, leading: 32, bottom: 26, trailing: 32))
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.1)))
        .padding(EdgeInsets(top: 34, leading: 22, bottom: 22, trailing: 22))
        .frame(width: 680, height: 640)
        .background(Color(red: 0.043, green: 0.043, blue: 0.051))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Button(action: back) { Image(systemName: "arrow.left").font(.system(size: 13, weight: .semibold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(index == 0 ? 0 : 0.9))
                .disabled(index == 0)
                .help("Back")
                .frame(width: 32, height: 32)
            Spacer()
            Text("\(page.kicker)   //   0\(index + 1)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
            Color.clear.frame(width: 32, height: 32)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            OnboardingArt(kind: index, still: still).frame(maxWidth: 560).frame(height: page.keys == nil ? 56 : 160)
            Text(page.line1)
                .font(.system(size: 38, weight: .medium))
                .tracking(-1.1)
                .foregroundStyle(.white.opacity(0.95))
                .padding(.top, 26)
            Text(page.line2)
                .font(.system(size: 38, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(.white.opacity(0.45))
            Text(page.body)
                .font(.system(size: 14))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            if let keys = page.keys {
                let (code, mods) = storedHotkey(codeKey: keys.code, modsKey: keys.mods, code: keys.code0, mods: keys.mods0)
                HStack(spacing: 4) {
                    ForEach(Array(shortcutParts(code: Int(code), mods: Int(mods.rawValue)).enumerated()), id: \.offset) { _, part in
                        Text(part)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(minWidth: 26, minHeight: 26)
                            .padding(.horizontal, 4)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Color.white.opacity(0.16)))
                    }
                }
                .padding(.top, 16)
            } else {
                PermissionList().padding(.top, 16)
                welcome.padding(.top, 14)
            }
        }
        .multilineTextAlignment(.center)
    }

    // The one-time welcome from PRODUCT.md, verbatim.
    private var welcome: some View {
        (Text("🙏 Namaste, Welcome to ") + Text("Jerox").bold() + Text(" Family — this is developed by ")
            + Text("[jxngrx.com](http://jxngrx.com)") + Text(" 🎉💚"))
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.6))
            .tint(JeroxInk.accent)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(pages.indices, id: \.self) { i in
                Capsule()
                    .fill(i == index ? Color.white.opacity(0.9) : Color.white.opacity(0.15))
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(.easeOut(duration: 0.22), value: index)
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button(action: onDone) {
                Text("SKIP").frame(width: 92, height: 40)
            }
            .buttonStyle(OnboardingButton(strong: false))
            .keyboardShortcut(.cancelAction)
            Button(action: next) {
                Text(last ? "ENTER  →" : "CONTINUE  →").frame(width: 150, height: 40)
            }
            .buttonStyle(OnboardingButton(strong: true))
            .keyboardShortcut(.defaultAction)
        }
    }

    private func next() {
        guard !last else { return onDone() }
        forward = true
        withAnimation(.easeOut(duration: 0.28)) { index += 1 }
    }

    private func back() {
        guard index > 0 else { return }
        forward = false
        withAnimation(.easeOut(duration: 0.28)) { index -= 1 }
    }
}

private struct OnboardingButton: ButtonStyle {
    var strong: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(1.8)
            .foregroundStyle(strong ? Color.black : Color.white.opacity(0.75))
            .background(strong ? Color.white.opacity(configuration.isPressed ? 0.8 : 0.92) : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(strong ? 0 : 0.18)))
            .contentShape(Capsule())
    }
}

/// Live permission status; polls once a second because macOS sends no change events for these.
private struct PermissionList: View {
    @State private var ax = false
    @State private var mic = false
    @State private var screen = false
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            item("Accessibility", "Paste back into the app you were using", ax) {
                let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                if !AXIsProcessTrustedWithOptions([key: true] as CFDictionary) { open("Privacy_Accessibility") }
            }
            item("Microphone & Speech", "Dictation, transcribed on this Mac", mic) {
                AVAudioApplication.requestRecordPermission { granted in
                    SFSpeechRecognizer.requestAuthorization { _ in DispatchQueue.main.async { refresh() } }
                    if !granted { DispatchQueue.main.async { open("Privacy_Microphone") } }
                }
            }
            item("Screen Recording", "Read text you select on screen", screen) {
                if !CGRequestScreenCaptureAccess() { open("Privacy_ScreenCapture") }
            }
        }
        .frame(width: 440)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.1)))
        .onAppear(perform: refresh)
        .onReceive(tick) { _ in refresh() }
    }

    private func item(_ title: String, _ note: String, _ granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.92))
                Text(note).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(JeroxInk.accent)
            } else {
                Button("Allow", action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(JeroxInk.accent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1).padding(.horizontal, 14) }
    }

    private func refresh() {
        ax = AXIsProcessTrusted()
        mic = AVAudioApplication.shared.recordPermission == .granted && SFSpeechRecognizer.authorizationStatus() == .authorized
        screen = CGPreflightScreenCaptureAccess()
    }

    private func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}

/// One small animated drawing per page, in the app's own visual language.
private struct OnboardingArt: View {
    var kind: Int
    var still = false

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: still)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                backdrop(&ctx, size, t)
                switch kind {
                case 0: history(&ctx, size, t)
                case 1: rewrite(&ctx, size, t)
                case 2: dictate(&ctx, size, t)
                case 3: read(&ctx, size, t)
                default: setup(&ctx, size, t)
                }
            }
        }
    }

    private let ink = Color.white
    private let blue = JeroxInk.accent

    private func backdrop(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        var x = 12.0
        while x < size.width {
            var y = 10.0
            while y < size.height {
                ctx.fill(Path(ellipseIn: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)), with: .color(ink.opacity(0.06)))
                y += 26
            }
            x += 26
        }
    }

    private func bar(_ ctx: inout GraphicsContext, _ rect: CGRect, _ color: Color) {
        ctx.fill(Path(roundedRect: rect, cornerRadius: rect.height / 2), with: .color(color))
    }

    // Rows rise into a panel; the top one lands at the caret.
    private func history(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let panel = CGRect(x: size.width / 2 - 130, y: 18, width: 260, height: size.height - 36)
        ctx.fill(Path(roundedRect: panel, cornerRadius: 12), with: .color(ink.opacity(0.05)))
        ctx.stroke(Path(roundedRect: panel, cornerRadius: 12), with: .color(ink.opacity(0.12)))
        let phase = t.truncatingRemainder(dividingBy: 3) / 3
        for i in 0..<4 {
            let y = panel.minY + 18 + Double(i) * 28 - phase * 28
            guard y > panel.minY + 6, y < panel.maxY - 20 else { continue }
            let selected = i == 1
            if selected { bar(&ctx, CGRect(x: panel.minX + 10, y: y - 6, width: panel.width - 20, height: 24), blue.opacity(0.22)) }
            bar(&ctx, CGRect(x: panel.minX + 22, y: y + 3, width: [150, 120, 170, 96][i], height: 6), ink.opacity(selected ? 0.85 : 0.35))
        }
        let blink = sin(t * 6) > 0 ? 0.9 : 0.2
        ctx.fill(Path(CGRect(x: panel.maxX + 18, y: panel.midY - 12, width: 2, height: 24)), with: .color(blue.opacity(blink)))
    }

    // A ragged line resolves into a clean one, on loop.
    private func rewrite(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let p = (sin(t * 1.3) + 1) / 2
        let widths: [Double] = [44, 18, 70, 30, 52, 26, 60]
        var x = size.width / 2 - 200
        for (i, w) in widths.enumerated() {
            let jitter = (1 - p) * sin(Double(i) * 2.3 + t * 3) * 10
            bar(&ctx, CGRect(x: x, y: size.height / 2 - 26 + jitter, width: w, height: 8), ink.opacity(0.25 + 0.2 * p))
            x += w + 10
        }
        bar(&ctx, CGRect(x: size.width / 2 - 200, y: size.height / 2 + 12, width: 400 * p, height: 8), blue.opacity(0.9))
    }

    // Level bars around a recording dot.
    private func dictate(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let n = 23, gap = 10.0, w = 5.0
        let start = size.width / 2 - Double(n) * (w + gap) / 2
        for i in 0..<n {
            let d = abs(Double(i - n / 2)) / Double(n / 2)
            let level = (0.25 + 0.75 * abs(sin(t * 3.1 + Double(i) * 0.55)) * abs(sin(t * 1.7 + Double(i) * 0.31))) * (1 - d * 0.7)
            let h = 10 + 90 * level
            bar(&ctx, CGRect(x: start + Double(i) * (w + gap), y: size.height / 2 - h / 2, width: w, height: h), i == n / 2 ? blue : ink.opacity(0.55))
        }
    }

    // A selection sweeps over text lines and lifts them out.
    private func read(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        let box = CGRect(x: size.width / 2 - 170, y: 22, width: 340, height: size.height - 44)
        for i in 0..<5 {
            bar(&ctx, CGRect(x: box.minX + 20, y: box.minY + 14 + Double(i) * 22, width: [260, 220, 280, 180, 240][i], height: 6), ink.opacity(0.3))
        }
        let p = (t.truncatingRemainder(dividingBy: 3.2)) / 3.2
        let sel = CGRect(x: box.minX + 10, y: box.minY + 4, width: (box.width - 20) * min(1, p * 1.6), height: 60)
        ctx.stroke(Path(sel), with: .color(ink.opacity(0.9)), lineWidth: 1.2)
        if p > 0.62 { ctx.fill(Path(sel), with: .color(blue.opacity(0.18))) }
    }

    // Three switches turning on in turn.
    private func setup(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        for i in 0..<3 {
            let on = (t.truncatingRemainder(dividingBy: 4.5)) > Double(i) * 1.2 + 0.4
            let track = CGRect(x: size.width / 2 - 150 + Double(i) * 110, y: size.height / 2 - 14, width: 64, height: 28)
            ctx.fill(Path(roundedRect: track, cornerRadius: 14), with: .color(on ? blue : ink.opacity(0.15)))
            ctx.fill(Path(ellipseIn: CGRect(x: on ? track.maxX - 25 : track.minX + 3, y: track.minY + 3, width: 22, height: 22)), with: .color(ink))
        }
    }
}
