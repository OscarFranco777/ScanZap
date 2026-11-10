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
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Parche: flutter_bluetooth_serial 0.4.0 es un plugin viejo sin namespace
// (requerido por AGP 8). Se lo asignamos antes de que AGP cree los variants.
subprojects {
    val setNamespace: () -> Unit = {
        if (name == "flutter_bluetooth_serial") {
            extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
                namespace = "io.github.edufolly.flutterbluetoothserial"
            }
        }
    }
    if (state.executed) {
        setNamespace()
    } else {
        afterEvaluate { setNamespace() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
