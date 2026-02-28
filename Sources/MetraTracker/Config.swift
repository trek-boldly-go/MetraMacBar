import Foundation

// MARK: - Timezone (pinned to Metra's service timezone; safe when laptop is in another zone)

extension TimeZone {
    static let centralTime = TimeZone(identifier: "America/Chicago")!
}

extension Calendar {
    static var central: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .centralTime
        return c
    }
}

// MARK: - Route Slot

struct RouteSlot: Codable, Equatable, Identifiable {
    var id: UUID
    var startTime: String         // "HH:mm" 24-hour, Central time
    var endTime: String           // "HH:mm" 24-hour, Central time
    var departureStopId: String
    var departureStopName: String
    var destinationStopId: String?    // nil = no filter; filters express trains that skip this stop
    var destinationStopName: String?  // nil = no display; shown in subtitle when set
    var directionId: Int              // 0 = outbound (from Chicago), 1 = inbound (toward Chicago)

    init(
        id: UUID = UUID(), startTime: String, endTime: String,
        departureStopId: String, departureStopName: String,
        destinationStopId: String? = nil, destinationStopName: String? = nil,
        directionId: Int
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.departureStopId = departureStopId
        self.departureStopName = departureStopName
        self.destinationStopId = destinationStopId
        self.destinationStopName = destinationStopName
        self.directionId = directionId
    }
}

// MARK: - Route Config

struct RouteConfig: Codable, Equatable {
    var lineId: String
    var maxTrains: Int
    var slots: [RouteSlot]

    static let `default` = RouteConfig(
        lineId: "BNSF",
        maxTrains: 5,
        slots: [
            RouteSlot(
                startTime: "00:00", endTime: "23:59",
                departureStopId: "NAPERVILLE", departureStopName: "Naperville",
                directionId: 1)
        ]
    )

    /// Returns the effective slot for the given time (Central), respecting any manual override.
    ///
    /// Logic:
    /// 1. If overrideId is set and matches a known slot, return that slot.
    /// 2. Return the first slot whose [startTime, endTime) window contains `date` (Central).
    /// 3. If no window matches, return the most recently completed slot, or `slots.first`.
    func activeSlot(overrideId: UUID? = nil, at date: Date = Date()) -> RouteSlot? {
        guard !slots.isEmpty else { return nil }

        if let id = overrideId, let slot = slots.first(where: { $0.id == id }) {
            return slot
        }

        let cal = Calendar.central
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        if let active = slots.first(where: {
            minutesFromHHmm($0.startTime) <= nowMinutes && nowMinutes < minutesFromHHmm($0.endTime)
        }) {
            return active
        }

        // No active window — return the last slot whose end has passed, else slots.first
        let pastSlots = slots.filter { minutesFromHHmm($0.endTime) <= nowMinutes }
        return pastSlots.last ?? slots.first
    }
}

private func minutesFromHHmm(_ timeStr: String) -> Int {
    let parts = timeStr.split(separator: ":").compactMap { Int($0) }
    guard parts.count >= 2 else { return 0 }
    return parts[0] * 60 + parts[1]
}

// MARK: - Config Store (UserDefaults persistence with migration from old single-stop format)

enum ConfigStore {
    private static let key = "routeConfig"

    static func load() -> RouteConfig {
        guard let data = UserDefaults.standard.data(forKey: key) else { return .default }

        // Try current multi-slot format first
        if let config = try? JSONDecoder().decode(RouteConfig.self, from: data) {
            return config
        }

        // Migration: old format had stopId/stopName/directionId directly on RouteConfig
        if let old: LegacyRouteConfig = try? JSONDecoder().decode(
            LegacyRouteConfig.self, from: data)
        {
            let slot = RouteSlot(
                startTime: "00:00", endTime: "23:59",
                departureStopId: old.stopId, departureStopName: old.stopName,
                directionId: old.directionId)
            return RouteConfig(lineId: old.lineId, maxTrains: old.maxTrains, slots: [slot])
        }

        return .default
    }

    static func save(_ config: RouteConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// Used only for migration — matches the old stored format
private struct LegacyRouteConfig: Codable {
    var lineId: String
    var stopId: String
    var stopName: String
    var destinationName: String
    var directionId: Int
    var maxTrains: Int
}
