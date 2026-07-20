// tool-json 模块 — JSON 格式化工具
@file:Suppress("DEPRECATION")

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

    // Compose Desktop（提供 Skiko 原生库）
    implementation(compose.desktop.currentOs)

    // Material 3 + 图标
    implementation(compose.material3)
    implementation(compose.materialIconsExtended)
}
