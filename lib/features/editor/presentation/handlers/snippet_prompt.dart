import 'package:re_editor/re_editor.dart';
import '../../../../core/services/language_service.dart';

class CodeSnippetPrompt extends CodePrompt {
  final CodeSnippet snippet;

  CodeSnippetPrompt({
    required this.snippet,
  }) : super(word: snippet.label);

  @override
  CodeAutocompleteResult get autocomplete => CodeAutocompleteResult(
    input: '',
    word: snippet.snippet,
    selection: snippet.selection,
  );

  @override
  bool match(String input) {
    return word.toLowerCase().startsWith(input.toLowerCase());
  }
}
