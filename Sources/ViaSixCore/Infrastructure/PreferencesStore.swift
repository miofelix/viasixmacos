import Foundation

public actor PreferencesStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func load(defaults: UserPreferences) -> UserPreferences {
        guard let data = try? Data(contentsOf: fileURL),
              let value = try? decoder.decode(UserPreferences.self, from: data) else {
            return defaults
        }
        return value
    }

    public func save(_ preferences: UserPreferences) throws {
        let data = try encoder.encode(preferences)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

