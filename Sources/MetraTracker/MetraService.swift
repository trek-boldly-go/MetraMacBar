import Foundation

enum MetraError: LocalizedError {
    case noToken
    case badURL
    case httpError(Int)
    case decodingError(Error)
    case noData

    var errorDescription: String? {
        switch self {
        case .noToken: return "No API token configured. Click to set up."
        case .badURL: return "Invalid API URL."
        case .httpError(let code): return "API returned HTTP \(code)."
        case .decodingError(let e): return "Failed to parse response: \(e.localizedDescription)"
        case .noData: return "No data returned from API."
        }
    }
}

final class MetraService {
    private let baseURL = "https://gtfspublic.metrarr.com/gtfs/public/tripupdates"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    func fetchUpcomingTrains(token: String, lineId: String, stopId: String, destinationStopId: String?, directionId: Int, maxTrains: Int) async throws -> [TrainDeparture] {
        guard var components = URLComponents(string: baseURL) else {
            throw MetraError.badURL
        }
        components.queryItems = [URLQueryItem(name: "api_token", value: token)]
        guard let url = components.url else { throw MetraError.badURL }

        var request = URLRequest(url: url)
        request.setValue("MetraTracker/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw MetraError.httpError(http.statusCode)
        }

        let entities: [RTEntity]
        do {
            entities = try parseGTFSRTFeed(data)
        } catch {
            throw MetraError.decodingError(error)
        }

        return parseTrains(from: entities, lineId: lineId, stopId: stopId, destinationStopId: destinationStopId, directionId: directionId, maxTrains: maxTrains)
    }

    private func parseTrains(from entities: [RTEntity], lineId: String, stopId: String, destinationStopId: String?, directionId: Int, maxTrains: Int) -> [TrainDeparture] {
        let now = Date()

        var departures: [TrainDeparture] = []

        for entity in entities {
            guard let tripUpdate = entity.tripUpdate else { continue }
            let trip = tripUpdate.trip

            // Filter by route
            if let routeId = trip.routeId, routeId != lineId { continue }

            // When destination is set, direction is implied by stop order; skip directionId filter
            if destinationStopId == nil {
                if let dirId = trip.directionId, dirId != directionId { continue }
            }

            // Find the stop time update for our station
            let updates = tripUpdate.stopTimes
            guard
                let depIdx = updates.firstIndex(where: { $0.stopId == stopId }),
                let event = updates[depIdx].departure ?? updates[depIdx].arrival,
                let timeValue = event.time
            else { continue }

            // If a destination stop is configured, require it appears after the departure stop
            if let destId = destinationStopId {
                guard let destIdx = updates.firstIndex(where: { $0.stopId == destId }),
                    destIdx > depIdx else { continue }
            }

            let scheduledTime = Date(timeIntervalSince1970: TimeInterval(timeValue))
            let delaySeconds = event.delay ?? 0
            let effectiveTime = scheduledTime.addingTimeInterval(TimeInterval(delaySeconds))

            // Skip trains already departed (with a small buffer)
            guard effectiveTime > now.addingTimeInterval(-60) else { continue }

            let minutesUntil = max(0, Int(effectiveTime.timeIntervalSince(now) / 60))
            let tripId = trip.tripId ?? entity.id

            departures.append(TrainDeparture(
                id: entity.id,
                tripId: tripId,
                scheduledTime: scheduledTime,
                delaySeconds: delaySeconds,
                minutesUntil: minutesUntil,
                isRealTime: true
            ))
        }

        return departures
            .sorted { $0.effectiveTime < $1.effectiveTime }
            .prefix(maxTrains)
            .map { $0 }
    }
}
