import SwiftUI

struct TrainListView: View {
    @ObservedObject var appState: AppState
    var onRefresh: () -> Void
    var onSetup: () -> Void
    var onCycleSlot: () -> Void

    // Resolve effective slot: manual override → time-based → first slot
    private var activeSlot: RouteSlot? {
        appState.config.slots.first(where: { $0.id == appState.overrideSlotId })
            ?? appState.config.activeSlot()
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
                .frame(maxHeight: .infinity, alignment: .top)
            Divider()
            footerView
        }
        .frame(width: 300)
        .frame(minHeight: 360)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(headerTitle)
                        .font(.system(size: 13, weight: .semibold))
                    if !appState.isRealTime {
                        Text("SCHEDULED")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if appState.config.slots.count > 1 {
                Button(action: onCycleSlot) {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Switch route")
            }
            Button(action: onSetup) {
                Image(systemName: "gearshape")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var headerTitle: String {
        let line = appState.config.lineId
        let direction = activeSlot?.directionId == 0 ? "Outbound" : "Inbound"
        return "\(line) — \(direction)"
    }

    private var headerSubtitle: String {
        guard let slot = activeSlot else { return "No route configured" }
        if slot.directionId == 1 {
            return "from \(slot.departureStopName) → \(slot.destinationStopName ?? "Chicago")"
        } else {
            if let dest = slot.destinationStopName {
                return "from \(slot.departureStopName) → \(dest)"
            } else {
                return "Outbound from \(slot.departureStopName)"
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if appState.isLoading && appState.departures.isEmpty {
            ProgressView()
                .padding(24)
        } else if let error = appState.errorMessage, appState.departures.isEmpty {
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(24)
        } else if appState.departures.isEmpty {
            Text("No upcoming trains found.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(24)
        } else {
            VStack(spacing: 0) {
                ForEach(appState.departures) { train in
                    TrainRowView(train: train)
                    if train.id != appState.departures.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if appState.isRealTime {
                if let updated = appState.lastUpdated {
                    Text("Updated \(relativeTime(updated))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } else if appState.apiToken != nil && appState.rtError != nil {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                    Text("Live unavailable")
                }
                .foregroundColor(.orange)
                .help(appState.rtError ?? "Live data unavailable. Check your API token in Settings.")
            } else {
                HStack(spacing: 3) {
                    Text("Scheduled")
                    Image(systemName: "info.circle")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
                .help(appState.apiToken != nil
                    ? "No trains currently active. Token ready. Showing static schedule."
                    : "Showing static schedule times. Add an API token in Settings for live tracking.")
            }
            Spacer()
            Button(action: onRefresh) {
                HStack(spacing: 4) {
                    if appState.isLoading {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    Text("Refresh")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(appState.isRealTime ? .accentColor : .secondary)
            .disabled(appState.isLoading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func relativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 { return "just now" }
        if seconds < 60 { return "\(seconds)s ago" }
        return "\(seconds / 60)m ago"
    }
}

// MARK: - Train Row

struct TrainRowView: View {
    let train: TrainDeparture

    var hasDelay: Bool { train.delaySeconds > 60 }
    var delayMinutes: Int { train.delaySeconds / 60 }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Train \(train.trainNumber)")
                        .font(.system(size: 12, weight: .medium))
                    if train.isRealTime {
                        Image(systemName: "dot.radiowaves.right")
                            .font(.system(size: 9))
                            .foregroundColor(.accentColor)
                            .help("Live tracking")
                    }
                }
                if hasDelay {
                    Text("+\(delayMinutes) min delay")
                        .font(.caption2)
                        .foregroundColor(delayMinutes >= 5 ? .red : .orange)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(train.formattedDepartureTime)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(hasDelay ? .orange : .primary)
                Text(train.formattedMinutesUntil)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
