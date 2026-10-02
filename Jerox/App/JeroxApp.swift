import AppKit
import Carbon
import Foundation
import os

let log = Logger(subsystem: "com.jxngrx.jerox", category: "app")

let appDelegate = AppDelegate()

@main
enum JeroxMain {
    static func main() {
        let app = NSApplication.shared
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

func jeroxHotKeyHandler(
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
