allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // Patrol 4.x brings uiautomator 2.3.0, which turns on
    // FLAG_RETRIEVE_INTERACTIVE_WINDOWS; with it, UiAutomator sees the survey
    // WebView with no children, so the golden journey cannot find its
    // content. 2.2.0 does not set the flag. leancodepl/patrol#3178.
    configurations.all {
        resolutionStrategy.force("androidx.test.uiautomator:uiautomator:2.4.1")
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
