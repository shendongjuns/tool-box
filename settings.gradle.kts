pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        maven("https://maven.pkg.jetbrains.space/public/p/compose/dev")
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        maven("https://maven.pkg.jetbrains.space/public/p/compose/dev")
    }
}

rootProject.name = "tool-box"

// 主程序
include(":app")

// 工具接口定义
include(":tool-api")

// 通用基础设施
include(":common")

// 平台相关（Windows）
include(":platform")

// ═══ 工具模块 ═══
include(":tools:tool-json")
