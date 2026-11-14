A powerful and feature-rich alternative for [flutter_code_editor](https://pub.dev/packages/flutter_code_editor) and [code_text_field](https://pub.dev/packages/code_text_field). Designed to bring a seamless and efficient coding experience.


> [!WARNING]
> **This package is outdated.** A better and faster alternative, `code_forge`, is now available at [https://github.com/heckmon/code_forge](https://github.com/heckmon/code_forge). It uses rope data structure and low-level Flutter RenderBox and ParagraphBuilder APIs instead of Flutter's built-in `TextField`.


[![pub package](https://img.shields.io/pub/v/flutter_code_crafter.svg?cacheSeconds=60)](https://pub.dev/packages/flutter_code_crafter)
![GitHub license](https://img.shields.io/github/license/heckmon/flutter_code_crafter.svg)
![GitHub stars](https://img.shields.io/github/stars/heckmon/flutter_code_crafter.svg?style=social&label=Star&cacheSeconds=60)

> [!NOTE]
> 
> Web support has been removed since 0.1.8 because of some conflicts with dart:io. A seperate package `flutter_code_crafter_web` will be released soon for web.

## Features

- Syntax highlighting ([available languages](https://github.com/git-touch/highlight.dart/tree/master/highlight/lib/languages))
- Multiple themes ([available themes](https://github.com/git-touch/highlight.dart/tree/master/flutter_highlight/lib/themes))
- Code folding
- AI code completion
- Built-in universal LSP client (Suggestions, diagnostics, etc.)
- Vertical ruler lines (Indentation guides lines similar to VSCode)
- Code formatting (Auto indentation, line   wrapping, etc.)
<br>

<p align="left">
  <img src="https://files.catbox.moe/ohyfpu.gif" alt="Syntax Highlighting" width="425" height="415"><br>
  <sub>AI Code completion and LSP suggestion</sub>
</p>

<p align="left">
  <img src="https://files.catbox.moe/kic1bb.gif" alt="Code Folding" width="425" height="415"><br>
  <sub>Code folding and breakpoints</sub>
</p>

<p align="left">
  <img src="https://files.catbox.moe/4skc39.gif" alt="AI Completion" width="425" height="415"><br>
  <sub>LSP hover using pyright LSP server</sub>
</p>

<p align="left">
  <img src="https://files.catbox.moe/y5kzcr.gif" alt="LSP Client" width="425" height="425"><br>
  <sub>Bracket matching and auto indentation<br>error highlight using clangd LSP server</sub>
</p>

<br>

> [!NOTE]
>
> The above features works on all supported languages, I just used python for the demo.<br> You can use any language with corresponding LSP server to get hover details and suggestions similar to VScode.

## Usage

### Basic usage
Plug and play with `CodeCrafter` widget. Import a langauge from the [highlight](https://pub.dev/packages/highlight) package and theme from the [flutter_highlight](https://pub.dev/packages/flutter_highlight) package, and you're good to go!

```dart
import 'package:flutter/material.dart';
import 'package:flutter_code_crafter/code_crafter.dart';
import 'package:flutter_highlight/themes/an-old-hope.dart'; // Import the theme you want to use
import 'package:highlight/languages/python.dart'; // Import the language you want to use

void main() {
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late final CodeCrafterController controller; // Initialize the CodeCrafterController

  @override
  void initState() {
    controller = CodeCrafterController();
    controller.language = python; // Set the language for syntax highlighting
    super.initState();
  }

  @override
  Widget build(BuildContext context){
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Code Crafter Example')),
        body: CodeCrafter(
          controller: controller,
          theme: anOldHopeTheme, // Use the imported theme
        ),
      ),
    );
  }
}

```
### Advanced usage
 - To Setup AI code completion, follow this documentation: [AI Code Completion](https://github.com/heckmon/flutter_code_crafter/blob/main/docs/AICompletion.md)
 - To Setup LSP client, follow this documentation: [LSP Client](https://github.com/heckmon/flutter_code_crafter/blob/main/docs/LSPClient.md)


## Additional information

This package contains `dart:io` import, so web supported may be limited. Also there is an issue with tab key when `wrapLines` property is set to false. This is a known issue with the underlying text editing library and will be fixed in future releases.

Contributions are welcome! If you find any bugs or have any feature requests, please open an issue on the [GitHub repository](https://github.com/heckmon/flutter_code_crafter).

## CodeCrafter Class
```dart
CodeCrafter({
  super.key,
    required this.controller,
    this.initialText,
    this.filePath,
    this.focusNode,
    this.textStyle,
    this.gutterStyle,
    this.editorTheme,
    this.aiCompletion,
    this.aiCompletionTextStyle,
    this.lspConfig,
    this.suggestionStyle,
    this.hoverDetailsStyle,
    this.selectionHandleColor,
    this.selectionColor,
    this.cursorColor,
    this.enableBreakPoints = true,
    this.enableFolding = true,
    this.enableRulerLines = true,
    this.enableSuggestions = true,
    this.enableGutterDivider = false,
    this.wrapLines = false,
    this.autoFocus = false,
    this.readOnly = false,
    this.tabSize = 3,
    this.editorField,
})
```

## GutterStyle class
```dart
GutterStyle({
    this.lineNumberStyle,
    this.gutterWidth,
    this.breakpointIcon = Icons.circle,
    this.unfilledBreakpointIcon = Icons.circle_outlined,
    this.foldedIcon = Icons.chevron_right_outlined,
    this.unfoldedIcon = Icons.keyboard_arrow_down_outlined,
    this.dividerColor,
    this.dividerThickness,
    this.breakpointSize,
    this.foldingIconSize,
    this.breakpointColor = Colors.red,
    this.unfilledBreakpointColor = Colors.transparent,
    this.foldedIconColor = Colors.grey,
    this.unfoldedIconColor = Colors.grey,
  });
```

## Sample App Image
<img src="https://files.catbox.moe/v52e0r.jpg" height = "775" width = "350">
