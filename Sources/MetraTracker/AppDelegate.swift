import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Reduce tooltip delay from the default ~1.5s to 0.5s for this app
        UserDefaults.standard.set(0.5, forKey: "NSInitialToolTipDelay")

        // Load token from Keychain into state
        appState.apiToken = KeychainHelper.loadToken()

        menuBarController = MenuBarController(appState: appState)
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.stop()
    }
}
