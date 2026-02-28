import Foundation

// MARK: - Lightweight binary protobuf parser for GTFS-RT
// Only parses the fields needed for trip update filtering and display.
// Field numbers from the GTFS Realtime protobuf spec.

enum ProtoError: Error { case truncated }

struct ProtoReader {
    let data: Data
    var pos: Int = 0
    var isAtEnd: Bool { pos >= data.count }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while pos < data.count {
            let b = UInt64(data[pos]); pos += 1
            result |= (b & 0x7F) << shift
            if b & 0x80 == 0 { return result }
            shift += 7
        }
        throw ProtoError.truncated
    }

    mutating func readBytes() throws -> Data {
        let len = Int(try readVarint())
        guard pos + len <= data.count else { throw ProtoError.truncated }
        defer { pos += len }
        return Data(data[pos..<pos+len])
    }

    mutating func readString() throws -> String {
        String(bytes: try readBytes(), encoding: .utf8) ?? ""
    }

    // Returns (fieldNumber, wireType) or nil at end of message
    mutating func nextTag() throws -> (field: UInt64, wire: UInt64)? {
        guard !isAtEnd else { return nil }
        let t = try readVarint()
        return (t >> 3, t & 7)
    }

    mutating func skip(wire: UInt64) throws {
        switch wire {
        case 0: _ = try readVarint()
        case 1:
            guard pos + 8 <= data.count else { throw ProtoError.truncated }
            pos += 8
        case 2: _ = try readBytes()
        case 5:
            guard pos + 4 <= data.count else { throw ProtoError.truncated }
            pos += 4
        default: throw ProtoError.truncated
        }
    }
}

// MARK: - Parsed structs (only fields used for filtering and display)

struct RTEntity {
    var id: String = ""
    var tripUpdate: RTTripUpdate?
}

struct RTTripUpdate {
    var trip: RTTripDescriptor = RTTripDescriptor()
    var stopTimes: [RTStopTimeUpdate] = []
}

struct RTTripDescriptor {
    var tripId: String?
    var routeId: String?
    var directionId: Int?
}

struct RTStopTimeUpdate {
    var stopId: String?
    var stopSequence: Int?
    var arrival: RTStopTimeEvent?
    var departure: RTStopTimeEvent?
}

struct RTStopTimeEvent {
    var delay: Int?
    var time: Int64?
}

// MARK: - Top-level parse entry point

func parseGTFSRTFeed(_ data: Data) throws -> [RTEntity] {
    var r = ProtoReader(data: data)
    var entities: [RTEntity] = []
    while let (f, w) = try r.nextTag() {
        if f == 2 {
            // entity field — parse each one, skip errors so one bad entity doesn't fail all
            if let entity = try? parseRTEntity(try r.readBytes()) {
                entities.append(entity)
            }
        } else {
            try r.skip(wire: w)
        }
    }
    return entities
}

// MARK: - Message parsers

private func parseRTEntity(_ data: Data) throws -> RTEntity {
    var r = ProtoReader(data: data)
    var e = RTEntity()
    while let (f, w) = try r.nextTag() {
        switch f {
        case 1: e.id = try r.readString()                          // id
        case 3: e.tripUpdate = try parseRTTripUpdate(try r.readBytes())  // trip_update
        default: try r.skip(wire: w)
        }
    }
    return e
}

private func parseRTTripUpdate(_ data: Data) throws -> RTTripUpdate {
    var r = ProtoReader(data: data)
    var u = RTTripUpdate()
    while let (f, w) = try r.nextTag() {
        switch f {
        case 1: u.trip = try parseRTTripDescriptor(try r.readBytes())       // trip
        case 2: u.stopTimes.append(try parseRTStopTimeUpdate(try r.readBytes()))  // stop_time_update
        default: try r.skip(wire: w)
        }
    }
    return u
}

private func parseRTTripDescriptor(_ data: Data) throws -> RTTripDescriptor {
    var r = ProtoReader(data: data)
    var d = RTTripDescriptor()
    while let (f, w) = try r.nextTag() {
        switch f {
        case 1: d.tripId = try r.readString()               // trip_id
        case 5: d.routeId = try r.readString()              // route_id
        case 6: d.directionId = Int(try r.readVarint())     // direction_id (uint32)
        default: try r.skip(wire: w)
        }
    }
    return d
}

private func parseRTStopTimeUpdate(_ data: Data) throws -> RTStopTimeUpdate {
    var r = ProtoReader(data: data)
    var u = RTStopTimeUpdate()
    while let (f, w) = try r.nextTag() {
        switch f {
        case 1: u.stopSequence = Int(try r.readVarint())                       // stop_sequence (uint32)
        case 2: u.arrival = try parseRTStopTimeEvent(try r.readBytes())        // arrival
        case 3: u.departure = try parseRTStopTimeEvent(try r.readBytes())      // departure
        case 4: u.stopId = try r.readString()                                   // stop_id
        default: try r.skip(wire: w)
        }
    }
    return u
}

private func parseRTStopTimeEvent(_ data: Data) throws -> RTStopTimeEvent {
    var r = ProtoReader(data: data)
    var e = RTStopTimeEvent()
    while let (f, w) = try r.nextTag() {
        switch f {
        // delay: int32 — negative values sign-extend to 64 bits in varint encoding
        case 1: e.delay = Int(Int64(bitPattern: try r.readVarint()))
        // time: int64 — Unix timestamp in seconds
        case 2: e.time = Int64(bitPattern: try r.readVarint())
        default: try r.skip(wire: w)
        }
    }
    return e
}
