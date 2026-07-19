import CryptoKit
import Foundation

public enum RuntimeArchitecture: String, CaseIterable, Codable, Hashable, Sendable {
    case arm64
    case x86_64

    public static var current: Self {
        #if arch(arm64)
        .arm64
        #elseif arch(x86_64)
        .x86_64
        #else
        #error("ViaSix runtime components only support arm64 and x86_64 on macOS")
        #endif
    }
}

public enum RuntimeComponent: String, CaseIterable, Codable, Hashable, Sendable {
    case cfst
    case xray
}

public enum RuntimePayloadFile: String, CaseIterable, Codable, Hashable, Sendable {
    case cfst
    case xray
    case geoIP = "geoip.dat"
    case geoSite = "geosite.dat"

    public var component: RuntimeComponent {
        switch self {
        case .cfst:
            .cfst
        case .xray, .geoIP, .geoSite:
            .xray
        }
    }

    public var requiresExecutablePermission: Bool {
        switch self {
        case .cfst, .xray:
            true
        case .geoIP, .geoSite:
            false
        }
    }
}

public struct RuntimeAsset: Codable, Equatable, Hashable, Sendable {
    public let component: RuntimeComponent
    public let version: String
    public let architecture: RuntimeArchitecture
    public let archiveName: String
    public let downloadURL: URL
    public let sha256: String
    public let payloadFiles: [RuntimePayloadFile]

    public init(
        component: RuntimeComponent,
        version: String,
        architecture: RuntimeArchitecture,
        archiveName: String,
        downloadURL: URL,
        sha256: String,
        payloadFiles: [RuntimePayloadFile]
    ) {
        self.component = component
        self.version = version
        self.architecture = architecture
        self.archiveName = archiveName
        self.downloadURL = downloadURL
        self.sha256 = sha256.lowercased()
        self.payloadFiles = payloadFiles
    }
}

public struct RuntimeManifest: Equatable, Sendable {
    public static let cfstVersion = "2.3.5"
    public static let xrayVersion = "26.3.27"

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
                downloadURL: URL(
                    string: "https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.5/cfst_darwin_arm64.zip"
                )!,
                sha256: "0623f6d24c939e3d3716f556f4d39c7b8781cf6600ee838a1b64e6b2fe4609dc",
                payloadFiles: [.cfst]
            ),
            RuntimeAsset(
                component: .cfst,
                version: cfstVersion,
                architecture: .x86_64,
                archiveName: "cfst_darwin_amd64.zip",
                downloadURL: URL(
                    string: "https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.5/cfst_darwin_amd64.zip"
                )!,
                sha256: "66ce3ae89430e851cab9710d54b6d91324e0aae255f0c92a91072d57724561d5",
                payloadFiles: [.cfst]
            ),
            RuntimeAsset(
                component: .xray,
                version: xrayVersion,
                architecture: .arm64,
                archiveName: "Xray-macos-arm64-v8a.zip",
                downloadURL: URL(
                    string: "https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-macos-arm64-v8a.zip"
                )!,
                sha256: "2e93a67e8aa1936ecefb307e120830fcbd4c643ab9b1c46a2d0838d5f8409eaf",
                payloadFiles: [.xray, .geoIP, .geoSite]
            ),
            RuntimeAsset(
                component: .xray,
                version: xrayVersion,
                architecture: .x86_64,
                archiveName: "Xray-macos-64.zip",
                downloadURL: URL(
                    string: "https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-macos-64.zip"
                )!,
                sha256: "f5b0471d3459eff1b82e48af0aeac186abcc3298210070afbbbd8437a4e8b203",
                payloadFiles: [.xray, .geoIP, .geoSite]
            )
        ]
    )
}

public enum RuntimeSHA256 {
    public static func hexDigest(of data: Data) -> String {
        hexString(SHA256.hash(data: data))
    }

    public static func hexDigest(ofFileAt fileURL: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: fileURL)
        defer { try? file.close() }

        var hasher = SHA256()
        while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
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
