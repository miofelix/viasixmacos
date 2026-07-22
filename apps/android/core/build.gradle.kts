plugins {
    id("org.jetbrains.kotlin.jvm")
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation("org.yaml:snakeyaml:2.3")
    testImplementation(kotlin("test"))
    testImplementation("org.junit.jupiter:junit-jupiter:5.11.4")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test {
    useJUnitPlatform()
    // monorepo contracts live at repo root: apps/android/core -> ../../..
    systemProperty(
        "viasix.contracts.root",
        rootProject.projectDir.resolve("../..").canonicalPath,
    )
}
