import Combine
import Foundation

// MARK: - Cached DateFormatters

enum DateFormatters {
    /// 12-hour time with AM/PM for departure display (e.g., "7:45 AM")
    static let departureTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = .centralTime
        return f
    }()
    
    /// YYYYMMDD for GTFS date comparisons
    static let gtfsDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = .centralTime
        return f
    }()
    
    /// HH:mm:ss for GTFS time comparisons
    static let gtfsTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = .centralTime
        return f
    }()
}

// MARK: - Domain Model

struct TrainDeparture: Identifiable {
    let id: String
    let tripId: String
    let scheduledTime: Date
    let delaySeconds: Int
    let isRealTime: Bool

    var effectiveTime: Date {
        scheduledTime.addingTimeInterval(TimeInterval(delaySeconds))
    }

    var minutesUntil: Int {
        max(0, Int(effectiveTime.timeIntervalSince(Date()) / 60))
    }

    var formattedDepartureTime: String {
        DateFormatters.departureTime.string(from: effectiveTime)
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
