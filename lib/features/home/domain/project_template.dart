import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter/widgets.dart';

enum ProjectTemplateType {
  html('HTML/JS', 'Simple web project with HTML, CSS, and JS', LucideIcons.globe),
  react('React', 'Modern React project using Vite', LucideIcons.atom),
  vue('Vue', 'Modern Vue.js project using Vite', LucideIcons.monitor),
  node('Node.js', 'Express.js backend project', LucideIcons.server),
  php('PHP', 'Traditional PHP web project', LucideIcons.file_code),
  python('Python', 'Simple Python script or app', LucideIcons.code),
  flutter('Flutter', 'Cross-platform mobile & web app', LucideIcons.layout_template),
  genkit('Genkit AI App', 'Fullstack AI agents & flows with Dart & Genkit 1.0', LucideIcons.sparkles),
  androidCompose('Android (Compose)', 'Native Android app with Jetpack Compose & Material 3', LucideIcons.smartphone),
  androidKotlin('Android (Kotlin/Views)', 'Native Android app with Kotlin & XML layouts', LucideIcons.layers),
  androidJava('Android (Java/Views)', 'Native Android app with Java & XML layouts', LucideIcons.coffee),
  rust('Rust', 'High-performance systems programming', LucideIcons.cpu);

  final String title;
  final String description;
  final IconData icon;

  const ProjectTemplateType(this.title, this.description, this.icon);
}

class ProjectTemplate {
  static Map<String, String> getFiles(ProjectTemplateType type, String projectName) {
    switch (type) {
      case ProjectTemplateType.html:
        return {
          'index.html': '''<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$projectName</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <div class="container">
        <h1>Hello from QuantumIDE!</h1>
        <p>Welcome to your new HTML/JS project: <strong>$projectName</strong></p>
        <button onclick="showAlert()">Click Me</button>
    </div>
    <script src="script.js"></script>
</body>
</html>''',
          'style.css': '''body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    background: #0f172a;
    color: white;
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100vh;
    margin: 0;
}
.container {
    text-align: center;
    padding: 2rem;
    background: #1e293b;
    border-radius: 1rem;
    box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
}
h1 { color: #38bdf8; }
button {
    background: #38bdf8;
    color: #0f172a;
    border: none;
    padding: 0.5rem 1rem;
    border-radius: 0.5rem;
    cursor: pointer;
    font-weight: bold;
}''',
          'script.js': '''function showAlert() {
  alert("Hello from QuantumIDE!");
  console.log("Project $projectName is running!");
}''',
        };

      case ProjectTemplateType.react:
        return {
          'index.html': '''<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>$projectName</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>''',
          'src/main.jsx': '''import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.jsx'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)''',
          'src/App.jsx': '''import { useState } from 'react'
import './App.css'

function App() {
  const [count, setCount] = useState(0)

  return (
    <div className="App">
      <h1>$projectName</h1>
      <div className="card">
        <button onClick={() => setCount((count) => count + 1)}>
          count is {count}
        </button>
      </div>
    </div>
  )
}

export default App''',
          'src/index.css': 'body { margin: 0; font-family: sans-serif; background: #242424; color: white; }',
          'package.json': '''{
  "name": "${projectName.toLowerCase().replaceAll(' ', '-')}",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  },
  "devDependencies": {
    "@types/react": "^18.2.66",
    "@types/react-dom": "^18.2.22",
    "@vitejs/plugin-react": "^4.2.1",
    "vite": "^5.2.0"
  }
}''',
        };

      case ProjectTemplateType.vue:
        return {
          'index.html': '''<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>$projectName</title>
  </head>
  <body>
    <div id="app"></div>
    <script type="module" src="/src/main.js"></script>
  </body>
</html>''',
          'src/main.js': '''import { createApp } from 'vue'
import './style.css'
import App from './App.vue'

createApp(App).mount('#app')''',
          'src/App.vue': '''<script setup>
import { ref } from 'vue'
const count = ref(0)
</script>

<template>
  <div>
    <h1>$projectName</h1>
    <button type="button" @click="count++">count is {{ count }}</button>
  </div>
</template>

<style scoped>
h1 { color: #42b883; }
</style>''',
          'package.json': '''{
  "name": "${projectName.toLowerCase().replaceAll(' ', '-')}",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "vue": "^3.4.21"
  },
  "devDependencies": {
    "@vitejs/plugin-vue": "^5.0.4",
    "vite": "^5.2.0"
  }
}''',
        };

      case ProjectTemplateType.node:
        return {
          'src/index.js': '''const express = require('express');
const app = express();
const port = 3000;

app.get('/', (req, res) => {
  res.send('Hello from $projectName!');
});

app.listen(port, () => {
  console.log(`Server running at http://localhost:\${port}`);
});''',
          'package.json': '''{
  "name": "${projectName.toLowerCase().replaceAll(' ', '-')}",
  "version": "1.0.0",
  "main": "src/index.js",
  "dependencies": {
    "express": "^4.18.2"
  }
}''',
          'README.md': '# $projectName\\n\\nNode.js backend project.',
        };

      case ProjectTemplateType.php:
        return {
          'index.php': '''<?php
\$projectName = "$projectName";
?>
<!DOCTYPE html>
<html>
<head>
    <title><?php echo \$projectName; ?></title>
</head>
<body>
    <h1>Hello from PHP in <?php echo \$projectName; ?>!</h1>
</body>
</html>''',
          'config.php': '<?php define("DB_HOST", "localhost"); ?>',
        };

      case ProjectTemplateType.python:
        return {
          'main.py': '''def main():
    print("Hello from $projectName!")
    print("Welcome to QuantumIDE Python template.")

if __name__ == "__main__":
    main()''',
          'requirements.txt': '# Add your dependencies here\n# requests==2.31.0',
          'README.md': '# $projectName\n\nA simple Python project created with QuantumIDE.',
        };

      case ProjectTemplateType.flutter:
        return {
          'lib/main.dart': '''import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '$projectName',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: '$projectName Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '\$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}''',
          'pubspec.yaml': '''name: ${projectName.toLowerCase().replaceAll(' ', '_')}
description: "A new Flutter project."
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.3.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.6

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true''',
          'README.md': '# $projectName\n\nA new Flutter project created with QuantumIDE.',
        };

      case ProjectTemplateType.genkit:
        final pkgSlug = projectName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
        return {
          'pubspec.yaml': '''name: $pkgSlug
description: "AI-powered application built with Genkit Dart 1.0 and Flutter."
publish_to: 'none'
version: 1.0.0

environment:
  sdk: '>=3.12.0 <4.0.0'

dependencies:
  genkit: ^1.0.0
  genkit_google_genai: ^1.0.0
  genkit_openai: ^1.0.0
  genkit_middleware: ^1.0.0
  schemantic: ^1.0.0

dev_dependencies:
  lints: ^5.0.0
  test: ^1.25.0
''',
          'bin/main.dart': '''import 'dart:io';
import 'package:genkit/genkit.dart';
import 'package:genkit_google_genai/genkit_google_genai.dart';
import 'package:genkit_middleware/genkit_middleware.dart';
import 'package:schemantic/schemantic.dart';

void main() async {
  // Initialize Genkit with Gemini and production middleware
  final ai = Genkit(plugins: [
    googleAI(apiKey: Platform.environment['GEMINI_API_KEY']),
    ToolApprovalPlugin(),
  ]);

  // Define a tool with Human-in-the-Loop interrupt
  final calculateDiscount = ai.defineTool(
    name: 'calculateDiscount',
    description: 'Calculates a discount for a customer. Requires confirmation.',
    inputSchema: SchemanticType.from<Map<String, dynamic>>(
      jsonSchema: {
        'type': 'object',
        'properties': {
          'percent': {'type': 'integer', 'description': 'Discount percent'},
          'amount': {'type': 'number', 'description': 'Original price'},
        },
        'required': ['percent', 'amount'],
      },
      parse: (j) => Map<String, dynamic>.from(j as Map),
    ),
    fn: (input, ctx) async {
      final percent = input['percent'] as int;
      final amount = (input['amount'] as num).toDouble();

      // Require user confirmation before applying discount
      if (ctx.resumed == null) {
        return ToolResult.interrupt({
          'action': 'apply_discount',
          'percent': percent,
          'amount': amount,
        });
      }

      final discounted = amount * (1.0 - percent / 100.0);
      return ToolResult.response('Discounted price is \\\$\${discounted.toStringAsFixed(2)}');
    },
  );

  print('🤖 Generating with Genkit Dart 1.0...');
  final result = await ai.generate(
    model: googleAI.gemini('gemini-2.5-flash'),
    prompt: 'Give me a 20% discount on a 150 dollar purchase.',
    tools: [calculateDiscount],
    use: [
      retry(maxRetries: 3),
      toolApproval(approved: ['calculateDiscount']),
    ],
  );

  print('Result: \${result.text}');
}
''',
          'prompts/greeting.prompt': '''---
model: googleai/gemini-2.5-flash
input:
  schema:
    user: string
    role: string
---
You are an expert developer assistant in QuantumIDE.
Welcome {{user}} who is working as a {{role}}.
Explain how Genkit Dart 1.0 flows and tools can help them build agentic apps.
''',
          'README.md': '''# $projectName

AI-powered application built with **Genkit Dart 1.0**.

## 🚀 Getting Started

1. Set your Gemini API key:
   ```bash
   export GEMINI_API_KEY="your-api-key"
   ```

2. Run the application:
   ```bash
   dart run bin/main.dart
   ```

3. Launch Genkit Developer UI:
   ```bash
   genkit start -- dart run bin/main.dart
   ```
''',
        };

      case ProjectTemplateType.rust:
        return {
          'Cargo.toml': '''[package]
name = "${projectName.toLowerCase().replaceAll(' ', '-')}"
version = "0.1.0"
edition = "2021"

[dependencies]
''',
          'src/main.rs': '''fn main() {
    println!("Hello from $projectName!");
}
''',
          'README.md': '# $projectName\n\nA Rust project created with QuantumIDE.',
        };

      case ProjectTemplateType.androidCompose:
        final pkgSlug = projectName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
        final pkgName = 'com.example.$pkgSlug';
        return {
          'settings.gradle.kts': '''pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "$projectName"
include(":app")
''',
          'build.gradle.kts': '''plugins {
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}
''',
          'gradle.properties': '''android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
org.gradle.jvmargs=-Xmx1024m -XX:MaxMetaspaceSize=256m
org.gradle.daemon=false
org.gradle.parallel=false
org.gradle.java.home=/usr/lib/jvm/java-17-openjdk-arm64
''',
          'app/build.gradle.kts': '''plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "$pkgName"
    compileSdk = 35

    defaultConfig {
        applicationId = "$pkgName"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.15"
    }
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation(platform("androidx.compose:compose-bom:2024.02.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
}
''',
          'app/src/main/AndroidManifest.xml': '''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:allowBackup="true"
        android:label="$projectName"
        android:supportsRtl="true"
        android:theme="@android:style/Theme.Material.NoActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
''',
          'app/src/main/java/com/example/$pkgSlug/MainActivity.kt': '''package $pkgName

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    Greeting("$projectName")
                }
            }
        }
    }
}

@Composable
fun Greeting(name: String, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.fillMaxSize().padding(16.dp),
        contentAlignment = Alignment.Center
    ) {
        Text(text = "Hello from \$name on Quantum IDE!")
    }
}
''',
          'README.md': '# $projectName\n\nNative Android Jetpack Compose project created with Quantum IDE.',
          '.gitignore': '.gradle/\nlocal.properties\n**/build/\n*.iml\n.idea/\n',
        };

      case ProjectTemplateType.androidKotlin:
        final pkgSlug = projectName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
        final pkgName = 'com.example.$pkgSlug';
        return {
          'settings.gradle.kts': '''pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "$projectName"
include(":app")
''',
          'build.gradle.kts': '''plugins {
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}
''',
          'gradle.properties': '''android.useAndroidX=true
android.enableJetifier=false
kotlin.code.style=official
android.nonTransitiveRClass=true
systemProp.java.net.preferIPv4Stack=true
org.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m
org.gradle.daemon=false
org.gradle.parallel=false
org.gradle.workers.max=1
android.aapt2.daemon=false
android.aapt2FromMaven=false
android.aapt2FromMavenOverride=/usr/bin/aapt2
org.gradle.java.home=/usr/lib/jvm/java-17-openjdk-arm64
''',
          'gradle/wrapper/gradle-wrapper.properties': '''distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
''',
          'gradlew': '''#!/bin/bash
# Smart gradlew for QuantumIDE ARM64 environment
DIR="\$(cd "\$(dirname "\$0")" && pwd)"

# Ensure AAPT2 modern override and IPv4 in gradle.properties
if [ -f "\$DIR/gradle.properties" ]; then
    grep -q "android.aapt2FromMavenOverride" "\$DIR/gradle.properties" 2>/dev/null || printf "\\nsystemProp.java.net.preferIPv4Stack=true\\nandroid.useAndroidX=true\\nandroid.enableJetifier=false\\nandroid.aapt2.daemon=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\norg.gradle.daemon=false\\norg.gradle.parallel=false\\norg.gradle.workers.max=1\\n" >> "\$DIR/gradle.properties"
fi

# Auto-repair deprecated kotlinOptions in app/build.gradle.kts
if [ -f "\$DIR/app/build.gradle.kts" ] && grep -q "kotlinOptions" "\$DIR/app/build.gradle.kts" 2>/dev/null; then
    python3 -c 'import re, os
p = "'"\$DIR/app/build.gradle.kts"'"
if os.path.exists(p):
    with open(p, "r") as f: c = f.read()
    if "kotlinOptions" in c:
        c = re.sub(r"[ \t]*kotlinOptions\\s*[{][^}]*[}]", "\n", c)
        if "compilerOptions" not in c:
            c += "\ntasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {\n    compilerOptions {\n        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)\n    }\n}\n"
        with open(p, "w") as f: f.write(c)' 2>/dev/null || true
fi

GRADLE_BIN=""
if [ -x "/opt/gradle/gradle-8.13/bin/gradle" ]; then
    GRADLE_BIN="/opt/gradle/gradle-8.13/bin/gradle"
elif [ -x "/usr/local/bin/gradle" ]; then
    GRADLE_BIN="/usr/local/bin/gradle"
elif command -v gradle >/dev/null 2>&1; then
    GRADLE_BIN="\$(command -v gradle)"
fi

JAVACMD="java"
if [ -n "\$JAVA_HOME" ] && [ -x "\$JAVA_HOME/bin/java" ]; then
    JAVACMD="\$JAVA_HOME/bin/java"
elif [ -x "/usr/lib/jvm/java-17-openjdk-arm64/bin/java" ]; then
    JAVACMD="/usr/lib/jvm/java-17-openjdk-arm64/bin/java"
fi

if [ -f "\$DIR/gradle/wrapper/gradle-wrapper.jar" ]; then
    exec "\$JAVACMD" -Dorg.gradle.appname=gradlew -classpath "\$DIR/gradle/wrapper/gradle-wrapper.jar" org.gradle.wrapper.GradleWrapperMain "\$@"
elif [ -n "\$GRADLE_BIN" ]; then
    exec "\$GRADLE_BIN" "\$@"
else
    echo "Downloading Gradle Wrapper..."
    mkdir -p "\$DIR/gradle/wrapper"
    if curl -k -fsSL --retry 2 "https://raw.githubusercontent.com/gradle/gradle/v8.11.1/gradle/wrapper/gradle-wrapper.jar" -o "\$DIR/gradle/wrapper/gradle-wrapper.jar" 2>/dev/null; then
        exec "\$JAVACMD" -Dorg.gradle.appname=gradlew -classpath "\$DIR/gradle/wrapper/gradle-wrapper.jar" org.gradle.wrapper.GradleWrapperMain "\$@"
    fi
    echo "ERROR: Gradle not found. Please install Gradle in QuantumIDE Packages." >&2
    exit 1
fi
''',
          'app/build.gradle.kts': '''plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "$pkgName"
    compileSdk = 35

    defaultConfig {
        applicationId = "$pkgName"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
}
''',
          'app/src/main/AndroidManifest.xml': '''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:allowBackup="true"
        android:label="$projectName"
        android:supportsRtl="true"
        android:theme="@style/Theme.AppCompat.Light.DarkActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
''',
          'app/src/main/res/layout/activity_main.xml': '''<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center"
    android:padding="24dp">

    <TextView
        android:id="@+id/textViewTitle"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="$projectName (Kotlin)"
        android:textSize="22sp"
        android:textStyle="bold" />

    <TextView
        android:id="@+id/textViewCounter"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="16dp"
        android:text="Clicks: 0"
        android:textSize="18sp" />

    <Button
        android:id="@+id/btnClick"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="24dp"
        android:text="Click Me!" />

</LinearLayout>
''',
          'app/src/main/res/values/strings.xml': '''<resources>
    <string name="app_name">$projectName</string>
</resources>
''',
          'app/src/main/java/com/example/$pkgSlug/MainActivity.kt': '''package $pkgName

import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
    private var counter = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        val titleView = findViewById<TextView>(R.id.textViewTitle)
        val counterView = findViewById<TextView>(R.id.textViewCounter)
        val button = findViewById<Button>(R.id.btnClick)

        titleView.text = "$projectName (Kotlin)"
        button.setOnClickListener {
            counter++
            counterView.text = "Clicks: \$counter"
            Toast.makeText(this, "Button clicked: \$counter", Toast.LENGTH_SHORT).show()
        }
    }
}
''',
          'README.md': '# $projectName\n\nNative Android Kotlin project created with Quantum IDE.\n\n### Build:\n- Debug: `./gradlew assembleDebug`\n- Release: `./gradlew assembleRelease`\n',
          '.gitignore': '.gradle/\nlocal.properties\n**/build/\n*.iml\n.idea/\n',
        };

      case ProjectTemplateType.androidJava:
        final pkgSlug = projectName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
        final pkgName = 'com.example.$pkgSlug';
        return {
          'settings.gradle.kts': '''pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "$projectName"
include(":app")
''',
          'build.gradle.kts': '''plugins {
    id("com.android.application") version "8.11.1" apply false
}
''',
          'gradle.properties': '''android.useAndroidX=true
android.enableJetifier=false
android.nonTransitiveRClass=true
systemProp.java.net.preferIPv4Stack=true
org.gradle.jvmargs=-Xmx2048m -XX:MaxMetaspaceSize=512m
org.gradle.daemon=false
org.gradle.parallel=false
org.gradle.workers.max=1
android.aapt2.daemon=false
android.aapt2FromMaven=false
android.aapt2FromMavenOverride=/usr/bin/aapt2
org.gradle.java.home=/usr/lib/jvm/java-17-openjdk-arm64
''',
          'gradle/wrapper/gradle-wrapper.properties': '''distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\\://services.gradle.org/distributions/gradle-8.13-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
''',
          'gradlew': '''#!/bin/bash
# Smart gradlew for QuantumIDE ARM64 environment
DIR="\$(cd "\$(dirname "\$0")" && pwd)"

# Ensure AAPT2 modern override and IPv4 in gradle.properties
if [ -f "\$DIR/gradle.properties" ]; then
    grep -q "android.aapt2FromMavenOverride" "\$DIR/gradle.properties" 2>/dev/null || printf "\\nsystemProp.java.net.preferIPv4Stack=true\\nandroid.useAndroidX=true\\nandroid.enableJetifier=false\\nandroid.aapt2.daemon=false\\nandroid.aapt2FromMaven=false\\nandroid.aapt2FromMavenOverride=/usr/bin/aapt2\\norg.gradle.daemon=false\\norg.gradle.parallel=false\\norg.gradle.workers.max=1\\n" >> "\$DIR/gradle.properties"
fi

# Auto-repair deprecated kotlinOptions in app/build.gradle.kts
if [ -f "\$DIR/app/build.gradle.kts" ] && grep -q "kotlinOptions" "\$DIR/app/build.gradle.kts" 2>/dev/null; then
    python3 -c 'import re, os
p = "'"\$DIR/app/build.gradle.kts"'"
if os.path.exists(p):
    with open(p, "r") as f: c = f.read()
    if "kotlinOptions" in c:
        c = re.sub(r"[ \t]*kotlinOptions\\s*[{][^}]*[}]", "\n", c)
        if "compilerOptions" not in c:
            c += "\ntasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {\n    compilerOptions {\n        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)\n    }\n}\n"
        with open(p, "w") as f: f.write(c)' 2>/dev/null || true
fi

GRADLE_BIN=""
if [ -x "/opt/gradle/gradle-8.13/bin/gradle" ]; then
    GRADLE_BIN="/opt/gradle/gradle-8.13/bin/gradle"
elif [ -x "/usr/local/bin/gradle" ]; then
    GRADLE_BIN="/usr/local/bin/gradle"
elif command -v gradle >/dev/null 2>&1; then
    GRADLE_BIN="\$(command -v gradle)"
fi

JAVACMD="java"
if [ -n "\$JAVA_HOME" ] && [ -x "\$JAVA_HOME/bin/java" ]; then
    JAVACMD="\$JAVA_HOME/bin/java"
elif [ -x "/usr/lib/jvm/java-17-openjdk-arm64/bin/java" ]; then
    JAVACMD="/usr/lib/jvm/java-17-openjdk-arm64/bin/java"
fi

if [ -f "\$DIR/gradle/wrapper/gradle-wrapper.jar" ]; then
    exec "\$JAVACMD" -Dorg.gradle.appname=gradlew -classpath "\$DIR/gradle/wrapper/gradle-wrapper.jar" org.gradle.wrapper.GradleWrapperMain "\$@"
elif [ -n "\$GRADLE_BIN" ]; then
    exec "\$GRADLE_BIN" "\$@"
else
    echo "Downloading Gradle Wrapper..."
    mkdir -p "\$DIR/gradle/wrapper"
    if curl -k -fsSL --retry 2 "https://raw.githubusercontent.com/gradle/gradle/v8.11.1/gradle/wrapper/gradle-wrapper.jar" -o "\$DIR/gradle/wrapper/gradle-wrapper.jar" 2>/dev/null; then
        exec "\$JAVACMD" -Dorg.gradle.appname=gradlew -classpath "\$DIR/gradle/wrapper/gradle-wrapper.jar" org.gradle.wrapper.GradleWrapperMain "\$@"
    fi
    echo "ERROR: Gradle not found. Please install Gradle in QuantumIDE Packages." >&2
    exit 1
fi
''',
          'app/build.gradle.kts': '''plugins {
    id("com.android.application")
}

android {
    namespace = "$pkgName"
    compileSdk = 35

    defaultConfig {
        applicationId = "$pkgName"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("com.google.android.material:material:1.11.0")
}
''',
          'app/src/main/AndroidManifest.xml': '''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:allowBackup="true"
        android:label="$projectName"
        android:supportsRtl="true"
        android:theme="@style/Theme.AppCompat.Light.DarkActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
''',
          'app/src/main/res/layout/activity_main.xml': '''<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical"
    android:gravity="center"
    android:padding="24dp">

    <TextView
        android:id="@+id/textViewTitle"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="$projectName (Java)"
        android:textSize="22sp"
        android:textStyle="bold" />

    <TextView
        android:id="@+id/textViewCounter"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="16dp"
        android:text="Clicks: 0"
        android:textSize="18sp" />

    <Button
        android:id="@+id/btnClick"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="24dp"
        android:text="Click Me!" />

</LinearLayout>
''',
          'app/src/main/res/values/strings.xml': '''<resources>
    <string name="app_name">$projectName</string>
</resources>
''',
          'app/src/main/java/com/example/$pkgSlug/MainActivity.java': '''package $pkgName;

import android.os.Bundle;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;
import androidx.appcompat.app.AppCompatActivity;

public class MainActivity extends AppCompatActivity {
    private int counter = 0;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        TextView titleView = findViewById(R.id.textViewTitle);
        TextView counterView = findViewById(R.id.textViewCounter);
        Button button = findViewById(R.id.btnClick);

        titleView.setText("$projectName (Java)");
        button.setOnClickListener(v -> {
            counter++;
            counterView.setText("Clicks: " + counter);
            Toast.makeText(MainActivity.this, "Button clicked: " + counter, Toast.LENGTH_SHORT).show();
        });
    }
}
''',
          'README.md': '# $projectName\n\nNative Android Java project created with Quantum IDE.\n\n### Build:\n- Debug: `./gradlew assembleDebug`\n- Release: `./gradlew assembleRelease`\n',
          '.gitignore': '.gradle/\nlocal.properties\n**/build/\n*.iml\n.idea/\n',
        };
    }
  }
}
