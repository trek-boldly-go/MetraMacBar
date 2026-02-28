import Foundation

// MARK: - Errors

enum GTFSError: LocalizedError {
    case noCache
    case downloadFailed(Int)
    case extractionFailed
    case missingColumns(String)

    var errorDescription: String? {
        switch self {
        case .noCache:
            return "No cached schedule and network unavailable."
        case .downloadFailed(let code):
            return "Schedule download failed (HTTP \(code))."
        case .extractionFailed:
            return "Failed to extract schedule files."
        case .missingColumns(let file):
            return "Unexpected format in \(file)."
        }
    }
}

// MARK: - Internal data types

private struct GTFSServiceCalendar {
    let monday, tuesday, wednesday, thursday, friday, saturday, sunday: Bool
    let startDate: String  // YYYYMMDD
    let endDate: String  // YYYYMMDD
}

// MARK: - Service

final class GTFSScheduleService {

    // ~/Library/Application Support/com.metratracker/gtfs/
    private static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let dir = base.appendingPathComponent("com.metratracker/gtfs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let publishedURL = URL(string: "https://schedules.metrarail.com/gtfs/published.txt")!
    private let scheduleZipURL = URL(string: "https://schedules.metrarail.com/gtfs/schedule.zip")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    // In-memory parsed data
    // trips[trip_id] = (routeId, serviceId, directionId)
    private var trips: [String: (routeId: String, serviceId: String, directionId: Int)] = [:]
    // stopTimes[trip_id] = [(stopId, departureTime "HH:MM:SS")]
    private var stopTimes: [String: [(stopId: String, departureTime: String)]] = [:]
    private var services: [String: GTFSServiceCalendar] = [:]
    // calendarExceptions[service_id] = [(date "YYYYMMDD", exceptionType 1/2)]
    private var calendarExceptions: [String: [(date: String, type: Int)]] = [:]
    // stops[stop_id] = stop_name
    private var stops: [String: String] = [:]
    // lineStops[route_id] = set of stop_ids that appear on that line
    private var lineStops: [String: Set<String>] = [:]
    // routes sorted by name: [(id, name)]
    private var parsedRoutes: [(id: String, name: String)] = []

    private var isLoaded = false

    // MARK: - Public API

    func fetchUpcomingTrains(lineId: String, stopId: String, destinationStopId: String?, directionId: Int, maxTrains: Int)
        async throws -> [TrainDeparture]
    {
        try await ensureLoaded()
        return computeDepartures(
            lineId: lineId, stopId: stopId, destinationStopId: destinationStopId,
            directionId: directionId, maxTrains: maxTrains)
    }

    /// Returns stops that serve `lineId`, sorted alphabetically. Requires GTFS to be loaded.
    func stopsForLine(_ lineId: String) async throws -> [(id: String, name: String)] {
        try await ensureLoaded()
        guard let ids = lineStops[lineId] else { return [] }
        return
            ids
            .compactMap { id -> (id: String, name: String)? in
                guard let name = stops[id] else { return nil }
                return (id: id, name: name)
            }
            .sorted { $0.name < $1.name }
    }

    /// Returns all lines from routes.txt, sorted by name.
    func availableLines() async throws -> [(id: String, name: String)] {
        try await ensureLoaded()
        return parsedRoutes
    }

    // Call this when config changes so we re-filter on next fetch
    func invalidate() {
        isLoaded = false
    }

    // MARK: - Loading

    private func ensureLoaded() async throws {
        if isLoaded { return }
        try await updateCacheIfNeeded()
        try parseFiles()
        isLoaded = true
    }

    private static let neededFiles = [
        "trips.txt", "stop_times.txt", "calendar.txt", "calendar_dates.txt", "stops.txt",
        "routes.txt",
    ]

    private func updateCacheIfNeeded() async throws {
        let needed = Self.neededFiles
        // Require each file to exist AND be non-empty (guards against stale zero-byte files
        // left behind by a previous failed extraction)
        let allCached = needed.allSatisfy { filename in
            let url = Self.cacheDir.appendingPathComponent(filename)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                let size = attrs[.size] as? Int
            else { return false }
            return size > 0
        }

        do {
            let (data, _) = try await session.data(from: publishedURL)
            let remote =
                String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            let localFile = Self.cacheDir.appendingPathComponent("published.txt")
            let local =
                (try? String(contentsOf: localFile, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if !allCached || remote != local {
                try await downloadAndExtract(publishedTimestamp: remote)
            }
        } catch let e as GTFSError {
            throw e  // re-throw our own errors (download/extraction failures)
        } catch {
            // Network unavailable — fall back to cached files if present
            guard allCached else { throw GTFSError.noCache }
        }
    }

    private func downloadAndExtract(publishedTimestamp: String) async throws {
        let (data, response) = try await session.data(from: scheduleZipURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw GTFSError.downloadFailed(code)
        }

        let zipPath = Self.cacheDir.appendingPathComponent("schedule.zip")
        try data.write(to: zipPath, options: .atomic)

        let needed = Self.neededFiles
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        // -j junks directory paths so files nested inside the ZIP land flat in cacheDir
        process.arguments = ["-o", "-j", zipPath.path, "-d", Self.cacheDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        // unzip exit 0 = success, 1 = success with warnings — both are acceptable
        guard process.terminationStatus <= 1 else { throw GTFSError.extractionFailed }

        // Verify every required file was actually extracted and is non-empty
        for filename in needed {
            let url = Self.cacheDir.appendingPathComponent(filename)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                let size = attrs[.size] as? Int, size > 0
            else { throw GTFSError.extractionFailed }
        }

        // Save timestamp so we know what version is cached
        let tsFile = Self.cacheDir.appendingPathComponent("published.txt")
        try publishedTimestamp.write(to: tsFile, atomically: true, encoding: .utf8)

        try? FileManager.default.removeItem(at: zipPath)
    }

    // MARK: - Parsing

    private func parseFiles() throws {
        trips = [:]
        stopTimes = [:]
        services = [:]
        calendarExceptions = [:]
        stops = [:]
        lineStops = [:]
        parsedRoutes = []

        try parseRoutes()
        try parseTrips()
        try parseCalendar()
        try parseCalendarDates()
        try parseStops()
        try parseStopTimes()  // last — can filter against trips dict and build lineStops
    }

    private func parseTrips() throws {
        let url = Self.cacheDir.appendingPathComponent("trips.txt")
        let content = try String(contentsOf: url, encoding: .utf8)
        let (headers, rows) = splitCSV(content)

        guard let tripCol = headers.firstIndex(of: "trip_id"),
            let routeCol = headers.firstIndex(of: "route_id"),
            let serviceCol = headers.firstIndex(of: "service_id")
        else { throw GTFSError.missingColumns("trips.txt") }
        let dirCol = headers.firstIndex(of: "direction_id")

        for row in rows {
            guard row.count > max(tripCol, routeCol, serviceCol) else { continue }
            let tripId = row[tripCol]
            guard !tripId.isEmpty else { continue }
            trips[tripId] = (
                routeId: row[routeCol],
                serviceId: row[serviceCol],
                directionId: dirCol.flatMap { $0 < row.count ? Int(row[$0]) : nil } ?? 0
            )
        }
    }

    private func parseCalendar() throws {
        let url = Self.cacheDir.appendingPathComponent("calendar.txt")
        let content = try String(contentsOf: url, encoding: .utf8)
        let (headers, rows) = splitCSV(content)

        guard let sidCol = headers.firstIndex(of: "service_id"),
            let monCol = headers.firstIndex(of: "monday"),
            let tueCol = headers.firstIndex(of: "tuesday"),
            let wedCol = headers.firstIndex(of: "wednesday"),
            let thuCol = headers.firstIndex(of: "thursday"),
            let friCol = headers.firstIndex(of: "friday"),
            let satCol = headers.firstIndex(of: "saturday"),
            let sunCol = headers.firstIndex(of: "sunday"),
            let startCol = headers.firstIndex(of: "start_date"),
            let endCol = headers.firstIndex(of: "end_date")
        else { throw GTFSError.missingColumns("calendar.txt") }

        for row in rows {
            let maxIdx = max(
                sidCol, monCol, tueCol, wedCol, thuCol, friCol, satCol, sunCol, startCol, endCol)
            guard row.count > maxIdx else { continue }
            let sid = row[sidCol]
            guard !sid.isEmpty else { continue }
            services[sid] = GTFSServiceCalendar(
                monday: row[monCol] == "1",
                tuesday: row[tueCol] == "1",
                wednesday: row[wedCol] == "1",
                thursday: row[thuCol] == "1",
                friday: row[friCol] == "1",
                saturday: row[satCol] == "1",
                sunday: row[sunCol] == "1",
                startDate: row[startCol],
                endDate: row[endCol]
            )
        }
    }

    private func parseCalendarDates() throws {
        let url = Self.cacheDir.appendingPathComponent("calendar_dates.txt")
        let content = try String(contentsOf: url, encoding: .utf8)
        let (headers, rows) = splitCSV(content)

        guard let sidCol = headers.firstIndex(of: "service_id"),
            let dateCol = headers.firstIndex(of: "date"),
            let typeCol = headers.firstIndex(of: "exception_type")
        else { throw GTFSError.missingColumns("calendar_dates.txt") }

        for row in rows {
            guard row.count > max(sidCol, dateCol, typeCol) else { continue }
            let sid = row[sidCol]
            guard !sid.isEmpty, let exType = Int(row[typeCol]) else { continue }
            calendarExceptions[sid, default: []].append((date: row[dateCol], type: exType))
        }
    }

    private func parseRoutes() throws {
        let url = Self.cacheDir.appendingPathComponent("routes.txt")
        let content = try String(contentsOf: url, encoding: .utf8)
        let (headers, rows) = splitCSV(content)

        guard let idCol = headers.firstIndex(of: "route_id"),
            let nameCol = headers.firstIndex(of: "route_long_name")
        else { throw GTFSError.missingColumns("routes.txt") }

        var result: [(id: String, name: String)] = []
        for row in rows {
            guard row.count > max(idCol, nameCol) else { continue }
            let id = row[idCol]
            guard !id.isEmpty else { continue }
            result.append((id: id, name: row[nameCol]))
        }
        parsedRoutes = result.sorted { $0.name < $1.name }
    }

    private func parseStops() throws {
        let url = Self.cacheDir.appendingPathComponent("stops.txt")
        let content = try String(contentsOf: url, encoding: .utf8)
        let (headers, rows) = splitCSV(content)

        guard let idCol = headers.firstIndex(of: "stop_id"),
            let nameCol = headers.firstIndex(of: "stop_name")
        else { throw GTFSError.missingColumns("stops.txt") }

        for row in rows {
            guard row.count > max(idCol, nameCol) else { continue }
            let id = row[idCol]
            guard !id.isEmpty else { continue }
            stops[id] = row[nameCol]
        }
    }

    // stop_times.txt can be large — use index-based parsing and filter to known trips
    private func parseStopTimes() throws {
        let url = Self.cacheDir.appendingPathComponent("stop_times.txt")
        let content = try String(contentsOf: url, encoding: .utf8)

        var lines = content.components(separatedBy: "\n")
        guard !lines.isEmpty else { return }
        if lines[0].hasPrefix("\u{FEFF}") { lines[0] = String(lines[0].dropFirst()) }

        let headers = csvSplitLine(lines[0].trimmingCharacters(in: .whitespacesAndNewlines))
        guard let tripCol = headers.firstIndex(of: "trip_id"),
            let stopCol = headers.firstIndex(of: "stop_id"),
            let depCol = headers.firstIndex(of: "departure_time")
        else { throw GTFSError.missingColumns("stop_times.txt") }

        let maxNeeded = max(tripCol, stopCol, depCol)

        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let row = csvSplitLine(trimmed)
            guard row.count > maxNeeded else { continue }
            let tripId = row[tripCol]
            // Only store stop times for trips we know about (filters non-relevant lines)
            guard !tripId.isEmpty, let trip = trips[tripId] else { continue }
            let stopId = row[stopCol]
            stopTimes[tripId, default: []].append((stopId: stopId, departureTime: row[depCol]))
            // Build line→stops index for the settings station picker
            lineStops[trip.routeId, default: []].insert(stopId)
        }
    }

    // MARK: - Computing Departures

    private func computeDepartures(lineId: String, stopId: String, destinationStopId: String?, directionId: Int, maxTrains: Int)
        -> [TrainDeparture]
    {
        let now = Date()
        let cal = Calendar.central  // always Central — safe when laptop TZ changes

        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd"
        df.timeZone = .centralTime
        let todayStr = df.string(from: now)

        let tf = DateFormatter()
        tf.dateFormat = "HH:mm:ss"
        tf.timeZone = .centralTime
        let nowTimeStr = tf.string(from: now)

        let weekday = cal.component(.weekday, from: now)  // 1=Sun … 7=Sat

        // Build active service set for today
        var activeServices = Set<String>()
        for (sid, svc) in services {
            guard todayStr >= svc.startDate && todayStr <= svc.endDate else { continue }
            let runs: Bool
            switch weekday {
            case 1: runs = svc.sunday
            case 2: runs = svc.monday
            case 3: runs = svc.tuesday
            case 4: runs = svc.wednesday
            case 5: runs = svc.thursday
            case 6: runs = svc.friday
            case 7: runs = svc.saturday
            default: runs = false
            }
            if runs { activeServices.insert(sid) }
        }
        // Apply calendar_dates exceptions
        for (sid, exceptions) in calendarExceptions {
            for exc in exceptions where exc.date == todayStr {
                if exc.type == 1 {
                    activeServices.insert(sid)
                } else if exc.type == 2 {
                    activeServices.remove(sid)
                }
            }
        }

        // Find matching stop times
        var departures: [TrainDeparture] = []

        for (tripId, trip) in trips {
            guard trip.routeId == lineId else { continue }
            // When destination is set, direction is implied by stop order; skip directionId filter
            if destinationStopId == nil {
                guard trip.directionId == directionId else { continue }
            }
            guard activeServices.contains(trip.serviceId) else { continue }

            guard let entries = stopTimes[tripId],
                let depIdx = entries.firstIndex(where: { $0.stopId == stopId })
            else { continue }
            let entry = entries[depIdx]

            // If a destination stop is configured, require it appears after the departure stop
            if let destId = destinationStopId {
                guard let destIdx = entries.firstIndex(where: { $0.stopId == destId }),
                    destIdx > depIdx else { continue }
            }

            let depTimeStr = entry.departureTime
            // Simple string compare works for zero-padded HH:MM:SS (handles up to 23:59:59)
            guard depTimeStr >= nowTimeStr else { continue }

            guard let depDate = parseGTFSTime(depTimeStr, referenceDate: now, calendar: cal)
            else { continue }

            let minutesUntil = max(0, Int(depDate.timeIntervalSince(now) / 60))
            departures.append(
                TrainDeparture(
                    id: tripId,
                    tripId: tripId,
                    scheduledTime: depDate,
                    delaySeconds: 0,
                    minutesUntil: minutesUntil,
                    isRealTime: false
                ))
        }

        return
            departures
            .sorted { $0.scheduledTime < $1.scheduledTime }
            .prefix(maxTrains)
            .map { $0 }
    }

    /// Converts a GTFS "HH:MM:SS" time (may exceed 24h for overnight service) to a Date.
    private func parseGTFSTime(_ timeStr: String, referenceDate: Date, calendar: Calendar) -> Date?
    {
        let parts = timeStr.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let h = parts[0]
        let m = parts[1]
        let s = parts[2]

        var comps = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        comps.hour = h % 24
        comps.minute = m
        comps.second = s
        guard var date = calendar.date(from: comps) else { return nil }
        if h >= 24 { date.addTimeInterval(TimeInterval((h / 24) * 86400)) }
        return date
    }

    // MARK: - CSV Parsing

    /// Returns (headers, rows) where each row is an array of field values.
    private func splitCSV(_ content: String) -> ([String], [[String]]) {
        var lines = content.components(separatedBy: "\n")
        guard !lines.isEmpty else { return ([], []) }
        if lines[0].hasPrefix("\u{FEFF}") { lines[0] = String(lines[0].dropFirst()) }

        let headers = csvSplitLine(lines[0].trimmingCharacters(in: .whitespacesAndNewlines))
        let rows = lines.dropFirst().compactMap { line -> [String]? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : csvSplitLine(trimmed)
        }
        return (headers, rows)
    }

    /// RFC 4180-compatible CSV line splitter (handles double-quoted fields).
    private func csvSplitLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for ch in line {
            switch ch {
            case "\"":
                inQuotes.toggle()
            case "," where !inQuotes:
                fields.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            default:
                current.append(ch)
            }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }
}
