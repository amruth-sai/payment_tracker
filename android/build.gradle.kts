buildscript {
    repositories {
        google()
        mavenCentral()
    }
}

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
    
    // Fix namespace for plugins that don't specify it
    afterEvaluate {
        val android = project.extensions.findByName("android")
        if (android != null) {
            when (android) {
                is com.android.build.gradle.LibraryExtension -> {
                    if (android.namespace.isNullOrEmpty()) {
                        // Get package from AndroidManifest.xml
                        val manifestFile = project.file("src/main/AndroidManifest.xml")
                        if (manifestFile.exists()) {
                            val manifest = groovy.util.XmlSlurper().parse(manifestFile)
                            val packageName = manifest.getProperty("@package")?.toString()
                            if (!packageName.isNullOrEmpty()) {
                                android.namespace = packageName
                            }
                        }
                    }
                }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
