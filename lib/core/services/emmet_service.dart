class EmmetService {
  static final EmmetService _instance = EmmetService._();
  factory EmmetService() => _instance;
  EmmetService._();

  String expandAbbreviation(String abbreviation, String language) {
    if (language == 'html' || language == 'xml' || language == 'svg') {
      return _expandHtml(abbreviation);
    } else if (language == 'css') {
      return _expandCss(abbreviation);
    }
    return abbreviation;
  }

  String _expandHtml(String abbr) {
    // Handle multiplication: li*3
    final mulMatch = RegExp(r'^(\w+)\*(\d+)$').firstMatch(abbr);
    if (mulMatch != null) {
      final tag = mulMatch.group(1)!;
      final count = int.parse(mulMatch.group(2)!);
      final buffer = StringBuffer();
      for (int i = 1; i <= count; i++) {
        buffer.writeln('<$tag></$tag>');
      }
      return buffer.toString().trimRight();
    }

    // Handle child combinator: div>ul>li
    if (abbr.contains('>')) {
      final parts = abbr.split('>');
      String result = _expandSingleTag(parts[0].trim());
      String indent = '';
      
      for (int i = 1; i < parts.length; i++) {
        final part = parts[i].trim();
        indent += '  ';
        
        if (part.contains('+')) {
          final siblings = part.split('+');
          for (final sibling in siblings) {
            result += '\n$indent${_expandSingleTag(sibling.trim())}';
          }
        } else {
          result += '\n$indent${_expandSingleTag(part)}';
        }
      }
      
      return result;
    }

    // Handle sibling combinator: div+p
    if (abbr.contains('+')) {
      final parts = abbr.split('+');
      return parts.map((p) => _expandSingleTag(p.trim())).join('\n');
    }

    return _expandSingleTag(abbr);
  }

  String _expandSingleTag(String tag) {
    if (tag.isEmpty) return '';
    
    // Handle classes: div.container
    final classMatch = RegExp(r'^(\w+)?\.([\w-]+)$').firstMatch(tag);
    if (classMatch != null) {
      final tagName = classMatch.group(1) ?? 'div';
      final className = classMatch.group(2);
      return '<$tagName class="$className"></$tagName>';
    }

    // Handle id: div#main
    final idMatch = RegExp(r'^(\w+)?#([\w-]+)$').firstMatch(tag);
    if (idMatch != null) {
      final tagName = idMatch.group(1) ?? 'div';
      final id = idMatch.group(2);
      return '<$tagName id="$id"></$tagName>';
    }

    // Handle self-closing tags
    final selfClosingTags = ['img', 'br', 'hr', 'input', 'meta', 'link', 'area', 'base', 'col', 'embed', 'source', 'track', 'wbr'];
    if (selfClosingTags.contains(tag)) {
      return '<$tag />';
    }

    return '<$tag></$tag>';
  }

  String _expandCss(String abbr) {
    // Handle common CSS abbreviations
    final abbreviations = {
      'm': 'margin',
      'p': 'padding',
      'w': 'width',
      'h': 'height',
      'bg': 'background',
      'c': 'color',
      'fz': 'font-size',
      'fw': 'font-weight',
      'd': 'display',
      'pos': 'position',
      't': 'top',
      'r': 'right',
      'b': 'bottom',
      'l': 'left',
      'z': 'z-index',
      'op': 'opacity',
      'br': 'border-radius',
      'bs': 'box-shadow',
      'ai': 'align-items',
      'jc': 'justify-content',
      'fd': 'flex-direction',
      'fs': 'flex-shrink',
      'fg': 'flex-grow',
      'ff': 'flex-flow',
      'g': 'gap',
      'ov': 'overflow',
      'tr': 'transform',
      'trs': 'transition',
      'an': 'animation',
    };

    // Handle value shortcuts: m10 => margin: 10px
    final valueMatch = RegExp(r'^([a-z]+)(-?\d+)([a-z]*)$').firstMatch(abbr);
    if (valueMatch != null) {
      final prop = valueMatch.group(1)!;
      final value = valueMatch.group(2)!;
      final unit = valueMatch.group(3)!.isEmpty ? 'px' : valueMatch.group(3)!;
      
      final fullProp = abbreviations[prop] ?? prop;
      return '$fullProp: $value$unit';
    }

    return abbr;
  }

  bool isEmmetAbbreviation(String text) {
    // Check if text looks like an Emmet abbreviation
    if (text.isEmpty) return false;
    
    // HTML patterns
    if (RegExp(r'^[a-z][a-z0-9]*(\.[\w-]+|#[\w-]+|\*[\d]+)?(>[\w\.\#\*]+(\*[\d]+)?)*(\+[\w\.\#\*]+)*$').hasMatch(text)) {
      return true;
    }
    
    // CSS patterns
    if (RegExp(r'^[a-z]{1,4}-?\d+$').hasMatch(text)) {
      return true;
    }
    
    return false;
  }
}