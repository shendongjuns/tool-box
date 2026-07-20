# ToolBox

[![Kotlin](https://img.shields.io/badge/Kotlin-2.3.0-7F52FF.svg)](https://kotlinlang.org)
[![Compose](https://img.shields.io/badge/Compose%20Desktop-1.11.1-4285F4.svg)](https://www.jetbrains.com/lp/compose-multiplatform/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

基于 Kotlin + Jetpack Compose Desktop 构建的现代桌面工具箱。简洁、克制、高效 —— 借鉴 Apple 设计语言。

## ✨ 特性

- 🎨 **极简设计** — Apple 风格定制设计系统，干净克制
- 🧩 **模块化架构** — 工具通过 ServiceLoader 插件化注册，独立模块互不干扰
- 🪟 **Windows 原生** — 针对 Windows 优化，支持 MSI 安装包
- 🚢 **CI/CD** — Tag 推送自动构建发布

## 🚀 快速开始

### 环境要求

- JDK 25+
- Gradle（已包含 Wrapper）

### 运行

```bash
./gradlew :app:run
```

### 打包安装包

```bash
./gradlew :app:createDistributable
```

安装包生成在 `app/build/compose/binaries/main/msi/` 目录下。

## 📦 项目结构

```
tool-box/
├── app/               # 主程序壳 + 框架层（窗口、导航、插件加载）
├── tool-api/          # 工具接口定义（Tool、ToolCategory）
├── common/            # 共享设计系统 + 通用工具类
├── platform/          # 平台相关（Windows 注册表、进程管理等）
└── .github/workflows/ # CI/CD（Tag 触发构建 → GitHub Release）
```

## 🏗️ 添加新工具

1. 在 `settings.gradle.kts` 中添加模块：`include(":tools:tool-xxx")`
2. 创建模块目录和 `build.gradle.kts`
3. 实现 `Tool` 接口，用 Compose 编写 UI
4. 在 `META-INF/services/com.toolbox.api.Tool` 中注册
5. 在 `app/build.gradle.kts` 中添加依赖：`implementation(project(":tools:tool-xxx"))`
6. 运行 `./gradlew :app:run` 验证

## 🚢 发布

推送版本 Tag 即可触发自动构建：

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions 会自动构建 MSI 安装包并附加到新 Release。

## 📝 许可证

MIT © shendongjuns
