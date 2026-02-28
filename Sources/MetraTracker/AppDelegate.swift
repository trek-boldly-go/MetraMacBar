import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarController: MenuBarController?
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
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

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit Metra Tracker",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(
            withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(
            withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
