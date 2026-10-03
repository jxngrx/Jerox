import AppKit
import Foundation
import Observation
import Sparkle

@Observable
final class JeroxUpdater: NSObject, SPUUpdaterDelegate {
    static let shared = JeroxUpdater()

    @ObservationIgnored
    private(set) var controller: SPUStandardUpdaterController!
    var availableVersion: String?
    var note = ""

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        NSApp.activate()
        controller.checkForUpdates(sender)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableVersion = item.displayVersionString
        note = ""
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        availableVersion = nil
        note = ""
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let urlError = (error as NSError).domain == NSURLErrorDomain
        note = urlError ? "" : error.localizedDescription
    }
}
