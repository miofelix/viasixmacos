import Foundation

public enum DefaultResourceInstaller {
    public static func install(into paths: AppPaths, using fileManager: FileManager = .default) throws {
        try paths.prepare(using: fileManager)
        try copyIfMissing(resource: "ip", extension: "txt", to: paths.ipv4List, using: fileManager)
        try copyIfMissing(resource: "ipv6", extension: "txt", to: paths.ipv6List, using: fileManager)
        try copyIfMissing(resource: "template", extension: "json", to: paths.templateConfig, using: fileManager)
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
