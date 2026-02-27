import SwiftUI

struct TrainListView: View {
    @ObservedObject var appState: AppState
    var onRefresh: () -> Void
    var onSetup: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentView
            Divider()
            footerView
        }
        .frame(width: 300)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("BNSF — Inbound")
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
                Text("from \(appState.config.stopName) → Chicago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
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
            } else {
                HStack(spacing: 3) {
                    Text("Scheduled")
                    Image(systemName: "info.circle")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
                .help("Showing static schedule times. Add an API token in Settings for live tracking.")
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
                Text("Train \(train.trainNumber)")
                    .font(.system(size: 12, weight: .medium))
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
