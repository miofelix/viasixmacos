import CryptoKit
import Foundation

public enum RuntimeArchitecture: String, CaseIterable, Codable, Hashable, Sendable {
    case arm64
    case x8664 = "x86_64"

    public static var current: Self {
        #if arch(arm64)
            .arm64
        #elseif arch(x86_64)
            .x8664
        #else
            #error("ViaSix runtime components only support arm64 and x86_64 on macOS")
        #endif
    }
}

public enum RuntimeComponent: String, CaseIterable, Codable, Hashable, Sendable {
    case cfst
    case mihomo

    public var displayName: String {
        switch self {
        case .cfst: "CloudflareSpeedTest"
        case .mihomo: "Mihomo"
        }
    }

    public var repositoryURL: URL {
        switch self {
        case .cfst: URL(string: "https://github.com/XIU2/CloudflareSpeedTest")!
        case .mihomo: URL(string: "https://github.com/MetaCubeX/mihomo")!
        }
    }

    var payloadFiles: [RuntimePayloadFile] {
        switch self {
        case .cfst: [.cfst]
        case .mihomo: [.mihomo]
        }
    }
}

public enum RuntimePayloadFile: String, CaseIterable, Codable, Hashable, Sendable {
    case cfst
    case mihomo

    public var component: RuntimeComponent {
        switch self {
        case .cfst:
            .cfst
        case .mihomo:
            .mihomo
        }
    }

    public var requiresExecutablePermission: Bool {
        switch self {
        case .cfst, .mihomo:
            true
        }
    }
}

public enum RuntimeArchiveFormat: Codable, Equatable, Hashable, Sendable {
    case zip
    case gzip(output: RuntimePayloadFile)
}

public struct RuntimePayloadExpectation: Codable, Equatable, Hashable, Sendable {
    public let file: RuntimePayloadFile
    public let byteCount: Int64?
    public let sha256: String?

    public init(
        file: RuntimePayloadFile,
        byteCount: Int64? = nil,
        sha256: String? = nil
    ) {
        self.file = file
        self.byteCount = byteCount
        self.sha256 = sha256?.lowercased()
    }
}

public struct RuntimeAsset: Codable, Equatable, Hashable, Sendable {
    public let component: RuntimeComponent
    public let version: String
    public let architecture: RuntimeArchitecture
    public let archiveName: String
    public let archiveFormat: RuntimeArchiveFormat
    public let downloadURL: URL
    public let sha256: String
    public let payloadExpectations: [RuntimePayloadExpectation]

    public init(
        component: RuntimeComponent,
        version: String,
        architecture: RuntimeArchitecture,
        archiveName: String,
        archiveFormat: RuntimeArchiveFormat,
        downloadURL: URL,
        sha256: String,
        payloadExpectations: [RuntimePayloadExpectation]
    ) {
        self.component = component
        self.version = version
        self.architecture = architecture
        self.archiveName = archiveName
        self.archiveFormat = archiveFormat
        self.downloadURL = downloadURL
        self.sha256 = sha256.lowercased()
        self.payloadExpectations = payloadExpectations
    }
}

public struct RuntimeManifest: Equatable, Sendable {
    public static let cfstVersion = "2.3.5"
    public static let mihomoVersion = "1.19.29"

    public let assets: [RuntimeAsset]

    public init(assets: [RuntimeAsset]) {
        self.assets = assets
    }

    public func asset(
        for component: RuntimeComponent,
        architecture: RuntimeArchitecture
    ) -> RuntimeAsset? {
        assets.first {
            $0.component == component && $0.architecture == architecture
        }
    }

    public func assets(for architecture: RuntimeArchitecture) -> [RuntimeAsset] {
        RuntimeComponent.allCases.compactMap {
            asset(for: $0, architecture: architecture)
        }
    }

    public static let current = RuntimeManifest(
        assets: [
            RuntimeAsset(
                component: .cfst,
                version: cfstVersion,
                architecture: .arm64,
                archiveName: "cfst_darwin_arm64.zip",
                archiveFormat: .zip,
                downloadURL: URL(
                    string: "https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.5/cfst_darwin_arm64.zip"
                )!,
                sha256: "0623f6d24c939e3d3716f556f4d39c7b8781cf6600ee838a1b64e6b2fe4609dc",
                payloadExpectations: [
                    RuntimePayloadExpectation(
                        file: .cfst,
                        byteCount: 7_739_890,
                        sha256: "c98628414b8812a78c36de0b7fd50066a9fda57347658c212f32f9796dea064a"
                    )
                ]
            ),
            RuntimeAsset(
                component: .cfst,
                version: cfstVersion,
                architecture: .x8664,
                archiveName: "cfst_darwin_amd64.zip",
                archiveFormat: .zip,
                downloadURL: URL(
                    string: "https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.5/cfst_darwin_amd64.zip"
                )!,
                sha256: "66ce3ae89430e851cab9710d54b6d91324e0aae255f0c92a91072d57724561d5",
                payloadExpectations: [
                    RuntimePayloadExpectation(
                        file: .cfst,
                        byteCount: 8_151_056,
                        sha256: "899f2db79f3a68d60d35dbaf7f0c34ccbbe3c3ef06d9c8db1a411f99df91c9bf"
                    )
                ]
            ),
            RuntimeAsset(
                component: .mihomo,
                version: mihomoVersion,
                architecture: .arm64,
                archiveName: "mihomo-darwin-arm64-v1.19.29.gz",
                archiveFormat: .gzip(output: .mihomo),
                downloadURL: URL(
                    string:
                        "https://github.com/MetaCubeX/mihomo/releases/download/v1.19.29/mihomo-darwin-arm64-v1.19.29.gz"
                )!,
                sha256: "4dc25df9e899f14161911302a8ee5fc9e202ed9c976fc405bf82c50ff27466ca",
                payloadExpectations: [
                    RuntimePayloadExpectation(
                        file: .mihomo,
                        byteCount: 43_229_330,
                        sha256: "ec66e3e883bdc3fca06753784e324e08921e13239f8e945587cb1bfbf4c6b936"
                    )
                ]
            ),
            RuntimeAsset(
                component: .mihomo,
                version: mihomoVersion,
                architecture: .x8664,
                archiveName: "mihomo-darwin-amd64-v1-v1.19.29.gz",
                archiveFormat: .gzip(output: .mihomo),
                downloadURL: URL(
                    string:
                        "https://github.com/MetaCubeX/mihomo/releases/download/v1.19.29/mihomo-darwin-amd64-v1-v1.19.29.gz"
                )!,
                sha256: "addf68bf604e05cce5334e949bb8915dd68b25744669b320f7d4c1e240ab92a0",
                payloadExpectations: [
                    RuntimePayloadExpectation(
                        file: .mihomo,
                        byteCount: 47_015_456,
                        sha256: "a139a209965e34ef30fac77ea9bfa9e6ab63c01cad6f94804131fd7f4a552c02"
                    )
                ]
            ),
        ]
    )
}

public enum RuntimeSHA256 {
    public static func hexDigest(of data: Data) -> String {
        hexString(SHA256.hash(data: data))
    }

    public static func hexDigest(ofFileAt fileURL: URL) throws -> String {
        try Task.checkCancellation()
        let file = try FileHandle(forReadingFrom: fileURL)
        defer { try? file.close() }

        var hasher = SHA256()
        while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        try Task.checkCancellation()
        return hexString(hasher.finalize())
    }

    private static func hexString<Digest: Sequence>(_ digest: Digest) -> String
    where Digest.Element == UInt8 {
        let digits = Array("0123456789abcdef".utf8)
        var result = [UInt8]()
        result.reserveCapacity(64)
        for byte in digest {
            result.append(digits[Int(byte >> 4)])
            result.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: result, as: UTF8.self)
    }
}
