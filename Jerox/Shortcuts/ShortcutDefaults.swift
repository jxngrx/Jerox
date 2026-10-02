import AppKit
import Carbon
import Foundation

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
