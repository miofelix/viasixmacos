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

    private func makePaths() -> AppPaths {
        AppPaths(
            root: FileManager.default.temporaryDirectory
                .appendingPathComponent("AppBootstrapperTests-\(UUID().uuidString)", isDirectory: true)
        )
    }
}
