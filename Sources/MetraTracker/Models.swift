import Combine
import Foundation

// MARK: - Domain Model

struct TrainDeparture: Identifiable {
    let id: String
    let tripId: String
    let scheduledTime: Date
    let delaySeconds: Int
    let minutesUntil: Int
    let isRealTime: Bool

    var effectiveTime: Date {
        scheduledTime.addingTimeInterval(TimeInterval(delaySeconds))
    }

    var formattedDepartureTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = .centralTime  // always display in Central regardless of laptop TZ
        return formatter.string(from: effectiveTime)
    }

    var formattedMinutesUntil: String {
        if minutesUntil < 1 { return "Now" }
        if minutesUntil < 60 { return "\(minutesUntil)m" }
        let h = minutesUntil / 60
        let m = minutesUntil % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    var trainNumber: String {
        // Metra trip IDs are like "BNSF_BN1200_V4_A" — the run number is in the BN#### component
        for component in tripId.split(separator: "_") {
            let digits = component.filter { $0.isNumber }
            if digits.count >= 3 {
                return "#\(digits)"
            }
        }
        return tripId
    }
}

// MARK: - App State (shared observable)

final class AppState: ObservableObject {
    @Published var departures: [TrainDeparture] = []
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    @Published var isRealTime: Bool = true  // false = showing static schedule
    @Published var apiToken: String?
    @Published var config: RouteConfig = ConfigStore.load()

    // Slot override: set when user manually cycles via ⇄; cleared on auto-slot change
    @Published var overrideSlotId: UUID? = nil
    // Tracks the last time-based slot to detect when auto-selection changes
    @Published var lastAutoSlotId: UUID? = nil

    @Published var rtError: String? = nil  // non-nil = token present but RT fetch failed

    // GTFS-derived data for settings UI (populated after first GTFS load)
    @Published var lineStops: [String: [(id: String, name: String)]] = [:]
    @Published var inboundHeadsign: String? = nil
    @Published var outboundHeadsign: String? = nil
    @Published var availableLines: [(id: String, name: String)] = []
}
