// app 模块 — 主程序壳
@file:Suppress("DEPRECATION")

plugins {
    kotlin("jvm")
    kotlin("plugin.compose")
    id("org.jetbrains.compose")
}

dependencies {
    // Compose Desktop（提供 Skiko 原生库，不可省略）
    implementation(compose.desktop.currentOs)

    // Material 3 + 图标
    implementation(compose.material3)
    implementation(compose.materialIconsExtended)

    // 内部模块
    implementation(project(":tool-api"))
    implementation(project(":common"))
    implementation(project(":platform"))
}

compose.desktop {
    application {
        mainClass = "djshen.toolbox.MainKt"
        nativeDistributions {
            targetFormats(org.jetbrains.compose.desktop.application.dsl.TargetFormat.Msi)
            // CI 传入 -PappVersion=x.y.z，本地默认 1.0.0
            packageVersion = project.findProperty("appVersion") as String? ?: "1.0.0"
            packageName = "ToolBox"
            description = "A modern desktop toolbox"
            vendor = "shendongjuns"

            windows {
                menuGroup = "ToolBox"
                upgradeUuid = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
                shortcut = true
                dirChooser = true
                iconFile.set(project.file("src/main/resources/icon.ico"))
            }
        }
    }
}
