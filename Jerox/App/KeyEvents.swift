import AppKit
import Carbon
import Foundation

func postCommandV() {
    postCommand(CGKeyCode(kVK_ANSI_V))
}

func postCommand(_ key: CGKeyCode) {
    let source = CGEventSource(stateID: .hidSystemState)
    source?.localEventsSuppressionInterval = 0
    let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
    down?.flags = .maskCommand
    up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}
