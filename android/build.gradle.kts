allprojects {
    repositories {
        google()
        mavenCentral()
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

    afterEvaluate {
        tasks.matching { it.name.startsWith("lint") || it.name.contains("Lint") }.configureEach {
            enabled = false
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
    tasks.withType<JavaCompile>().configureEach {
        doFirst {
            val sqfliteUtils = project.file("src/main/java/com/tekartik/sqflite/Utils.java")
            if (sqfliteUtils.exists()) {
                val src = sqfliteUtils.readText()
                if (src.contains("BAKLAVA") || src.contains("Locale.of(") || src.contains("thread.threadId()")) {
                    val patched = src
                        .replace(
                            Regex("""if\s*\(\s*Build\.VERSION\.SDK_INT\s*>=\s*Build\.VERSION_CODES\.BAKLAVA\s*\)\s*\{[^}]*Locale\.of\([^}]*\}\s*else\s*\{([^}]*)\}"""),
                            "$1"
                        )
                        .replace(
                            Regex("""if\s*\(\s*Build\.VERSION\.SDK_INT\s*>=\s*Build\.VERSION_CODES\.BAKLAVA\s*\)\s*\{[^}]*thread\.threadId\(\)[^}]*\}\s*else\s*\{([^}]*)\}"""),
                            "$1"
                        )
                    if (patched != src) {
                        sqfliteUtils.writeText(patched)
                    }
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
