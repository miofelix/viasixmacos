import Foundation
import XCTest

@testable import ViaSixApp
@testable import ViaSixCore

final class ConnectionPresentationTests: XCTestCase {
    func testConnectionSortOrdersUseStartTimeAndTrafficTotals() {
        let first = ConnectionRecord(
            connection: connection(
                id: "first",
                start: "2026-07-21T10:00:00Z",
                upload: 900,
                download: 100
            ),
            closedAt: nil
        )
        let second = ConnectionRecord(
            connection: connection(
                id: "second",
                start: "2026-07-21T11:00:00Z",
                upload: 200,
                download: 800
            ),
            closedAt: nil
        )

        XCTAssertEqual(
            [first, second].sorted(by: ConnectionSortOrder.recent.areInIncreasingOrder)
                .map(\.connection.id),
            ["second", "first"]
        )
        XCTAssertEqual(
            [first, second].sorted(by: ConnectionSortOrder.download.areInIncreasingOrder)
                .map(\.connection.id),
            ["second", "first"]
        )
        XCTAssertEqual(
            [first, second].sorted(by: ConnectionSortOrder.upload.areInIncreasingOrder)
                .map(\.connection.id),
            ["first", "second"]
        )
    }

    func testConnectionDurationParsesMihomoTimestamps() throws {
        let end = try XCTUnwrap(RuntimePresentation.date("2026-07-21T11:02:03Z"))

        XCTAssertEqual(
            RuntimePresentation.connectionDuration(
                start: "2026-07-21T10:00:00.000Z",
                end: end
            ),
            "1 小时 2 分"
        )
        XCTAssertEqual(RuntimePresentation.connectionDuration(start: nil, end: end), "未知")
    }

    private func connection(
        id: String,
        start: String,
        upload: Int64,
        download: Int64
    ) -> MihomoConnection {
        MihomoConnection(
            id: id,
            metadata: MihomoConnection.Metadata(
                network: "tcp",
                type: "HTTP",
                sourceIP: "127.0.0.1",
                destinationIP: "1.1.1.1",
                sourcePort: "50000",
                destinationPort: "443",
                host: "example.com",
                dnsMode: "normal",
                processPath: nil,
                process: nil
            ),
            upload: upload,
            download: download,
            start: start,
            chains: ["GLOBAL"],
            rule: "Match",
            rulePayload: ""
        )
    }
}
