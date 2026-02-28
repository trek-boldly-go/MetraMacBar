import SwiftUI

// MARK: - Main Settings View

struct SettingsView: View {
    @ObservedObject var appState: AppState
    var onSave: () -> Void

    @State private var config: RouteConfig
    @State private var tokenInput: String = ""
    @State private var tokenError: String?
    @State private var showToken = false
    @State private var showAddSlot = false
    @State private var editingSlot: RouteSlot? = nil

    init(appState: AppState, onSave: @escaping () -> Void) {
        self.appState = appState
        self.onSave = onSave
        _config = State(initialValue: appState.config)
        _tokenInput = State(initialValue: appState.apiToken ?? "")
    }

    // Fallback line list for when GTFS isn't loaded yet
    private static let fallbackLines: [(id: String, name: String)] = [
        ("BNSF", "BNSF Railway"),
        ("HC", "Heritage Corridor"),
        ("MD-N", "Milwaukee District North"),
        ("MD-W", "Milwaukee District West"),
        ("ME", "Metra Electric"),
        ("NCS", "North Central Service"),
        ("RI", "Rock Island"),
        ("SWS", "SouthWest Service"),
        ("UP-N", "Union Pacific North"),
        ("UP-NW", "Union Pacific Northwest"),
        ("UP-W", "Union Pacific West"),
    ]

    private var availableLines: [(id: String, name: String)] {
        appState.availableLines.isEmpty ? Self.fallbackLines : appState.availableLines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            lineSection
            Divider()
            tokenSection
            Divider()
            scheduleSection
        }
        .padding(20)
        .frame(width: 420)
        .sheet(isPresented: $showAddSlot) {
            SlotEditorView(
                slot: nil,
                lineId: config.lineId,
                availableStops: appState.lineStops[config.lineId] ?? [],
                onCommit: { newSlot in
                    config.slots.append(newSlot)
                    saveConfig()
                    showAddSlot = false
                },
                onCancel: { showAddSlot = false }
            )
        }
        .sheet(item: $editingSlot) { slot in
            SlotEditorView(
                slot: slot,
                lineId: config.lineId,
                availableStops: appState.lineStops[config.lineId] ?? [],
                onCommit: { updated in
                    if let i = config.slots.firstIndex(where: { $0.id == updated.id }) {
                        config.slots[i] = updated
                    }
                    saveConfig()
                    editingSlot = nil
                },
                onCancel: { editingSlot = nil }
            )
        }
    }

    // MARK: - Line Section

    private var lineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Line")
                .font(.headline)
            Picker("Line", selection: $config.lineId) {
                ForEach(availableLines, id: \.id) { line in
                    Text(line.name).tag(line.id)
                }
            }
            .labelsHidden()
            .onChange(of: config.lineId) { _ in
                saveConfig()
            }
            Text(
                "After changing lines, update your schedule slots below to use stations on the new line — stops from other lines won't return results."
            )
            .font(.caption)
            .foregroundColor(.orange)
            Text("Station list refreshes after the next data fetch.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Token Section

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API Token")
                .font(.headline)
            Text("Optional — enables live departure times with delay info.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                if showToken {
                    TextField("Paste token here", text: $tokenInput)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("Paste token here", text: $tokenInput)
                        .textFieldStyle(.roundedBorder)
                }
                Button(action: { showToken.toggle() }) {
                    Image(systemName: showToken ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(showToken ? "Hide token" : "Show token")
                Button("Save") { saveToken() }
                    .buttonStyle(.borderedProminent)
                    .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                if appState.apiToken != nil {
                    Button("Remove") { removeToken() }
                        .buttonStyle(.bordered)
                }
            }

            if let error = tokenError {
                Text(error).font(.caption).foregroundColor(.red)
            } else if appState.apiToken != nil {
                Text("Token saved in Keychain.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Schedule")
                .font(.headline)
            Text(
                "Departures switch automatically based on the time window. Outside all windows, the last active slot is used."
            )
            .font(.caption)
            .foregroundColor(.secondary)

            if config.slots.isEmpty {
                Text("No slots configured.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(config.slots) { slot in
                        SlotRowView(slot: slot) {
                            editingSlot = slot
                        } onDelete: {
                            config.slots.removeAll { $0.id == slot.id }
                            if appState.overrideSlotId == slot.id {
                                appState.overrideSlotId = nil
                            }
                            saveConfig()
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    showAddSlot = true
                } label: {
                    Label("Add Slot", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Actions

    private func saveToken() {
        let trimmed = tokenInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if KeychainHelper.saveToken(trimmed) {
            appState.apiToken = trimmed
            tokenError = nil
            onSave()
        } else {
            tokenError = "Failed to save to Keychain."
        }
    }

    private func removeToken() {
        KeychainHelper.deleteToken()
        appState.apiToken = nil
        tokenInput = ""
        tokenError = nil
        onSave()
    }

    private func saveConfig() {
        appState.config = config
        ConfigStore.save(config)
    }
}

// MARK: - Slot Row

private struct SlotRowView: View {
    let slot: RouteSlot
    var onEdit: () -> Void
    var onDelete: () -> Void

    private var timeLabel: String {
        "\(formatHHmm(slot.startTime)) – \(formatHHmm(slot.endTime))"
    }

    private var directionLabel: String {
        slot.directionId == 0 ? "Outbound" : "Inbound"
    }

    private var stopsLabel: String {
        var label = slot.departureStopName
        if let dest = slot.destinationStopName { label += " → \(dest)" }
        label += " · \(directionLabel)"
        return label
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeLabel)
                    .font(.system(size: 12, weight: .medium))
                Text(stopsLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit")
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Slot Editor Sheet

struct SlotEditorView: View {
    let existingId: UUID?
    let lineId: String
    let availableStops: [(id: String, name: String)]
    var onCommit: (RouteSlot) -> Void
    var onCancel: () -> Void

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var departureStopId: String
    @State private var departureStopName: String
    @State private var directionId: Int
    @State private var manualDepartureStopId: String
    @State private var destStopId: String       // empty = "None"
    @State private var manualDestStopId: String

    private var isAdding: Bool { existingId == nil }
    private var hasStops: Bool { !availableStops.isEmpty }

    init(
        slot: RouteSlot?, lineId: String, availableStops: [(id: String, name: String)],
        onCommit: @escaping (RouteSlot) -> Void, onCancel: @escaping () -> Void
    ) {
        self.existingId = slot?.id
        self.lineId = lineId
        self.availableStops = availableStops
        self.onCommit = onCommit
        self.onCancel = onCancel

        let start = slot?.startTime ?? "06:00"
        let end = slot?.endTime ?? "10:00"
        _startDate = State(initialValue: Self.dateFromHHmm(start))
        _endDate = State(initialValue: Self.dateFromHHmm(end))

        let sid = slot?.departureStopId ?? availableStops.first?.id ?? ""
        let sname = slot?.departureStopName ?? availableStops.first?.name ?? ""
        _departureStopId = State(initialValue: sid)
        _departureStopName = State(initialValue: sname)
        _manualDepartureStopId = State(initialValue: slot?.departureStopId ?? "")
        _directionId = State(initialValue: slot?.directionId ?? 1)
        _destStopId = State(initialValue: slot?.destinationStopId ?? "")
        _manualDestStopId = State(initialValue: slot?.destinationStopId ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isAdding ? "Add Route Slot" : "Edit Route Slot")
                .font(.headline)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start").font(.caption).foregroundColor(.secondary)
                    DatePicker("", selection: $startDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .environment(\.timeZone, .centralTime)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("End").font(.caption).foregroundColor(.secondary)
                    DatePicker("", selection: $endDate, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .environment(\.timeZone, .centralTime)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Departure Station").font(.caption).foregroundColor(.secondary)
                if hasStops {
                    Picker("Departure Station", selection: $departureStopId) {
                        ForEach(availableStops, id: \.id) { stop in
                            Text(stop.name).tag(stop.id)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: departureStopId) { newId in
                        departureStopName = availableStops.first(where: { $0.id == newId })?.name ?? newId
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Stop ID (e.g. NAPERVILLE)", text: $manualDepartureStopId)
                            .textFieldStyle(.roundedBorder)
                        Text(
                            "Station picker loads after the first refresh. You can enter a stop ID manually for now."
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Destination (optional)").font(.caption).foregroundColor(.secondary)
                Text("When set, hides express trains that skip this stop.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if hasStops {
                    Picker("Destination", selection: $destStopId) {
                        Text("None — show all trains").tag("")
                        ForEach(availableStops, id: \.id) { stop in
                            Text(stop.name).tag(stop.id)
                        }
                    }
                    .labelsHidden()
                } else {
                    TextField("Stop ID (optional, e.g. AURORA)", text: $manualDestStopId)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if destStopId.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Direction").font(.caption).foregroundColor(.secondary)
                    Picker("Direction", selection: $directionId) {
                        Text("Inbound (→ Chicago)").tag(1)
                        Text("Outbound (← Chicago)").tag(0)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
            }

            Text("Times are in US Central (Chicago) time.")
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isAdding ? "Add" : "Save") { commit() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func commit() {
        let sid = hasStops ? departureStopId : manualDepartureStopId.trimmingCharacters(in: .whitespaces)
        let sname: String
        if hasStops {
            sname = availableStops.first(where: { $0.id == sid })?.name ?? sid
        } else {
            sname = sid
        }
        let dstId = hasStops ? destStopId : manualDestStopId.trimmingCharacters(in: .whitespaces)
        let isDestSet = !dstId.isEmpty
        let slot = RouteSlot(
            id: existingId ?? UUID(),
            startTime: Self.hhmmFromDate(startDate),
            endTime: Self.hhmmFromDate(endDate),
            departureStopId: sid,
            departureStopName: sname,
            destinationStopId: isDestSet ? dstId : nil,
            destinationStopName: isDestSet ? (availableStops.first(where: { $0.id == dstId })?.name ?? dstId) : nil,
            directionId: directionId
        )
        onCommit(slot)
    }

    private static func dateFromHHmm(_ timeStr: String) -> Date {
        let parts = timeStr.split(separator: ":").compactMap { Int($0) }
        var comps = Calendar.central.dateComponents([.year, .month, .day], from: Date())
        comps.hour = parts.count >= 1 ? parts[0] : 0
        comps.minute = parts.count >= 2 ? parts[1] : 0
        comps.second = 0
        return Calendar.central.date(from: comps) ?? Date()
    }

    private static func hhmmFromDate(_ date: Date) -> String {
        let comps = Calendar.central.dateComponents([.hour, .minute], from: date)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        return String(format: "%02d:%02d", h, m)
    }
}

// MARK: - Helpers

private func formatHHmm(_ timeStr: String) -> String {
    let parts = timeStr.split(separator: ":").compactMap { Int($0) }
    guard parts.count >= 2 else { return timeStr }
    let h = parts[0]
    let m = parts[1]
    let period = h < 12 ? "AM" : "PM"
    let h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
    return String(format: "%d:%02d %@", h12, m, period)
}
