import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AIPanelMode { chat, cli }

final aiPanelModeProvider = StateProvider<AIPanelMode>((ref) => AIPanelMode.chat);
final selectedAgentProvider = StateProvider<String?>((ref) => null);
final rightChatPanelOpenProvider = StateProvider<bool>((ref) => false);
final rightPanelWidthProvider = StateProvider<double>((ref) => 340.0);
final leftPanelWidthProvider = StateProvider<double>((ref) => 320.0);
