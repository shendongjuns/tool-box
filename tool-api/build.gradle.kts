// tool-api 模块 — 工具接口定义
plugins {
    kotlin("jvm")
    kotlin("plugin.compose")
    id("org.jetbrains.compose")
}

dependencies {
    implementation(project(":common"))

    // Compose 运行时（Tool.Content() 返回 @Composable 需要）
    implementation(compose.runtime)
}
