import XCTest
@testable import ViaSixCore

final class CfstOutputParserTests: XCTestCase {
    func testProgressAndANSIOutputAreParsed() {
        var parser = CfstOutputParser()
        let first = parser.consume(Data("\u{001B}[2K 12 / 100 [====\r".utf8))
        let second = parser.consume(Data("\nready\n".utf8))
        let events = first + second + parser.finish()

        XCTAssertTrue(events.contains(.progress(current: 12, total: 100)))
        XCTAssertTrue(events.contains(.line("ready")))
        XCTAssertTrue(events.contains { event in
            if case .heartbeat(let bytes) = event { return bytes > 0 }
            return false
        })
    }

    func testProgressIsFoundBeforeLineTerminationAndHeartbeatIsThrottled() {
        var parser = CfstOutputParser()
        let start = Date(timeIntervalSince1970: 100)
        let first = parser.consume(Data("1 / 20 [=".utf8), now: start)
        let second = parser.consume(Data("==".utf8), now: start.addingTimeInterval(0.1))

        XCTAssertTrue(first.contains(.progress(current: 1, total: 20)))
        XCTAssertEqual(first.filter(\.isHeartbeat).count, 1)
        XCTAssertEqual(second.filter(\.isHeartbeat).count, 0)
    }
}

private extension CfstOutputEvent {
    var isHeartbeat: Bool {
        if case .heartbeat = self { return true }
        return false
    }
}
