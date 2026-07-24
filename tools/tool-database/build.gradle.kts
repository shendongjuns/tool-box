// tool-database 模块 — 数据库管理 SQL 客户端
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

    // Compose
    implementation(compose.runtime)
    implementation(compose.material3)
    implementation(compose.materialIconsExtended)
    implementation(compose.desktop.currentOs)

    // MySQL JDBC Driver
    implementation("com.mysql:mysql-connector-j:9.1.0")

    // HikariCP 连接池
    implementation("com.zaxxer:HikariCP:6.2.1")

    // kotlinx-serialization（JSON 配置持久化）
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
}
