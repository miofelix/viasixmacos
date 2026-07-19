import XCTest
@testable import ViaSixCore

final class AppBootstrapperTests: XCTestCase {
    func testPrepareDefaultsInstallsFirstLaunchResources() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)

        try await bootstrapper.prepareDefaults()

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.ipv4List.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.ipv6List.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.templateConfig.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.runtime.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.logs.path))

        let ipv4Ranges = try String(contentsOf: paths.ipv4List, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        XCTAssertEqual(ipv4Ranges.count, 25)
        XCTAssertEqual(ipv4Ranges.last, "131.0.72.0/22")
    }

    func testPrepareDefaultsMigratesOnlyThePreviouslyShippedIPv4List() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try paths.prepare()
        let legacyIPv4List = """
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
        try Data(legacyIPv4List.utf8).write(to: paths.ipv4List)

        try await bootstrapper.prepareDefaults()

        let migrated = try String(contentsOf: paths.ipv4List, encoding: .utf8)
        XCTAssertTrue(migrated.contains("172.67.0.0/16"))
        XCTAssertTrue(migrated.contains("131.0.72.0/22"))

        let customized = migrated + "203.0.113.0/24\n"
        try Data(customized.utf8).write(to: paths.ipv4List, options: .atomic)
        try await bootstrapper.prepareDefaults()
        XCTAssertEqual(
            try String(contentsOf: paths.ipv4List, encoding: .utf8),
            customized
        )
    }

    func testLoadResultsReturnsEmptyWhenMissingAndThrowsForMalformedCSV() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)

        let missingResults = try await bootstrapper.loadResults()
        XCTAssertEqual(missingResults, [])

        try paths.prepare()
        try Data("IP,Sent,Recv,Loss,Latency,Speed,Region\n\"unterminated".utf8)
            .write(to: paths.resultCSV, options: .atomic)

        do {
            _ = try await bootstrapper.loadResults()
            XCTFail("Expected malformed CSV to throw")
        } catch {
            XCTAssertEqual(error as? CSVError, .unclosedQuote)
        }
    }

    func testLoadResultsParsesEveryValidRow() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try paths.prepare()
        let csv = """
        IP,Sent,Recv,Loss,Latency,Speed,Region
        2606::1,4,4,0.00,18.2,10.5,SJC
        2606::2,4,4,0.00,22.8,8.1,LAX
        """
        try Data(csv.utf8).write(to: paths.resultCSV, options: .atomic)

        let results = try await bootstrapper.loadResults()

        XCTAssertEqual(results.map(\.ip), ["2606::1", "2606::2"])
        XCTAssertEqual(results[1].region, "LAX")
    }

    func testSelectedResultCanBeNonFirstRowAndFallsBackToCurrentConfig() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        let csv = """
        IP,Sent,Recv,Loss,Latency,Speed,Region
        2606::1,4,4,0.00,18.2,10.5,SJC
        2606::2,4,4,0.00,22.8,8.1,LAX
        """
        try Data(csv.utf8).write(to: paths.resultCSV, options: .atomic)

        let explicitSelection = try await bootstrapper.resultForSelectedIP(" 2606::2 ")
        XCTAssertEqual(explicitSelection?.ip, "2606::2")

        try await bootstrapper.writeConfig(ip: "2606::2")
        let currentSelection = try await bootstrapper.resultForSelectedIP()
        XCTAssertEqual(currentSelection?.ip, "2606::2")
    }

    func testWriteConfigAtomicallyGeneratesConfigAndReadsCurrentIP() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()

        let missingIP = try await bootstrapper.currentConfigIP()
        XCTAssertNil(missingIP)

        try await bootstrapper.writeConfig(ip: " 2606::99 ")

        let currentIP = try await bootstrapper.currentConfigIP()
        XCTAssertEqual(currentIP, "2606::99")
        let generated = try Data(contentsOf: paths.generatedConfig)
        XCTAssertEqual(ConfigTemplate.address(in: generated), "2606::99")
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: generated))
    }

    func testEnsureConfigRepairsMismatchWithoutRewritingAnAlreadyMatchingConfig() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let bootstrapper = AppBootstrapper(paths: paths)
        try await bootstrapper.prepareDefaults()
        try await bootstrapper.writeConfig(ip: "2606::1")

        try Data("not json".utf8).write(to: paths.templateConfig, options: .atomic)
        let unchanged = try await bootstrapper.ensureConfig(ip: " 2606::1 ")
        XCTAssertFalse(unchanged)

        do {
            _ = try await bootstrapper.ensureConfig(ip: "2606::2")
            XCTFail("Expected the mismatched config to be regenerated from the template")
        } catch {
            XCTAssertEqual(error as? ConfigTemplateError, .invalidJSON)
        }

        try FileManager.default.removeItem(at: paths.templateConfig)
        try DefaultResourceInstaller.install(into: paths)
        let repaired = try await bootstrapper.ensureConfig(ip: "2606::2")
        let currentIP = try await bootstrapper.currentConfigIP()
        XCTAssertTrue(repaired)
        XCTAssertEqual(currentIP, "2606::2")
    }

    private func makePaths() -> AppPaths {
        AppPaths(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("AppBootstrapperTests-\(UUID().uuidString)", isDirectory: true)
        )
    }
}
