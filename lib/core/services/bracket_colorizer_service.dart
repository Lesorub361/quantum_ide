import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BracketPair {
  final int openOffset;
  final int closeOffset;
  final String type;

  const BracketPair({
    required this.openOffset,
    required this.closeOffset,
    required this.type,
  });
}

class BracketColorizerService extends ChangeNotifier {
  final Map<int, int> _matchingBrackets = {};
  final List<BracketPair> _pairs = <BracketPair>[];

  Map<int, int> get matchingBrackets => Map.unmodifiable(_matchingBrackets);
  List<BracketPair> get pairs => List.unmodifiable(_pairs);

  static const List<Color> _nestingColors = [
    Color(0xFFFF6B6B),
    Color(0xFF4ECDC4),
    Color(0xFFFFE66D),
    Color(0xFF95E1D3),
    Color(0xFFF38181),
    Color(0xFFAA96DA),
    Color(0xFFFCBDAD),
    Color(0xFFA8E6CF),
  ];

  Color getBracketColor(int nestingLevel) {
    return _nestingColors[nestingLevel % _nestingColors.length];
  }

  void analyzeText(String text) {
    _matchingBrackets.clear();
    _pairs.clear();

    final stack = <MapEntry<String, int>>[];
    final openBrackets = {'(': '(', '{': '{', '[': '[', '<': '<'};
    final closeBrackets = {')': '(', '}': '{', ']': '[', '>': '<'};

    for (int i = 0; i < text.length; i++) {
      final char = text[i];

      if (openBrackets.containsKey(char)) {
        stack.add(MapEntry(char, i));
      } else if (closeBrackets.containsKey(char)) {
        if (stack.isNotEmpty && stack.last.key == closeBrackets[char]) {
          final open = stack.removeLast();
          _matchingBrackets[open.key == '(' ? i : i] = open.value;
          _matchingBrackets[open.value] = i;
          _pairs.add(BracketPair(
            openOffset: open.value,
            closeOffset: i,
            type: open.key,
          ));
        }
      }
    }

    notifyListeners();
  }

  int? findMatchingBracket(String text, int position) {
    if (position < 0 || position >= text.length) return null;

    final char = text[position];
    final openBrackets = {'(': '(', '{': '{', '[': '[', '<': '<'};
    final closeBrackets = {')': '(', '}': '{', ']': '[', '>': '<'};

    if (openBrackets.containsKey(char)) {
      int depth = 0;
      final matchType = openBrackets[char];
      for (int i = position; i < text.length; i++) {
        if (text[i] == char) depth++;
        if (closeBrackets[text[i]] == matchType) depth--;
        if (depth == 0) return i;
      }
    } else if (closeBrackets.containsKey(char)) {
      int depth = 0;
      final matchType = closeBrackets[char];
      for (int i = position; i >= 0; i--) {
        if (text[i] == char) depth++;
        if (openBrackets[text[i]] == matchType) depth--;
        if (depth == 0) return i;
      }
    }

    return null;
  }

  int getNestingLevel(int offset) {
    int level = 0;
    for (final pair in _pairs) {
      if (offset > pair.openOffset && offset < pair.closeOffset) {
        level++;
      }
    }
    return level;
  }

  void clear() {
    _matchingBrackets.clear();
    _pairs.clear();
    notifyListeners();
  }
}

final bracketColorizerProvider = ChangeNotifierProvider<BracketColorizerService>((ref) {
  return BracketColorizerService();
});
