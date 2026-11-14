// Ported & adapted from roxum-ide (MIT License) - https://github.com/heckmon/roxum-ide

class AgenticToolSpec {
  final String name;
  final String label;
  final String description;
  final bool requiresWriteAccess;

  const AgenticToolSpec({
    required this.name,
    required this.label,
    required this.description,
    required this.requiresWriteAccess,
  });
}

const List<AgenticToolSpec> agenticToolSpecs = [
  AgenticToolSpec(
    name: 'activeEditorFile',
    label: 'Активный файл',
    description: 'Получает путь к текущему открытому файлу в редакторе.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'currentlySelectedText',
    label: 'Выделенный текст',
    description: 'Получает выделенный текст в активном редакторе.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'getLspDiagnostics',
    label: 'Диагностика / ошибки',
    description: 'Получает ошибки и предупреждения из открытых файлов.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'readFile',
    label: 'Чтение файла',
    description: 'Читает содержимое файла.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'readFilesBatch',
    label: 'Пакетное чтение',
    description: 'Читает несколько файлов за один вызов.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'writeFile',
    label: 'Запись файла',
    description: 'Создаёт или перезаписывает файл с отслеживанием diff.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'editFile',
    label: 'Правка файла',
    description: 'Заменяет фрагмент текста в файле с отслеживанием diff.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'insertAtLine',
    label: 'Вставка в строку',
    description: 'Вставляет текст перед или после указанной строки.',
    requiresWriteAccess: true,
  ),
  AgenticToolSpec(
    name: 'replaceAllInFile',
    label: 'Замена в файле',
    description: 'Заменяет все вхождения текста в файле.',
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
    description: 'Ищет строки в файлах проекта.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'getFileInfo',
    label: 'Метаданные файла',
    description: 'Возвращает размер и время изменения файла.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'getPendingEditsForFile',
    label: 'Ожидающие правки',
    description: 'Показывает неподтверждённые изменения агента.',
    requiresWriteAccess: false,
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
  AgenticToolSpec(
    name: 'gitLog',
    label: 'Git log',
    description: 'Возвращает последние коммиты git.',
    requiresWriteAccess: false,
  ),
  AgenticToolSpec(
    name: 'runCommand',
    label: 'Терминал (PRoot)',
    description: 'Выполняет команду в Ubuntu PRoot-окружении.',
    requiresWriteAccess: true,
  ),
];

Map<String, bool> normalizeAgenticToolSelections(
  Map<String, bool>? selections,
) {
  return {
    for (final spec in agenticToolSpecs)
      spec.name: selections?[spec.name] ?? true,
  };
}

List<Map<String, dynamic>> filterAgenticToolsBySelection(
  List<Map<String, dynamic>> tools,
  Map<String, bool>? selections,
) {
  if (selections == null || selections.isEmpty) {
    return tools;
  }

  return tools.where((tool) {
    final function = tool['function'];
    if (function is! Map) return true;
    final toolName = function['name']?.toString();
    if (toolName == null || toolName.isEmpty) return true;
    return selections[toolName] ?? true;
  }).toList();
}

bool isAgenticWriteTool(String toolName) {
  return agenticToolSpecs.any(
    (spec) => spec.name == toolName && spec.requiresWriteAccess,
  );
}
