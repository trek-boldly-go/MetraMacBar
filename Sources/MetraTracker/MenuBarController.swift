import AppKit
import SwiftUI

final class MenuBarController: NSObject, NSWindowDelegate {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private var settingsPanel: NSWindow?
    private var refreshTimer: Timer?
    private let metraService = MetraService()
    private let scheduleService = GTFSScheduleService()
    private let appState: AppState

    private var eventMonitor: Any?

    init(appState: AppState) {
        self.appState = appState

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

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
            onSetup: { [weak self] in self?.showSettings() },
            onCycleSlot: { [weak self] in self?.cycleSlot() }
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
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        refresh()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)

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

    // MARK: - Settings Panel

    func showSettings() {
        closePopover()

        // If already open, just bring it forward
        if let existing = settingsPanel {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = SettingsView(appState: appState) { [weak self] in
            self?.settingsPanel?.close()
            self?.scheduleService.invalidate()
            self?.refresh()
        }

        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 540),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Metra Tracker Settings"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        // Switch to .regular so the window activates the app and receives keyboard events
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        settingsPanel = window
    }

    func windowWillClose(_ notification: Notification) {
        settingsPanel = nil
        NSApp.setActivationPolicy(.accessory)
    }

    // MARK: - Slot Cycling

    private func cycleSlot() {
        let slots = appState.config.slots
        guard slots.count > 1 else { return }
        let currentId = appState.overrideSlotId ?? appState.config.activeSlot()?.id
        let nextIndex: Int
        if let ci = currentId, let i = slots.firstIndex(where: { $0.id == ci }) {
            nextIndex = (i + 1) % slots.count
        } else {
            nextIndex = 0
        }
        appState.overrideSlotId = slots[nextIndex].id
        refresh()
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
        let config = appState.config

        // Detect time-based slot change → clear manual override so auto-switch takes effect
        let autoSlot = config.activeSlot()
        if autoSlot?.id != appState.lastAutoSlotId {
            appState.lastAutoSlotId = autoSlot?.id
            appState.overrideSlotId = nil
        }

        // Resolve the effective slot (manual override or time-based)
        guard let slot = config.slots.first(where: { $0.id == appState.overrideSlotId }) ?? autoSlot else {
            appState.departures = []
            appState.errorMessage = "No route slots configured. Open Settings to add one."
            return
        }

        appState.isLoading = true

        Task { @MainActor in
            defer { appState.isLoading = false }

            // 1. Try the real-time feed if we have a token
            var rtTrains: [TrainDeparture] = []
            if let token = appState.apiToken {
                do {
                    rtTrains = try await metraService.fetchUpcomingTrains(
                        token: token,
                        lineId: config.lineId,
                        stopId: slot.departureStopId,
                        destinationStopId: slot.destinationStopId,
                        directionId: slot.directionId,
                        maxTrains: config.maxTrains
                    )
                    appState.rtError = nil
                    // If RT returned a full list, use it directly — no static needed
                    if rtTrains.count >= config.maxTrains {
                        appState.departures = rtTrains
                        appState.isRealTime = true
                        appState.errorMessage = nil
                        appState.lastUpdated = Date()
                        updateMenuBarTitle(departures: rtTrains)
                        return
                    }
                    // Partial RT list — fall through to fetch static for padding
                } catch {
                    appState.rtError = error.localizedDescription
                    // fall through to static only
                }
            }

            // 2. Fetch static GTFS schedule (always needed when RT is partial or absent)
            do {
                let staticTrains = try await scheduleService.fetchUpcomingTrains(
                    lineId: config.lineId,
                    stopId: slot.departureStopId,
                    destinationStopId: slot.destinationStopId,
                    directionId: slot.directionId,
                    maxTrains: config.maxTrains
                )

                if !rtTrains.isEmpty {
                    // Merge: RT trains take priority; pad with static trains not already in RT
                    let rtTripIds = Set(rtTrains.map { $0.tripId })
                    let padding = staticTrains.filter { !rtTripIds.contains($0.tripId) }
                    let merged = (rtTrains + padding)
                        .sorted { $0.effectiveTime < $1.effectiveTime }
                        .prefix(config.maxTrains)
                        .map { $0 }
                    appState.departures = merged
                    appState.isRealTime = true   // we have live data for some trains
                } else {
                    // No live data — show static only
                    appState.departures = staticTrains
                    appState.isRealTime = false
                }

                appState.errorMessage = nil
                appState.lastUpdated = Date()
                updateMenuBarTitle(departures: appState.departures)

                // Populate GTFS metadata for settings UI (best-effort, background)
                populateGTFSMetadata(lineId: config.lineId)
            } catch {
                appState.errorMessage = error.localizedDescription
                updateMenuBarTitle(departures: appState.departures)
            }
        }
    }

    // MARK: - GTFS Metadata for Settings UI

    private func populateGTFSMetadata(lineId: String) {
        Task { @MainActor in
            if let stops = try? await scheduleService.stopsForLine(lineId), !stops.isEmpty {
                appState.lineStops[lineId] = stops
            }
            if appState.availableLines.isEmpty,
               let lines = try? await scheduleService.availableLines(), !lines.isEmpty {
                appState.availableLines = lines
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
