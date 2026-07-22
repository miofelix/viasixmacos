package dev.viasix.core.projection

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.yaml.snakeyaml.Yaml
import java.io.File
import java.nio.file.Files

class ContractFixtureTest {
    @Test
    fun allContractProjectionCases() {
        val casesDir = contractsRoot().resolve("contracts/fixtures/mihomo-config/cases")
        assertTrue(casesDir.isDirectory, "missing cases dir: $casesDir")
        val cases = casesDir.listFiles()?.filter { it.isDirectory }?.sortedBy { it.name }.orEmpty()
        assertTrue(cases.isNotEmpty(), "no contract cases")

        for (caseDir in cases) {
            runCase(caseDir)
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun runCase(caseDir: File) {
        val caseJson = Files.readString(caseDir.resolve("case.json").toPath())
        val case = parseCase(caseJson)
        val input = Files.readString(caseDir.resolve("input.yaml").toPath())

        val options =
            ProjectOptions(
                routingMode = RoutingMode.parse(case.routingMode)!!,
                projection = ProjectionKind.parse(case.projection)!!,
                selectedAddress = case.selectedAddress,
            )
        val profile =
            if (case.requireProfile == false) {
                null
            } else {
                input
            }

        try {
            val root = MihomoProjection.project(profile, options)
            assertTrue(case.expect.success, "case ${case.id} expected failure but succeeded")
            assertSuccess(case.id, root, case.expect)
        } catch (error: ProjectError) {
            assertFalse(case.expect.success, "case ${case.id} unexpected error: $error")
            assertEquals(case.expect.errorCode, error.contractCode, "case ${case.id} error code")
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun assertSuccess(id: String, root: Map<String, Any?>, expect: Expect) {
        expect.mode?.let { assertEquals(it, root["mode"], "$id: mode") }
        val proxies = (root["proxies"] as? List<*>).orEmpty()
        expect.proxyCount?.let { assertEquals(it, proxies.size, "$id: proxyCount") }
        val primary = proxies.firstOrNull() as? Map<*, *>
        expect.primaryProxyName?.let {
            assertEquals(it, primary?.get("name")?.toString(), "$id: primaryProxyName")
        }
        expect.primaryProxyServer?.let {
            assertEquals(it, primary?.get("server")?.toString(), "$id: primaryProxyServer")
        }
        for (key in expect.absentKeys.orEmpty()) {
            assertFalse(root.containsKey(key), "$id: expected absent $key")
        }
        val rules = (root["rules"] as? List<*>)?.map { it.toString() }.orEmpty()
        expect.lastRule?.let { assertEquals(it, rules.lastOrNull(), "$id: lastRule") }
        for (rule in expect.rulesMustContain.orEmpty()) {
            assertTrue(rules.contains(rule), "$id: missing rule $rule in $rules")
        }
        expect.rulesExact?.let { assertEquals(it, rules, "$id: rulesExact") }
        expect.tunEnable?.let {
            val tun = root["tun"] as? Map<*, *>
            assertEquals(it, tun?.get("enable") as? Boolean, "$id: tunEnable")
        }
    }

    private fun contractsRoot(): File {
        val prop = System.getProperty("viasix.contracts.root")
        if (!prop.isNullOrBlank()) {
            return File(prop)
        }
        var dir = File("").absoluteFile
        repeat(10) {
            if (File(dir, "contracts/VERSION").isFile) return dir
            dir = dir.parentFile ?: return@repeat
        }
        error("contracts/VERSION not found")
    }

    private fun parseCase(json: String): CaseFile {
        // Minimal JSON parse without extra deps: use org.json? not available.
        // SnakeYAML can parse JSON as YAML.
        @Suppress("UNCHECKED_CAST")
        val map = Yaml().load<Map<String, Any?>>(json)
        val expectMap = map["expect"] as Map<String, Any?>
        return CaseFile(
            id = map["id"].toString(),
            selectedAddress = map["selectedAddress"] as String?,
            routingMode = map["routingMode"].toString(),
            projection = map["projection"].toString(),
            requireProfile = map["requireProfile"] as Boolean?,
            expect =
                Expect(
                    success = expectMap["success"] as Boolean,
                    errorCode = expectMap["errorCode"] as String?,
                    mode = expectMap["mode"] as String?,
                    proxyCount = (expectMap["proxyCount"] as Number?)?.toInt(),
                    primaryProxyName = expectMap["primaryProxyName"] as String?,
                    primaryProxyServer = expectMap["primaryProxyServer"] as String?,
                    absentKeys = (expectMap["absentKeys"] as List<*>?)?.map { it.toString() },
                    lastRule = expectMap["lastRule"] as String?,
                    rulesMustContain =
                        (expectMap["rulesMustContain"] as List<*>?)?.map { it.toString() },
                    rulesExact = (expectMap["rulesExact"] as List<*>?)?.map { it.toString() },
                    tunEnable = expectMap["tunEnable"] as Boolean?,
                ),
        )
    }

    private data class CaseFile(
        val id: String,
        val selectedAddress: String?,
        val routingMode: String,
        val projection: String,
        val requireProfile: Boolean?,
        val expect: Expect,
    )

    private data class Expect(
        val success: Boolean,
        val errorCode: String?,
        val mode: String?,
        val proxyCount: Int?,
        val primaryProxyName: String?,
        val primaryProxyServer: String?,
        val absentKeys: List<String>?,
        val lastRule: String?,
        val rulesMustContain: List<String>?,
        val rulesExact: List<String>?,
        val tunEnable: Boolean?,
    )
}
