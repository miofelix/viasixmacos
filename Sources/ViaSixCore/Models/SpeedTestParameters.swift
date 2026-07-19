import Foundation

public struct SpeedTestParameters: Codable, Equatable, Sendable {
    public var ipFile: String
    public var ipRange: String
    public var threads: Int
    public var pingCount: Int
    public var downloadCount: Int
    public var downloadTime: Int
    public var latencyUpperBound: Int
    public var latencyLowerBound: Int
    public var lossRateUpperBound: Double
    public var speedLowerBound: Double
    public var colo: String
    public var port: Int
    public var url: String
    public var httping: Bool
    public var httpingCode: Int
    public var disableDownload: Bool
    public var allIP: Bool
    public var debug: Bool

    public init(
        ipFile: String = "",
        ipRange: String = "",
        threads: Int = 200,
        pingCount: Int = 4,
        downloadCount: Int = 10,
        downloadTime: Int = 10,
        latencyUpperBound: Int = 9_999,
        latencyLowerBound: Int = 0,
        lossRateUpperBound: Double = 1.0,
        speedLowerBound: Double = 0,
        colo: String = "",
        port: Int = 443,
        url: String = "",
        httping: Bool = true,
        httpingCode: Int = 0,
        disableDownload: Bool = false,
        allIP: Bool = false,
        debug: Bool = false
    ) {
        self.ipFile = ipFile
        self.ipRange = ipRange
        self.threads = threads
        self.pingCount = pingCount
        self.downloadCount = downloadCount
        self.downloadTime = downloadTime
        self.latencyUpperBound = latencyUpperBound
        self.latencyLowerBound = latencyLowerBound
        self.lossRateUpperBound = lossRateUpperBound
        self.speedLowerBound = speedLowerBound
        self.colo = colo
        self.port = port
        self.url = url
        self.httping = httping
        self.httpingCode = httpingCode
        self.disableDownload = disableDownload
        self.allIP = allIP
        self.debug = debug
    }

    public static func defaults(ipv6File: URL) -> Self {
        Self(ipFile: ipv6File.path)
    }

    public func validated() throws -> Self {
        guard !ipFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !ipRange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.missingIPSource
        }
        guard (1...1_000).contains(threads) else {
            throw ValidationError.outOfRange("线程数应在 1 到 1000 之间")
        }
        guard (1...100).contains(pingCount) else {
            throw ValidationError.outOfRange("Ping 次数应在 1 到 100 之间")
        }
        guard (0...100).contains(downloadCount) else {
            throw ValidationError.outOfRange("下载测速数量应在 0 到 100 之间")
        }
        guard (1...3_600).contains(downloadTime) else {
            throw ValidationError.outOfRange("单 IP 下载时长应在 1 到 3600 秒之间")
        }
        guard (0...999_999).contains(latencyLowerBound), (1...999_999).contains(latencyUpperBound),
              latencyLowerBound <= latencyUpperBound else {
            throw ValidationError.outOfRange("延迟上下限不合法")
        }
        guard (0...1).contains(lossRateUpperBound) else {
            throw ValidationError.outOfRange("丢包率应在 0 到 1 之间")
        }
        guard speedLowerBound.isFinite, speedLowerBound >= 0 else {
            throw ValidationError.outOfRange("速度下限不合法")
        }
        guard (1...65_535).contains(port) else {
            throw ValidationError.outOfRange("端口应在 1 到 65535 之间")
        }
        guard httpingCode == 0 || (100...599).contains(httpingCode) else {
            throw ValidationError.outOfRange("HTTP 状态码应为 0 或 100 到 599")
        }
        return self
    }

    public func commandLineArguments(resultURL: URL) throws -> [String] {
        let parameters = try validated()
        var args = [
            "-o", resultURL.path,
            "-tp", String(parameters.port),
            "-n", String(parameters.threads),
            "-t", String(parameters.pingCount),
            "-dn", String(parameters.downloadCount),
            "-dt", String(parameters.downloadTime),
            "-tl", String(parameters.latencyUpperBound),
            "-tll", String(parameters.latencyLowerBound),
            "-tlr", parameters.lossRateUpperBound.cliString,
            "-sl", parameters.speedLowerBound.cliString,
            "-p", "0"
        ]

        if !parameters.ipRange.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(contentsOf: ["-ip", parameters.ipRange.trimmingCharacters(in: .whitespacesAndNewlines)])
        } else {
            args.append(contentsOf: ["-f", parameters.ipFile])
        }
        if parameters.httping {
            args.append("-httping")
            if parameters.httpingCode > 0 {
                args.append(contentsOf: ["-httping-code", String(parameters.httpingCode)])
            }
        }
        if !parameters.colo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(contentsOf: ["-cfcolo", parameters.colo.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        if !parameters.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(contentsOf: ["-url", parameters.url.trimmingCharacters(in: .whitespacesAndNewlines)])
        }
        if parameters.disableDownload { args.append("-dd") }
        if parameters.allIP { args.append("-allip") }
        if parameters.debug { args.append("-debug") }
        return args
    }

    private enum CodingKeys: String, CodingKey {
        case ipFile, ipRange, threads, pingCount, downloadCount, downloadTime
        case latencyUpperBound, latencyLowerBound, lossRateUpperBound, speedLowerBound
        case colo, port, url, httping, httpingCode, disableDownload, allIP, debug
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            ipFile: try values.decodeIfPresent(String.self, forKey: .ipFile) ?? "",
            ipRange: try values.decodeIfPresent(String.self, forKey: .ipRange) ?? "",
            threads: try values.decodeIfPresent(Int.self, forKey: .threads) ?? 200,
            pingCount: try values.decodeIfPresent(Int.self, forKey: .pingCount) ?? 4,
            downloadCount: try values.decodeIfPresent(Int.self, forKey: .downloadCount) ?? 10,
            downloadTime: try values.decodeIfPresent(Int.self, forKey: .downloadTime) ?? 10,
            latencyUpperBound: try values.decodeIfPresent(Int.self, forKey: .latencyUpperBound) ?? 9_999,
            latencyLowerBound: try values.decodeIfPresent(Int.self, forKey: .latencyLowerBound) ?? 0,
            lossRateUpperBound: try values.decodeIfPresent(Double.self, forKey: .lossRateUpperBound) ?? 1.0,
            speedLowerBound: try values.decodeIfPresent(Double.self, forKey: .speedLowerBound) ?? 0,
            colo: try values.decodeIfPresent(String.self, forKey: .colo) ?? "",
            port: try values.decodeIfPresent(Int.self, forKey: .port) ?? 443,
            url: try values.decodeIfPresent(String.self, forKey: .url) ?? "",
            httping: try values.decodeIfPresent(Bool.self, forKey: .httping) ?? true,
            httpingCode: try values.decodeIfPresent(Int.self, forKey: .httpingCode) ?? 0,
            disableDownload: try values.decodeIfPresent(Bool.self, forKey: .disableDownload) ?? false,
            allIP: try values.decodeIfPresent(Bool.self, forKey: .allIP) ?? false,
            debug: try values.decodeIfPresent(Bool.self, forKey: .debug) ?? false
        )
    }
}

public enum SpeedTestParameterError: LocalizedError, Equatable, Sendable {
    case missingIPSource
    case outOfRange(String)

    public var errorDescription: String? {
        switch self {
        case .missingIPSource: "请选择 IP 文件或填写 IP 段"
        case .outOfRange(let message): message
        }
    }
}

private extension Double {
    var cliString: String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), self)
    }
}

public typealias ValidationError = SpeedTestParameterError

