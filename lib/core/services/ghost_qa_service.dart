import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Recorded runtime Flutter error / RenderFlex overflow event.
class QARuntimeError {
  final DateTime timestamp;
  final String message;
  final String? library;
  final String stackTrace;
  final bool isOverflow;

  const QARuntimeError({
    required this.timestamp,
    required this.message,
    this.library,
    required this.stackTrace,
    this.isOverflow = false,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'message': message,
    'library': library,
    'stackTrace': stackTrace,
    'isOverflow': isOverflow,
  };
}

/// Element summary discovered by the UI tree walker.
class QAElementInfo {
  final String id;
  final String type;
  final String label;
  final String? tooltip;
  final String? key;
  final Rect bounds;
  final bool isClickable;
  final bool isInput;
  final bool isScrollable;

  const QAElementInfo({
    required this.id,
    required this.type,
    required this.label,
    this.tooltip,
    this.key,
    required this.bounds,
    this.isClickable = false,
    this.isInput = false,
    this.isScrollable = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'label': label,
    if (tooltip != null) 'tooltip': tooltip,
    if (key != null) 'key': key,
    'bounds': {
      'x': bounds.left,
      'y': bounds.top,
      'width': bounds.width,
      'height': bounds.height,
    },
    'center': {
      'x': bounds.center.dx,
      'y': bounds.center.dy,
    },
    'isClickable': isClickable,
    'isInput': isInput,
    'isScrollable': isScrollable,
  };
}

/// Ghost QA Engine for autonomous testing, inspection, and error detection.
///
/// RESTRICTED TO OWNER / DEVELOPER ONLY:
/// Completely inactive and zero overhead on regular users' devices unless
/// an authorization key or compile-time flag is explicitly present.
class GhostQAService {
  static final GhostQAService instance = GhostQAService._internal();
  GhostQAService._internal();

  /// Root RepaintBoundary GlobalKey to capture app render frames.
  static final GlobalKey repaintKey = GlobalKey(debugLabel: 'GhostQARootRepaintKey');

  static const int defaultPort = 9988;

  bool? _authorizedCache;
  HttpServer? _server;
  int _pointerId = 1000;
  final List<QARuntimeError> _errorLog = [];
  static const int _maxErrorLogSize = 50;

  /// Check whether the current user is verified as the project owner/developer.
  bool get isAuthorized {
    if (_authorizedCache != null) return _authorizedCache!;
    _authorizedCache = _computeAuthorization();
    return _authorizedCache!;
  }

  /// Manually authorize (e.g. from developer settings or secret passkey).
  void authorizeDirectly() {
    _authorizedCache = true;
    _startHttpServerIfAuthorized();
  }

  bool _computeAuthorization() {
    // 1. Compile-time flag
    if (const bool.fromEnvironment('QUANTUM_OWNER_QA', defaultValue: false)) {
      return true;
    }

    // 2. Runtime environment variable
    final env = Platform.environment['QUANTUM_OWNER_QA'];
    if (env == 'true' || env == '1') {
      return true;
    }

    // 3. Local owner verification key file
    final keyPaths = [
      '/root/.quantum/owner_qa.key',
      '/root/projects/quantum_ide-main/.quantum/owner_qa.key',
      '${Directory.systemTemp.path}/quantum_owner_qa.key',
    ];

    for (final path in keyPaths) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          final content = f.readAsStringSync().trim();
          if (content.isNotEmpty) {
            return true;
          }
        }
      } catch (_) {}
    }

    return false;
  }

  /// Initialize Ghost QA engine on app launch.
  Future<void> init() async {
    if (!isAuthorized) {
      debugPrint('[GhostQA] Owner verification negative: QA Engine remains dormant.');
      return;
    }

    debugPrint('[GhostQA] 🛡️ Owner authorized. Activating Ghost QA Engine...');
    await _startHttpServerIfAuthorized();
  }

  /// Start the loopback HTTP server (127.0.0.1:9988).
  Future<void> _startHttpServerIfAuthorized() async {
    if (!isAuthorized || _server != null) return;

    for (final port in [defaultPort, 9989, 9990]) {
      try {
        _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
        debugPrint('[GhostQA] 🚀 Ghost QA HTTP Bridge listening on http://127.0.0.1:$port');
        _server!.listen(_handleHttpRequest);
        break;
      } catch (e) {
        debugPrint('[GhostQA] Port $port in use, trying next...');
      }
    }
  }

  /// Stop server on dispose.
  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
  }

  /// Capture runtime Flutter errors or RenderFlex overflows.
  void recordFlutterError(FlutterErrorDetails details) {
    if (!isAuthorized) return;

    final msg = details.exceptionAsString();
    final isOverflow = msg.contains('RenderFlex overflowed') ||
        msg.contains('A RenderFlex overflowed') ||
        msg.contains('overflowed by');

    final entry = QARuntimeError(
      timestamp: DateTime.now(),
      message: msg,
      library: details.library,
      stackTrace: details.stack?.toString() ?? '',
      isOverflow: isOverflow,
    );

    if (_errorLog.length >= _maxErrorLogSize) {
      _errorLog.removeAt(0);
    }
    _errorLog.add(entry);
    debugPrint('[GhostQA] Intercepted error (overflow=$isOverflow): ${msg.split('\n').first}');
  }

  /// Get recorded errors.
  List<Map<String, dynamic>> getErrors() {
    return _errorLog.map((e) => e.toJson()).toList();
  }

  /// Clear error log.
  void clearErrors() {
    _errorLog.clear();
  }

  /// Take a PNG screenshot of the entire application.
  Future<Uint8List?> capturePng({double pixelRatio = 1.0}) async {
    if (!isAuthorized) return null;
    try {
      final boundary = repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        debugPrint('[GhostQA] RenderRepaintBoundary not ready yet');
        return null;
      }

      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[GhostQA] Error capturing screenshot: $e');
      return null;
    }
  }

  /// Save current screenshot to file.
  Future<String?> saveScreenshot({String? targetPath}) async {
    final bytes = await capturePng();
    if (bytes == null) return null;

    final filePath = targetPath ?? '/root/projects/quantum_ide-main/.quantum/screenshots/screen_${DateTime.now().millisecondsSinceEpoch}.png';
    try {
      final file = File(filePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return filePath;
    } catch (e) {
      debugPrint('[GhostQA] Error saving screenshot to $filePath: $e');
      return null;
    }
  }

  /// Inspect and extract current screen interactive UI elements.
  Future<Map<String, dynamic>> inspectUiElements() async {
    if (!isAuthorized) {
      return {'error': 'Unauthorized: Owner QA Engine disabled'};
    }

    final context = repaintKey.currentContext;
    if (context == null) {
      return {
        'error': 'Root context not mounted yet',
        'screen_size': {'width': 0.0, 'height': 0.0},
        'elements': [],
      };
    }

    final mediaQuery = MediaQuery.maybeOf(context);
    final screenSize = mediaQuery?.size ?? const Size(1080, 2400);

    final List<QAElementInfo> discovered = [];
    int counter = 0;

    void visitor(Element element, int depth) {
      if (depth > 60) return;

      final widget = element.widget;
      final renderBox = element.renderObject;

      if (renderBox is RenderBox && renderBox.hasSize && renderBox.attached) {
        try {
          final size = renderBox.size;
          if (size.width > 2 && size.height > 2) {
            final offset = renderBox.localToGlobal(Offset.zero);
            final bounds = Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height);

            // Determine if interesting widget
            final info = _analyzeWidget(element, widget, bounds, ++counter);
            if (info != null) {
              discovered.add(info);
            }
          }
        } catch (_) {}
      }

      element.visitChildren((child) => visitor(child, depth + 1));
    }

    visitor(context as Element, 0);

    return {
      'screen_size': {
        'width': screenSize.width,
        'height': screenSize.height,
      },
      'element_count': discovered.length,
      'elements': discovered.map((e) => e.toJson()).toList(),
    };
  }

  QAElementInfo? _analyzeWidget(Element element, Widget widget, Rect bounds, int index) {
    final type = widget.runtimeType.toString();
    String label = '';
    String? tooltip;
    final keyStr = widget.key?.toString();
    bool isClickable = false;
    bool isInput = false;
    bool isScrollable = false;

    // 1. Text & RichText
    if (widget is Text) {
      label = widget.data ?? widget.textSpan?.toPlainText() ?? '';
      if (label.trim().isEmpty) return null;
    } else if (widget is RichText) {
      label = widget.text.toPlainText();
      if (label.trim().isEmpty) return null;
    }

    // 2. Tooltip
    if (widget is Tooltip) {
      tooltip = widget.message;
    }

    // 3. Interactive Buttons
    if (widget is ElevatedButton ||
        widget is FilledButton ||
        widget is TextButton ||
        widget is OutlinedButton ||
        widget is IconButton ||
        widget is FloatingActionButton ||
        type.contains('Button')) {
      isClickable = true;
      if (widget is IconButton && widget.tooltip != null) {
        tooltip = widget.tooltip;
        label = widget.tooltip!;
      }
    }

    // 4. InkWell & GestureDetector
    if (widget is InkWell && widget.onTap != null) {
      isClickable = true;
    } else if (widget is GestureDetector && (widget.onTap != null || widget.onTapDown != null)) {
      isClickable = true;
    }

    // 5. Tabs & Navigations
    if (widget is Tab) {
      isClickable = true;
      label = widget.text ?? '';
    } else if (widget is NavigationDestination) {
      isClickable = true;
      label = widget.label;
    } else if (widget is ListTile) {
      isClickable = widget.onTap != null;
    }

    // 6. Text Inputs
    if (widget is TextField || widget is TextFormField || widget is EditableText) {
      isInput = true;
      isClickable = true;
      if (widget is TextField && widget.decoration?.hintText != null) {
        label = widget.decoration!.hintText!;
      }
    }

    // 7. Scrollables
    if (widget is Scrollable || widget is ListView || widget is SingleChildScrollView) {
      isScrollable = true;
    }

    // If nothing interesting or informative, skip
    if (!isClickable && !isInput && label.trim().isEmpty && tooltip == null) {
      return null;
    }

    // Collect child text for buttons without explicit label
    if (label.isEmpty && isClickable) {
      label = _findDescendantText(element) ?? tooltip ?? type;
    }

    return QAElementInfo(
      id: 'el_$index',
      type: type,
      label: label.trim(),
      tooltip: tooltip,
      key: keyStr,
      bounds: bounds,
      isClickable: isClickable,
      isInput: isInput,
      isScrollable: isScrollable,
    );
  }

  String? _findDescendantText(Element root) {
    String? found;
    void finder(Element el) {
      if (found != null) return;
      final w = el.widget;
      if (w is Text && w.data != null && w.data!.isNotEmpty) {
        found = w.data;
        return;
      }
      if (w is RichText) {
        final t = w.text.toPlainText();
        if (t.isNotEmpty) {
          found = t;
          return;
        }
      }
      el.visitChildren(finder);
    }
    root.visitChildren(finder);
    return found;
  }

  /// Simulate a tap gesture at coordinate (x, y).
  Future<bool> tapAt(double x, double y) async {
    if (!isAuthorized) return false;
    try {
      final pointer = _pointerId++;
      final down = PointerDownEvent(
        pointer: pointer,
        position: Offset(x, y),
        kind: PointerDeviceKind.touch,
      );
      GestureBinding.instance.handlePointerEvent(down);
      await Future.delayed(const Duration(milliseconds: 50));

      final up = PointerUpEvent(
        pointer: pointer,
        position: Offset(x, y),
        kind: PointerDeviceKind.touch,
      );
      GestureBinding.instance.handlePointerEvent(up);
      await Future.delayed(const Duration(milliseconds: 100));
      return true;
    } catch (e) {
      debugPrint('[GhostQA] tapAt error: $e');
      return false;
    }
  }

  /// Tap an element by text label, tooltip or key.
  Future<bool> tapByLabel(String query) async {
    final uiData = await inspectUiElements();
    final elements = (uiData['elements'] as List<dynamic>?) ?? [];
    final lower = query.toLowerCase();

    // 1. Exact or partial match on clickable elements
    for (final el in elements) {
      final label = (el['label'] as String? ?? '').toLowerCase();
      final tooltip = (el['tooltip'] as String? ?? '').toLowerCase();
      final isClickable = el['isClickable'] == true;

      if (isClickable && (label == lower || tooltip == lower || label.contains(lower) || tooltip.contains(lower))) {
        final center = el['center'] as Map<String, dynamic>;
        final x = (center['x'] as num).toDouble();
        final y = (center['y'] as num).toDouble();
        debugPrint('[GhostQA] Tapping element "${el['label']}" at ($x, $y)');
        return await tapAt(x, y);
      }
    }

    // 2. Fallback to any element matching text
    for (final el in elements) {
      final label = (el['label'] as String? ?? '').toLowerCase();
      if (label.contains(lower)) {
        final center = el['center'] as Map<String, dynamic>;
        final x = (center['x'] as num).toDouble();
        final y = (center['y'] as num).toDouble();
        debugPrint('[GhostQA] Tapping text match "${el['label']}" at ($x, $y)');
        return await tapAt(x, y);
      }
    }

    debugPrint('[GhostQA] Element matching "$query" not found on screen');
    return false;
  }

  /// Tap an element by ID (e.g. "el_14").
  Future<bool> tapById(String id) async {
    final uiData = await inspectUiElements();
    final elements = (uiData['elements'] as List<dynamic>?) ?? [];
    for (final el in elements) {
      if (el['id'] == id) {
        final center = el['center'] as Map<String, dynamic>;
        final x = (center['x'] as num).toDouble();
        final y = (center['y'] as num).toDouble();
        return await tapAt(x, y);
      }
    }
    return false;
  }

  /// Simulate a scroll gesture.
  Future<bool> scroll({
    required double startX,
    required double startY,
    required double dx,
    required double dy,
    int steps = 5,
  }) async {
    if (!isAuthorized) return false;
    try {
      final pointer = _pointerId++;
      final down = PointerDownEvent(
        pointer: pointer,
        position: Offset(startX, startY),
        kind: PointerDeviceKind.touch,
      );
      GestureBinding.instance.handlePointerEvent(down);

      for (int i = 1; i <= steps; i++) {
        await Future.delayed(const Duration(milliseconds: 25));
        final move = PointerMoveEvent(
          pointer: pointer,
          position: Offset(startX + (dx * i / steps), startY + (dy * i / steps)),
          kind: PointerDeviceKind.touch,
        );
        GestureBinding.instance.handlePointerEvent(move);
      }

      final up = PointerUpEvent(
        pointer: pointer,
        position: Offset(startX + dx, startY + dy),
        kind: PointerDeviceKind.touch,
      );
      GestureBinding.instance.handlePointerEvent(up);
      await Future.delayed(const Duration(milliseconds: 100));
      return true;
    } catch (e) {
      debugPrint('[GhostQA] scroll error: $e');
      return false;
    }
  }

  /// Enter text into the currently active/focused field.
  Future<bool> enterText(String text) async {
    if (!isAuthorized) return false;
    try {
      final focusNode = FocusManager.instance.primaryFocus;
      if (focusNode != null && focusNode.context != null) {
        final editable = focusNode.context!.findAncestorStateOfType<EditableTextState>();
        if (editable != null) {
          editable.userUpdateTextEditingValue(
            TextEditingValue(
              text: text,
              selection: TextSelection.collapsed(offset: text.length),
            ),
            SelectionChangedCause.keyboard,
          );
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('[GhostQA] enterText error: $e');
      return false;
    }
  }

  /// Perform autonomous UI walkthrough test across interactive elements.
  Future<Map<String, dynamic>> runAutonomousAudit() async {
    if (!isAuthorized) {
      return {'error': 'Unauthorized'};
    }

    final initialErrorsCount = _errorLog.length;
    final uiData = await inspectUiElements();
    final elements = (uiData['elements'] as List<dynamic>?) ?? [];

    final clickableElements = elements.where((e) => e['isClickable'] == true).toList();
    final auditResults = <Map<String, dynamic>>[];

    for (final el in clickableElements.take(15)) {
      final label = el['label'] as String? ?? el['type'];
      final center = el['center'] as Map<String, dynamic>;
      final x = (center['x'] as num).toDouble();
      final y = (center['y'] as num).toDouble();

      final errorsBefore = _errorLog.length;
      final tapped = await tapAt(x, y);
      await Future.delayed(const Duration(milliseconds: 300));
      final errorsAfter = _errorLog.length;

      auditResults.add({
        'element_id': el['id'],
        'label': label,
        'type': el['type'],
        'tapped': tapped,
        'new_errors_count': errorsAfter - errorsBefore,
      });
    }

    final totalNewErrors = _errorLog.length - initialErrorsCount;

    return {
      'status': 'completed',
      'clickable_found': clickableElements.length,
      'audited_count': auditResults.length,
      'total_new_errors': totalNewErrors,
      'audit_log': auditResults,
      'recent_errors': getErrors(),
    };
  }

  /// Handle incoming HTTP request on 127.0.0.1:9988.
  Future<void> _handleHttpRequest(HttpRequest request) async {
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.set('Access-Control-Allow-Headers', 'Content-Type');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;

    try {
      if (path == '/health') {
        _sendJsonResponse(request.response, {
          'status': 'ok',
          'app': 'Quantum IDE',
          'authorized': isAuthorized,
          'errors_recorded': _errorLog.length,
          'timestamp': DateTime.now().toIso8601String(),
        });
      } else if (path == '/ui') {
        final uiData = await inspectUiElements();
        _sendJsonResponse(request.response, uiData);
      } else if (path == '/screen' || path == '/screenshot' || path == '/screen.png') {
        final pngBytes = await capturePng();
        if (pngBytes == null) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          request.response.write('Screen not ready');
          await request.response.close();
          return;
        }

        if (request.uri.queryParameters['format'] == 'base64') {
          _sendJsonResponse(request.response, {
            'format': 'base64',
            'data': base64Encode(pngBytes),
          });
        } else {
          request.response.headers.contentType = ContentType('image', 'png');
          request.response.add(pngBytes);
          await request.response.close();
        }
      } else if (path == '/tap' && request.method == 'POST') {
        final bodyStr = await utf8.decodeStream(request);
        final data = bodyStr.isNotEmpty ? jsonDecode(bodyStr) as Map<String, dynamic> : <String, dynamic>{};

        bool ok = false;
        if (data.containsKey('x') && data.containsKey('y')) {
          ok = await tapAt((data['x'] as num).toDouble(), (data['y'] as num).toDouble());
        } else if (data.containsKey('label') || data.containsKey('text')) {
          ok = await tapByLabel((data['label'] ?? data['text']).toString());
        } else if (data.containsKey('id')) {
          ok = await tapById(data['id'].toString());
        }

        _sendJsonResponse(request.response, {'success': ok});
      } else if (path == '/scroll' && request.method == 'POST') {
        final bodyStr = await utf8.decodeStream(request);
        final data = bodyStr.isNotEmpty ? jsonDecode(bodyStr) as Map<String, dynamic> : <String, dynamic>{};

        final ok = await scroll(
          startX: (data['startX'] as num? ?? 300).toDouble(),
          startY: (data['startY'] as num? ?? 600).toDouble(),
          dx: (data['dx'] as num? ?? 0).toDouble(),
          dy: (data['dy'] as num? ?? -300).toDouble(),
        );

        _sendJsonResponse(request.response, {'success': ok});
      } else if (path == '/text' && request.method == 'POST') {
        final bodyStr = await utf8.decodeStream(request);
        final data = bodyStr.isNotEmpty ? jsonDecode(bodyStr) as Map<String, dynamic> : <String, dynamic>{};
        final ok = await enterText(data['text']?.toString() ?? '');
        _sendJsonResponse(request.response, {'success': ok});
      } else if (path == '/errors') {
        _sendJsonResponse(request.response, {
          'count': _errorLog.length,
          'errors': getErrors(),
        });
      } else if (path == '/clear_errors' && request.method == 'POST') {
        clearErrors();
        _sendJsonResponse(request.response, {'cleared': true});
      } else if (path == '/audit' && request.method == 'POST') {
        final auditReport = await runAutonomousAudit();
        _sendJsonResponse(request.response, auditReport);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Not Found');
        await request.response.close();
      }
    } catch (e, st) {
      debugPrint('[GhostQA] HTTP Error: $e\n$st');
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Internal Error: $e');
      await request.response.close();
    }
  }

  void _sendJsonResponse(HttpResponse response, Map<String, dynamic> data) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(data));
    response.close();
  }
}
