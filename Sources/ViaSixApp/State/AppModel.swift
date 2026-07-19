import Foundation
import Observation
import ViaSixCore

@MainActor
@Observable
final class AppModel {
    private(set) var state: AppState

    var parameters: SpeedTestParameters {
        get { state.preferences.parameters }
        set {
            state.preferences.parameters = newValue
            schedulePreferencesSave()
        }
    }

    var ipSourceMode: IPSourceMode {
        state.preferences.ipSourceMode
    }

    let paths: AppPaths

    @ObservationIgnored private let preferencesStore: PreferencesStore
    @ObservationIgnored private let bootstrapper: AppBootstrapper
    @ObservationIgnored private let runtimeManager: RuntimeComponentManager
    @ObservationIgnored private let exitDetector: ExitIPDetector

    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored private var runtimeTask: Task<Void, Never>?
    @ObservationIgnored private var templateTask: Task<Void, Never>?
    @ObservationIgnored private var speedTestTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var detectTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var xrayStartTask: Task<Void, Never>?
    @ObservationIgnored private var xrayStopTask: Task<Void, Never>?
    @ObservationIgnored private var activeRunner: CfstRunner?
    @ObservationIgnored private var activeSpeedTestID: UUID?
    @ObservationIgnored private var activeXray: XrayController?
    @ObservationIgnored private var activeXrayID: UUID?
    @ObservationIgnored private var xrayStopRequested = false
    @ObservationIgnored private var isShuttingDown = false

    init(
        paths: AppPaths,
        preferencesStore: PreferencesStore,
        bootstrapper: AppBootstrapper,
        runtimeManager: RuntimeComponentManager,
        exitDetector: ExitIPDetector
    ) {
        self.paths = paths
        self.preferencesStore = preferencesStore
        self.bootstrapper = bootstrapper
        self.runtimeManager = runtimeManager
        self.exitDetector = exitDetector
        self.state = AppState(
            preferences: UserPreferences(parameters: .defaults(ipv6File: paths.ipv6List))
        )
    }

    static func live() -> AppModel {
        let paths = AppPaths.live()
        return AppModel(
            paths: paths,
            preferencesStore: PreferencesStore(fileURL: paths.preferences),
            bootstrapper: AppBootstrapper(paths: paths),
            runtimeManager: RuntimeComponentManager(paths: paths),
            exitDetector: ExitIPDetector()
        )
    }

    func start() {
        guard !isShuttingDown, bootstrapTask == nil, state.launchPhase == .idle else { return }
        state.launchPhase = .loading
        bootstrapTask = Task { [weak self] in
            await self?.bootstrap()
        }
    }

    func retryBootstrap() {
        guard case .failed = state.launchPhase, bootstrapTask == nil else { return }
        state.launchPhase = .idle
        start()
    }

    func installRuntime() {
        guard runtimeTask == nil else { return }
        state.runtimePhase = .installing
        appendLog(source: .app, message: "正在下载并校验运行组件…")

        runtimeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let status = try await runtimeManager.downloadAndInstall()
                state.runtimeStatus = status
                refreshRuntimePhase()
                appendLog(source: .app, level: .success, message: "运行组件安装完成")
                showNotice("运行组件已安装", style: .success)
            } catch {
                state.runtimePhase = .failed(error.localizedDescription)
                appendLog(source: .app, level: .error, message: error.localizedDescription)
                showNotice("安装失败：\(error.localizedDescription)", style: .error)
            }
            runtimeTask = nil
        }
    }

    func importRuntime(from urls: [URL]) {
        guard runtimeTask == nil, !urls.isEmpty else { return }
        state.runtimePhase = .installing
        runtimeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let status = try await runtimeManager.install(from: urls)
                state.runtimeStatus = status
                refreshRuntimePhase()
                appendLog(source: .app, level: .success, message: "已导入本地运行组件")
                showNotice("运行组件已导入", style: .success)
            } catch {
                state.runtimePhase = .failed(error.localizedDescription)
                appendLog(source: .app, level: .error, message: error.localizedDescription)
                showNotice("导入失败：\(error.localizedDescription)", style: .error)
            }
            runtimeTask = nil
        }
    }

    func importXrayTemplate(from url: URL) {
        guard templateTask == nil else { return }
        switch state.xrayPhase {
        case .validating, .starting, .running, .stopping:
            showNotice("请先停止本地代理再更换连接配置", style: .error)
            return
        case .stopped, .failed:
            break
        }

        let selectedIP = state.preferences.selectedIP
        templateTask = Task { [weak self] in
            guard let self else { return }
            let isAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessingSecurityScopedResource {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                try await bootstrapper.importTemplate(from: url, selectedIP: selectedIP)
                appendLog(source: .app, level: .success, message: "已导入代理连接模板")
                showNotice("代理配置已导入", style: .success)
            } catch {
                appendLog(source: .app, level: .error, message: "导入代理配置失败：\(error.localizedDescription)")
                showNotice("导入失败：\(error.localizedDescription)", style: .error)
            }
            templateTask = nil
        }
    }

    func refreshRuntimeStatus() {
        Task { [weak self] in
            guard let self else { return }
            state.runtimePhase = .checking
            state.runtimeStatus = await runtimeManager.installedStatus()
            refreshRuntimePhase()
        }
    }

    func selectIPSource(_ mode: IPSourceMode) {
        state.preferences.ipSourceMode = mode
        switch mode {
        case .ipv6:
            state.preferences.parameters.ipFile = paths.ipv6List.path
            state.preferences.parameters.ipRange = ""
        case .ipv4:
            state.preferences.parameters.ipFile = paths.ipv4List.path
            state.preferences.parameters.ipRange = ""
        case .file:
            state.preferences.parameters.ipRange = ""
        case .range:
            state.preferences.parameters.ipFile = ""
        }
        schedulePreferencesSave()
    }

    func selectIPFile(_ url: URL) {
        state.preferences.ipSourceMode = .file
        state.preferences.parameters.ipFile = url.path
        state.preferences.parameters.ipRange = ""
        schedulePreferencesSave()
    }

    func resetParameters() {
        state.preferences.ipSourceMode = .ipv6
        state.preferences.parameters = .defaults(ipv6File: paths.ipv6List)
        schedulePreferencesSave()
        showNotice("测速参数已重置")
    }

    func setCustomExecutable(_ component: RuntimeComponent, url: URL?) {
        let path = url?.path ?? ""
        switch component {
        case .cfst:
            state.preferences.cfstPath = path
        case .xray:
            state.preferences.xrayPath = path
        }
        schedulePreferencesSave()
        refreshRuntimePhase()
    }

    func startSpeedTest() {
        guard activeRunner == nil else { return }
        do {
            _ = try state.preferences.parameters.validated()
        } catch {
            showNotice(error.localizedDescription, style: .error)
            return
        }
        guard let executableURL = resolvedExecutable(
            preferredPath: state.preferences.cfstPath,
            managedURL: state.runtimeStatus?.cfstURL,
            commandName: "cfst"
        ) else {
            showNotice("请先安装 CFST 运行组件", style: .error)
            return
        }

        let runner = CfstRunner(
            executableURL: executableURL,
            resultURL: paths.resultCSV,
            workingDirectoryURL: executableURL.deletingLastPathComponent()
        )
        let runID = UUID()
        let snapshot = state.preferences.parameters
        activeRunner = runner
        activeSpeedTestID = runID
        state.speedTest = .init(phase: .running, startedAt: Date(), lastActivityAt: Date())
        appendLog(source: .speedTest, message: "开始节点测速")

        speedTestTask = Task { [weak self] in
            guard let self else { return }
            do {
                let results = try await runner.run(parameters: snapshot) { [weak self] event in
                    await self?.receiveSpeedTestEvent(event, runID: runID)
                }
                guard activeSpeedTestID == runID else { return }
                state.results = results
                if state.preferences.selectedIP.isEmpty, let first = results.first {
                    do {
                        try await applySelection(first.ip)
                    } catch {
                        appendLog(source: .app, level: .error, message: "生成首选节点配置失败：\(error.localizedDescription)")
                    }
                }
                appendLog(source: .speedTest, level: .success, message: "测速完成，共 \(results.count) 个候选节点")
                showNotice("测速完成：\(results.count) 个候选节点", style: .success)
                finishSpeedTest(runID: runID, phase: .idle)
            } catch CfstRunnerError.userCancelled {
                guard activeSpeedTestID == runID else { return }
                appendLog(source: .speedTest, level: .warning, message: "测速已停止")
                finishSpeedTest(runID: runID, phase: .idle)
            } catch {
                guard activeSpeedTestID == runID else { return }
                appendLog(source: .speedTest, level: .error, message: error.localizedDescription)
                showNotice("测速失败：\(error.localizedDescription)", style: .error)
                finishSpeedTest(runID: runID, phase: .failed(error.localizedDescription))
            }
        }
    }

    func stopSpeedTest() {
        guard let runner = activeRunner else { return }
        state.speedTest.phase = .stopping
        Task { await runner.cancel() }
    }

    func selectIP(_ ip: String) async {
        let shouldRestartXray = state.isXrayRunning
        do {
            try await applySelection(ip)
        } catch {
            appendLog(source: .app, level: .error, message: error.localizedDescription)
            showNotice("切换失败：\(error.localizedDescription)", style: .error)
            return
        }

        appendLog(source: .app, level: .success, message: "已切换节点：\(ip)")
        if shouldRestartXray, activeXray != nil {
            state.xrayPhase = .stopping
            do {
                try await restartActiveXray()
            } catch {
                showNotice("节点已切换，但 Xray 重启失败", style: .error)
                return
            }
        }
        showNotice("已切换到 \(ip)", style: .success)
    }

    func startXray() {
        guard activeXray == nil, xrayStartTask == nil, xrayStopTask == nil else { return }
        guard let executableURL = resolvedExecutable(
            preferredPath: state.preferences.xrayPath,
            managedURL: state.runtimeStatus?.xrayIsReady == true
                ? state.runtimeStatus?.xrayURL
                : nil,
            commandName: "xray"
        ) else {
            showNotice("请先安装 Xray 运行组件", style: .error)
            return
        }

        xrayStopRequested = false
        state.xrayPhase = .validating
        xrayStartTask = Task { [weak self] in
            guard let self else { return }
            do {
                let selectedIP = state.preferences.selectedIP
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !selectedIP.isEmpty else {
                    throw AppModelError.missingSelectedIP
                }
                try await bootstrapper.prepareConfigForLaunch(ip: selectedIP)
                appendLog(source: .app, message: "已应用当前节点与代理连接配置")

                var environment: [String: String] = [:]
                if state.runtimeStatus?.xrayIsReady == true,
                   executableURL.standardizedFileURL == state.runtimeStatus?.xrayURL?.standardizedFileURL,
                   let assetURL = state.runtimeStatus?.geoIPURL {
                    environment["XRAY_LOCATION_ASSET"] = assetURL.deletingLastPathComponent().path
                }
                let controller = XrayController(
                    executableURL: executableURL,
                    configURL: paths.generatedConfig,
                    workingDirectoryURL: executableURL.deletingLastPathComponent(),
                    environment: environment
                )
                let controllerID = UUID()
                activeXray = controller
                activeXrayID = controllerID
                appendLog(source: .xray, message: "正在校验配置并启动 Xray")

                try await controller.start { [weak self] event in
                    await self?.receiveXrayEvent(event, controllerID: controllerID)
                }
                guard activeXrayID == controllerID else { return }
                appendLog(source: .xray, level: .success, message: "Xray 已启动，监听 127.0.0.1:11451")
                showNotice("Xray 已启动", style: .success)
            } catch XrayControllerError.cancelled where xrayStopRequested {
                state.xrayPhase = .stopped
            } catch {
                state.xrayPhase = .failed(error.localizedDescription)
                appendLog(source: .xray, level: .error, message: error.localizedDescription)
                showNotice("Xray 启动失败：\(error.localizedDescription)", style: .error)
                activeXray = nil
                activeXrayID = nil
            }
            xrayStartTask = nil
        }
    }

    func stopXray() {
        guard xrayStopTask == nil else { return }
        let controller = activeXray
        let startTask = xrayStartTask
        guard controller != nil || startTask != nil else { return }

        xrayStopRequested = true
        state.xrayPhase = .stopping
        xrayStopTask = Task { [weak self] in
            guard let self else { return }
            startTask?.cancel()
            if let controller {
                await controller.stop()
            }
            if let startTask {
                await startTask.value
            }

            activeXray = nil
            activeXrayID = nil
            state.xrayPhase = .stopped
            appendLog(source: .xray, level: .warning, message: "Xray 已停止")
            showNotice("Xray 已停止")
            xrayStopRequested = false
            xrayStopTask = nil
        }
    }

    func restartXray() {
        guard state.isXrayRunning,
              activeXray != nil,
              xrayStartTask == nil,
              xrayStopTask == nil else { return }
        state.xrayPhase = .stopping
        xrayStartTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await restartActiveXray()
                showNotice("Xray 已重启", style: .success)
            } catch {
                showNotice("Xray 重启失败：\(error.localizedDescription)", style: .error)
            }
            xrayStartTask = nil
        }
    }

    func detectExitIP() {
        guard detectTask == nil else { return }
        state.exit.isDetecting = true
        state.exit.errorMessage = nil
        detectTask = Task { [weak self] in
            guard let self else { return }
            do {
                let proxy = state.isXrayRunning ? ProxyEndpoint() : nil
                state.exit.info = try await exitDetector.detect(proxy: proxy)
                appendLog(source: .app, level: .success, message: "出口 IP：\(state.exit.info?.ip ?? "")")
            } catch {
                state.exit.errorMessage = error.localizedDescription
                showNotice("检测失败：\(error.localizedDescription)", style: .error)
            }
            state.exit.isDetecting = false
            detectTask = nil
        }
    }

    func clearLogs() {
        state.logs.removeAll()
    }

    func clearNotice() {
        noticeTask?.cancel()
        noticeTask = nil
        state.notice = nil
    }

    func shutdown() async {
        guard !isShuttingDown else { return }
        isShuttingDown = true

        let pendingTasks = [
            bootstrapTask,
            runtimeTask,
            templateTask,
            speedTestTask,
            saveTask,
            detectTask,
            noticeTask,
            xrayStartTask,
            xrayStopTask
        ].compactMap { $0 }
        pendingTasks.forEach { $0.cancel() }

        if let activeRunner {
            await activeRunner.cancel()
        }
        if let activeXray {
            await activeXray.stop()
        }

        for task in pendingTasks {
            await task.value
        }
        try? await preferencesStore.save(state.preferences)
    }

    private func bootstrap() async {
        do {
            try await bootstrapper.prepareDefaults()
            let defaults = UserPreferences(parameters: .defaults(ipv6File: paths.ipv6List))
            var preferences = await preferencesStore.load(defaults: defaults)
            let loadedPreferences = preferences
            normalizeBundledSourcePath(in: &preferences)

            async let results = bootstrapper.loadResults()
            async let status = runtimeManager.installedStatus()
            let (loadedResults, installedStatus) = try await (results, status)

            if let configuredIP = try await bootstrapper.currentConfigIP()?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !configuredIP.isEmpty {
                preferences.selectedIP = configuredIP
            } else if !preferences.selectedIP.isEmpty {
                try await bootstrapper.ensureConfig(ip: preferences.selectedIP)
            }
            state.preferences = preferences
            state.results = loadedResults
            state.runtimeStatus = installedStatus
            refreshRuntimePhase()
            state.launchPhase = .ready
            if preferences != loadedPreferences {
                schedulePreferencesSave()
            }
            appendLog(source: .app, level: .success, message: "应用已就绪")
        } catch {
            state.launchPhase = .failed(error.localizedDescription)
            appendLog(source: .app, level: .error, message: error.localizedDescription)
        }
        bootstrapTask = nil
    }

    private func normalizeBundledSourcePath(in preferences: inout UserPreferences) {
        switch preferences.ipSourceMode {
        case .ipv6:
            preferences.parameters.ipFile = paths.ipv6List.path
            preferences.parameters.ipRange = ""
        case .ipv4:
            preferences.parameters.ipFile = paths.ipv4List.path
            preferences.parameters.ipRange = ""
        case .file:
            if preferences.parameters.ipFile.isEmpty {
                preferences.ipSourceMode = .ipv6
                preferences.parameters.ipFile = paths.ipv6List.path
            }
            preferences.parameters.ipRange = ""
        case .range:
            preferences.parameters.ipFile = ""
        }
    }

    private func refreshRuntimePhase() {
        let cfst = resolvedExecutable(
            preferredPath: state.preferences.cfstPath,
            managedURL: state.runtimeStatus?.cfstURL,
            commandName: "cfst"
        )
        let managedXrayURL = state.runtimeStatus?.xrayIsReady == true
            ? state.runtimeStatus?.xrayURL
            : nil
        let xray = resolvedExecutable(
            preferredPath: state.preferences.xrayPath,
            managedURL: managedXrayURL,
            commandName: "xray"
        )
        state.runtimePhase = cfst != nil && xray != nil ? .ready : .missing
    }

    private func resolvedExecutable(
        preferredPath: String,
        managedURL: URL?,
        commandName: String
    ) -> URL? {
        var candidates: [URL] = []
        if !preferredPath.isEmpty {
            candidates.append(URL(fileURLWithPath: preferredPath))
        }
        if let managedURL { candidates.append(managedURL) }
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/\(commandName)"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/\(commandName)"))
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0)).appendingPathComponent(commandName)
            })
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func applySelection(_ ip: String) async throws {
        let normalized = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        try await bootstrapper.writeConfig(ip: normalized)
        state.preferences.selectedIP = normalized
        try await savePreferencesNow()
    }

    private func restartActiveXray() async throws {
        guard let controller = activeXray, let controllerID = activeXrayID else { return }
        appendLog(source: .xray, message: "节点已变更，正在重启 Xray")
        do {
            try await controller.restart { [weak self] event in
                await self?.receiveXrayEvent(event, controllerID: controllerID)
            }
            guard activeXrayID == controllerID else { return }
            appendLog(source: .xray, level: .success, message: "Xray 已使用新节点重新启动")
        } catch {
            state.xrayPhase = .failed(error.localizedDescription)
            appendLog(source: .xray, level: .error, message: "Xray 重启失败：\(error.localizedDescription)")
            activeXray = nil
            activeXrayID = nil
            throw error
        }
    }

    private func receiveXrayEvent(_ event: XrayEvent, controllerID: UUID) {
        guard activeXrayID == controllerID else { return }
        switch event {
        case .stateChanged(let xrayState):
            switch xrayState {
            case .stopped:
                if case .failed = state.xrayPhase { return }
                state.xrayPhase = .stopped
            case .validating:
                state.xrayPhase = .validating
            case .starting:
                state.xrayPhase = .starting
            case .running:
                state.xrayPhase = .running
            case .stopping:
                state.xrayPhase = .stopping
            }
        case .log(let line):
            let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                appendLog(source: .xray, message: clean)
            }
        case .unexpectedExit(let status, let output):
            let detail = output.isEmpty ? "状态码 \(status)" : output
            state.xrayPhase = .failed("Xray 意外退出：\(detail)")
            appendLog(source: .xray, level: .error, message: "Xray 意外退出：\(detail)")
            showNotice("Xray 意外退出", style: .error)
            activeXray = nil
            activeXrayID = nil
        }
    }

    private func receiveSpeedTestEvent(_ event: CfstOutputEvent, runID: UUID) {
        guard activeSpeedTestID == runID else { return }
        state.speedTest.lastActivityAt = Date()
        switch event {
        case .progress(let current, let total):
            state.speedTest.current = current
            state.speedTest.total = total
        case .heartbeat(let bytes):
            state.speedTest.outputBytes = bytes
        case .line(let line):
            appendLog(source: .speedTest, message: line)
        }
    }

    private func finishSpeedTest(runID: UUID, phase: AppState.SpeedTestPhase) {
        guard activeSpeedTestID == runID else { return }
        state.speedTest.phase = phase
        activeRunner = nil
        activeSpeedTestID = nil
        speedTestTask = nil
    }

    private func schedulePreferencesSave() {
        guard state.launchPhase == .ready else { return }
        saveTask?.cancel()
        let snapshot = state.preferences
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(400))
                try Task.checkCancellation()
                try await self?.preferencesStore.save(snapshot)
            } catch is CancellationError {
                return
            } catch {
                self?.showNotice("保存设置失败：\(error.localizedDescription)", style: .error)
            }
        }
    }

    private func savePreferencesNow() async throws {
        saveTask?.cancel()
        saveTask = nil
        try await preferencesStore.save(state.preferences)
    }

    private func appendLog(
        source: AppLogEntry.Source,
        level: AppLogEntry.Level = .info,
        message: String
    ) {
        state.logs.append(AppLogEntry(source: source, level: level, message: message))
        if state.logs.count > 500 {
            state.logs.removeFirst(state.logs.count - 500)
        }
    }

    private func showNotice(_ message: String, style: AppNotice.Style = .info) {
        noticeTask?.cancel()
        let notice = AppNotice(message: message, style: style)
        state.notice = notice
        noticeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(3))
                guard self?.state.notice?.id == notice.id else { return }
                self?.state.notice = nil
            } catch {
                return
            }
        }
    }
}

private enum AppModelError: LocalizedError {
    case missingSelectedIP

    var errorDescription: String? {
        switch self {
        case .missingSelectedIP: "请先完成测速并选择一个节点"
        }
    }
}
