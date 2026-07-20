// common 模块 — 通用基础设施（设计系统、工具类、扩展函数）
@file:Suppress("DEPRECATION")

plugins {
    kotlin("jvm")
    kotlin("plugin.compose")
    id("org.jetbrains.compose")
}

dependencies {
    // Compose 运行时 + Material 3（设计系统需要）
    implementation(compose.runtime)
    implementation(compose.material3)
    implementation(compose.materialIconsExtended)
}
