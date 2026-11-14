import 'package:flutter/material.dart';
import 'package:quantum_ide/features/ai_assistant/roxum/roxum_chat_panel.dart';

class QuantumAiAgentPanel extends StatelessWidget {
  final VoidCallback? onClose;
  final VoidCallback? onToggleExpand;
  final bool isExpanded;

  const QuantumAiAgentPanel({
    super.key,
    this.onClose,
    this.onToggleExpand,
    this.isExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return RoxumChatPanel(
      onClose: onClose,
      onToggleExpand: onToggleExpand,
      isExpanded: isExpanded,
    );
  }
}
