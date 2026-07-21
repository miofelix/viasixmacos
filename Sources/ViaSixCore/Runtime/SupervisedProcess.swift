import Darwin
import Foundation

/// The direct child started by the app is a small supervisor. It launches the
/// requested executable in the same process group and watches a pipe that is
/// held open by the app. When the app exits unexpectedly, the kernel closes
/// that pipe and the supervisor terminates the whole group.
struct SupervisedProcess: Sendable {
    let pid: pid_t
    let processGroup: pid_t
    let output: SupervisedProcessOutput
    let lifetime: ProcessLifetime

    static func start(
        executableURL: URL,
        arguments: [String],
        workingDirectoryURL: URL,
        environmentOverrides: [String: String] = [:],
        inheritParentEnvironment: Bool = true
    ) throws -> Self {
        var outputDescriptors: [Int32] = [-1, -1]
        guard Darwin.pipe(&outputDescriptors) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var lifetimeDescriptors: [Int32] = [-1, -1]
        var shouldCloseOutputReadDescriptor = true
        var shouldCloseLifetimeWriteDescriptor = true
        defer {
            if shouldCloseOutputReadDescriptor {
                Self.closeIfValid(outputDescriptors[0])
            }
            Self.closeIfValid(outputDescriptors[1])
            Self.closeIfValid(lifetimeDescriptors[0])
            if shouldCloseLifetimeWriteDescriptor {
                Self.closeIfValid(lifetimeDescriptors[1])
            }
        }

        guard Darwin.pipe(&lifetimeDescriptors) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        // A pipe can occupy stdin/stdout/stderr when a host process started
        // without standard descriptors. Move all source descriptors away
        // from those slots before constructing dup2/close file actions.
        try Self.moveOutOfStandardDescriptorRange(&outputDescriptors)
        try Self.moveOutOfStandardDescriptorRange(&lifetimeDescriptors)
        try (outputDescriptors + lifetimeDescriptors).forEach(Self.setCloseOnExec)

        var fileActions: posix_spawn_file_actions_t?
        var spawnAttributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            throw POSIXError(.EIO)
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        guard posix_spawnattr_init(&spawnAttributes) == 0 else {
            throw POSIXError(.EIO)
        }
        defer { posix_spawnattr_destroy(&spawnAttributes) }

        try check(
            posix_spawn_file_actions_adddup2(
                &fileActions,
                outputDescriptors[1],
                STDOUT_FILENO
            ))
        try check(
            posix_spawn_file_actions_adddup2(
                &fileActions,
                outputDescriptors[1],
                STDERR_FILENO
            ))
        try check(
            posix_spawn_file_actions_adddup2(
                &fileActions,
                lifetimeDescriptors[0],
                STDIN_FILENO
            ))
        try check(posix_spawn_file_actions_addclose(&fileActions, outputDescriptors[0]))
        try check(posix_spawn_file_actions_addclose(&fileActions, outputDescriptors[1]))
        try check(posix_spawn_file_actions_addclose(&fileActions, lifetimeDescriptors[0]))
        try check(posix_spawn_file_actions_addclose(&fileActions, lifetimeDescriptors[1]))
        try workingDirectoryURL.path.withCString { path in
            try check(posix_spawn_file_actions_addchdir_np(&fileActions, path))
        }

        try check(posix_spawnattr_setflags(&spawnAttributes, Int16(POSIX_SPAWN_SETPGROUP)))
        try check(posix_spawnattr_setpgroup(&spawnAttributes, 0))

        let supervisorURL = URL(fileURLWithPath: "/bin/sh")
        let argumentStrings =
            [
                supervisorURL.path,
                "-c",
                Self.supervisorScript,
                "viasix-process-supervisor",
                executableURL.path,
            ] + arguments
        var argv = argumentStrings.map { strdup($0) }
        defer { argv.forEach { free($0) } }
        argv.append(nil)

        let baseEnvironment = inheritParentEnvironment ? ProcessInfo.processInfo.environment : [:]
        let environment = baseEnvironment.merging(
            environmentOverrides,
            uniquingKeysWith: { _, override in override }
        )
        let environmentStrings = environment.map { "\($0.key)=\($0.value)" }.sorted()
        var envp = environmentStrings.map { strdup($0) }
        defer { envp.forEach { free($0) } }
        envp.append(nil)

        var pid: pid_t = 0
        let spawnResult = supervisorURL.path.withCString { executablePath in
            posix_spawn(
                &pid,
                executablePath,
                &fileActions,
                &spawnAttributes,
                &argv,
                &envp
            )
        }
        try check(spawnResult)

        shouldCloseOutputReadDescriptor = false
        shouldCloseLifetimeWriteDescriptor = false
        return Self(
            pid: pid,
            processGroup: pid,
            output: SupervisedProcessOutput(fileDescriptor: outputDescriptors[0]),
            lifetime: ProcessLifetime(fileDescriptor: lifetimeDescriptors[1])
        )
    }

    /// The runtime and watchdog intentionally share the supervisor's process
    /// group. Redirecting the watchdog's output prevents it from keeping the
    /// app's output pipe open after the runtime exits.
    private static let supervisorScript = #"""
        runtime=$1
        shift

        exec 3<&0
        exec 0<&-
        "$runtime" "$@" 3<&- </dev/null &
        runtime_pid=$!

        # Install this after launching the runtime so it retains the default
        # SIGTERM disposition. The supervisor stays alive to reap the runtime.
        trap '' TERM

        (
          trap '' TERM
          while IFS= read -r _ <&3; do :; done

          kill -TERM 0 2>/dev/null || true

          attempts=0
          while kill -0 "$runtime_pid" 2>/dev/null && [ "$attempts" -lt 40 ]; do
            attempts=$((attempts + 1))
            sleep 0.05
          done

          kill -KILL 0 2>/dev/null || true
        ) >/dev/null 2>&1 &

        exec 3<&-
        wait "$runtime_pid"
        status=$?

        exit "$status"
        """#

    private static func moveOutOfStandardDescriptorRange(
        _ descriptors: inout [Int32]
    ) throws {
        for index in descriptors.indices where descriptors[index] <= STDERR_FILENO {
            let duplicate = Darwin.fcntl(descriptors[index], F_DUPFD_CLOEXEC, 3)
            guard duplicate != -1 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            Darwin.close(descriptors[index])
            descriptors[index] = duplicate
        }
    }

    private static func setCloseOnExec(_ descriptor: Int32) throws {
        let flags = Darwin.fcntl(descriptor, F_GETFD)
        guard flags != -1, Darwin.fcntl(descriptor, F_SETFD, flags | FD_CLOEXEC) != -1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func closeIfValid(_ descriptor: Int32) {
        if descriptor >= 0 {
            Darwin.close(descriptor)
        }
    }

    private static func check(_ status: Int32) throws {
        guard status != 0 else { return }
        throw POSIXError(POSIXErrorCode(rawValue: status) ?? .EIO)
    }
}

/// Parent-owned write end of the supervisor lifetime pipe.
final class ProcessLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var fileDescriptor: Int32?

    init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard let descriptor = fileDescriptor else { return }
        fileDescriptor = nil
        Darwin.close(descriptor)
    }

    deinit {
        close()
    }
}

final class SupervisedProcessOutput: @unchecked Sendable {
    let fileDescriptor: Int32

    init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }
}

struct SupervisedProcessTermination: Sendable {
    let status: Int32
}

enum SupervisedProcessControl {
    static func waitForProcess(_ pid: pid_t) -> SupervisedProcessTermination {
        var waitStatus: Int32 = 0
        while Darwin.waitpid(pid, &waitStatus, 0) == -1 {
            if errno == EINTR { continue }
            return SupervisedProcessTermination(status: -1)
        }

        let signal = waitStatus & 0x7f
        if signal == 0 {
            return SupervisedProcessTermination(status: (waitStatus >> 8) & 0xff)
        }
        return SupervisedProcessTermination(status: 128 + signal)
    }

    static func killRemainingGroupIfNeeded(_ processGroup: pid_t) {
        if processGroupExists(processGroup) {
            _ = Darwin.kill(-processGroup, SIGKILL)
        }
    }

    static func processGroupExists(_ processGroup: pid_t) -> Bool {
        if Darwin.kill(-processGroup, 0) == 0 { return true }
        return errno == EPERM
    }
}
