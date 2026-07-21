import Darwin
import Foundation

public enum TunSessionPhase: String, Codable, CaseIterable, Sendable {
    case preparing
    case running
    case restoring
    case stopped
    case failed
}

public struct TunSessionJournal: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    fileprivate static let maximumLastErrorBytes = 4_096

    public let schemaVersion: Int
    public let sessionIdentifier: UUID
    public let ownerUserIdentifier: UInt32
    public var phase: TunSessionPhase
    public var cleanupRequired: Bool
    public var processIdentifier: Int32?
    public var routingModeRawValue: Int?
    public var tunInterfaceName: String?
    public let createdAt: Date
    public var updatedAt: Date
    public var lastError: String?

    public init(
        sessionIdentifier: UUID = UUID(),
        ownerUserIdentifier: UInt32,
        phase: TunSessionPhase,
        cleanupRequired: Bool,
        processIdentifier: Int32? = nil,
        routingModeRawValue: Int? = nil,
        tunInterfaceName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.sessionIdentifier = sessionIdentifier
        self.ownerUserIdentifier = ownerUserIdentifier
        self.phase = phase
        self.cleanupRequired = cleanupRequired
        self.processIdentifier = processIdentifier
        self.routingModeRawValue = routingModeRawValue
        self.tunInterfaceName = tunInterfaceName
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.lastError = lastError
    }

    public var recoveryPending: Bool {
        cleanupRequired || phase == .preparing || phase == .running || phase == .restoring
    }

    fileprivate func validated() throws -> Self {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw TunSessionJournalError.unsupportedSchemaVersion(schemaVersion)
        }
        guard updatedAt >= createdAt else {
            throw TunSessionJournalError.invalidJournal("更新时间早于创建时间")
        }
        guard ownerUserIdentifier > 0 else {
            throw TunSessionJournalError.invalidJournal("会话用户无效")
        }
        if let processIdentifier, processIdentifier <= 1 {
            throw TunSessionJournalError.invalidJournal("会话进程标识无效")
        }
        if let routingModeRawValue, !(0...2).contains(routingModeRawValue) {
            throw TunSessionJournalError.invalidJournal("会话路由模式无效")
        }
        if let tunInterfaceName,
            !Self.isValidTunInterfaceName(tunInterfaceName)
        {
            throw TunSessionJournalError.invalidJournal("TUN 接口名称无效")
        }
        if let lastError, lastError.utf8.count > Self.maximumLastErrorBytes {
            throw TunSessionJournalError.invalidJournal("错误信息过长")
        }
        return self
    }

    private static func isValidTunInterfaceName(_ name: String) -> Bool {
        guard name.hasPrefix("utun") else { return false }
        let suffix = name.dropFirst(4)
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }
}

public enum TunSessionJournalError: LocalizedError, Equatable, Sendable {
    case invalidRootDirectory(String)
    case insecureOwnership(expected: UInt32, actual: UInt32)
    case insecureGroup(expected: UInt32, actual: UInt32)
    case insecurePermissions(UInt16)
    case invalidJournalFile(String)
    case journalTooLarge(Int64)
    case unsupportedSchemaVersion(Int)
    case invalidJournal(String)
    case recoveryBackendUnavailable
    case staleSession(expected: UUID, actual: UUID)
    case posix(operation: String, code: Int32)

    public var errorDescription: String? {
        switch self {
        case .invalidRootDirectory(let path):
            "虚拟网卡恢复目录无效：\(path)"
        case .insecureOwnership(let expected, let actual):
            "虚拟网卡恢复目录所有者无效（需要 \(expected)，实际 \(actual)）"
        case .insecureGroup(let expected, let actual):
            "虚拟网卡恢复目录所属组无效（需要 \(expected)，实际 \(actual)）"
        case .insecurePermissions(let mode):
            "虚拟网卡恢复目录权限不安全：\(String(mode, radix: 8))"
        case .invalidJournalFile(let reason):
            "虚拟网卡恢复记录无效：\(reason)"
        case .journalTooLarge(let size):
            "虚拟网卡恢复记录过大：\(size) 字节"
        case .unsupportedSchemaVersion(let version):
            "虚拟网卡恢复记录版本不受支持：\(version)"
        case .invalidJournal(let reason):
            "虚拟网卡恢复记录内容无效：\(reason)"
        case .recoveryBackendUnavailable:
            "虚拟网卡恢复后端不可用，恢复记录已保留"
        case .staleSession(let expected, let actual):
            "虚拟网卡会话已变化（需要 \(expected)，实际 \(actual)）"
        case .posix(let operation, let code):
            "虚拟网卡恢复记录操作失败（\(operation)，errno \(code)）"
        }
    }
}

/// Stores the privileged session record in a directory that cannot be
/// replaced or edited by the GUI user. File writes use a same-directory
/// temporary file, fsync, and rename so launchd or machine crashes cannot
/// expose a partially encoded journal.
public struct TunSessionJournalStore: Sendable {
    public static let systemDirectory = URL(
        fileURLWithPath: "/Library/Application Support/com.felix.viasix",
        isDirectory: true
    )

    private static let journalFileName = "tun-session.json"
    private static let maximumJournalSize: Int64 = 1_048_576

    public let rootDirectoryURL: URL
    public let expectedOwnerUserIdentifier: UInt32
    public let expectedOwnerGroupIdentifier: UInt32

    public init(
        rootDirectoryURL: URL = Self.systemDirectory,
        expectedOwnerUserIdentifier: UInt32 = 0,
        expectedOwnerGroupIdentifier: UInt32 = 0
    ) {
        self.rootDirectoryURL = rootDirectoryURL.standardizedFileURL
        self.expectedOwnerUserIdentifier = expectedOwnerUserIdentifier
        self.expectedOwnerGroupIdentifier = expectedOwnerGroupIdentifier
    }

    public func load() throws -> TunSessionJournal? {
        let directory = try openRootDirectory(createIfMissing: true)
        defer { close(directory) }

        let descriptor = openat(
            directory,
            Self.journalFileName,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw posixError("openat(journal)")
        }
        defer { close(descriptor) }

        let metadata = try validateJournalDescriptor(descriptor)
        guard metadata.st_size <= Self.maximumJournalSize else {
            throw TunSessionJournalError.journalTooLarge(metadata.st_size)
        }

        var data = Data()
        data.reserveCapacity(Int(metadata.st_size))
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count == 0 { break }
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError("read(journal)")
            }
            data.append(buffer, count: count)
            if data.count > Self.maximumJournalSize {
                throw TunSessionJournalError.journalTooLarge(Int64(data.count))
            }
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            return try decoder.decode(TunSessionJournal.self, from: data).validated()
        } catch let error as TunSessionJournalError {
            throw error
        } catch {
            throw TunSessionJournalError.invalidJournalFile(error.localizedDescription)
        }
    }

    public func save(_ journal: TunSessionJournal) throws {
        let journal = try journal.validated()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(journal)
        guard data.count <= Self.maximumJournalSize else {
            throw TunSessionJournalError.journalTooLarge(Int64(data.count))
        }

        let directory = try openRootDirectory(createIfMissing: true)
        defer { close(directory) }

        let temporaryName = ".tun-session.\(UUID().uuidString).tmp"
        let descriptor = openat(
            directory,
            temporaryName,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            mode_t(S_IRUSR | S_IWUSR)
        )
        guard descriptor >= 0 else { throw posixError("openat(temporary journal)") }

        var shouldRemoveTemporaryFile = true
        defer {
            close(descriptor)
            if shouldRemoveTemporaryFile {
                _ = unlinkat(directory, temporaryName, 0)
            }
        }

        guard
            fchown(
                descriptor,
                expectedOwnerUserIdentifier,
                expectedOwnerGroupIdentifier
            ) == 0
        else {
            throw posixError("fchown(temporary journal)")
        }
        guard fchmod(descriptor, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
            throw posixError("fchmod(temporary journal)")
        }

        try data.withUnsafeBytes { rawBuffer in
            guard var baseAddress = rawBuffer.baseAddress else { return }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let written = write(descriptor, baseAddress, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw posixError("write(temporary journal)")
                }
                guard written > 0 else {
                    throw TunSessionJournalError.invalidJournalFile("写入没有取得进展")
                }
                remaining -= written
                baseAddress = baseAddress.advanced(by: written)
            }
        }

        guard fsync(descriptor) == 0 else { throw posixError("fsync(temporary journal)") }
        guard
            renameat(directory, temporaryName, directory, Self.journalFileName) == 0
        else {
            throw posixError("renameat(journal)")
        }
        shouldRemoveTemporaryFile = false
        guard fsync(directory) == 0 else { throw posixError("fsync(journal directory)") }
    }

    public func remove() throws {
        let directory = try openRootDirectory(createIfMissing: true)
        defer { close(directory) }
        if unlinkat(directory, Self.journalFileName, 0) != 0, errno != ENOENT {
            throw posixError("unlinkat(journal)")
        }
        guard fsync(directory) == 0 else { throw posixError("fsync(journal directory)") }
    }

    private func openRootDirectory(createIfMissing: Bool) throws -> Int32 {
        let parentURL = rootDirectoryURL.deletingLastPathComponent()
        let directoryName = rootDirectoryURL.lastPathComponent
        guard
            rootDirectoryURL.isFileURL,
            !directoryName.isEmpty,
            directoryName != ".",
            directoryName != ".."
        else {
            throw TunSessionJournalError.invalidRootDirectory(rootDirectoryURL.path)
        }

        let parent = open(
            parentURL.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard parent >= 0 else { throw posixError("open(journal parent)") }
        defer { close(parent) }

        var created = false
        if createIfMissing {
            if mkdirat(parent, directoryName, mode_t(S_IRWXU)) == 0 {
                created = true
            } else if errno != EEXIST {
                throw posixError("mkdirat(journal directory)")
            }
        }

        let directory = openat(
            parent,
            directoryName,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard directory >= 0 else { throw posixError("openat(journal directory)") }

        do {
            if created {
                guard
                    fchown(
                        directory,
                        expectedOwnerUserIdentifier,
                        expectedOwnerGroupIdentifier
                    ) == 0
                else {
                    throw posixError("fchown(journal directory)")
                }
                guard fchmod(directory, mode_t(S_IRWXU)) == 0 else {
                    throw posixError("fchmod(journal directory)")
                }
            } else {
                try migrateLegacyRootGroupIfSafe(
                    directory,
                    parent: parent
                )
            }
            var metadata = stat()
            guard fstat(directory, &metadata) == 0 else {
                throw posixError("fstat(journal directory)")
            }
            guard metadata.st_mode & S_IFMT == S_IFDIR else {
                throw TunSessionJournalError.invalidRootDirectory(rootDirectoryURL.path)
            }
            guard metadata.st_uid == expectedOwnerUserIdentifier else {
                throw TunSessionJournalError.insecureOwnership(
                    expected: expectedOwnerUserIdentifier,
                    actual: metadata.st_uid
                )
            }
            guard metadata.st_gid == expectedOwnerGroupIdentifier else {
                throw TunSessionJournalError.insecureGroup(
                    expected: expectedOwnerGroupIdentifier,
                    actual: metadata.st_gid
                )
            }
            if metadata.st_mode & mode_t(S_IRWXG | S_IRWXO) != 0 {
                guard fchmod(directory, mode_t(S_IRWXU)) == 0 else {
                    throw posixError("fchmod(journal directory)")
                }
            }
            return directory
        } catch {
            close(directory)
            throw error
        }
    }

    private func validateJournalDescriptor(_ descriptor: Int32) throws -> stat {
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw posixError("fstat(journal)")
        }
        guard metadata.st_mode & S_IFMT == S_IFREG, metadata.st_nlink == 1 else {
            throw TunSessionJournalError.invalidJournalFile("文件类型或链接数无效")
        }
        guard metadata.st_uid == expectedOwnerUserIdentifier else {
            throw TunSessionJournalError.insecureOwnership(
                expected: expectedOwnerUserIdentifier,
                actual: metadata.st_uid
            )
        }
        guard metadata.st_gid == expectedOwnerGroupIdentifier else {
            throw TunSessionJournalError.insecureGroup(
                expected: expectedOwnerGroupIdentifier,
                actual: metadata.st_gid
            )
        }
        let exposedPermissions = metadata.st_mode & mode_t(S_IRWXG | S_IRWXO)
        guard exposedPermissions == 0 else {
            throw TunSessionJournalError.insecurePermissions(UInt16(metadata.st_mode & 0o777))
        }
        return metadata
    }

    private func migrateLegacyRootGroupIfSafe(
        _ directory: Int32,
        parent: Int32
    ) throws {
        var metadata = stat()
        guard fstat(directory, &metadata) == 0 else {
            throw posixError("fstat(journal directory migration)")
        }
        guard
            metadata.st_gid != expectedOwnerGroupIdentifier,
            metadata.st_uid == expectedOwnerUserIdentifier,
            UInt16(metadata.st_mode & 0o7777) == 0o700,
            UInt32(geteuid()) == expectedOwnerUserIdentifier
        else { return }

        // Older builds inherited group `admin` from /Library/Application
        // Support. With owner root and mode 0700, changing only the group to
        // wheel does not widen access and keeps Runtime and journal contracts
        // consistent across upgrades.
        guard
            fchown(
                directory,
                expectedOwnerUserIdentifier,
                expectedOwnerGroupIdentifier
            ) == 0
        else {
            throw posixError("fchown(legacy journal directory)")
        }
        guard fsync(directory) == 0 else {
            throw posixError("fsync(legacy journal directory)")
        }
        guard fsync(parent) == 0 else {
            throw posixError("fsync(journal parent)")
        }
    }

    private func posixError(_ operation: String) -> TunSessionJournalError {
        .posix(operation: operation, code: errno)
    }
}

public final class TunSessionJournalController: @unchecked Sendable {
    private let lock = NSLock()
    private let store: TunSessionJournalStore
    private let now: @Sendable () -> Date

    public init(
        store: TunSessionJournalStore = TunSessionJournalStore(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.now = now
    }

    public func currentJournal() throws -> TunSessionJournal? {
        try lock.withLock { try store.load() }
    }

    public func recoveryPending() throws -> Bool {
        try currentJournal()?.recoveryPending ?? false
    }

    /// Reports that this helper build cannot safely recover a pending session
    /// without changing the recovery evidence on disk.
    public func rejectPendingRecoveryWithoutBackend() throws {
        try lock.withLock {
            guard try store.load()?.recoveryPending == true else { return }
            throw TunSessionJournalError.recoveryBackendUnavailable
        }
    }

    @discardableResult
    public func begin(ownerUserIdentifier: UInt32) throws -> TunSessionJournal {
        try lock.withLock {
            if let existing = try store.load(), existing.recoveryPending {
                throw TunSessionJournalError.invalidJournal("已有会话等待恢复")
            }
            let journal = TunSessionJournal(
                ownerUserIdentifier: ownerUserIdentifier,
                phase: .preparing,
                cleanupRequired: true,
                createdAt: now()
            )
            try store.save(journal)
            return journal
        }
    }

    @discardableResult
    public func markRunning(sessionIdentifier: UUID) throws -> TunSessionJournal {
        try transition(
            sessionIdentifier: sessionIdentifier,
            phase: .running,
            cleanupRequired: true,
            lastError: nil
        )
    }

    @discardableResult
    public func recordProcess(
        sessionIdentifier: UUID,
        processIdentifier: Int32,
        routingModeRawValue: Int
    ) throws -> TunSessionJournal {
        try lock.withLock {
            guard var journal = try store.load() else {
                throw TunSessionJournalError.invalidJournal("会话不存在")
            }
            try requireSession(journal, sessionIdentifier: sessionIdentifier)
            guard processIdentifier > 1 else {
                throw TunSessionJournalError.invalidJournal("会话进程标识无效")
            }
            guard (0...2).contains(routingModeRawValue) else {
                throw TunSessionJournalError.invalidJournal("会话路由模式无效")
            }
            journal.processIdentifier = processIdentifier
            journal.routingModeRawValue = routingModeRawValue
            journal.updatedAt = max(now(), journal.createdAt)
            try store.save(journal)
            return journal
        }
    }

    @discardableResult
    public func updateRoutingMode(
        sessionIdentifier: UUID,
        routingModeRawValue: Int
    ) throws -> TunSessionJournal {
        try lock.withLock {
            guard var journal = try store.load() else {
                throw TunSessionJournalError.invalidJournal("会话不存在")
            }
            try requireSession(journal, sessionIdentifier: sessionIdentifier)
            guard (0...2).contains(routingModeRawValue) else {
                throw TunSessionJournalError.invalidJournal("会话路由模式无效")
            }
            journal.routingModeRawValue = routingModeRawValue
            journal.updatedAt = max(now(), journal.createdAt)
            try store.save(journal)
            return journal
        }
    }

    @discardableResult
    public func recordTunInterface(
        sessionIdentifier: UUID,
        interfaceName: String
    ) throws -> TunSessionJournal {
        try lock.withLock {
            guard var journal = try store.load() else {
                throw TunSessionJournalError.invalidJournal("会话不存在")
            }
            try requireSession(journal, sessionIdentifier: sessionIdentifier)
            guard interfaceName.hasPrefix("utun"),
                !interfaceName.dropFirst(4).isEmpty,
                interfaceName.dropFirst(4).allSatisfy(\.isNumber)
            else {
                throw TunSessionJournalError.invalidJournal("TUN 接口名称无效")
            }
            journal.tunInterfaceName = interfaceName
            journal.updatedAt = max(now(), journal.createdAt)
            try store.save(journal)
            return journal
        }
    }

    @discardableResult
    public func markRestoring(sessionIdentifier: UUID) throws -> TunSessionJournal {
        try transition(
            sessionIdentifier: sessionIdentifier,
            phase: .restoring,
            cleanupRequired: true,
            lastError: nil
        )
    }

    public func markFailed(
        sessionIdentifier: UUID,
        error: any Error,
        cleanupRequired: Bool = true
    ) throws {
        _ = try transition(
            sessionIdentifier: sessionIdentifier,
            phase: .failed,
            cleanupRequired: cleanupRequired,
            lastError: boundedUTF8Prefix(
                error.localizedDescription,
                maximumBytes: TunSessionJournal.maximumLastErrorBytes
            )
        )
    }

    public func complete(sessionIdentifier: UUID) throws {
        try lock.withLock {
            guard var journal = try store.load() else { return }
            try requireSession(journal, sessionIdentifier: sessionIdentifier)
            journal.phase = .stopped
            journal.cleanupRequired = false
            journal.updatedAt = max(now(), journal.createdAt)
            journal.lastError = nil
            try store.save(journal)
            try store.remove()
        }
    }

    public func recoverIfNeeded(cleanup: (TunSessionJournal) throws -> Void) throws {
        try lock.withLock {
            guard var journal = try store.load(), journal.recoveryPending else { return }
            journal.phase = .restoring
            journal.cleanupRequired = true
            journal.updatedAt = max(now(), journal.createdAt)
            journal.lastError = nil
            try store.save(journal)

            do {
                try cleanup(journal)
                journal.phase = .stopped
                journal.cleanupRequired = false
                journal.updatedAt = max(now(), journal.createdAt)
                try store.save(journal)
                try store.remove()
            } catch {
                journal.phase = .failed
                journal.cleanupRequired = true
                journal.updatedAt = max(now(), journal.createdAt)
                journal.lastError = boundedUTF8Prefix(
                    error.localizedDescription,
                    maximumBytes: TunSessionJournal.maximumLastErrorBytes
                )
                try? store.save(journal)
                throw error
            }
        }
    }

    private func transition(
        sessionIdentifier: UUID,
        phase: TunSessionPhase,
        cleanupRequired: Bool,
        lastError: String?
    ) throws -> TunSessionJournal {
        try lock.withLock {
            guard var journal = try store.load() else {
                throw TunSessionJournalError.invalidJournal("会话不存在")
            }
            try requireSession(journal, sessionIdentifier: sessionIdentifier)
            journal.phase = phase
            journal.cleanupRequired = cleanupRequired
            journal.updatedAt = max(now(), journal.createdAt)
            journal.lastError = lastError
            try store.save(journal)
            return journal
        }
    }

    private func requireSession(
        _ journal: TunSessionJournal,
        sessionIdentifier: UUID
    ) throws {
        guard journal.sessionIdentifier == sessionIdentifier else {
            throw TunSessionJournalError.staleSession(
                expected: sessionIdentifier,
                actual: journal.sessionIdentifier
            )
        }
    }
}

private func boundedUTF8Prefix(_ value: String, maximumBytes: Int) -> String {
    guard value.utf8.count > maximumBytes else { return value }

    var result = String()
    var byteCount = 0
    for character in value {
        let characterBytes = String(character).utf8.count
        guard byteCount + characterBytes <= maximumBytes else { break }
        result.append(character)
        byteCount += characterBytes
    }
    return result
}
