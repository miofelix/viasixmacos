import Darwin
import Foundation
import ViaSixMihomoConfig
import ViaSixPrivilegedProtocol
import ViaSixTunHelperSupport

struct TunBackendSnapshot: Sendable {
    let supportedFeatures: TunHelperFeature
    let runtimeState: TunPrivilegedRuntimeState
    let runtimeVersion: String?
    let sessionPhase: TunHelperSessionPhase
    let sessionIdentifier: UUID?
    let ownerUserIdentifier: UInt32?
    let recoveryRequired: Bool
    let routingMode: TunHelperRoutingMode?
    let lastError: String?
}

protocol TunSessionBackend: AnyObject, Sendable {
    func probe() throws -> TunBackendSnapshot
    func status() throws -> TunBackendSnapshot
    func installOrRepairRuntime() throws -> TunBackendSnapshot
    func startSession(
        plan: MihomoPrivilegedRuntimePlan,
        ownerUserIdentifier: UInt32
    ) throws -> TunBackendSnapshot
    func stopSession(requestingUserIdentifier: UInt32) throws -> TunBackendSnapshot
    func setRoutingMode(
        _ routingMode: TunHelperRoutingMode,
        requestingUserIdentifier: UInt32
    ) throws -> TunBackendSnapshot
    func recover(requestingUserIdentifier: UInt32) throws -> TunBackendSnapshot
}

enum PrivilegedTunBackendError: LocalizedError, Equatable, Sendable {
    case runtimeNotReady
    case sessionAlreadyActive
    case sessionNotActive
    case sessionOwnedByAnotherUser
    case processLaunchFailed(String)
    case processExitedDuringStart(String)
    case processDidNotStop(Int32)
    case unsafeSessionDirectory(String)
    case unsafeRecoveryProcess(Int32)
    case readinessTimedOut(String)
    case interfaceDidNotDisappear(String)
    case routingModeRequiresRestart

    var errorDescription: String? {
        switch self {
        case .runtimeNotReady:
            "特权 Mihomo 尚未安装或需要修复"
        case .sessionAlreadyActive:
            "已有虚拟网卡会话正在运行或等待恢复"
        case .sessionNotActive:
            "当前没有可停止的虚拟网卡会话"
        case .sessionOwnedByAnotherUser:
            "虚拟网卡会话由另一位登录用户启动"
        case .processLaunchFailed(let detail):
            "无法启动特权 Mihomo：\(detail)"
        case .processExitedDuringStart(let detail):
            "特权 Mihomo 在 TUN 就绪前退出：\(detail)"
        case .processDidNotStop(let processIdentifier):
            "特权 Mihomo 未能停止（PID \(processIdentifier)）"
        case .unsafeSessionDirectory(let path):
            "TUN 会话目录不安全：\(path)"
        case .unsafeRecoveryProcess(let processIdentifier):
            "拒绝终止无法确认身份的恢复进程（PID \(processIdentifier)）"
        case .readinessTimedOut(let detail):
            "TUN 未在期限内就绪：\(detail)"
        case .interfaceDidNotDisappear(let interfaceName):
            "TUN 进程停止后接口仍然存在：\(interfaceName)"
        case .routingModeRequiresRestart:
            "TUN 路由模式需要由应用重新生成配置并重启会话"
        }
    }
}

/// Single-owner privileged TUN backend.
///
/// The executable is always resolved and verified by `PrivilegedRuntimeManager`.
/// The process receives only fixed `-d` and `-f` arguments pointing into a
/// root-owned session directory derived from the journal UUID.
final class PrivilegedTunBackend: TunSessionBackend, @unchecked Sendable {
    private static let tunDirectoryName = "Tun"
    private static let configFileName = "config.yaml"
    private static let homeDirectoryName = "Home"
    private static let readinessTimeout: TimeInterval = 10
    private static let gracefulStopTimeout: TimeInterval = 5
    private static let interfaceRemovalTimeout: TimeInterval = 3

    private let lock = NSLock()
    private let runtimeManager: PrivilegedRuntimeManager
    private let journalController: TunSessionJournalController
    private let fileManager: FileManager
    private let containerDirectoryURL: URL
    private var activeProcess: ManagedTunProcess?
    private var activeSessionIdentifier: UUID?

    private let features: TunHelperFeature = [
        .fixedRuntimeManagement,
        .sessionLifecycle,
        .recovery,
        .ipv4,
        .ipv6,
        .systemRouting,
        .loopbackPrevention,
        .dnsManagement,
        .networkChangeRecovery,
        .loopbackController,
    ]

    init(
        runtimeManager: PrivilegedRuntimeManager = PrivilegedRuntimeManager(),
        journalController: TunSessionJournalController = TunSessionJournalController(),
        fileManager: FileManager = .default,
        containerDirectoryURL: URL = PrivilegedRuntimeManager.systemContainerDirectory
    ) {
        self.runtimeManager = runtimeManager
        self.journalController = journalController
        self.fileManager = fileManager
        self.containerDirectoryURL = containerDirectoryURL.standardizedFileURL
    }

    func probe() throws -> TunBackendSnapshot {
        try lock.withLock { try snapshotLocked() }
    }

    func status() throws -> TunBackendSnapshot {
        try lock.withLock {
            try reconcileExitedProcessLocked()
            return try snapshotLocked()
        }
    }

    func installOrRepairRuntime() throws -> TunBackendSnapshot {
        try lock.withLock {
            guard activeProcess == nil, try journalController.recoveryPending() == false else {
                throw PrivilegedTunBackendError.sessionAlreadyActive
            }
            _ = try runtimeManager.installBundledRuntime()
            return try snapshotLocked()
        }
    }

    func startSession(
        plan: MihomoPrivilegedRuntimePlan,
        ownerUserIdentifier: UInt32
    ) throws -> TunBackendSnapshot {
        try lock.withLock {
            try reconcileExitedProcessLocked()
            guard activeProcess == nil, try journalController.recoveryPending() == false else {
                throw PrivilegedTunBackendError.sessionAlreadyActive
            }
            guard runtimeStatusLocked().state == .ready else {
                throw PrivilegedTunBackendError.runtimeNotReady
            }

            let journal = try journalController.begin(
                ownerUserIdentifier: ownerUserIdentifier
            )
            let sessionIdentifier = journal.sessionIdentifier
            let sessionDirectory = sessionDirectoryURL(for: sessionIdentifier)
            let baselineTunInterfaces = tunInterfaceNames()

            do {
                let layout = try prepareSessionDirectory(
                    at: sessionDirectory,
                    configuration: plan.configuration
                )
                let process = try runtimeManager.withVerifiedInstalledRuntime { runtime in
                    try ManagedTunProcess(
                        executableURL: runtime.executableURL,
                        configurationURL: layout.configuration,
                        homeURL: layout.home
                    )
                }
                activeProcess = process
                activeSessionIdentifier = sessionIdentifier
                try journalController.recordProcess(
                    sessionIdentifier: sessionIdentifier,
                    processIdentifier: process.processIdentifier,
                    routingModeRawValue: helperRoutingMode(plan.options.routingMode).rawValue
                )
                process.onTermination = { [weak self] processIdentifier, output in
                    self?.recordUnexpectedExit(
                        sessionIdentifier: sessionIdentifier,
                        processIdentifier: processIdentifier,
                        output: output
                    )
                }
                let tunInterfaceName = try waitUntilReady(
                    process: process,
                    baselineTunInterfaces: baselineTunInterfaces,
                    controllerPort: plan.options.externalController?.port
                )
                try journalController.recordTunInterface(
                    sessionIdentifier: sessionIdentifier,
                    interfaceName: tunInterfaceName
                )
                try journalController.markRunning(sessionIdentifier: sessionIdentifier)
                return try snapshotLocked()
            } catch {
                let process = activeProcess
                if let process {
                    process.onTermination = nil
                    process.forceStopIfRunning()
                    let deadline = Date().addingTimeInterval(Self.gracefulStopTimeout)
                    while process.isRunning, Date() < deadline {
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                }
                let cleanupRequired = process?.isRunning == true
                if !cleanupRequired {
                    activeProcess = nil
                    activeSessionIdentifier = nil
                    try? removeSessionDirectory(sessionIdentifier: sessionIdentifier)
                }
                try? journalController.markFailed(
                    sessionIdentifier: sessionIdentifier,
                    error: error,
                    cleanupRequired: cleanupRequired
                )
                throw error
            }
        }
    }

    func stopSession(requestingUserIdentifier: UInt32) throws -> TunBackendSnapshot {
        try lock.withLock {
            try reconcileExitedProcessLocked()
            guard let journal = try journalController.currentJournal(),
                journal.phase != .stopped
            else {
                throw PrivilegedTunBackendError.sessionNotActive
            }
            guard journal.ownerUserIdentifier == requestingUserIdentifier else {
                throw PrivilegedTunBackendError.sessionOwnedByAnotherUser
            }

            _ = try journalController.markRestoring(
                sessionIdentifier: journal.sessionIdentifier
            )
            if let activeProcess,
                activeSessionIdentifier == journal.sessionIdentifier
            {
                activeProcess.onTermination = nil
                try stop(process: activeProcess)
            } else if let processIdentifier = journal.processIdentifier {
                try stopRecoveredProcess(
                    processIdentifier: processIdentifier,
                    sessionIdentifier: journal.sessionIdentifier
                )
            }
            try waitForTunInterfaceRemoval(journal.tunInterfaceName)
            activeProcess = nil
            activeSessionIdentifier = nil
            try removeSessionDirectory(sessionIdentifier: journal.sessionIdentifier)
            try journalController.complete(sessionIdentifier: journal.sessionIdentifier)
            return try snapshotLocked()
        }
    }

    func setRoutingMode(
        _ routingMode: TunHelperRoutingMode,
        requestingUserIdentifier: UInt32
    ) throws -> TunBackendSnapshot {
        try lock.withLock {
            guard let journal = try journalController.currentJournal(),
                journal.phase == .running
            else {
                throw PrivilegedTunBackendError.sessionNotActive
            }
            guard journal.ownerUserIdentifier == requestingUserIdentifier else {
                throw PrivilegedTunBackendError.sessionOwnedByAnotherUser
            }
            _ = routingMode
            throw PrivilegedTunBackendError.routingModeRequiresRestart
        }
    }

    func recover(requestingUserIdentifier: UInt32) throws -> TunBackendSnapshot {
        try lock.withLock {
            if let journal = try journalController.currentJournal(),
                journal.phase != .stopped,
                journal.ownerUserIdentifier != requestingUserIdentifier
            {
                throw PrivilegedTunBackendError.sessionOwnedByAnotherUser
            }
            return try recoverLocked()
        }
    }

    /// The launch daemon owns crash recovery before it accepts any client
    /// connection. This path is intentionally not user-scoped: it reconciles
    /// the root-owned journal left by the previous helper process.
    func recoverAtStartup() throws -> TunBackendSnapshot {
        try lock.withLock { try recoverLocked() }
    }

    private func recoverLocked() throws -> TunBackendSnapshot {
        try journalController.recoverIfNeeded { journal in
            if let activeProcess,
                activeSessionIdentifier == journal.sessionIdentifier
            {
                activeProcess.onTermination = nil
                try stop(process: activeProcess)
            } else if let processIdentifier = journal.processIdentifier {
                try stopRecoveredProcess(
                    processIdentifier: processIdentifier,
                    sessionIdentifier: journal.sessionIdentifier
                )
            }
            try waitForTunInterfaceRemoval(journal.tunInterfaceName)
            try removeSessionDirectory(sessionIdentifier: journal.sessionIdentifier)
        }
        activeProcess = nil
        activeSessionIdentifier = nil
        return try snapshotLocked()
    }

    private func snapshotLocked() throws -> TunBackendSnapshot {
        let runtime = runtimeStatusLocked()
        guard let journal = try journalController.currentJournal() else {
            return TunBackendSnapshot(
                supportedFeatures: features,
                runtimeState: runtime.state,
                runtimeVersion: runtime.version,
                sessionPhase: .inactive,
                sessionIdentifier: nil,
                ownerUserIdentifier: nil,
                recoveryRequired: false,
                routingMode: nil,
                lastError: nil
            )
        }

        let phase: TunHelperSessionPhase
        let recoveryRequired: Bool
        switch journal.phase {
        case .preparing:
            phase = activeProcess?.isRunning == true ? .starting : .recoveryRequired
            recoveryRequired = phase == .recoveryRequired
        case .running:
            if activeProcess?.isRunning == true {
                phase = .running
                recoveryRequired = false
            } else {
                phase = .recoveryRequired
                recoveryRequired = true
            }
        case .restoring:
            phase = .recovering
            recoveryRequired = false
        case .stopped:
            phase = .inactive
            recoveryRequired = false
        case .failed:
            phase = journal.cleanupRequired ? .recoveryRequired : .failed
            recoveryRequired = journal.cleanupRequired
        }

        let routingMode = journal.routingModeRawValue.flatMap(TunHelperRoutingMode.init(rawValue:))
        return TunBackendSnapshot(
            supportedFeatures: features,
            runtimeState: runtime.state,
            runtimeVersion: runtime.version,
            sessionPhase: phase,
            sessionIdentifier: phase == .inactive ? nil : journal.sessionIdentifier,
            ownerUserIdentifier: phase == .inactive ? nil : journal.ownerUserIdentifier,
            recoveryRequired: recoveryRequired,
            routingMode: phase == .inactive ? nil : routingMode,
            lastError: phase == .inactive ? nil : journal.lastError
        )
    }

    private func runtimeStatusLocked() -> (
        state: TunPrivilegedRuntimeState,
        version: String?
    ) {
        do {
            let runtime = try runtimeManager.verifiedInstalledRuntime()
            return (.ready, runtime.manifest.runtimeVersion)
        } catch let error as PrivilegedRuntimeManagerError {
            if case .posix(_, let code) = error, code == ENOENT {
                return (.notInstalled, nil)
            }
            return (.repairRequired, nil)
        } catch {
            return (.repairRequired, nil)
        }
    }

    private func prepareSessionDirectory(
        at sessionDirectory: URL,
        configuration: Data
    ) throws -> (configuration: URL, home: URL) {
        let tunDirectory = containerDirectoryURL.appendingPathComponent(
            Self.tunDirectoryName,
            isDirectory: true
        )
        try createPrivateDirectoryIfNeeded(tunDirectory)
        guard !fileManager.fileExists(atPath: sessionDirectory.path) else {
            throw PrivilegedTunBackendError.unsafeSessionDirectory(sessionDirectory.path)
        }
        try fileManager.createDirectory(
            at: sessionDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        guard chmod(sessionDirectory.path, mode_t(0o700)) == 0 else {
            throw PrivilegedTunBackendError.unsafeSessionDirectory(sessionDirectory.path)
        }
        let home = sessionDirectory.appendingPathComponent(
            Self.homeDirectoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(
            at: home,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        guard chmod(home.path, mode_t(0o700)) == 0 else {
            throw PrivilegedTunBackendError.unsafeSessionDirectory(home.path)
        }
        let configurationURL = sessionDirectory.appendingPathComponent(Self.configFileName)
        try configuration.write(to: configurationURL, options: [.atomic])
        guard chmod(configurationURL.path, mode_t(0o600)) == 0 else {
            throw PrivilegedTunBackendError.unsafeSessionDirectory(configurationURL.path)
        }
        return (configurationURL, home)
    }

    private func createPrivateDirectoryIfNeeded(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue, !isSymbolicLink(url) else {
                throw PrivilegedTunBackendError.unsafeSessionDirectory(url.path)
            }
        } else {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        }
        guard chmod(url.path, mode_t(0o700)) == 0 else {
            throw PrivilegedTunBackendError.unsafeSessionDirectory(url.path)
        }
        var metadata = stat()
        guard lstat(url.path, &metadata) == 0,
            metadata.st_mode & S_IFMT == S_IFDIR,
            metadata.st_uid == 0,
            metadata.st_gid == 0,
            metadata.st_mode & mode_t(0o077) == 0
        else {
            throw PrivilegedTunBackendError.unsafeSessionDirectory(url.path)
        }
    }

    private func isSymbolicLink(_ url: URL) -> Bool {
        var metadata = stat()
        return lstat(url.path, &metadata) == 0 && metadata.st_mode & S_IFMT == S_IFLNK
    }

    private func stop(process: ManagedTunProcess) throws {
        process.requestStop()
        let deadline = Date().addingTimeInterval(Self.gracefulStopTimeout)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.forceStopIfRunning()
        }
        guard !process.isRunning else {
            throw PrivilegedTunBackendError.processDidNotStop(process.processIdentifier)
        }
    }

    private func stopRecoveredProcess(
        processIdentifier: Int32,
        sessionIdentifier: UUID
    ) throws {
        guard processIdentifier > 1 else { return }
        guard kill(processIdentifier, 0) == 0 || errno == EPERM else { return }

        let expectedRuntime =
            containerDirectoryURL
            .appendingPathComponent("Runtime", isDirectory: true)
            .appendingPathComponent("mihomo")
            .standardizedFileURL.path
        guard processPath(processIdentifier) == expectedRuntime else {
            throw PrivilegedTunBackendError.unsafeRecoveryProcess(processIdentifier)
        }
        let expectedHome = sessionDirectoryURL(for: sessionIdentifier)
            .appendingPathComponent(Self.homeDirectoryName, isDirectory: true)
            .standardizedFileURL.path
        guard processCurrentDirectory(processIdentifier) == expectedHome else {
            throw PrivilegedTunBackendError.unsafeRecoveryProcess(processIdentifier)
        }

        _ = kill(processIdentifier, SIGTERM)
        let deadline = Date().addingTimeInterval(Self.gracefulStopTimeout)
        while processExists(processIdentifier), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if processExists(processIdentifier) {
            _ = kill(processIdentifier, SIGKILL)
        }
        guard !processExists(processIdentifier) else {
            throw PrivilegedTunBackendError.processDidNotStop(processIdentifier)
        }
    }

    private func waitUntilReady(
        process: ManagedTunProcess,
        baselineTunInterfaces: Set<String>,
        controllerPort: Int?
    ) throws -> String {
        guard let controllerPort else {
            throw PrivilegedTunBackendError.readinessTimedOut("缺少回环 Controller")
        }
        let deadline = Date().addingTimeInterval(Self.readinessTimeout)
        while Date() < deadline {
            guard process.isRunning else {
                throw PrivilegedTunBackendError.processExitedDuringStart(
                    process.diagnosticOutput.ifEmpty("进程已退出")
                )
            }
            let createdInterfaces = tunInterfaceNames().subtracting(baselineTunInterfaces)
            if let interfaceName = createdInterfaces.sorted().first,
                probeLoopbackTCP(port: controllerPort)
            {
                return interfaceName
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard process.isRunning else {
            throw PrivilegedTunBackendError.processExitedDuringStart(
                process.diagnosticOutput.ifEmpty("进程已退出")
            )
        }
        throw PrivilegedTunBackendError.readinessTimedOut(
            "未同时检测到新 utun 接口与 Controller 监听"
        )
    }

    private func waitForTunInterfaceRemoval(_ interfaceName: String?) throws {
        guard let interfaceName else { return }
        let deadline = Date().addingTimeInterval(Self.interfaceRemovalTimeout)
        while tunInterfaceNames().contains(interfaceName), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard !tunInterfaceNames().contains(interfaceName) else {
            throw PrivilegedTunBackendError.interfaceDidNotDisappear(interfaceName)
        }
    }

    private func tunInterfaceNames() -> Set<String> {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return [] }
        defer { freeifaddrs(head) }

        var result = Set<String>()
        var current: UnsafeMutablePointer<ifaddrs>? = head
        while let entry = current {
            if let namePointer = entry.pointee.ifa_name {
                let name = String(cString: namePointer)
                if name.hasPrefix("utun"),
                    !name.dropFirst(4).isEmpty,
                    name.dropFirst(4).allSatisfy(\.isNumber)
                {
                    result.insert(name)
                }
            }
            current = entry.pointee.ifa_next
        }
        return result
    }

    private func probeLoopbackTCP(port: Int) -> Bool {
        guard (1...65_535).contains(port) else { return false }
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                ) == 0
            }
        }
    }

    private func processPath(_ processIdentifier: Int32) -> String? {
        // The SDK exposes PROC_PIDPATHINFO_MAXSIZE only as a C macro. Keep the
        // documented `4 * MAXPATHLEN` size explicit for Swift.
        var buffer = [CChar](repeating: 0, count: 16_384)
        let length = proc_pidpath(
            processIdentifier,
            &buffer,
            UInt32(buffer.count)
        )
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map(UInt8.init(bitPattern:))
        return String(decoding: bytes, as: UTF8.self)
    }

    private func processCurrentDirectory(_ processIdentifier: Int32) -> String? {
        var information = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard
            proc_pidinfo(
                processIdentifier,
                PROC_PIDVNODEPATHINFO,
                0,
                &information,
                size
            ) == size
        else { return nil }
        return withUnsafePointer(to: &information.pvi_cdir.vip_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
    }

    private func processExists(_ processIdentifier: Int32) -> Bool {
        if kill(processIdentifier, 0) == 0 { return true }
        return errno == EPERM
    }

    private func removeSessionDirectory(sessionIdentifier: UUID) throws {
        let url = sessionDirectoryURL(for: sessionIdentifier)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func sessionDirectoryURL(for identifier: UUID) -> URL {
        containerDirectoryURL
            .appendingPathComponent(Self.tunDirectoryName, isDirectory: true)
            .appendingPathComponent(identifier.uuidString.lowercased(), isDirectory: true)
    }

    private func reconcileExitedProcessLocked() throws {
        guard let activeProcess, !activeProcess.isRunning,
            let sessionIdentifier = activeSessionIdentifier
        else { return }
        let error = PrivilegedTunBackendError.processExitedDuringStart(
            activeProcess.diagnosticOutput.ifEmpty("进程已退出")
        )
        activeProcess.onTermination = nil
        self.activeProcess = nil
        activeSessionIdentifier = nil
        try? removeSessionDirectory(sessionIdentifier: sessionIdentifier)
        try journalController.markFailed(
            sessionIdentifier: sessionIdentifier,
            error: error,
            cleanupRequired: false
        )
    }

    private func recordUnexpectedExit(
        sessionIdentifier: UUID,
        processIdentifier: Int32,
        output: String
    ) {
        lock.withLock {
            guard activeSessionIdentifier == sessionIdentifier,
                activeProcess?.processIdentifier == processIdentifier
            else { return }
            activeProcess?.onTermination = nil
            activeProcess = nil
            activeSessionIdentifier = nil
            try? removeSessionDirectory(sessionIdentifier: sessionIdentifier)
            let error = PrivilegedTunBackendError.processExitedDuringStart(
                output.ifEmpty("进程意外退出")
            )
            try? journalController.markFailed(
                sessionIdentifier: sessionIdentifier,
                error: error,
                cleanupRequired: false
            )
        }
    }

    private func helperRoutingMode(_ mode: MihomoRoutingMode) -> TunHelperRoutingMode {
        switch mode {
        case .rule: .rule
        case .global: .global
        case .direct: .direct
        }
    }
}

private final class ManagedTunProcess: @unchecked Sendable {
    private static let maximumDiagnosticBytes = 64 * 1_024

    private let process: Process
    private let outputPipe: Pipe
    private let outputLock = NSLock()
    private var output = Data()
    private var terminationCallback: (@Sendable (Int32, String) -> Void)?

    init(
        executableURL: URL,
        configurationURL: URL,
        homeURL: URL
    ) throws {
        let process = Process()
        let outputPipe = Pipe()
        self.process = process
        self.outputPipe = outputPipe

        process.executableURL = executableURL
        process.arguments = ["-d", homeURL.path, "-f", configurationURL.path]
        process.currentDirectoryURL = homeURL
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.appendOutput(data)
        }
        process.terminationHandler = { [weak self] process in
            guard let self else { return }
            outputPipe.fileHandleForReading.readabilityHandler = nil
            let remaining = outputPipe.fileHandleForReading.readDataToEndOfFile()
            appendOutput(remaining)
            let callback = outputLock.withLock { terminationCallback }
            callback?(process.processIdentifier, diagnosticOutput)
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            throw PrivilegedTunBackendError.processLaunchFailed(error.localizedDescription)
        }
    }

    var processIdentifier: Int32 { process.processIdentifier }
    var isRunning: Bool { process.isRunning }

    var diagnosticOutput: String {
        outputLock.withLock {
            String(decoding: output, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var onTermination: (@Sendable (Int32, String) -> Void)? {
        get { outputLock.withLock { terminationCallback } }
        set { outputLock.withLock { terminationCallback = newValue } }
    }

    func requestStop() {
        guard process.isRunning else { return }
        process.terminate()
    }

    func forceStopIfRunning() {
        guard process.isRunning else { return }
        _ = kill(process.processIdentifier, SIGKILL)
    }

    private func appendOutput(_ data: Data) {
        guard !data.isEmpty else { return }
        outputLock.withLock {
            output.append(data)
            if output.count > Self.maximumDiagnosticBytes {
                output.removeFirst(output.count - Self.maximumDiagnosticBytes)
            }
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
