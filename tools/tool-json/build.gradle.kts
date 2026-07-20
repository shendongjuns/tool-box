// tool-json 模块 — JSON 格式化工具
plugins {
    kotlin("jvm")
    kotlin("plugin.compose")
    kotlin("plugin.serialization")
    id("org.jetbrains.compose")
}

dependencies {
    implementation(project(":tool-api"))
    implementation(project(":common"))

    // JSON 序列化
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.10.0")

    // Compose Desktop（UI 组件）
    implementation(compose.desktop.currentOs)
    implementation(compose.material3)
    implementation(compose.materialIconsExtended)
}
