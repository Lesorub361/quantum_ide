// Ported & adapted from roxum-ide (MIT License) - https://github.com/heckmon/roxum-ide

class AgenticToolSpec {
  final String name;
  final String label;
  final String description;
  final bool requiresWriteAccess;
  final bool defaultEnabled;

  const AgenticToolSpec({
    required this.name,
    required this.label,
    required this.description,
    required this.requiresWriteAccess,
    this.defaultEnabled = true,
  });
}

const List<AgenticToolSpec> agenticToolSpecs = [
  AgenticToolSpec(
    name: 'readFile',
    label: 'Чтение файла',
    description: 'Читает содержимое файла (до 1200 строк за один вызов).',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'writeFile',
    label: 'Запись файла',
    description:
        'Создаёт или перезаписывает файл с авто-проверкой ошибок и diff.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'editFile',
    label: 'Правка файла',
    description:
        'Точечно заменяет фрагмент кода (с умным поиском отступов и авто-диагностикой).',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'multiEditFile',
    label: 'Пакетная правка (MultiEdit)',
    description:
        'Применяет сразу несколько правок к одному файлу за 1 шаг (как multiedit в OpenCode).',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'listFiles',
    label: 'Список файлов',
    description: 'Показывает файлы и папки в директории.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'globSearchFiles',
    label: 'Поиск по маске',
    description: 'Ищет файлы по glob-шаблону.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'grepInFiles',
    label: 'Поиск по тексту',
    description: 'Ищет строки или регулярные выражения в файлах проекта.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'codeOutline',
    label: 'Структура кода (AST/Символы)',
    description:
        'Возвращает список классов, функций и строк (#L) без чтения всего файла.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'getLspDiagnostics',
    label: 'Диагностика / ошибки',
    description: 'Получает ошибки компилятора и анализатора по проекту или файлу.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'runCommand',
    label: 'Терминал (Shell / Root / PRoot)',
    description: 'Выполняет команду в терминале проекта с авто-поиском путей.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'deleteFile',
    label: 'Удаление файла',
    description: 'Удаляет файл из проекта.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'renamePath',
    label: 'Переименование',
    description: 'Переименовывает или перемещает файл/папку.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'gitStatus',
    label: 'Git status',
    description: 'Возвращает статус git-репозитория.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'gitDiff',
    label: 'Git diff',
    description: 'Возвращает git diff изменений.',
    requiresWriteAccess: false,
  ),
  // Дополнительные инструменты (можно включить вручную, всегда поддерживаются при вызове)
  AgenticToolSpec(
    name: 'readFilesBatch',
    label: 'Пакетное чтение',
    description: 'Читает несколько файлов за один вызов.',
    requiresWriteAccess: false,
    defaultEnabled: false,
  ),
  AgenticToolSpec(
    name: 'replaceAllInFile',
    label: 'Замена всех вхождений',
    description: 'Заменяет все вхождения строки в файле.',
    requiresWriteAccess: true,
    defaultEnabled: false,
  ),
  AgenticToolSpec(
    name: 'insertAtLine',
    label: 'Вставка в строку',
    description: 'Вставляет текст перед или после указанной строки.',
    requiresWriteAccess: true,
    defaultEnabled: false,
  ),
  AgenticToolSpec(
    name: 'checkEnvironment',
    label: 'Поиск SDK и окружения',
    description:
        'Ищет установленные в системе Flutter, Dart, Java, Gradle, Node, Python, Git, Rust.',
    requiresWriteAccess: false,
    defaultEnabled: false,
  ),
  AgenticToolSpec(
    name: 'installPackages',
    label: 'Авто-установка пакетов',
    description:
        'Устанавливает недостающие пакеты и библиотеки (pub, npm, pip, apt, cargo).',
    requiresWriteAccess: true,
    defaultEnabled: false,
  ),
  AgenticToolSpec(
    name: 'activeEditorFile',
    label: 'Активный файл',
    description: 'Получает путь к текущему открытому файлу в редакторе.',
    requiresWriteAccess: false,
    defaultEnabled: false,
  ),
  AgenticToolSpec(
    name: 'currentlySelectedText',
    label: 'Выделенный текст',
    description: 'Получает выделенный текст в активном редакторе.',
    requiresWriteAccess: false,
    defaultEnabled: false,
  ),
  AgenticToolSpec(
    name: 'getFileInfo',
    label: 'Метаданные файла',
    description: 'Возвращает размер и время изменения файла.',
    requiresWriteAccess: false,
    defaultEnabled: false,
  ),
  AgenticToolSpec(
    name: 'getPendingEditsForFile',
    label: 'Ожидающие правки',
    description: 'Показывает неподтверждённые изменения агента.',
    requiresWriteAccess: false,
    defaultEnabled: false,
  ),
  AgenticToolSpec(
    name: 'gitLog',
    label: 'Git log',
    description: 'Возвращает последние коммиты git.',
    requiresWriteAccess: false,
    defaultEnabled: false,
  ),
];

Map<String, bool> normalizeAgenticToolSelections(
  Map<String, bool>? selections,
) {
  return {
    for (final spec in agenticToolSpecs)
      spec.name: selections?[spec.name] ?? spec.defaultEnabled,
  };
}

List<Map<String, dynamic>> filterAgenticToolsBySelection(
  List<Map<String, dynamic>> tools,
  Map<String, bool>? selections,
) {
  if (selections == null || selections.isEmpty) {
    return tools;
  }

  final knownSpecs = {
    for (final spec in agenticToolSpecs) spec.name: spec.defaultEnabled,
  };

  return tools.where((tool) {
    final function = tool['function'];
    if (function is! Map) return true;
    final toolName = function['name']?.toString();
    if (toolName == null || toolName.isEmpty) return true;
    if (selections.containsKey(toolName)) {
      return selections[toolName]!;
    }
    return knownSpecs[toolName] ?? false;
  }).toList();
}

bool isAgenticWriteTool(String toolName) {
  return agenticToolSpecs.any(
    (spec) => spec.name == toolName && spec.requiresWriteAccess,
  );
}
