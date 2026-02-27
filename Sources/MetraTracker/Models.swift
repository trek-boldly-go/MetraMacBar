import Foundation

// MARK: - GTFS-RT Feed (snake_case JSON from Metra API)

struct FeedMessage: Decodable {
    let header: FeedHeader
    let entity: [FeedEntity]
}

struct FeedHeader: Decodable {
    let gtfs_realtime_version: String?
    let timestamp: String?
    let incrementality: String?
}

struct FeedEntity: Decodable {
    let id: String
    let trip_update: TripUpdate?
}

struct TripUpdate: Decodable {
    let trip: TripDescriptor
    let stop_time_update: [StopTimeUpdate]?
    let timestamp: String?
    let delay: Int?
    let vehicle: VehicleDescriptor?
}

struct TripDescriptor: Decodable {
    let trip_id: String?
    let route_id: String?
    let direction_id: Int?
    let start_date: String?
    let start_time: String?
    let schedule_relationship: String?
}

struct StopTimeUpdate: Decodable {
    let stop_sequence: Int?
    let stop_id: String?
    let departure: StopTimeEvent?
    let arrival: StopTimeEvent?
    let schedule_relationship: String?
}

struct StopTimeEvent: Decodable {
    let delay: Int?
    let time: String?   // Unix timestamp as string
    let uncertainty: Int?
}

struct VehicleDescriptor: Decodable {
    let id: String?
    let label: String?
}

// MARK: - Domain Model

struct TrainDeparture: Identifiable {
    let id: String
    let tripId: String
    let scheduledTime: Date
    let delaySeconds: Int
    let minutesUntil: Int

    var effectiveTime: Date {
        scheduledTime.addingTimeInterval(TimeInterval(delaySeconds))
    }

    var formattedDepartureTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
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

import Combine

final class AppState: ObservableObject {
    @Published var departures: [TrainDeparture] = []
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var isLoading: Bool = false
    @Published var isRealTime: Bool = true   // false = showing static schedule
    @Published var apiToken: String?
    @Published var config: RouteConfig = ConfigStore.load()
}
