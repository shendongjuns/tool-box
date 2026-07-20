// platform 模块 — 平台相关（Windows）
plugins {
    kotlin("jvm")
}

dependencies {
    implementation(project(":common"))

    // 后续按需添加：JNA、Win32 API 封装等
}
