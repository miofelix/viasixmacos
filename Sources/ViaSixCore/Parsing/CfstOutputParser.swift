import Foundation

public enum CfstOutputEvent: Equatable, Sendable {
    case line(String)
    case progress(current: Int, total: Int)
    case heartbeat(bytes: Int64)
}

public struct CfstOutputParser: Sendable {
    private var carry = Data()
    private var totalBytes: Int64 = 0
    private var lastProgress: (Int, Int)?
    private var lastHeartbeat: Date?
    private var emittedLines = 0

    public init() {}

    public mutating func consume(_ data: Data, now: Date = Date()) -> [CfstOutputEvent] {
        guard !data.isEmpty else { return [] }
        totalBytes += Int64(data.count)
        carry.append(data)
        var events: [CfstOutputEvent] = []
        if lastHeartbeat == nil || now.timeIntervalSince(lastHeartbeat!) >= 0.25 {
            events.append(.heartbeat(bytes: totalBytes))
            lastHeartbeat = now
        }

        while let newlineIndex = carry.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let delimiter = carry[newlineIndex]
            let lineData = carry.prefix(upTo: newlineIndex)
            carry.removeFirst(carry.distance(from: carry.startIndex, to: newlineIndex) + 1)
            if delimiter == 0x0D && carry.first == 0x0A { carry.removeFirst() }
            events.append(contentsOf: parseLine(Data(lineData)))
        }

        if let progress = parseProgress(in: String(decoding: carry, as: UTF8.self)) {
            events.append(progress)
        }

        if carry.count > 16_384 {
            carry.removeFirst(carry.count - 4_096)
        }
        return events
    }

    public mutating func finish() -> [CfstOutputEvent] {
        guard !carry.isEmpty else { return [] }
        let data = carry
        carry.removeAll(keepingCapacity: true)
        return parseLine(data)
    }

    private mutating func parseLine(_ data: Data) -> [CfstOutputEvent] {
        let raw = String(decoding: data, as: UTF8.self)
        let clean =
            raw
            .replacingOccurrences(of: "\u{001B}\\[[0-9;]*[a-zA-Z]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }

        if let progress = parseProgress(in: clean) {
            return [progress]
        }
        guard emittedLines < 50 else { return [] }
        emittedLines += 1
        return [.line(clean)]
    }

    private mutating func parseProgress(in text: String) -> CfstOutputEvent? {
        guard let match = text.matches(of: /(?<current>\d+)\s*\/\s*(?<total>\d+)\s*\[/).last,
            let current = Int(match.current), let total = Int(match.total), total > 0
        else {
            return nil
        }
        if lastProgress?.0 != current || lastProgress?.1 != total {
            lastProgress = (current, total)
            return .progress(current: current, total: total)
        }
        return nil
    }
}
