import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter/widgets.dart';

enum ProjectTemplateType {
  html('HTML/JS', 'Simple web project with HTML, CSS, and JS', LucideIcons.globe),
  react('React', 'Modern React project using Vite', LucideIcons.atom),
  vue('Vue', 'Modern Vue.js project using Vite', LucideIcons.monitor),
  node('Node.js', 'Express.js backend project', LucideIcons.server),
  php('PHP', 'Traditional PHP web project', LucideIcons.file_code),
  python('Python', 'Simple Python script or app', LucideIcons.code),
  flutter('Flutter', 'Cross-platform mobile & web app', LucideIcons.layout_template);

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
    }
  }
}
