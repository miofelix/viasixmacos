import XCTest

@testable import ViaSixCore

final class TrafficMonitorTests: XCTestCase {
    func testDecodesTrafficAndMemoryPayloads() throws {
        let traffic = try MihomoAPIDecoder.decodeTraffic(Data(#"{"up":1200,"down":3400}"#.utf8))
        XCTAssertEqual(traffic.up, 1_200)
        XCTAssertEqual(traffic.down, 3_400)

        let memory = try MihomoAPIDecoder.decodeMemory(Data(#"{"inuse":8388608,"oslimit":0}"#.utf8))
        XCTAssertEqual(memory.inuse, 8_388_608)
        XCTAssertEqual(memory.oslimit, 0)
    }

    func testDecodesNumericVariants() throws {
        let traffic = try MihomoAPIDecoder.decodeTraffic(Data(#"{"up":12.5,"down":-1}"#.utf8))
        XCTAssertEqual(traffic.up, 12)
        XCTAssertEqual(traffic.down, 0)
    }

    func testAppliesSamplesAndTrimsHistory() async {
        let monitor = TrafficMonitor(
            configuration: TrafficMonitorConfiguration(
                historyWindow: .seconds(60),
                reconnectDelay: .milliseconds(10),
                initialConnectDelay: .zero,
                maxPoints: 3
            )
        )

        let now = Date()
        await monitor.testApplyTraffic(up: 1, down: 2, at: now.addingTimeInterval(-120))
        await monitor.testApplyTraffic(up: 3, down: 4, at: now.addingTimeInterval(-30))
        await monitor.testApplyTraffic(up: 5, down: 6, at: now.addingTimeInterval(-10))
        await monitor.testApplyTraffic(up: 7, down: 8, at: now)
        await monitor.testApplyMemory(inuse: 4_096)

        let snapshot = await monitor.currentSnapshot()
        XCTAssertEqual(snapshot.up, 7)
        XCTAssertEqual(snapshot.down, 8)
        XCTAssertEqual(snapshot.memoryInUse, 4_096)
        XCTAssertEqual(snapshot.points.count, 3)
        XCTAssertEqual(snapshot.points.map(\.up), [3, 5, 7])
    }

    func testStopResetsSnapshot() async {
        let monitor = TrafficMonitor(
            configuration: TrafficMonitorConfiguration(initialConnectDelay: .zero)
        )
        await monitor.testApplyTraffic(up: 100, down: 200)
        await monitor.testApplyMemory(inuse: 512)
        await monitor.stop()

        let snapshot = await monitor.currentSnapshot()
        XCTAssertEqual(snapshot, .empty)
    }

    func testAPIConfigurationBuildsWebSocketURL() {
        let config = MihomoAPIConfiguration(host: "127.0.0.1", port: 9_090, secret: "abc")
        XCTAssertEqual(
            config.webSocketURL(path: "/traffic")?.absoluteString,
            "ws://127.0.0.1:9090/traffic"
        )
        XCTAssertEqual(
            config.webSocketURL(path: "memory")?.absoluteString,
            "ws://127.0.0.1:9090/memory"
        )
    }
}
