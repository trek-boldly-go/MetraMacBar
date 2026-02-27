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

    func fetchUpcomingTrains(token: String, config: RouteConfig) async throws -> [TrainDeparture] {
        guard var components = URLComponents(string: baseURL) else {
            throw MetraError.badURL
        }
        components.queryItems = [URLQueryItem(name: "api_token", value: token)]
        guard let url = components.url else { throw MetraError.badURL }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MetraTracker/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw MetraError.httpError(http.statusCode)
        }

        let feed: FeedMessage
        do {
            feed = try JSONDecoder().decode(FeedMessage.self, from: data)
        } catch {
            throw MetraError.decodingError(error)
        }

        return parseTrains(from: feed, config: config)
    }

    private func parseTrains(from feed: FeedMessage, config: RouteConfig) -> [TrainDeparture] {
        let now = Date()

        var departures: [TrainDeparture] = []

        for entity in feed.entity {
            guard let tripUpdate = entity.trip_update else { continue }
            let trip = tripUpdate.trip

            // Filter by route
            if let routeId = trip.route_id, routeId != config.lineId { continue }

            // Filter by direction if present
            if let dirId = trip.direction_id, dirId != config.directionId { continue }

            // Find the stop time update for our station
            guard
                let updates = tripUpdate.stop_time_update,
                let stopUpdate = updates.first(where: { $0.stop_id == config.stopId }),
                let departure = stopUpdate.departure,
                let timeStr = departure.time,
                let timeInterval = TimeInterval(timeStr)
            else { continue }

            let scheduledTime = Date(timeIntervalSince1970: timeInterval)
            let delaySeconds = departure.delay ?? 0
            let effectiveTime = scheduledTime.addingTimeInterval(TimeInterval(delaySeconds))

            // Skip trains already departed (with a small buffer)
            guard effectiveTime > now.addingTimeInterval(-60) else { continue }

            let minutesUntil = max(0, Int(effectiveTime.timeIntervalSince(now) / 60))
            let tripId = trip.trip_id ?? entity.id

            departures.append(TrainDeparture(
                id: entity.id,
                tripId: tripId,
                scheduledTime: scheduledTime,
                delaySeconds: delaySeconds,
                minutesUntil: minutesUntil
            ))
        }

        return departures
            .sorted { $0.effectiveTime < $1.effectiveTime }
            .prefix(config.maxTrains)
            .map { $0 }
    }
}
