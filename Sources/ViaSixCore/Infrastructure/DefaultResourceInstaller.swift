import Foundation

public enum DefaultResourceInstaller {
    private static let legacyIPv4List = """
    173.245.48.0/20
    103.21.244.0/22
    103.22.200.0/22
    103.31.4.0/22
    141.101.64.0/18
    108.162.192.0/18
    190.93.240.0/20
    188.114.96.0/20
    197.234.240.0/22
    198.41.128.0/17
    162.158.0.0/15
    104.16.0.0/12

    """

    public static func install(into paths: AppPaths, using fileManager: FileManager = .default) throws {
        try paths.prepare(using: fileManager)
        try installIPv4List(to: paths.ipv4List, using: fileManager)
        try copyIfMissing(resource: "ipv6", extension: "txt", to: paths.ipv6List, using: fileManager)
        try copyIfMissing(resource: "template", extension: "json", to: paths.templateConfig, using: fileManager)
    }

    private static func installIPv4List(to destination: URL, using fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: destination.path) else {
            try copyIfMissing(resource: "ip", extension: "txt", to: destination, using: fileManager)
            return
        }

        let installedData = try Data(contentsOf: destination)
        guard installedData == Data(legacyIPv4List.utf8) else { return }
        guard let source = resourceURL(named: "ip", extension: "txt") else {
            throw ResourceError.missing("ip.txt")
        }
        try Data(contentsOf: source).write(to: destination, options: .atomic)
    }

    private static func copyIfMissing(
        resource: String,
        extension: String,
        to destination: URL,
        using fileManager: FileManager
    ) throws {
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        guard let source = resourceURL(named: resource, extension: `extension`) else {
            throw ResourceError.missing(resource + "." + `extension`)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private static func resourceURL(named resource: String, extension: String) -> URL? {
        if let packaged = Bundle.main.url(forResource: resource, withExtension: `extension`) {
            return packaged
        }
        return Bundle.module.url(forResource: resource, withExtension: `extension`)
    }
}

public enum ResourceError: LocalizedError, Equatable, Sendable {
    case missing(String)

    public var errorDescription: String? {
        switch self {
        case .missing(let name): "缺少内置资源：\(name)"
        }
    }
}
