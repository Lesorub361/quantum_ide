import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quantum_ide/core/models/agent_activity_item.dart';
import 'package:quantum_ide/core/services/cli_auth_service.dart';
import 'package:quantum_ide/core/services/cli_agent_bridge.dart';
import 'package:quantum_ide/core/services/cli_installer_service.dart';
import 'package:quantum_ide/core/services/package_service.dart';
import 'package:quantum_ide/core/services/runtime_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Antigravity CLI Auth & Bridge Tests', () {
    test('Token file exists on system and email is extracted', () {
      final tokenFile = File('/root/.gemini/antigravity-cli/antigravity-oauth-token');
      expect(tokenFile.existsSync(), isTrue, reason: 'Antigravity OAuth token file must exist');
    });

    test('CliAuthNotifier loads active token and recognizes Antigravity as signedIn', () async {
      final notifier = CliAuthNotifier();
      await notifier.loadAuthInfo();

      final state = notifier.state;
      expect(state.antigravityStatus, equals(AntigravityAuthStatus.signedIn));
      expect(state.isGoogleAuthenticated, isTrue);
      expect(state.googleAccountEmail, contains('@'));
      expect(state.googleAccountEmail, equals('lesorub0051@gmail.com'));
    });

    test('startAntigravityLogin immediately succeeds when token is present', () async {
      final notifier = CliAuthNotifier();
      await notifier.startAntigravityLogin();

      final state = notifier.state;
      expect(state.antigravityStatus, equals(AntigravityAuthStatus.signedIn));
      expect(state.googleAccountEmail, equals('lesorub0051@gmail.com'));
    });

    test('CliAgentBridge resolves Antigravity binary correctly', () {
      final runtime = RuntimeService();
      final bridge = CliAgentBridge(runtime);

      final binary = bridge.resolveBinary(AgentKind.antigravity);
      expect(binary, isNotNull, reason: 'Antigravity binary must be resolved');
      expect(binary, equals('/usr/local/bin/agy'));
    });

    test('CliAgentBridge reports Antigravity as installed', () async {
      final runtime = RuntimeService();
      final bridge = CliAgentBridge(runtime);

      final installed = await bridge.isAgentInstalled(AgentKind.antigravity);
      expect(installed, isTrue, reason: 'Antigravity CLI must be detected as installed');
    });

    test('CliInstallerService detects installed version of Antigravity', () async {
      final runtime = RuntimeService();
      final installer = CliInstallerService(runtime);
      await installer.refreshInstalledAgents();

      final versions = installer.state.installedVersions;
      expect(versions.containsKey(AgentKind.antigravity), isTrue);
      expect(versions[AgentKind.antigravity], isNotEmpty);
    });

    test('PackageService detects antigravity-cli, opencode-ai and nodejs as installed', () async {
      final container = ProviderContainer();
      await container.read(packageServiceProvider.notifier).checkActualInstallation();
      final packages = container.read(packageServiceProvider);

      final agy = packages.firstWhere((p) => p.id == 'antigravity-cli');
      final opencode = packages.firstWhere((p) => p.id == 'opencode-ai');
      final nodejs = packages.firstWhere((p) => p.id == 'nodejs');

      expect(agy.isInstalled, isTrue, reason: 'antigravity-cli must be detected as installed');
      expect(opencode.isInstalled, isTrue, reason: 'opencode-ai must be detected as installed');
      expect(nodejs.isInstalled, isTrue, reason: 'nodejs must be detected as installed');
    });
  });
}
