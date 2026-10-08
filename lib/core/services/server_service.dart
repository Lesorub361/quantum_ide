import 'package:flutter_riverpod/flutter_riverpod.dart';

class ServerConfig {
  final String id;
  final String name;
  final int port;
  final String startCommand;
  bool isRunning;

  ServerConfig({
    required this.id,
    required this.name,
    required this.port,
    required this.startCommand,
    this.isRunning = false,
  });
}

class ServerService extends StateNotifier<List<ServerConfig>> {
  ServerService() : super([
    ServerConfig(
      id: 'web-server',
      name: 'Local Web Server',
      port: 8080,
      startCommand: 'python3 -m http.server 8080',
    ),
    ServerConfig(
      id: 'node-app',
      name: 'Node.js Backend',
      port: 3000,
      startCommand: 'node index.js',
    ),
  ]);

  void toggleServer(String id) {
    state = [
      for (final s in state)
        if (s.id == id)
          ServerConfig(
            id: s.id,
            name: s.name,
            port: s.port,
            startCommand: s.startCommand,
            isRunning: !s.isRunning,
          )
        else
          s
    ];
  }
}

final serverServiceProvider = StateNotifierProvider<ServerService, List<ServerConfig>>((ref) {
  return ServerService();
});
