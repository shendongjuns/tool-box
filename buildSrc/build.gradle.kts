plugins {
    kotlin("jvm") version "2.3.0"
}

repositories {
    mavenCentral()
}

dependencies {
    implementation("org.apache.xmlgraphics:batik-transcoder:1.17")
    implementation("org.apache.xmlgraphics:batik-codec:1.17")
    implementation("org.apache.xmlgraphics:batik-awt-util:1.17")
}
