import org.gradle.api.plugins.JavaPluginExtension
import org.gradle.jvm.toolchain.JavaLanguageVersion
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// ---------------------------------------------------------------------------
// Java / Kotlin 目标版本统一
//
// 为什么需要：部分第三方插件（file_picker 10.3.3 等）在自己的 build.gradle 里
// 写死了 `kotlinOptions { jvmTarget = "1.8" }`，而 AGP 9 的默认 Java 目标已经是 11。
// Kotlin 编译器会在任务执行时直接报：
//   Inconsistent JVM-target compatibility detected for tasks
//   'compileDebugJavaWithJavac' (11) and 'compileDebugKotlin' (1.8)
// 于是整个 APK 构建失败 —— 而 App 自己的代码完全没问题。
//
// 做法：
//   Java 侧 → Java toolchain = 17（AGP 在没显式写 compileOptions 时按 toolchain 取）
//   Kotlin 侧 → 任务级 jvmTarget = 17（覆盖插件 build.gradle 里写死的值）
// 只在插件模块上动，:app 本来就是 17/17。
// ---------------------------------------------------------------------------
subprojects {
    plugins.withId("com.android.library") {
        extensions.configure<JavaPluginExtension> {
            toolchain.languageVersion.set(JavaLanguageVersion.of(17))
        }
    }
    plugins.withId("com.android.application") {
        extensions.configure<JavaPluginExtension> {
            toolchain.languageVersion.set(JavaLanguageVersion.of(17))
        }
    }
    tasks.withType<KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
