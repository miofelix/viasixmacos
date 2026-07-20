import XCTest

@testable import ViaSixCore

final class VirtualInterfaceManagerTests: XCTestCase {
    func testNetworkAccessModeIsSingleAndDecodesCommonAliases() throws {
        XCTAssertEqual(NetworkAccessMode.localProxy.displayName, "本地代理")
        XCTAssertTrue(NetworkAccessMode.systemProxy.usesSystemProxy)
        XCTAssertTrue(NetworkAccessMode.virtualInterface.usesVirtualInterface)

        let decoder = JSONDecoder()
        XCTAssertEqual(try decoder.decode(NetworkAccessMode.self, from: Data(#""tun""#.utf8)), .virtualInterface)
        XCTAssertEqual(try decoder.decode(NetworkAccessMode.self, from: Data(#""system-proxy""#.utf8)), .systemProxy)
        XCTAssertThrowsError(try decoder.decode(NetworkAccessMode.self, from: Data(#""both""#.utf8)))
    }

    func testParsesMihomoVersionOutputAndIgnoresGoVersion() throws {
        let output = "Mihomo Meta v1.19.29 darwin arm64 with go1.26.5 Sat Jul 18 12:19:57 UTC 2026"
        let version = try XCTUnwrap(MihomoRuntimeVersion.parse(output))
        XCTAssertEqual(version, MihomoRuntimeVersion(1, 19, 29))
        XCTAssertEqual(version.description, "1.19.29")
        XCTAssertEqual(MihomoRuntimeVersion.minimumSafe, MihomoRuntimeVersion(1, 19, 29))
        XCTAssertNil(MihomoRuntimeVersion.parse("Mihomo development build without a version"))
        XCTAssertNil(MihomoRuntimeVersion.parse("go1.26.5 darwin/arm64"))
        XCTAssertNil(MihomoRuntimeVersion.parse("1.19.29"))
    }

    func testVersionComparisonTreatsReleaseAsNewerThanPrerelease() {
        XCTAssertLessThan(MihomoRuntimeVersion(1, 19, 29), MihomoRuntimeVersion(1, 20, 0))
        XCTAssertLessThan(
            MihomoRuntimeVersion(major: 1, minor: 19, patch: 29, prerelease: "rc1"),
            MihomoRuntimeVersion(1, 19, 29)
        )
        XCTAssertGreaterThanOrEqual(MihomoRuntimeVersion(1, 19, 29), .minimumSafe)
        XCTAssertLessThan(MihomoRuntimeVersion(1, 19, 28), .minimumSafe)
    }

    func testFeatureSetRequiresExplicitDNSManagement() {
        XCTAssertTrue(VirtualInterfaceFeature.minimumSafe.contains(.ipv4))
        XCTAssertTrue(VirtualInterfaceFeature.minimumSafe.contains(.ipv6))
        XCTAssertTrue(VirtualInterfaceFeature.minimumSafe.contains(.systemRouting))
        XCTAssertTrue(VirtualInterfaceFeature.minimumSafe.contains(.loopbackPrevention))
        XCTAssertTrue(VirtualInterfaceFeature.minimumSafe.contains(.crashRecovery))
        XCTAssertTrue(VirtualInterfaceFeature.minimumSafe.contains(.networkChangeRecovery))
        XCTAssertTrue(VirtualInterfaceFeature.minimumSafe.contains(.dnsManagement))
        XCTAssertEqual(VirtualInterfaceFeature.systemRoutes, .systemRouting)
    }

    func testCapabilityEvaluationFailsClosedInDeterministicOrder() {
        XCTAssertEqual(
            VirtualInterfaceCapability.evaluate(.unsupportedBuild),
            .unavailable(.unsupportedBuild)
        )
        XCTAssertEqual(
            VirtualInterfaceCapability.evaluate(VirtualInterfaceProbe()),
            .unavailable(.runtimeMissing)
        )

        let oldRuntime = VirtualInterfaceProbe(
            runtimeVersion: MihomoRuntimeVersion(1, 18, 10),
            helperAvailable: true,
            permissionAvailable: true
        )
        XCTAssertEqual(
            VirtualInterfaceCapability.evaluate(oldRuntime),
            .unavailable(
                .runtimeTooOld(installed: MihomoRuntimeVersion(1, 18, 10), minimum: .minimumSafe)
            )
        )

        let currentRuntime = MihomoRuntimeVersion.minimumSafe
        XCTAssertEqual(
            VirtualInterfaceCapability.evaluate(
                VirtualInterfaceProbe(
                    runtimeVersion: currentRuntime,
                    supportedFeatures: .minimumSafe
                )
            ),
            .unavailable(.helperUnavailable)
        )
        XCTAssertEqual(
            VirtualInterfaceCapability.evaluate(
                VirtualInterfaceProbe(
                    runtimeVersion: currentRuntime,
                    helperAvailable: true,
                    supportedFeatures: .minimumSafe
                )
            ),
            .unavailable(.permissionUnavailable)
        )
        XCTAssertEqual(
            VirtualInterfaceCapability.evaluate(
                VirtualInterfaceProbe(
                    runtimeVersion: currentRuntime,
                    helperAvailable: true,
                    permissionAvailable: true
                )
            ),
            .unavailable(.unsupportedBuild)
        )

        let available = VirtualInterfaceCapability.evaluate(
            VirtualInterfaceProbe(
                runtimeVersion: currentRuntime,
                helperAvailable: true,
                permissionAvailable: true,
                supportedFeatures: .minimumSafe
            )
        )
        XCTAssertTrue(available.isAvailable)
        XCTAssertTrue(available.isAvailableForUI)
        XCTAssertTrue(available.features.contains(.loopbackPrevention))
    }

    func testMissingRequiredFeatureFailsAsUnsupportedBuild() {
        let probe = VirtualInterfaceProbe(
            runtimeVersion: .minimumSafe,
            helperAvailable: true,
            permissionAvailable: true,
            supportedFeatures: [.ipv4, .ipv6, .systemRouting],
            requiredFeatures: .minimumSafe
        )
        XCTAssertEqual(
            VirtualInterfaceCapability.evaluate(probe),
            .unavailable(.unsupportedBuild)
        )

        let cannotWeakenBaseline = VirtualInterfaceProbe(
            runtimeVersion: .minimumSafe,
            helperAvailable: true,
            permissionAvailable: true,
            supportedFeatures: [],
            requiredFeatures: []
        )
        XCTAssertEqual(
            VirtualInterfaceCapability.evaluate(cannotWeakenBaseline),
            .unavailable(.unsupportedBuild)
        )
    }

    func testConfigurationValidationRejectsUnsafeValues() {
        XCTAssertNoThrow(try VirtualInterfaceConfiguration().validated())
        XCTAssertThrowsError(try VirtualInterfaceConfiguration(mtu: 128).validated()) { error in
            XCTAssertEqual(error as? VirtualInterfaceManagerError, .invalidMTU(128))
        }
        XCTAssertThrowsError(
            try VirtualInterfaceConfiguration(features: [.ipv4, .ipv6]).validated()
        ) { error in
            guard case .missingRequiredFeatures = error as? VirtualInterfaceManagerError else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testUnavailableManagerFailsEnableAndMakesCleanupNoOps() async {
        let manager = UnavailableVirtualInterfaceManager(reason: .helperUnavailable)
        let capability = await manager.probe()
        XCTAssertEqual(capability, .unavailable(.helperUnavailable))
        let uiEnabled = await manager.isAvailableForUI
        XCTAssertFalse(uiEnabled)
        let initialStatus = await manager.status()
        XCTAssertEqual(initialStatus, .unavailable(.helperUnavailable))

        do {
            try await manager.enable(configuration: .init())
            XCTFail("enable must fail explicitly")
        } catch {
            XCTAssertEqual(
                error as? VirtualInterfaceManagerError,
                .unavailable(.helperUnavailable)
            )
        }

        try? await manager.disable()
        try? await manager.recoverIfNeeded()
        let finalStatus = await manager.status()
        XCTAssertEqual(finalStatus, .unavailable(.helperUnavailable))
    }

    func testCapabilityCodableRoundTrip() throws {
        let value = MihomoRuntimeVersion(major: 1, minor: 19, patch: 29, prerelease: "rc1")
        let encoded = try JSONEncoder().encode(value)
        XCTAssertEqual(String(data: encoded, encoding: .utf8), #""1.19.29-rc1""#)
        XCTAssertEqual(try JSONDecoder().decode(MihomoRuntimeVersion.self, from: encoded), value)
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                MihomoRuntimeVersion.self,
                from: Data(#""Mihomo Meta v1.19.29""#.utf8)
            )
        )

        let features: VirtualInterfaceFeature = [.ipv4, .systemRouting, .crashRecovery]
        let featureData = try JSONEncoder().encode(features)
        XCTAssertEqual(try JSONDecoder().decode(VirtualInterfaceFeature.self, from: featureData), features)
    }
}
