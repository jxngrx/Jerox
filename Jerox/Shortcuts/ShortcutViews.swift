import AppKit
import Carbon
import Foundation
import SwiftUI

func storedHotkey(codeKey: String, modsKey: String, code: Int, mods: Int) -> (UInt16, NSEvent.ModifierFlags) {
    let storedCode = (UserDefaults.standard.object(forKey: codeKey) as? Int) ?? code
    let storedMods = (UserDefaults.standard.object(forKey: modsKey) as? Int) ?? mods
    let flags = NSEvent.ModifierFlags(rawValue: UInt(storedMods)).intersection([.command, .shift, .option, .control])
    return (UInt16(storedCode), flags)
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
