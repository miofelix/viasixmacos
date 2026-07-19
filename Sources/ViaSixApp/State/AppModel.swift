import Foundation
import Observation
import ViaSixCore

protocol XrayTemplateReplacing: Sendable {
    func replaceTemplate(
        with data: Data,
        selectedIP: String?,
        expectedTemplateData: Data?
    ) async throws -> ProxyEndpoint
}

extension AppBootstrapper: XrayTemplateReplacing {
    func replaceTemplate(
        with data: Data,
        selectedIP: String?,
        expectedTemplateData: Data?
    ) throws -> ProxyEndpoint {
        if let expectedTemplateData {
            let currentTemplateData = try? Data(contentsOf: paths.templateConfig)
            guard currentTemplateData == expectedTemplateData else {
                throw AppModelError.templateChangedExternally
            }
        }
        return try replaceTemplate(with: data, selectedIP: selectedIP)
    }
}

@MainActor
@Observable
final class AppModel {
    private(set) var state: AppState
    private(set) var switchingIP: String?

    var parameters: SpeedTestParameters {
        get { state.preferences.parameters }
        set {
            guard !isShuttingDown else { return }
            state.preferences.parameters = newValue
            state.configurationTest.result = nil
            state.configurationTest.parameters = nil
            schedulePreferencesSave()
        }
    }

    var ipSourceMode: IPSourceMode {
        state.preferences.ipSourceMode
    }

    var isCfstBusy: Bool {
        activeRunner != nil
    }

    var exitIPEndpoint: String {
        get { state.preferences.exitIPEndpoint }
        set {
            guard !isShuttingDown else { return }
            let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = normalized.isEmpty ? AppMetadata.defaultExitIPEndpoint : normalized
            guard state.preferences.exitIPEndpoint != value else { return }
            if state.preferences.exitIPDetectionMode == .automatic {
                cancelExitIPDetection()
            }
            state.preferences.exitIPEndpoint = value
            state.exit.errorMessage = nil
            schedulePreferencesSave()
        }
    }

    var exitIPDetectionMode: ExitIPDetectionMode {
        get { state.preferences.exitIPDetectionMode }
        set {
            guard !isShuttingDown else { return }
            guard state.preferences.exitIPDetectionMode != newValue else { return }
            cancelExitIPDetection()
            state.preferences.exitIPDetectionMode = newValue
            state.exit.errorMessage = nil
            schedulePreferencesSave()
        }
    }

    var exitIPResultIsStale: Bool {
        guard let context = state.exit.context else { return false }
        return context != currentExitIPDetectionContext
    }

    var exitIPRouteDescription: String? {
        guard let route = state.exit.context?.route else { return nil }
        switch route {
        case .direct:
            return "直连"
        case .proxy(let endpoint, _):
            return "本地代理 \(endpoint.displayAddress)"
        }
    }

    /// CFST and Xray are independent capabilities. Keeping them separate lets
    /// the UI offer node testing even when the proxy component is not installed.
    var hasCfstExecutable: Bool {
        resolvedExecutable(
            preferredPath: state.preferences.cfstPath,
            managedURL: state.runtimeStatus?.cfstURL,
            commandName: "cfst"
        ) != nil
    }

    var hasXrayExecutable: Bool {
        let managedURL =
            state.runtimeStatus?.xrayIsReady == true
            ? state.runtimeStatus?.xrayURL
            : nil
        return resolvedExecutable(
            preferredPath: state.preferences.xrayPath,
            managedURL: managedURL,
            commandName: "xray"
        ) != nil
    }

    let paths: AppPaths

    @ObservationIgnored private let preferencesStore: PreferencesStore
    @ObservationIgnored private let bootstrapper: AppBootstrapper
    @ObservationIgnored private let runtimeManager: RuntimeComponentManager
    @ObservationIgnored private let exitDetector: any ExitIPDetecting
    @ObservationIgnored private let templateReplacer: any XrayTemplateReplacing

    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored private var runtimeTask: Task<Void, Never>?
    @ObservationIgnored private var templateImportTask: Task<Void, Never>?
    @ObservationIgnored private var templateSaveTask: Task<ProxyEndpoint, Error>?
    @ObservationIgnored private var speedTestTask: Task<Void, Never>?
    @ObservationIgnored private var configurationTestTask: Task<Void, Never>?
    @ObservationIgnored private var selectionTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var detectTask: Task<Void, Never>?
    @ObservationIgnored private var activeExitDetectionID: UUID?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var xrayStartTask: Task<Void, Never>?
    @ObservationIgnored private var xrayStopTask: Task<Void, Never>?
    @ObservationIgnored private var activeRunner: CfstRunner?
    @ObservationIgnored private var activeSpeedTestID: UUID?
    @ObservationIgnored private var activeConfigurationTestID: UUID?
    @ObservationIgnored private var activeXray: XrayController?
    @ObservationIgnored private var activeXrayID: UUID?
    @ObservationIgnored private var xrayStopRequested = false
    @ObservationIgnored private var isShuttingDown = false

    init(
        paths: AppPaths,
        preferencesStore: PreferencesStore,
        bootstrapper: AppBootstrapper,
        runtimeManager: RuntimeComponentManager,
        exitDetector: any ExitIPDetecting,
        templateReplacer: (any XrayTemplateReplacing)? = nil
    ) {
        self.paths = paths
        self.preferencesStore = preferencesStore
        self.bootstrapper = bootstrapper
        self.runtimeManager = runtimeManager
        self.exitDetector = exitDetector
        self.templateReplacer = templateReplacer ?? bootstrapper
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
        guard !isShuttingDown, case .failed = state.launchPhase, bootstrapTask == nil else { return }
        state.launchPhase = .idle
        start()
    }

    func installRuntime() {
        guard
            !isShuttingDown,
            runtimeTask == nil,
            activeRunner == nil,
            activeXray == nil,
            xrayStartTask == nil,
            xrayStopTask == nil
        else { return }
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
        guard
            !isShuttingDown,
            runtimeTask == nil,
            activeRunner == nil,
            activeXray == nil,
            xrayStartTask == nil,
            xrayStopTask == nil,
            !urls.isEmpty
        else { return }
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
        guard
            !isShuttingDown,
            templateImportTask == nil,
            templateSaveTask == nil,
            state.templateOperationPhase == .idle
        else { return }
        switch state.xrayPhase {
        case .validating, .starting, .running, .stopping:
            showNotice("请先停止本地代理再更换连接配置", style: .error)
            return
        case .stopped, .failed:
            break
        }

        let selectedIP = state.preferences.selectedIP
        state.templateOperationPhase = .importing
        templateImportTask = Task { [weak self] in
            guard let self else { return }
            defer {
                templateImportTask = nil
                state.templateOperationPhase = .idle
            }
            let isAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessingSecurityScopedResource {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                state.proxyEndpoint = try await bootstrapper.importTemplate(
                    from: url,
                    selectedIP: selectedIP
                )
                appendLog(source: .app, level: .success, message: "已导入代理连接模板")
                showNotice("代理配置已导入", style: .success)
            } catch {
                appendLog(source: .app, level: .error, message: "导入代理配置失败：\(error.localizedDescription)")
                showNotice("导入失败：\(error.localizedDescription)", style: .error)
            }
        }
    }

    func saveXrayTemplate(_ data: Data, expectedTemplateData: Data? = nil) async throws {
        guard
            templateImportTask == nil,
            templateSaveTask == nil,
            state.templateOperationPhase == .idle
        else {
            throw AppModelError.templateOperationInProgress
        }
        guard !isShuttingDown else { throw CancellationError() }
        switch state.xrayPhase {
        case .validating, .starting, .running, .stopping:
            throw AppModelError.xrayMustBeStopped
        case .stopped, .failed:
            break
        }

        let selectedIP = state.preferences.selectedIP
        state.templateOperationPhase = .saving
        let task = Task<ProxyEndpoint, Error> { [templateReplacer] in
            try Task.checkCancellation()
            let endpoint = try await templateReplacer.replaceTemplate(
                with: data,
                selectedIP: selectedIP,
                expectedTemplateData: expectedTemplateData
            )
            try Task.checkCancellation()
            return endpoint
        }
        templateSaveTask = task
        defer {
            templateSaveTask = nil
            state.templateOperationPhase = .idle
        }

        do {
            let endpoint = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            try Task.checkCancellation()
            guard !isShuttingDown else { throw CancellationError() }
            state.proxyEndpoint = endpoint
            appendLog(source: .app, level: .success, message: "已保存代理连接模板")
            showNotice("代理配置已保存", style: .success)
        } catch is CancellationError {
            throw CancellationError()
        } catch AppModelError.templateChangedExternally {
            appendLog(
                source: .app,
                level: .warning,
                message: "代理配置在编辑期间发生变化，已阻止覆盖外部修改"
            )
            throw AppModelError.templateChangedExternally
        } catch {
            appendLog(source: .app, level: .error, message: "保存代理配置失败：\(error.localizedDescription)")
            throw error
        }
    }

    func selectIPSource(_ mode: IPSourceMode) {
        guard !isShuttingDown else { return }
        state.configurationTest.result = nil
        state.configurationTest.parameters = nil
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
        guard !isShuttingDown else { return }
        state.configurationTest.result = nil
        state.configurationTest.parameters = nil
        state.preferences.ipSourceMode = .file
        state.preferences.parameters.ipFile = url.path
        state.preferences.parameters.ipRange = ""
        schedulePreferencesSave()
    }

    func resetParameters() {
        guard !isShuttingDown else { return }
        state.configurationTest.result = nil
        state.configurationTest.parameters = nil
        state.preferences.ipSourceMode = .ipv6
        state.preferences.parameters = .defaults(ipv6File: paths.ipv6List)
        schedulePreferencesSave()
        showNotice("测速参数已重置")
    }

    func setCustomExecutable(_ component: RuntimeComponent, url: URL?) {
        guard !isShuttingDown else { return }
        switch component {
        case .cfst where activeRunner != nil:
            showNotice("测速进行中，完成或停止后再修改 CFST 路径", style: .error)
            return
        case .xray where activeXray != nil || xrayStartTask != nil || xrayStopTask != nil:
            showNotice("本地代理运行中，停止后再修改 Xray 路径", style: .error)
            return
        default:
            break
        }
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
        guard !isShuttingDown, activeRunner == nil, state.templateOperationPhase == .idle else { return }
        do {
            _ = try state.preferences.parameters.validated()
        } catch {
            showNotice(error.localizedDescription, style: .error)
            return
        }
        guard
            let executableURL = resolvedExecutable(
                preferredPath: state.preferences.cfstPath,
                managedURL: state.runtimeStatus?.cfstURL,
                commandName: "cfst"
            )
        else {
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
                state.preferences.lastSuccessfulSpeedTestParameters = snapshot
                schedulePreferencesSave()
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
        guard activeSpeedTestID != nil, let runner = activeRunner else { return }
        state.speedTest.phase = .stopping
        speedTestTask?.cancel()
        Task { await runner.cancel() }
    }

    func startCurrentConfigurationTest() {
        guard !isShuttingDown, activeRunner == nil, state.templateOperationPhase == .idle else { return }
        let selectedIP = state.preferences.selectedIP
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedIP.isEmpty else {
            showNotice("请先选择当前节点", style: .error)
            return
        }
        guard
            let executableURL = resolvedExecutable(
                preferredPath: state.preferences.cfstPath,
                managedURL: state.runtimeStatus?.cfstURL,
                commandName: "cfst"
            )
        else {
            showNotice("请先安装 CFST 运行组件", style: .error)
            return
        }

        var parameters = state.preferences.parameters
        parameters.ipFile = ""
        parameters.ipRange = selectedIP
        parameters.allIP = false
        do {
            _ = try parameters.validated()
        } catch {
            showNotice(error.localizedDescription, style: .error)
            return
        }

        let runID = UUID()
        let resultURL = paths.data.appendingPathComponent(".current-test-\(runID.uuidString).csv")
        let runner = CfstRunner(
            executableURL: executableURL,
            resultURL: resultURL,
            workingDirectoryURL: executableURL.deletingLastPathComponent()
        )
        activeRunner = runner
        activeConfigurationTestID = runID
        state.configurationTest.phase = .running
        appendLog(source: .speedTest, message: "开始测试当前节点：\(selectedIP)")

        configurationTestTask = Task { [weak self] in
            guard let self else { return }
            defer { try? FileManager.default.removeItem(at: resultURL) }
            do {
                let results = try await runner.run(parameters: parameters) { [weak self] event in
                    await self?.receiveConfigurationTestEvent(event, runID: runID)
                }
                guard activeConfigurationTestID == runID else { return }
                guard let result = results.first else {
                    throw CfstRunnerError.noResults
                }
                state.configurationTest.result = result
                state.configurationTest.parameters = parameters
                appendLog(source: .speedTest, level: .success, message: "当前节点测速完成")
                showNotice("当前节点测速完成", style: .success)
                finishConfigurationTest(runID: runID, phase: .idle)
            } catch CfstRunnerError.userCancelled {
                guard activeConfigurationTestID == runID else { return }
                appendLog(source: .speedTest, level: .warning, message: "当前节点测速已停止")
                finishConfigurationTest(runID: runID, phase: .idle)
            } catch {
                guard activeConfigurationTestID == runID else { return }
                appendLog(source: .speedTest, level: .error, message: error.localizedDescription)
                showNotice("当前节点测速失败：\(error.localizedDescription)", style: .error)
                finishConfigurationTest(runID: runID, phase: .failed(error.localizedDescription))
            }
        }
    }

    func stopCurrentConfigurationTest() {
        guard activeConfigurationTestID != nil, let runner = activeRunner else { return }
        state.configurationTest.phase = .stopping
        configurationTestTask?.cancel()
        Task { await runner.cancel() }
    }

    func selectIP(_ ip: String) {
        guard selectionTask == nil, !isShuttingDown, state.templateOperationPhase == .idle else { return }
        switchingIP = ip
        selectionTask = Task { [weak self] in
            await self?.performIPSelection(ip)
        }
    }

    private func performIPSelection(_ ip: String) async {
        defer {
            if switchingIP == ip {
                switchingIP = nil
            }
            selectionTask = nil
        }

        let shouldRestartXray = state.isXrayRunning
        if shouldRestartXray {
            cancelExitIPDetection()
        }
        do {
            try Task.checkCancellation()
            try await applySelection(ip)
            try Task.checkCancellation()
        } catch is CancellationError {
            return
        } catch {
            if isShuttingDown || Task.isCancelled { return }
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
                if isShuttingDown || Task.isCancelled { return }
                showNotice("节点已切换，但本地代理重新连接失败", style: .error)
                return
            }
        }
        showNotice("已切换到 \(ip)", style: .success)
    }

    func startXray() {
        guard
            !isShuttingDown,
            state.templateOperationPhase == .idle,
            activeXray == nil,
            xrayStartTask == nil,
            xrayStopTask == nil
        else { return }
        guard
            let executableURL = resolvedExecutable(
                preferredPath: state.preferences.xrayPath,
                managedURL: state.runtimeStatus?.xrayIsReady == true
                    ? state.runtimeStatus?.xrayURL
                    : nil,
                commandName: "xray"
            )
        else {
            showNotice("请先安装代理运行组件", style: .error)
            return
        }

        cancelExitIPDetection()
        xrayStopRequested = false
        state.xrayPhase = .validating
        xrayStartTask = Task { [weak self] in
            guard let self else { return }
            defer { xrayStartTask = nil }
            do {
                let selectedIP = state.preferences.selectedIP
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !selectedIP.isEmpty else {
                    throw AppModelError.missingSelectedIP
                }
                let proxyEndpoint = try await bootstrapper.prepareConfigForLaunch(ip: selectedIP)
                state.proxyEndpoint = proxyEndpoint
                appendLog(source: .app, message: "已应用当前节点与代理连接配置")

                var environment: [String: String] = [:]
                if state.runtimeStatus?.xrayIsReady == true,
                    executableURL.standardizedFileURL == state.runtimeStatus?.xrayURL?.standardizedFileURL,
                    let assetURL = state.runtimeStatus?.geoIPURL
                {
                    environment["XRAY_LOCATION_ASSET"] = assetURL.deletingLastPathComponent().path
                }
                let controller = XrayController(
                    executableURL: executableURL,
                    configURL: paths.generatedConfig,
                    workingDirectoryURL: executableURL.deletingLastPathComponent(),
                    environment: environment,
                    host: proxyEndpoint.host,
                    port: UInt16(proxyEndpoint.port)
                )
                let controllerID = UUID()
                activeXray = controller
                activeXrayID = controllerID
                appendLog(source: .xray, message: "正在检查连接配置并启动本地代理")

                try await controller.start { [weak self] event in
                    await self?.receiveXrayEvent(event, controllerID: controllerID)
                }
                guard activeXrayID == controllerID else { return }
                appendLog(
                    source: .xray,
                    level: .success,
                    message: "本地代理已启动，监听 \(proxyEndpoint.displayAddress)"
                )
                showNotice("本地代理已启动", style: .success)
                refreshExitIPAfterNetworkChangeIfNeeded()
            } catch XrayControllerError.cancelled where xrayStopRequested {
                state.xrayPhase = .stopped
            } catch {
                state.xrayPhase = .failed(error.localizedDescription)
                appendLog(source: .xray, level: .error, message: error.localizedDescription)
                showNotice("本地代理启动失败：\(error.localizedDescription)", style: .error)
                activeXray = nil
                activeXrayID = nil
            }
        }
    }

    func stopXray() {
        guard xrayStopTask == nil else { return }
        let controller = activeXray
        let startTask = xrayStartTask
        guard controller != nil || startTask != nil else { return }

        cancelExitIPDetection()
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
            appendLog(source: .xray, level: .warning, message: "本地代理已停止")
            showNotice("本地代理已停止")
            refreshExitIPAfterNetworkChangeIfNeeded()
            xrayStopRequested = false
            xrayStopTask = nil
        }
    }

    func restartXray() {
        guard !isShuttingDown,
            state.templateOperationPhase == .idle,
            state.isXrayRunning,
            activeXray != nil,
            xrayStartTask == nil,
            xrayStopTask == nil
        else { return }
        cancelExitIPDetection()
        state.xrayPhase = .stopping
        xrayStartTask = Task { [weak self] in
            guard let self else { return }
            defer { xrayStartTask = nil }
            do {
                try await restartActiveXray()
                showNotice("本地代理已重新连接", style: .success)
            } catch {
                showNotice("本地代理重新连接失败：\(error.localizedDescription)", style: .error)
            }
        }
    }

    func detectExitIP() {
        guard !isShuttingDown, detectTask == nil else { return }
        let detectionID = UUID()
        let context = currentExitIPDetectionContext
        let proxy: ProxyEndpoint? =
            switch context.route {
            case .direct: nil
            case .proxy(let endpoint, _): endpoint
            }
        guard let endpoint = URL(string: context.serviceEndpoint) else {
            state.exit.errorMessage = ExitIPDetectionError.invalidEndpoint.localizedDescription
            showNotice("检测失败：\(ExitIPDetectionError.invalidEndpoint.localizedDescription)", style: .error)
            return
        }

        activeExitDetectionID = detectionID
        state.exit.isDetecting = true
        state.exit.errorMessage = nil
        detectTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if activeExitDetectionID == detectionID {
                    activeExitDetectionID = nil
                    state.exit.isDetecting = false
                    detectTask = nil
                }
            }
            do {
                let info = try await exitDetector.detect(
                    proxy: proxy,
                    endpoint: endpoint,
                    expectedFamily: context.mode.expectedAddressFamily
                )
                guard activeExitDetectionID == detectionID, !Task.isCancelled else { return }
                state.exit.info = info
                state.exit.detectedAt = Date()
                state.exit.context = context
                appendLog(
                    source: .app,
                    level: .success,
                    message: "出口 IP：\(info.ip)（\(exitIPRouteDescription ?? "未知路径")）"
                )
            } catch is CancellationError {
                return
            } catch {
                guard activeExitDetectionID == detectionID, !Task.isCancelled else { return }
                state.exit.errorMessage = error.localizedDescription
                showNotice("检测失败：\(error.localizedDescription)", style: .error)
            }
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
            templateImportTask,
            speedTestTask,
            configurationTestTask,
            selectionTask,
            saveTask,
            detectTask,
            noticeTask,
            xrayStartTask,
            xrayStopTask,
        ].compactMap { $0 }
        let pendingTemplateSaveTask = templateSaveTask
        pendingTasks.forEach { $0.cancel() }
        pendingTemplateSaveTask?.cancel()

        if let activeRunner {
            await activeRunner.cancel()
        }
        if let activeXray {
            await activeXray.stop()
        }

        for task in pendingTasks {
            await task.value
        }
        if let pendingTemplateSaveTask {
            _ = try? await pendingTemplateSaveTask.value
        }
        state.templateOperationPhase = .idle
        try? await preferencesStore.save(state.preferences)
    }

    private func bootstrap() async {
        defer { bootstrapTask = nil }
        do {
            try await bootstrapper.prepareDefaults()
            let defaults = UserPreferences(parameters: .defaults(ipv6File: paths.ipv6List))
            var preferences = await preferencesStore.load(defaults: defaults)
            let loadedPreferences = preferences
            normalizeBundledSourcePath(in: &preferences)
            if preferences.exitIPEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                preferences.exitIPEndpoint = AppMetadata.defaultExitIPEndpoint
            }

            async let installedStatus = runtimeManager.installedStatus()
            let loadedResults: [SpeedTestResult]
            do {
                loadedResults = try await bootstrapper.loadResults()
            } catch {
                loadedResults = []
                appendLog(source: .speedTest, level: .warning, message: "忽略了损坏的历史测速结果：\(error.localizedDescription)")
            }
            if loadedResults.isEmpty {
                preferences.lastSuccessfulSpeedTestParameters = nil
            }

            var configurationWarning: String?
            var proxyEndpoint = ProxyEndpoint()
            do {
                proxyEndpoint = try await bootstrapper.currentProxyEndpoint()
                if let configuredIP = try await bootstrapper.currentConfigIP()?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                    !configuredIP.isEmpty
                {
                    preferences.selectedIP = configuredIP
                } else if !preferences.selectedIP.isEmpty {
                    try await bootstrapper.ensureConfig(ip: preferences.selectedIP)
                }
            } catch {
                configurationWarning = error.localizedDescription
                appendLog(source: .app, level: .warning, message: "代理配置需要修复：\(error.localizedDescription)")
            }

            guard !Task.isCancelled, !isShuttingDown else { return }
            state.preferences = preferences
            state.results = loadedResults
            state.runtimeStatus = await installedStatus
            state.proxyEndpoint = proxyEndpoint
            refreshRuntimePhase()
            state.launchPhase = .ready
            if preferences != loadedPreferences {
                schedulePreferencesSave()
            }
            appendLog(source: .app, level: .success, message: "应用已就绪")
            if let configurationWarning {
                showNotice("代理配置需要重新导入或修复：\(configurationWarning)", style: .error)
            }
        } catch {
            guard !Task.isCancelled, !isShuttingDown else { return }
            state.launchPhase = .failed(error.localizedDescription)
            appendLog(source: .app, level: .error, message: error.localizedDescription)
        }
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
        let managedXrayURL =
            state.runtimeStatus?.xrayIsReady == true
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
            candidates.append(
                contentsOf: path.split(separator: ":").map {
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
        state.configurationTest.result = nil
        state.configurationTest.parameters = nil
        do {
            try await savePreferencesNow()
        } catch {
            appendLog(source: .app, level: .warning, message: "节点已应用，但偏好保存失败：\(error.localizedDescription)")
            schedulePreferencesSave()
        }
    }

    private func restartActiveXray() async throws {
        guard let controller = activeXray, let controllerID = activeXrayID else {
            throw AppModelError.xrayNotActive
        }
        appendLog(source: .xray, message: "节点已变更，正在重新连接本地代理")
        do {
            try await controller.restart { [weak self] event in
                await self?.receiveXrayEvent(event, controllerID: controllerID)
            }
            guard activeXrayID == controllerID else {
                throw AppModelError.xrayExitedDuringRestart
            }
            appendLog(source: .xray, level: .success, message: "本地代理已应用新节点")
            refreshExitIPAfterNetworkChangeIfNeeded()
        } catch {
            if activeXrayID == controllerID {
                state.xrayPhase = .failed(error.localizedDescription)
                appendLog(
                    source: .xray,
                    level: .error,
                    message: "本地代理重新连接失败：\(error.localizedDescription)"
                )
                activeXray = nil
                activeXrayID = nil
            }
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
            cancelExitIPDetection()
            let detail = output.isEmpty ? "状态码 \(status)" : output
            state.xrayPhase = .failed("本地代理意外退出：\(detail)")
            appendLog(source: .xray, level: .error, message: "本地代理意外退出：\(detail)")
            showNotice("本地代理意外退出", style: .error)
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

    private func receiveConfigurationTestEvent(_ event: CfstOutputEvent, runID: UUID) {
        guard activeConfigurationTestID == runID else { return }
        if case .line(let line) = event {
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

    private func finishConfigurationTest(runID: UUID, phase: AppState.SpeedTestPhase) {
        guard activeConfigurationTestID == runID else { return }
        state.configurationTest.phase = phase
        activeRunner = nil
        activeConfigurationTestID = nil
        configurationTestTask = nil
    }

    private var currentExitIPDetectionContext: AppState.ExitState.DetectionContext {
        let mode = state.preferences.exitIPDetectionMode
        let endpoint = AppMetadata.exitIPEndpoint(
            for: mode,
            automaticEndpoint: state.preferences.exitIPEndpoint
        )
        let route: AppState.ExitState.DetectionContext.Route =
            if state.isXrayRunning {
                .proxy(
                    endpoint: state.proxyEndpoint,
                    selectedIP: state.preferences.selectedIP
                )
            } else {
                .direct
            }
        return .init(route: route, mode: mode, serviceEndpoint: endpoint)
    }

    private func cancelExitIPDetection() {
        activeExitDetectionID = nil
        detectTask?.cancel()
        detectTask = nil
        state.exit.isDetecting = false
    }

    private func refreshExitIPAfterNetworkChangeIfNeeded() {
        guard state.exit.info != nil, detectTask == nil, !isShuttingDown else { return }
        detectExitIP()
    }

    private func schedulePreferencesSave() {
        guard state.launchPhase == .ready, !isShuttingDown else { return }
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
        guard !isShuttingDown else { return }
        noticeTask?.cancel()
        noticeTask = nil
        let notice = AppNotice(message: message, style: style)
        state.notice = notice

        // Errors stay visible until dismissed so failures from the menu bar or
        // a background task are not lost when the main window is closed.
        guard style != .error else { return }

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

enum AppModelError: LocalizedError, Equatable {
    case missingSelectedIP
    case templateOperationInProgress
    case templateChangedExternally
    case xrayMustBeStopped
    case xrayNotActive
    case xrayExitedDuringRestart

    var errorDescription: String? {
        switch self {
        case .missingSelectedIP: "请先完成测速并选择一个节点"
        case .templateOperationInProgress: "另一项代理配置操作尚未完成"
        case .templateChangedExternally: "代理配置已被其他操作修改，请重新载入后再保存"
        case .xrayMustBeStopped: "请先停止本地代理再保存连接配置"
        case .xrayNotActive: "本地代理当前未运行"
        case .xrayExitedDuringRestart: "本地代理在重新连接后立即退出"
        }
    }
}
