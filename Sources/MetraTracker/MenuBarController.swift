import AppKit
import SwiftUI

final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var setupPanel: NSPanel?
    private var refreshTimer: Timer?
    private let metraService = MetraService()
    private let scheduleService = GTFSScheduleService()
    private let appState: AppState

    private var eventMonitor: Any?

    init(appState: AppState) {
        self.appState = appState

        // Status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Popover
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        super.init()

        configureButton()
        configurePopover()

        // Always start refreshing — falls back to static schedule if no token
        startRefreshing()
    }

    // MARK: - Setup

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.title = "BNSF"
        button.image = NSImage(systemSymbolName: "tram.fill", accessibilityDescription: "Metra")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeft
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseDown])
        button.target = self
    }

    private func configurePopover() {
        let content = TrainListView(
            appState: appState,
            onRefresh: { [weak self] in self?.refresh() },
            onSetup: { [weak self] in self?.showSetup() }
        )
        let hostingController = NSHostingController(rootView: content)
        popover.contentViewController = hostingController
        popover.contentSize = NSSize(width: 300, height: 360)
    }

    // MARK: - Popover

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseDown {
            closePopover()
            showContextMenu()
        } else if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Metra Tracker", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // Temporarily set the menu so AppKit positions it correctly under the status item
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil   // clear so left-click still opens the popover
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)

        // Close popover when clicking outside
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Setup Panel

    func showSetup() {
        closePopover()

        let setupView = SetupView(appState: appState) { [weak self] in
            self?.setupPanel?.close()
            self?.setupPanel = nil
            self?.refresh()
        }

        let hostingController = NSHostingController(rootView: setupView)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 180),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Metra Tracker Setup"
        panel.contentViewController = hostingController
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        setupPanel = panel
    }

    // MARK: - Refresh

    func startRefreshing() {
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @objc func refresh() {
        appState.isLoading = true
        let config = appState.config

        Task { @MainActor in
            defer { appState.isLoading = false }

            // 1. Try the real-time feed if we have a token
            if let token = appState.apiToken {
                do {
                    let trains = try await metraService.fetchUpcomingTrains(token: token, config: config)
                    appState.departures = trains
                    appState.isRealTime = true
                    appState.errorMessage = nil
                    appState.lastUpdated = Date()
                    updateMenuBarTitle(departures: trains)
                    return
                } catch {
                    // RT failed — note the reason and fall through to static
                    appState.errorMessage = "Live data unavailable — showing scheduled times."
                }
            }

            // 2. Fall back to static GTFS schedule
            do {
                let trains = try await scheduleService.fetchUpcomingTrains(config: config)
                appState.departures = trains
                appState.isRealTime = false
                appState.lastUpdated = Date()
                // If no token at all, don't show an error — static data is expected
                if appState.apiToken == nil { appState.errorMessage = nil }
                updateMenuBarTitle(departures: trains)
            } catch {
                appState.errorMessage = error.localizedDescription
                updateMenuBarTitle(departures: appState.departures)
            }
        }
    }

    // MARK: - Menu Bar Title

    private func updateMenuBarTitle(departures: [TrainDeparture]) {
        guard let button = statusItem.button else { return }

        if let next = departures.first {
            let label = next.minutesUntil < 1 ? "Now" : next.formattedMinutesUntil
            button.title = " \(label)"
        } else if appState.errorMessage != nil {
            button.title = " !"
        } else {
            button.title = " --"
        }
    }
}
