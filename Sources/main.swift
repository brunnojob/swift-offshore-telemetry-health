import Foundation

enum Failure: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let message): return message } }
}
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure.invalid(message) }
}
func numeric(_ value: String) throws -> Double {
    guard let parsed = Double(value), parsed.isFinite else { throw Failure.invalid("Finite number required") }
    return parsed
}
func input(_ columns: Int) throws -> [[String]] {
    var rows: [[String]] = []
    while let line = readLine() {
        try require(rows.count < 100000, "Input capacity exceeded")
        let fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        try require(fields.count == columns && fields.allSatisfy { !$0.isEmpty }, "Invalid CSV row")
        rows.append(fields)
    }
    try require(!rows.isEmpty, "Missing input")
    return rows
}
func output<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    guard let text = String(data: data, encoding: .utf8) else { throw Failure.invalid("Encoding failed") }
    print(text)
}

struct Packet { let received: Double; let source: Double; let tag: String; let sequence: UInt16 }
struct Health: Codable {
    let tag: String
    let packets: Int
    let lost: Int
    let duplicate: Int
    let averageLatency: Double
    let latencyDeviation: Double
    let age: Double
    let stale: Bool
}
struct Channel {
    var count = 0
    var lost = 0
    var duplicates = 0
    var previous: UInt16? = nil
    var source = 0.0
    var mean = 0.0
    var m2 = 0.0
    mutating func accept(_ packet: Packet) throws {
        try require(packet.received >= packet.source && packet.source >= 0, "Invalid clock relationship")
        if let sequence = previous {
            let distance = packet.sequence &- sequence
            if distance == 0 { duplicates += 1; return }
            try require(distance < 32768 && packet.source >= source, "Out-of-order channel")
            lost += Int(distance) - 1
        }
        previous = packet.sequence; source = packet.source; count += 1
        let latency = packet.received - packet.source
        let delta = latency - mean
        mean += delta / Double(count); m2 += delta * (latency - mean)
    }
}
func analyze(_ packets: [Packet]) throws -> [Health] {
    var channels: [String: Channel] = [:]
    var now = -1.0
    for p in packets {
        try require(p.received >= now, "Receipt time must not decrease"); now = p.received
        var c = channels[p.tag] ?? Channel(); try c.accept(p); channels[p.tag] = c
    }
    return channels.keys.sorted().map { tag in
        let c = channels[tag]!
        return Health(tag: tag, packets: c.count, lost: c.lost, duplicate: c.duplicates, averageLatency: c.mean, latencyDeviation: c.count > 1 ? sqrt(c.m2 / Double(c.count - 1)) : 0, age: now - c.source, stale: now - c.source > 2)
    }
}
func test() throws {
    let result = try analyze([Packet(received: 0.1, source: 0, tag: "P", sequence: 65535), Packet(received: 1.1, source: 1, tag: "P", sequence: 0), Packet(received: 2.1, source: 2, tag: "P", sequence: 2), Packet(received: 2.2, source: 2, tag: "P", sequence: 2)])
    try require(result[0].packets == 3 && result[0].lost == 1 && result[0].duplicate == 1, "Sequence accounting mismatch")
    try require(abs(result[0].averageLatency - 0.1) < 1e-9, "Latency mismatch")
}
func run() throws {
    let packets = try input(4).map { row -> Packet in
        guard let sequence = UInt16(row[3]) else { throw Failure.invalid("Invalid sequence") }
        return Packet(received: try numeric(row[0]), source: try numeric(row[1]), tag: row[2], sequence: sequence)
    }
    for health in try analyze(packets) { try output(health) }
}

do {
    if Array(CommandLine.arguments.dropFirst()) == ["--self-test"] { try test(); print("Tests passed") }
    else { try run() }
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(2)
}
