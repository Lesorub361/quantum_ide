// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'QuantumIDE';

  @override
  String get explorer => 'Проводник';

  @override
  String get newFile => 'Новый файл';

  @override
  String get newFolder => 'Новая папка';

  @override
  String get refresh => 'Обновить';

  @override
  String get rename => 'Переименовать';

  @override
  String get delete => 'Удалить';

  @override
  String get cancel => 'Отмена';

  @override
  String get save => 'Сохранить';

  @override
  String get create => 'Создать';

  @override
  String get projectNotOpened => 'Проект не открыт';

  @override
  String get selectFileToStart =>
      'Выберите файл в проводнике, чтобы начать работу';

  @override
  String get openExplorer => 'Открыть проводник';

  @override
  String get confirmDelete => 'Подтвердите удаление';

  @override
  String areYouSureDelete(String name) {
    return 'Вы уверены, что хотите удалить $name?';
  }

  @override
  String get terminal => 'Терминал';

  @override
  String get run => 'Запуск';

  @override
  String get build => 'Сборка';

  @override
  String get aiAgent => 'AI Агент';

  @override
  String get servers => 'Серверы';

  @override
  String get buildLogs => 'Логи сборки';

  @override
  String get appLogs => 'Логи приложения';

  @override
  String get copy => 'Копировать';

  @override
  String get stop => 'Стоп';

  @override
  String get hotReload => 'Hot Reload';

  @override
  String get clear => 'Очистить';

  @override
  String get runProject => 'Запустить проект';

  @override
  String get pubGet => 'Pub Get';

  @override
  String get setupSdk => 'Настроить SDK';

  @override
  String get clean => 'Очистить';

  @override
  String get buildApk => 'Собрать APK';

  @override
  String get welcomeMessage => 'Добро пожаловать в премиум-среду.';

  @override
  String get typeRunToStart => 'Введите run для запуска вашего проекта.';

  @override
  String get settings => 'Настройки';

  @override
  String get interfaceAndLocalization => 'Интерфейс и локализация';

  @override
  String get language => 'Язык';

  @override
  String get theme => 'Тема оформления';

  @override
  String get darkTheme => 'Тёмная тема';

  @override
  String get lightTheme => 'Светлая тема';

  @override
  String get colorPalette => 'Цветовая палитра';

  @override
  String get customColor => 'Custom Color';

  @override
  String get accentColor => 'Акцентный цвет';

  @override
  String get projectIcon => 'Иконка проекта';

  @override
  String get defaultAccent => 'По умолчанию';

  @override
  String get codeEditor => 'Редактор кода';

  @override
  String get editorFontSize => 'Размер шрифта';

  @override
  String get autoCompletion => 'Автодополнение';

  @override
  String get showCodeHints => 'Показывать подсказки кода';

  @override
  String get aiAutoCompletion => 'AI-автодополнение';

  @override
  String get geminiCodeGeneration => 'Генерация кода от Gemini';

  @override
  String get wordWrap => 'Перенос строк';

  @override
  String get wordWrapDescription => 'Word wrap в редакторе';

  @override
  String get lineNumbers => 'Номера строк';

  @override
  String get showLineNumbers => 'Показывать нумерацию';

  @override
  String get minimap => 'Миникарта';

  @override
  String get showMinimap => 'Minimap в редакторе';

  @override
  String get autoSave => 'Автосохранение';

  @override
  String get autoSaveDescription => 'Сохранять через 2 сек';

  @override
  String get terminalFontSize => 'Размер шрифта терминала';

  @override
  String get terminalTheme => 'Тема терминала';

  @override
  String get toolsAndAi => 'Инструменты и AI';

  @override
  String get aiProviders => 'AI Провайдеры';

  @override
  String get aiProvidersSubtitle => 'Gemini, OpenAI, Ollama и др.';

  @override
  String get ubuntuPackages => 'Пакеты Ubuntu';

  @override
  String get manageCliTools => 'Управление CLI утилитами';

  @override
  String get hosts => 'Серверы';

  @override
  String get localRemoteHosts => 'Локальные/удалённые хосты';

  @override
  String get system => 'Система';

  @override
  String get showHiddenFiles => 'Скрытые файлы';

  @override
  String get showHiddenFilesDescription => 'Показывать .* файлы';

  @override
  String get vibration => 'Вибрация';

  @override
  String get hapticFeedback => 'Haptic Feedback';

  @override
  String get aboutApp => 'О приложении';

  @override
  String get aboutAppSubtitle => 'Quantum IDE v1.0.0';

  @override
  String get selectPalette => 'Выберите палитру';

  @override
  String get close => 'ЗАКРЫТЬ';

  @override
  String get resetToDefault => 'СБРОСИТЬ ПО УМОЛЧАНИЮ';

  @override
  String get aboutDialogContent =>
      'Мобильная IDE с поддержкой AI, созданная на Flutter.\n© 2026 Quantum IDE';

  @override
  String get ubuntuDarkPurple => 'Ubuntu Dark Purple';

  @override
  String get pureDark => 'Pure Dark';

  @override
  String get searchProjects => 'Поиск проектов...';

  @override
  String get open => 'Открыть';

  @override
  String get market => 'Маркет';

  @override
  String projectsHeader(int count) {
    return 'Проекты ($count)';
  }

  @override
  String get noProjects => 'Нет проектов';

  @override
  String get nothingFound => 'Ничего не найдено';

  @override
  String get createFirstProject => 'Создать первый проект';

  @override
  String get projectActions => 'Действия над проектом';

  @override
  String get fixAndroidBuild => 'Исправить сборку (AGP + compileSdk)';

  @override
  String get patchAndroidBuildDescription =>
      'Патч android-36 / AGP 8.7.3 / compileSdk 35';

  @override
  String get buildApkDescription => 'flutter build apk --debug';

  @override
  String apkBuildFixed(String name) {
    return '✅ Android build файлы исправлены для «$name»';
  }

  @override
  String confirmDeleteTitle(String name) {
    return 'Удалить \"$name\"?';
  }

  @override
  String get confirmDeleteMessage =>
      'Удалить только из списка или вместе с файлами?';

  @override
  String get deleteFromListOnly => 'Из списка';

  @override
  String get deleteFromDisk => 'С диска';

  @override
  String get projectSettings => 'Настройки проекта';

  @override
  String get createProject => 'Создать проект';

  @override
  String get projectName => 'Название проекта';

  @override
  String get projectType => 'ТИП ПРОЕКТА';

  @override
  String get androidCompileSdkVersion => 'ВЕРСИЯ ANDROID compileSdk';

  @override
  String get defaultSdkVersion => 'По умолчанию: 35';

  @override
  String get targetPlatforms => 'ЦЕЛЕВЫЕ УСТРОЙСТВА / ПЛАТФОРМЫ';

  @override
  String get saveAction => 'Сохранить';

  @override
  String get code => 'Код';

  @override
  String get preview => 'Предпросмотр';

  @override
  String get fastCommands => 'БЫСТРЫЕ КОМАНДЫ';

  @override
  String get serverAddress => 'Адрес сервера';

  @override
  String copied(String value) {
    return 'Скопировано: $value';
  }

  @override
  String get stopServer => 'Остановить';

  @override
  String get command => 'КОМАНДА';

  @override
  String get serverStarted => 'Сервер запущен';

  @override
  String get openAddressInBrowser => 'Откройте этот адрес в браузере Android';

  @override
  String get copyUrl => 'Копировать URL';

  @override
  String get openProjectToSeeCommands =>
      'Откройте проект чтобы увидеть команды запуска';

  @override
  String get running => 'Выполняется...';

  @override
  String get chat => 'Чат';

  @override
  String get agents => 'Агенты';

  @override
  String askAiHint(String provider) {
    return 'Спросить $provider...';
  }

  @override
  String get selectModel => 'Выберите модель';

  @override
  String get clearHistory => 'Очистить историю';

  @override
  String get askAboutCode => 'Задайте вопрос по коду';

  @override
  String get you => 'Вы';

  @override
  String workingOnFile(String file, String code, String question) {
    return 'Я работаю над файлом: $file. \nВот его содержимое:\n```\n$code\n```\n\nМой вопрос: $question';
  }

  @override
  String get aiAskDialogTitle => 'Запрос к AI Агенту';

  @override
  String aiAskFolder(String name) {
    return 'Папка: $name';
  }

  @override
  String aiAskFile(String name) {
    return 'Файл: $name';
  }

  @override
  String get aiAskFolderHint =>
      'Опишите задачу (например: \"создай контроллер\", \"добавь модель данных\"...) ';

  @override
  String get aiAskFileHint =>
      'Что нужно сделать? (например: \"добавь валидацию email\", \"оптимизируй метод\"...) ';

  @override
  String get decline => 'Отклонить';

  @override
  String get apply => 'Применить';

  @override
  String get showChanges => 'Показать изменения';

  @override
  String changesInFile(String name) {
    return 'Изменения в $name';
  }

  @override
  String get noFilesFound => 'Ничего не найдено';

  @override
  String get retry => 'Повторить';

  @override
  String errorOccurred(String error) {
    return 'Ошибка: $error';
  }

  @override
  String get aiProvidersInfo =>
      'Добавьте API ключи для разных AI провайдеров. Для локальных моделей (Ollama/LM Studio) ключ не требуется.';

  @override
  String get activeProvider => 'Активный провайдер';

  @override
  String get requiresApiKeyLabel => 'Требует API ключ';

  @override
  String get localNoKey => 'Локальный — без ключа';

  @override
  String get activeCaps => 'АКТИВЕН';

  @override
  String get apiKeyLabel => 'API Ключ';

  @override
  String get keySaved => 'Ключ сохранён';

  @override
  String get urlSaved => 'URL сохранён';

  @override
  String get serverUrlLabel => 'URL сервера';

  @override
  String get ollamaPhoneHint =>
      '💡 Для подключения с телефона используйте IP вашего компьютера (напр. http://192.168.1.10:11434)';

  @override
  String get modelLabel => 'МОДЕЛЬ';

  @override
  String get searching => 'Поиск...';

  @override
  String get findModels => 'Найти модели';

  @override
  String get searchModelHint => 'Поиск по названию модели...';

  @override
  String get customModelHint => 'Или введите название модели вручную...';

  @override
  String modelInstalled(String name) {
    return 'Модель установлена: $name';
  }

  @override
  String get modelsNotFound => 'Модели не найдены. Нажмите «Найти модели».';

  @override
  String get available => 'Доступна';

  @override
  String get quotaLimit => 'Лимит квоты / нагрузка';

  @override
  String get unavailable => 'Недоступна';

  @override
  String get availableCaps => 'ДОСТУПНА';

  @override
  String get activateProvider => 'Активировать провайдер';

  @override
  String providerActivated(String name) {
    return 'Провайдер $name активирован';
  }

  @override
  String get send => 'Отправить';

  @override
  String get acceptAll => 'Принять все';

  @override
  String get rejectAll => 'Отклонить все';

  @override
  String get projectAnalysis => 'Анализ проекта';

  @override
  String problemsFound(int count, int errors, int warnings) {
    return 'Проблем найдено: $count ($errors ошибок, $warnings предупреждений)';
  }

  @override
  String get fixWithAi => 'Исправить ИИ';

  @override
  String runningCommand(String command) {
    return 'Выполняю команду: $command...';
  }

  @override
  String applyingChange(String path) {
    return 'Применяю изменение: $path...';
  }

  @override
  String fileSuccessfullyWritten(String path) {
    return 'Файл $path успешно записан.';
  }

  @override
  String fileSuccessfullyDeleted(String path) {
    return 'Файл $path успешно удален.';
  }

  @override
  String commandExecutedResult(String command, String result) {
    return 'Команда \"$command\" выполнена. Результат:\n$result';
  }

  @override
  String commandSentToTerminal(String command) {
    return 'Команда \"$command\" отправлена в терминал.';
  }

  @override
  String unknownActionType(String type) {
    return 'Неизвестный тип действия: $type';
  }

  @override
  String failedToApplyAction(String error) {
    return 'Не удалось применить действие: $error';
  }

  @override
  String get noErrorsFound => 'Ошибок не обнаружено';

  @override
  String get noErrorsDescription =>
      'Анализатор кода проверил ваш проект. Проблем или предупреждений не найдено.';

  @override
  String get closeProject => 'Закрыть проект';

  @override
  String get closeProjectConfirm =>
      'Вы действительно хотите закрыть этот проект?';

  @override
  String get sortByName => 'По имени';

  @override
  String get sortBySize => 'По размеру';

  @override
  String get sortByDate => 'По дате';

  @override
  String get goToDefinition => 'Переход к определению';

  @override
  String get documentation => 'Документация';

  @override
  String get usages => 'Использования';

  @override
  String get cut => 'Вырезать';

  @override
  String get paste => 'Вставить';

  @override
  String get selectAll => 'Выбрать все';

  @override
  String get line => 'Строка';

  @override
  String get column => 'Колонка';

  @override
  String get info => 'Инфо';

  @override
  String get ok => 'ОК';

  @override
  String get problems => 'Ошибки';

  @override
  String get packages => 'Пакеты';

  @override
  String get tools => 'Инструменты';

  @override
  String get searchFiles => 'Поиск файлов...';

  @override
  String get imageLoadError => 'Ошибка загрузки изображения';
}
