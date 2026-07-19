import Foundation

public enum SpeedTestResultParser {
    public static func parse(data: Data) throws -> [SpeedTestResult] {
        try parse(rows: CSVParser.parse(data: data))
    }

    public static func parse(rows: [[String]]) throws -> [SpeedTestResult] {
        guard rows.count > 1 else { return [] }
        return rows.dropFirst().compactMap { row in
            guard row.count >= 6 else { return nil }
            let values = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !values[0].isEmpty else { return nil }
            return SpeedTestResult(
                ip: values[0],
                sent: values[1],
                received: values[2],
                loss: values[3],
                latency: values[4],
                speed: values[5],
                region: values.count > 6 ? values[6] : ""
            )
        }
    }
}

