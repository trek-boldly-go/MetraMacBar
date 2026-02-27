import Foundation

struct RouteConfig: Codable, Equatable {
    var lineId: String
    var stopId: String
    var stopName: String
    var directionId: Int
    var maxTrains: Int

    static let `default` = RouteConfig(
        lineId: "BNSF",
        stopId: "NAPERVILLE",
        stopName: "Naperville",
        directionId: 1,
        maxTrains: 5
    )
}

enum ConfigStore {
    private static let key = "routeConfig"

    static func load() -> RouteConfig {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let config = try? JSONDecoder().decode(RouteConfig.self, from: data)
        else { return .default }
        return config
    }

    static func save(_ config: RouteConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
