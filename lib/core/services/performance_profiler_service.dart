import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PerformanceSample {
  final double fps;
  final double memoryMB;
  final double buildTimeMs;
  final DateTime timestamp;

  const PerformanceSample({
    required this.fps,
    required this.memoryMB,
    required this.buildTimeMs,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'fps': fps,
    'memoryMB': memoryMB,
    'buildTimeMs': buildTimeMs,
    'timestamp': timestamp.toIso8601String(),
  };
}

class ProfilerSession {
  final String id;
  final String name;
  final DateTime startedAt;
  DateTime? stoppedAt;
  final List<PerformanceSample> samples;

  ProfilerSession({
    required this.id,
    required this.name,
    required this.startedAt,
    this.stoppedAt,
    this.samples = const [],
  });

  Duration get duration => (stoppedAt ?? DateTime.now()).difference(startedAt);

  double get avgFps {
    if (samples.isEmpty) return 0;
    return samples.map((s) => s.fps).reduce((a, b) => a + b) / samples.length;
  }

  double get avgMemoryMB {
    if (samples.isEmpty) return 0;
    return samples.map((s) => s.memoryMB).reduce((a, b) => a + b) / samples.length;
  }

  double get avgBuildTimeMs {
    if (samples.isEmpty) return 0;
    return samples.map((s) => s.buildTimeMs).reduce((a, b) => a + b) / samples.length;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'startedAt': startedAt.toIso8601String(),
    'stoppedAt': stoppedAt?.toIso8601String(),
    'samples': samples.map((s) => s.toJson()).toList(),
    'avgFps': avgFps,
    'avgMemoryMB': avgMemoryMB,
    'avgBuildTimeMs': avgBuildTimeMs,
  };
}

class PerformanceProfilerState {
  final bool isRecording;
  final ProfilerSession? currentSession;
  final List<ProfilerSession> sessions;
  final List<PerformanceSample> recentSamples;

  const PerformanceProfilerState({
    this.isRecording = false,
    this.currentSession,
    this.sessions = const [],
    this.recentSamples = const [],
  });

  PerformanceProfilerState copyWith({
    bool? isRecording,
    ProfilerSession? currentSession,
    List<ProfilerSession>? sessions,
    List<PerformanceSample>? recentSamples,
  }) {
    return PerformanceProfilerState(
      isRecording: isRecording ?? this.isRecording,
      currentSession: currentSession ?? this.currentSession,
      sessions: sessions ?? this.sessions,
      recentSamples: recentSamples ?? this.recentSamples,
    );
  }
}

class PerformanceProfilerService extends StateNotifier<PerformanceProfilerState> {
  Timer? _timer;
  int _frameCount = 0;
  DateTime? _lastFrameTime;
  double _currentFps = 0;
  int _sessionCounter = 0;

  PerformanceProfilerService() : super(const PerformanceProfilerState());

  void startRecording({String? name}) {
    if (state.isRecording) stopRecording();
    _sessionCounter++;
    final session = ProfilerSession(
      id: 'session_$_sessionCounter',
      name: name ?? 'Recording $_sessionCounter',
      startedAt: DateTime.now(),
    );
    state = state.copyWith(isRecording: true, currentSession: session);
    _startSampling();
  }

  void stopRecording() {
    _timer?.cancel();
    _timer = null;
    if (state.currentSession != null) {
      final completed = ProfilerSession(
        id: state.currentSession!.id,
        name: state.currentSession!.name,
        startedAt: state.currentSession!.startedAt,
        stoppedAt: DateTime.now(),
        samples: state.currentSession!.samples,
      );
      state = state.copyWith(
        isRecording: false,
        currentSession: null,
        sessions: [completed, ...state.sessions],
      );
    } else {
      state = state.copyWith(isRecording: false);
    }
  }

  void _startSampling() {
    _timer?.cancel();
    _lastFrameTime = DateTime.now();
    _frameCount = 0;
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _collectSample());
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    _frameCount += timings.length;
  }

  void _collectSample() {
    final now = DateTime.now();
    final elapsed = _lastFrameTime != null ? now.difference(_lastFrameTime!).inMilliseconds / 1000.0 : 1.0;
    _currentFps = elapsed > 0 ? (_frameCount / elapsed).clamp(0, 120) : 0.0;
    _frameCount = 0;
    _lastFrameTime = now;

    double memoryMB = 0;
    double buildTimeMs = 0;
    try {
      memoryMB = ProcessInfo.currentRss / (1024 * 1024);
    } catch (_) {}

    buildTimeMs = _measureBuildTime();

    final sample = PerformanceSample(
      fps: _currentFps,
      memoryMB: memoryMB,
      buildTimeMs: buildTimeMs,
      timestamp: now,
    );

    final updatedSamples = [...state.recentSamples, sample];
    if (updatedSamples.length > 300) updatedSamples.removeAt(0);

    if (state.isRecording && state.currentSession != null) {
      final updatedSession = ProfilerSession(
        id: state.currentSession!.id,
        name: state.currentSession!.name,
        startedAt: state.currentSession!.startedAt,
        samples: [...state.currentSession!.samples, sample],
      );
      state = state.copyWith(
        recentSamples: updatedSamples,
        currentSession: updatedSession,
      );
    } else {
      state = state.copyWith(recentSamples: updatedSamples);
    }
  }

  double _measureBuildTime() {
    final sw = Stopwatch()..start();
    sw.stop();
    return sw.elapsedMicroseconds / 1000.0;
  }

  double get currentFps => _currentFps;

  List<PerformanceSample> getLastSamples({int count = 60}) {
    if (state.recentSamples.length <= count) return state.recentSamples;
    return state.recentSamples.sublist(state.recentSamples.length - count);
  }

  Future<void> exportToJson(String filePath) async {
    final data = {
      'sessions': state.sessions.map((s) => s.toJson()).toList(),
      'exportedAt': DateTime.now().toIso8601String(),
    };
    final file = File(filePath);
    await file.writeAsString(jsonEncode(data));
  }

  void deleteSession(String sessionId) {
    state = state.copyWith(
      sessions: state.sessions.where((s) => s.id != sessionId).toList(),
    );
  }

  void clearHistory() {
    state = state.copyWith(sessions: []);
  }

  @override
  void dispose() {
    _timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    super.dispose();
  }
}

final performanceProfilerProvider = StateNotifierProvider<PerformanceProfilerService, PerformanceProfilerState>((ref) {
  final service = PerformanceProfilerService();
  ref.onDispose(() => service.dispose());
  return service;
});
