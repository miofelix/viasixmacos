import Foundation

public enum CSVParser {
    public static func parse(data: Data) throws -> [[String]] {
        try parse(string: String(decoding: data, as: UTF8.self))
    }

    public static func parse(string: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = String()
        var quoted = false
        var justClosedQuote = false
        let scalars = Array(string.unicodeScalars)
        var index = 0

        func appendField() {
            row.append(field)
            field.removeAll(keepingCapacity: true)
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if quoted {
                if scalar == "\"" {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    quoted = false
                    justClosedQuote = true
                } else {
                    field.unicodeScalars.append(scalar)
                }
                index += 1
                continue
            }

            if scalar == "\"" && field.isEmpty {
                quoted = true
                justClosedQuote = false
                index += 1
                continue
            }
            if justClosedQuote {
                if scalar == " " || scalar == "\t" {
                    index += 1
                    continue
                }
                justClosedQuote = false
            }
            switch scalar {
            case ",":
                appendField()
            case "\n":
                appendField()
                rows.append(row)
                row.removeAll(keepingCapacity: true)
            case "\r":
                appendField()
                rows.append(row)
                row.removeAll(keepingCapacity: true)
                if index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
            default:
                field.unicodeScalars.append(scalar)
            }
            index += 1
        }

        guard !quoted else { throw CSVError.unclosedQuote }
        if !field.isEmpty || !row.isEmpty || string.hasSuffix(",") {
            appendField()
            rows.append(row)
        }
        if let first = rows.first, first.first?.hasPrefix("\u{feff}") == true {
            rows[0][0].removeFirst()
        }
        return rows
    }
}

public enum CSVError: LocalizedError, Equatable, Sendable {
    case unclosedQuote

    public var errorDescription: String? { "CSV 包含未闭合的引号" }
}
