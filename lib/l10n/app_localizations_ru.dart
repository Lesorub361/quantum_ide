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
  String get close => 'Закрыть';

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
    return 'Подтвердите удаление';
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
  String get activeCaps => 'АКТИВНА';

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

  @override
  String get unsaved => 'Не сохранено';

  @override
  String get saved => 'Сохранено';

  @override
  String lineCol(int line, int col) {
    return 'Стр $line, Кол $col';
  }

  @override
  String get noOpenFiles => 'Нет открытых файлов в редакторе';

  @override
  String get fileNotFoundOnDisk => 'Файл не найден на диске';

  @override
  String parsingError(String error) {
    return 'Ошибка парсинга: $error';
  }

  @override
  String get outlineEmptyOrUnsupported =>
      'Структура кода пуста или не поддерживается';

  @override
  String outlineHeader(String filename) {
    return 'Структура: $filename';
  }

  @override
  String get projectFolderNotFound => 'Папка проекта не найдена';

  @override
  String get rootFiles => '[Файлы в корне]';

  @override
  String scanningError(String error) {
    return 'Ошибка сканирования: $error';
  }

  @override
  String get deleteFileConfirmTitle => 'Удаление файла';

  @override
  String deleteFileConfirmMessage(String name, String size) {
    return 'Вы уверены, что хотите безвозвратно удалить файл:\n\n$name\nРазмер: $size?';
  }

  @override
  String get fileDeletedSuccess => 'Файл успешно удален';

  @override
  String deleteFileError(String error) {
    return 'Ошибка удаления: $error';
  }

  @override
  String get diskSpaceAnalysis => 'Анализ дискового пространства...';

  @override
  String get projectFolderEmpty => 'Папка проекта пуста';

  @override
  String get projectSize => 'Размер проекта:';

  @override
  String get folderDistribution => 'Распределение по папкам';

  @override
  String get topHeavyFiles => 'Топ-10 тяжелых файлов';

  @override
  String get noHeavyFiles => 'Нет тяжелых файлов';

  @override
  String get searchPlaceholder => 'Поиск по содержимому...';

  @override
  String get searchCaseSensitive => 'Учитывать регистр';

  @override
  String get searchWholeWord => 'Целое слово';

  @override
  String get searchRegex => 'Регулярные выражения';

  @override
  String get searchInvalidRegex => 'Некорректное регулярное выражение';

  @override
  String get searchNoMatches => 'Совпадений не найдено';

  @override
  String searchMatchesFound(int matches, int files) {
    return 'Найдено $matches совпадений в $files файлах';
  }

  @override
  String searchError(String error) {
    return 'Ошибка поиска: $error';
  }

  @override
  String get searchingInProgress => 'Идет поиск...';

  @override
  String get searchPrompt => 'Введите запрос для поиска';

  @override
  String get apkSigner => 'Подпись APK';

  @override
  String get createKeystore => 'Создать Keystore';

  @override
  String get stepSelectApk => 'Шаг 1: Выберите APK для подписи';

  @override
  String get selectApk => 'Выберите APK';

  @override
  String get selectCustomPath => 'Указать свой путь...';

  @override
  String get apkPathHint => 'Полный путь к APK файлу на устройстве';

  @override
  String get stepSelectKeystore => 'Шаг 2: Выберите ключ (Keystore)';

  @override
  String get selectKeystore => 'Выберите Keystore';

  @override
  String get keystorePathHint => 'Полный путь к файлу .jks/.keystore';

  @override
  String get stepSignSettings => 'Шаг 3: Настройки подписи';

  @override
  String get keystorePassword => 'Пароль Keystore';

  @override
  String get keyAlias => 'Key Alias (псевдоним)';

  @override
  String get keyAliasPassword => 'Пароль Key Alias';

  @override
  String get outputApkName => 'Имя выходного APK-файла';

  @override
  String get signApkButton => 'Подписать APK';

  @override
  String get install => 'Установить';

  @override
  String get refreshProjectFiles => 'Обновить список файлов проекта';

  @override
  String get newKeystoreParams => 'Параметры нового ключа (Keystore)';

  @override
  String get keystoreFilenameHint => 'Имя файла (например, release.jks)';

  @override
  String get storePasswordHint => 'Пароль хранилища (минимум 6 символов)';

  @override
  String get keyAliasHint => 'Алиас ключа (например, key)';

  @override
  String get developerInfoDn => 'Информация о разработчике (DN)';

  @override
  String get devNameCn => 'Имя и фамилия (CN)';

  @override
  String get devUnitOu => 'Отдел (OU)';

  @override
  String get devOrgO => 'Организация (O)';

  @override
  String get devCityL => 'Город (L)';

  @override
  String get devStateS => 'Штат/Область (S)';

  @override
  String get devCountryC => 'Код страны (C)';

  @override
  String get genKeystoreButton => 'Сгенерировать Keystore';

  @override
  String get logSignGen => 'ЛОГ ПОДПИСИ И ГЕНЕРАЦИИ';

  @override
  String get clearLog => 'Очистить лог';

  @override
  String get logPlaceholder =>
      'Здесь будет выведен лог выполнения операций подписи.';

  @override
  String signProjectScanError(String error) {
    return 'Ошибка сканирования проекта: $error';
  }

  @override
  String signKeystoreSelected(String path) {
    return 'Выбран файл через FilePicker: $path';
  }

  @override
  String signFilePickError(String error) {
    return 'Ошибка выбора файла: $error';
  }

  @override
  String get signNoOpenProject => 'Нет открытого проекта';

  @override
  String get signNoApkSelected => 'Не выбран исходный APK';

  @override
  String get signNoKeystoreSelected => 'Не выбран файл Keystore';

  @override
  String get signFillAllFields => 'Заполните все поля подписи';

  @override
  String signApkProgress(String apk) {
    return 'Подпись APK: $apk...';
  }

  @override
  String signKeyFile(String key, String alias) {
    return 'Файл ключа: $key (alias: $alias)';
  }

  @override
  String get signRunningApksigner => 'Запуск apksigner...';

  @override
  String get signVerifying => 'Верификация подписи...';

  @override
  String get signSuccess => 'APK успешно подписан и верифицирован!';

  @override
  String get signVerifyFailed =>
      'Подпись не верифицирована или произошла ошибка.';

  @override
  String signError(String error) {
    return 'Ошибка при подписи APK: $error';
  }

  @override
  String get genKeystoreFillFields => 'Заполните ключевые поля генерации';

  @override
  String genKeystoreProgress(String name) {
    return 'Генерация Keystore: $name...';
  }

  @override
  String genKeystoreSuccess(String name) {
    return 'Keystore успешно создан по пути: $name';
  }

  @override
  String get genKeystoreFailed => 'Не удалось создать файл Keystore.';

  @override
  String genKeystoreError(String error) {
    return 'Ошибка при генерации Keystore: $error';
  }

  @override
  String installApkProgress(String apk) {
    return 'Запуск установки APK: $apk';
  }

  @override
  String installApkResult(String msg) {
    return 'Результат установки: $msg';
  }

  @override
  String installApkNotFound(String path) {
    return 'Файл APK не найден: $path';
  }

  @override
  String installApkError(String error) {
    return 'Ошибка установки: $error';
  }

  @override
  String get glassmorphismEffects => 'Эффекты стекла (Glassmorphism)';

  @override
  String get glassOpacity => 'Прозрачность эффекта';

  @override
  String get backdropBlur => 'Размытие фона (Blur)';

  @override
  String get editorFontFamily => 'Шрифт редактора';

  @override
  String get fontLigatures => 'Лигатуры шрифта';

  @override
  String get fontLigaturesDescription =>
      'Включить лигатуры в коде (например, -> или !=)';

  @override
  String get selectFontFamily => 'Выберите шрифт';

  @override
  String get selectLanguage => 'Выберите язык';

  @override
  String get format => 'Форматировать';

  @override
  String get liveShare => 'Совместная разработка';

  @override
  String get hostSession => 'Создать сессию';

  @override
  String get joinSession => 'Подключиться к сессии';

  @override
  String get stopSession => 'Остановить сессию';

  @override
  String get disconnectSession => 'Отключиться';

  @override
  String get sessionActive => 'Сессия активна';

  @override
  String get hostingAt => 'Хостинг на:';

  @override
  String get connectedTo => 'Подключен к:';

  @override
  String get userName => 'Ваше имя';

  @override
  String get usersList => 'Участники';

  @override
  String get messagePlaceholder => 'Введите сообщение...';

  @override
  String get connectError => 'Ошибка подключения';

  @override
  String get invalidAddress => 'Неверный адрес';

  @override
  String get joinLink => 'IP-адрес сессии';

  @override
  String get localIps => 'Локальные IP:';

  @override
  String get wasmPlugins => 'Плагины WASM';

  @override
  String get installPlugin => 'Установить плагин (.wasm)';

  @override
  String get noPluginsInstalled => 'Нет установленных плагинов';

  @override
  String get pluginEnabled => 'Плагин включен';

  @override
  String get pluginDisabled => 'Плагин выключен';

  @override
  String get runWasmAction => 'Запустить WASM плагин';

  @override
  String get noActiveSelection => 'Текст не выбран. Применить ко всему файлу?';

  @override
  String get applyToSelection => 'Применить к выделению';

  @override
  String get applyToDocument => 'Применить к документу';

  @override
  String get logs => 'Логи';

  @override
  String get clearLogs => 'Очистить логи';

  @override
  String get deletePlugin => 'Удалить плагин';

  @override
  String get resetToDefaults => 'Сбросить настройки';

  @override
  String get welcomeTitle => 'Добро пожаловать!';

  @override
  String get welcomeSubtitle => 'Выберите проект для работы или создайте новый';

  @override
  String get lastActiveProject => 'Последний активный проект';

  @override
  String get runTooltip => 'Запустить';

  @override
  String get actionsTooltip => 'Действия';

  @override
  String get packagesTooltip => 'Пакеты';

  @override
  String get extensionsAndTools => 'Расширения & Инструменты';

  @override
  String get searchExtensionsHint => 'Поиск расширений...';

  @override
  String get searchPubdevHint =>
      'Поиск библиотек на pub.dev (например, dio)...';

  @override
  String get tabAll => 'Все';

  @override
  String get tabInstalled => 'Установленные';

  @override
  String get tabLanguagesAndAi => 'Языки и ИИ';

  @override
  String get tabTools => 'Инструменты';

  @override
  String get tabBuild => 'Сборка';

  @override
  String get tabSdkPlatforms => 'Платформы SDK';

  @override
  String get tabPubLibraries => 'Библиотеки Pub';

  @override
  String get readyToBuildApk => 'Готовы к сборке APK?';

  @override
  String get installAndroidSdkJava => 'Установите Android SDK & Java 17';

  @override
  String get sdkSetupDescription =>
      'Это настроит SDK, компиляторы, утилиты zipalign, apksigner, оптимизирует настройки сети Gradle и подготовит ваше окружение к компиляции проектов.';

  @override
  String get initializingDevEnvironment => 'Инициализация среды разработки...';

  @override
  String get viewAction => 'Посмотреть';

  @override
  String get startSdkSetup => 'Начать настройку окружения';

  @override
  String get buildIssues => 'Проблемы со сборкой?';

  @override
  String get restoreAndroidGradleEnv =>
      'Восстановление окружения Android & Gradle';

  @override
  String get wrenchFixDescription =>
      'Автоматически исправляет ошибки AAPT2 daemon, выставляет правильные разрешения для проектов, восстанавливает бинарник компилятора ресурсов и настраивает потоки Gradle.';

  @override
  String get runningWrenchFix => 'Запуск исправления окружения сборки...';

  @override
  String get startWrenchFix => 'Запустить исправление (Wrench Fix)';

  @override
  String get statusInstalledCaps => 'УСТАНОВЛЕНО';

  @override
  String get reinstallOrUpdateTooltip => 'Переустановить / Обновить';

  @override
  String updatingPackage(String name) {
    return 'Обновление $name...';
  }

  @override
  String installingPackage(String name) {
    return 'Установка $name...';
  }

  @override
  String get installAction => 'Установить';

  @override
  String get searchPubdevTitle => 'Поиск Flutter-библиотек';

  @override
  String get searchPubdevDescription =>
      'Введите название библиотеки (например: dio, bloc, riverpod) в поиск выше и нажмите Enter';

  @override
  String loadError(String error) {
    return 'Ошибка загрузки: $error';
  }

  @override
  String get addAction => 'Добавить';

  @override
  String get openProjectToInstallLibraries =>
      'Сначала откройте проект, чтобы добавлять библиотеки.';

  @override
  String installingLibrary(String name) {
    return 'Установка библиотеки $name...';
  }

  @override
  String importError(String error) {
    return 'Ошибка импорта: $error';
  }

  @override
  String get filesImportedSuccessfully => 'Файлы успешно импортированы';

  @override
  String get dragFilesHereToImport => 'Перетащите файлы сюда для импорта';

  @override
  String selectedCount(int count) {
    return 'Выбрано: $count';
  }

  @override
  String get selectAllTooltip => 'Выбрать все';

  @override
  String get copyTooltip => 'Копировать';

  @override
  String copiedCount(int count) {
    return 'Скопировано объектов: $count';
  }

  @override
  String get cutTooltip => 'Вырезать';

  @override
  String cutCount(int count) {
    return 'Вырезано объектов: $count';
  }

  @override
  String get zipTooltip => 'Сжать в ZIP';

  @override
  String get deleteTooltip => 'Удалить';

  @override
  String foldersCount(int count) {
    return 'Папок: $count';
  }

  @override
  String get askAiAction => 'Спросить ИИ';

  @override
  String get explainAiAction => 'ИИ: Объяснить';

  @override
  String get documentAiAction => 'ИИ: Документация';

  @override
  String get testAiAction => 'ИИ: Создать тесты';

  @override
  String get optimizeAiAction => 'ИИ: Оптимизировать';

  @override
  String pasteCount(int count) {
    return 'Вставить ($count)';
  }

  @override
  String get archiveNameHint => 'Имя архива';

  @override
  String get compressAction => 'Сжать';

  @override
  String get archiveCreatedSuccessfully => 'Архив успешно создан!';

  @override
  String compressionError(String error) {
    return 'Ошибка сжатия: $error';
  }

  @override
  String get archiveExtractedSuccessfully => 'Архив успешно распакован!';

  @override
  String extractionError(String error) {
    return 'Ошибка распаковки: $error';
  }

  @override
  String get deleteSelectedTitle => 'Удалить выбранное?';

  @override
  String deleteSelectedConfirmation(int count) {
    return 'Вы уверены, что хотите удалить $count элементов?';
  }

  @override
  String get selectedElementsDeleted => 'Выбранные элементы удалены!';

  @override
  String deleteError(String error) {
    return 'Ошибка удаления: $error';
  }

  @override
  String get filesPastedSuccessfully => 'Файлы успешно вставлены!';

  @override
  String pasteError(String error) {
    return 'Ошибка вставки: $error';
  }

  @override
  String get repositoryNotFound => 'Репозиторий не найден';

  @override
  String get initGitRepoDescription =>
      'Инициализируйте локальный Git-репозиторий для отслеживания изменений.';

  @override
  String get initGitAction => 'Инициализировать Git';

  @override
  String get gitConflicted => 'КОНФЛИКТЫ';

  @override
  String get gitStaged => 'ИНДЕКСИРОВАНО';

  @override
  String get gitModified => 'ИЗМЕНЕНО';

  @override
  String get gitUntracked => 'НЕОТСЛЕЖИВАЕМОЕ';

  @override
  String get commitMessageHint => 'Сообщение коммита...';

  @override
  String get resetChangesTitle => 'Сбросить изменения?';

  @override
  String get resetChangesConfirmation =>
      'Вы действительно хотите безвозвратно сбросить все незакоммиченные изменения в этом файле?';

  @override
  String get resetAction => 'Сбросить';

  @override
  String get changesReset => 'Изменения сброшены';

  @override
  String resetError(String error) {
    return 'Ошибка сброса: $error';
  }

  @override
  String get normalView => 'Обычный вид';

  @override
  String get splitView => 'Сплит-вид (Side-by-Side)';

  @override
  String get stagedMessage => 'Файл добавлен в индекс';

  @override
  String get unstagedMessage => 'Файл убран из индекса';

  @override
  String stageError(String error) {
    return 'Ошибка индексации: $error';
  }

  @override
  String get failedToLoadChanges => 'Не удалось загрузить изменения';

  @override
  String get noChanges => 'Нет изменений';

  @override
  String get fileIdenticalToHead => 'Этот файл полностью совпадает с HEAD';

  @override
  String get runTerminalTooltip => 'Запустить';

  @override
  String get restartTerminalTooltip => 'Перезапустить';

  @override
  String get consoleSubTab => 'Консоль';

  @override
  String get signApkSubTab => 'Подпись APK';

  @override
  String get copiedToClipboard => 'Скопировано в буфер обмена';

  @override
  String get back => 'Назад';

  @override
  String get tryChangingSearchQuery => 'Попробуйте изменить запрос поиска';

  @override
  String get incomingBranch => 'Входящая ветка';

  @override
  String get resolveConflictsBeforeSaving =>
      'Пожалуйста, разрешите все конфликты перед сохранением!';

  @override
  String get fileSavedAndStaged =>
      'Файл успешно сохранен и добавлен в индекс Git';

  @override
  String saveError(String error) {
    return 'Ошибка при сохранении: $error';
  }

  @override
  String get acceptMerge => 'Принять слияние';

  @override
  String get errorLoadingConflictFile => 'Ошибка загрузки конфликтного файла';

  @override
  String get conflictsNotFound => 'Конфликты не найдены';

  @override
  String get noConflictMarkersFound =>
      'В данном файле отсутствуют стандартные маркеры конфликтов Git.';

  @override
  String get backToGit => 'Назад к Git';

  @override
  String get conflictBlock => 'Конфликтный блок';

  @override
  String get currentChangesOurs => 'Текущие изменения (Ours / HEAD)';

  @override
  String incomingChanges(String branch) {
    return 'Входящие изменения ($branch)';
  }

  @override
  String get useThisVersion => 'Использовать эту версию';

  @override
  String get mergeResultEditable => 'Результат слияния (Редактируемый)';

  @override
  String get chooseVersionOrWriteHint =>
      'Выберите одну из версий выше или напишите свой вариант разрешения конфликта...';

  @override
  String get markAsResolvedHint =>
      '* Чтобы пометить этот блок как разрешенный, введите или выберите текст.';

  @override
  String get emptyLabel => '(Пусто)';

  @override
  String get stageAction => 'Индексировать';

  @override
  String get unstageAction => 'Убрать из индекса';

  @override
  String get cursorColor => 'ЦВЕТ КУРСОРА';

  @override
  String get or => 'ИЛИ';

  @override
  String get ipCopiedToClipboard => 'IP скопирован в буфер обмена';

  @override
  String editingFile(String file) {
    return 'Редактирует: $file';
  }

  @override
  String get viewingProject => 'Просматривает проект';

  @override
  String get noProblemsFound => 'Проблем в коде не обнаружено';

  @override
  String get problemsList => 'Список проблем';

  @override
  String get sendToAi => 'Отправить ИИ';

  @override
  String get helpMeFixErrors =>
      'Пожалуйста, помоги мне исправить следующие ошибки компиляции в проекте:';

  @override
  String lineColumn(int line, int col) {
    return 'Строка $line, колонка $col';
  }

  @override
  String get decreaseFontSize => 'Уменьшить шрифт';

  @override
  String get increaseFontSize => 'Увеличить шрифт';

  @override
  String get undo => 'Отменить';

  @override
  String get redo => 'Повторить';

  @override
  String get moveLeft => 'Влево';

  @override
  String get moveUp => 'Вверх';

  @override
  String get moveDown => 'Вниз';

  @override
  String get moveRight => 'Вправо';

  @override
  String get edit => 'Редактировать';

  @override
  String get packagesAndEnv => 'Пакеты и окружение';

  @override
  String packagesInstalledCount(int count, int total) {
    return 'Установлено: $count/$total';
  }

  @override
  String get flutterProject => 'Flutter Проект';

  @override
  String get pythonProject => 'Python Проект';

  @override
  String get nodejsProject => 'Node.js Проект';

  @override
  String get dartProject => 'Dart Проект';

  @override
  String get webProject => 'Web Проект';

  @override
  String get androidProject => 'Android Проект';

  @override
  String get genericProject => 'Проект';

  @override
  String get runPC => 'Запуск (ПК)';

  @override
  String get runMob => 'Запуск (Тел.)';

  @override
  String get startServer => 'Старт Сервера';

  @override
  String get buildAPK => 'Собрать APK';

  @override
  String get startTheProject => 'Запустите проект';

  @override
  String get outputCopied => 'Вывод скопирован';

  @override
  String get console => 'Консоль';

  @override
  String get signApk => 'Подпись APK';

  @override
  String get buildPC => 'Сборка (ПК)';

  @override
  String get resetPlugins => 'Сбросить плагины';

  @override
  String get resetPluginsConfirmation =>
      'Это удалит все пользовательские плагины и восстановит настройки по умолчанию. Продолжить?';

  @override
  String get resetPluginsTitle => 'Сбросить плагины?';

  @override
  String get installWasm => 'Установить .wasm';

  @override
  String get availableActions => 'Доступные действия:';

  @override
  String get logsTerminal => 'Терминал логов';

  @override
  String get noLogsCaptured => 'Лонгборд логов пуст';

  @override
  String get installWasmPluginTitle => 'Установка WASM Плагина';

  @override
  String get selectWasmFile => 'Выбрать .wasm файл';

  @override
  String get pluginName => 'Название плагина';

  @override
  String get nameRequired => 'Введите название';

  @override
  String get pluginDescription => 'Описание';

  @override
  String get descriptionRequired => 'Введите описание';

  @override
  String get exposedActions => 'Действия плагина';

  @override
  String get add => 'Добавить';

  @override
  String get pickWasmFileFirst => 'Выберите .wasm файл';

  @override
  String get pluginInstalledSuccessfully => 'Плагин успешно установлен';

  @override
  String failedToInstall(String error) {
    return 'Ошибка установки: $error';
  }

  @override
  String get mcpServersTitle => 'Модули ИИ: MCP Серверы';

  @override
  String activeServers(int count) {
    return 'Активные серверы ($count)';
  }

  @override
  String get repository => 'Репозиторий';

  @override
  String get noMcpServers => 'Нет добавленных MCP серверов';

  @override
  String get goToRepository => 'Перейти в Репозиторий';

  @override
  String get addManually => 'Добавить вручную';

  @override
  String get addServerManually => 'Добавить сервер вручную';

  @override
  String get installed => 'УСТАНОВЛЕН';

  @override
  String packageDetail(String detail) {
    return 'Пакет: $detail';
  }

  @override
  String authParam(String key) {
    return 'Параметр авторизации: $key';
  }

  @override
  String enterValueFor(String key) {
    return 'Введите значение для $key';
  }

  @override
  String enterLabel(String label) {
    return 'Введите $label';
  }

  @override
  String installPreset(String name) {
    return 'Установка: $name';
  }

  @override
  String get serverName => 'Имя сервера';

  @override
  String get exampleLocalSearch => 'Например: local-search';

  @override
  String get connectionType => 'Тип подключения';

  @override
  String get stdioLocal => 'Stdio (Локальный процесс)';

  @override
  String get sseHttp => 'SSE (HTTP-поток)';

  @override
  String get startCommand => 'Команда запуска';

  @override
  String get exampleStartCommand => 'Например: node или npx или python3';

  @override
  String get argsSpace => 'Аргументы (через пробел)';

  @override
  String get searchFilesHint => 'Поиск файлов... (введите \"#\" для символов)';

  @override
  String get searchSymbolsHint => 'Поиск символов в коде...';

  @override
  String get modeFiles => 'РЕЖИМ: ФАЙЛЫ';

  @override
  String get modeSymbols => 'РЕЖИМ: СИМВОЛЫ';

  @override
  String resultsCount(int count) {
    return 'Найдено: $count';
  }

  @override
  String get noResults => 'Ничего не найдено';

  @override
  String confirmDeleteMultiple(int count) {
    return 'Вы действительно хотите удалить $count объектов?';
  }

  @override
  String get archiveExtracted => 'Архив успешно распакован!';

  @override
  String get archiveCreated => 'Архив успешно создан!';

  @override
  String get compressToZip => 'Сжать в ZIP';

  @override
  String folderLabel(String name) {
    return 'Папка: $name';
  }

  @override
  String fileLabel(String name) {
    return 'Файл: $name';
  }

  @override
  String get whatShouldAiDoFolder => 'Что сделать с этой папкой?';

  @override
  String get whatShouldAiDoFile => 'Что сделать с этим файлом?';

  @override
  String get askAi => 'Спросить ИИ';

  @override
  String get askAiDesc => 'Интерактивный диалог с ИИ-ассистентом';

  @override
  String get explainStructure => 'ИИ: Объяснить структуру';

  @override
  String get explainStructureDesc => 'Детальное описание кода или папки';

  @override
  String get addDoc => 'ИИ: Добавить документацию';

  @override
  String get addDocDesc => 'Сгенерировать docstrings и комментарии';

  @override
  String get generateTests => 'ИИ: Создать тесты';

  @override
  String get generateTestsDesc => 'Написать unit-тесты для кода';

  @override
  String get optimizeCode => 'ИИ: Оптимизировать';

  @override
  String get optimizeCodeDesc => 'Предложить улучшения производительности';

  @override
  String get newFileDesc => 'Создать файл в этой папке';

  @override
  String get newFolderDesc => 'Создать подпапку';

  @override
  String get removeFromBookmarks => 'Удалить из закладок';

  @override
  String get removeFromBookmarksDesc => 'Убрать файл из быстрого доступа';

  @override
  String get addToBookmarks => 'Добавить в закладки';

  @override
  String get addToBookmarksDesc => 'Закрепить файл для быстрого доступа';

  @override
  String get copyDesc => 'Добавить в буфер обмена';

  @override
  String get cutDesc => 'Переместить файлы';

  @override
  String get pasteDesc => 'Вставить скопированные объекты';

  @override
  String get renameDesc => 'Изменить имя элемента';

  @override
  String get extractZip => 'Распаковать ZIP';

  @override
  String get extractZipDesc => 'Извлечь файлы из архива';

  @override
  String get compressZip => 'Сжать в ZIP';

  @override
  String get compressZipDesc => 'Создать ZIP архив';

  @override
  String get compressSelectedZip => 'Сжать выбранные в ZIP';

  @override
  String get compressSelectedZipDesc => 'Создать архив из выбранных объектов';

  @override
  String get deleteDesc => 'Безвозвратное удаление';

  @override
  String get empty => 'пусто';

  @override
  String get nameFolderHint => 'имя_папки';

  @override
  String get nameFileHint => 'имя_файла.txt';

  @override
  String get itemMoved => 'Элемент успешно перемещен';

  @override
  String moveError(String error) {
    return 'Ошибка перемещения: $error';
  }

  @override
  String get image => 'ИЗОБРАЖЕНИЕ';

  @override
  String get document => 'ДОКУМЕНТ';

  @override
  String get failedToLoadImage => 'Не удалось загрузить изображение';

  @override
  String failedToReadFile(String error) {
    return 'Ошибка чтения файла: $error';
  }

  @override
  String get aiSettings => 'Настройки ИИ';

  @override
  String get provider => 'Провайдер';

  @override
  String get model => 'Модель';

  @override
  String get apiKey => 'API Ключ';

  @override
  String get customBaseUrl => 'Базовый URL (Custom Base URL)';

  @override
  String defaultHint(String url) {
    return 'По умолчанию: $url';
  }

  @override
  String get chatWithAi => 'ЧАТ С ИИ';

  @override
  String get chatHistory => 'История чатов';

  @override
  String get newChat => 'Новый чат';

  @override
  String get internetAccess => 'Доступ в интернет';

  @override
  String get mcpServers => 'MCP Серверы';

  @override
  String get manualMode => 'Ручной';

  @override
  String get safeAutopilot => 'Авто:Безопасный';

  @override
  String get fullAutonomy => 'Авто:Полный';

  @override
  String get agentsNotInstalled => 'Агенты не установлены';

  @override
  String get installGeminiCliInSettings => 'Установите gemini-cli в настройках';

  @override
  String get stopAgent => 'ОСТАНОВИТЬ АГЕНТА';

  @override
  String get withChanges => 'с изменениями';

  @override
  String get attachOpenFile => 'Прикрепить открытый файл';

  @override
  String get noHistoryFound => 'История пуста';

  @override
  String get untitled => 'Без названия';

  @override
  String messagesCount(int count) {
    return '$count сообщений';
  }

  @override
  String get systemEnv => 'Системное окружение';

  @override
  String get fixEnvironmentArm64 => 'Исправить окружение (ARM64)';

  @override
  String get environment => 'Окружение';

  @override
  String get collapseAll => 'Свернуть все';

  @override
  String get elementMovedToRoot => 'Элемент перемещен в корень';

  @override
  String get bookmarks => 'Закладки';

  @override
  String get noActiveWasmPlugins => 'Нет активных WASM плагинов';

  @override
  String get selectPluginAction => 'Выберите действие плагина';

  @override
  String get noSelection => 'Текст не выбран';

  @override
  String get applyPluginToFile => 'Применить действие плагина ко всему файлу?';

  @override
  String get pluginExecutedSuccess => 'Плагин выполнен успешно';

  @override
  String executionError(String error) {
    return 'Ошибка выполнения: $error';
  }

  @override
  String get quickSearch => 'Быстрый поиск (Ctrl+P)';

  @override
  String get saveTooltip => 'Сохранить';

  @override
  String get runWasmPlugin => 'Запустить WASM плагин';

  @override
  String get aiChat => 'Чат с ИИ';

  @override
  String get home => 'Домой';

  @override
  String get pendingDiff => 'Ожидающий Diff';

  @override
  String get keep => 'Принять';

  @override
  String get reject => 'Отклонить';

  @override
  String get keepAll => 'Принять все';

  @override
  String ranAction(String content) {
    return 'Выполнено: $content';
  }

  @override
  String get created => 'Создан';

  @override
  String get deleted => 'Удален';

  @override
  String get edited => 'Изменен';

  @override
  String get taskExecution => 'Выполнение задачи';

  @override
  String stepNumber(int step, int total) {
    return 'Шаг $step/$total';
  }

  @override
  String filesChangedCount(int count, int additions, int deletions) {
    return 'Изменено файлов: $count (+$additions -$deletions)';
  }

  @override
  String commandsExecutedCount(int count) {
    return 'Команд выполнено: $count';
  }

  @override
  String get changesAccepted => 'Изменения успешно сохранены';

  @override
  String undoneChanges(int count) {
    return 'Отменено изменений: $count';
  }

  @override
  String discardedFileChanges(String file) {
    return 'Отменено изменение файла $file';
  }

  @override
  String get thinking => 'Вычисление...';

  @override
  String get planner => 'ПЛАНИРОВЩИК';

  @override
  String get coder => 'КОДЕР';

  @override
  String get validator => 'ВАЛИДАТОР';

  @override
  String get aiAgentRole => 'ИИ-АГЕНТ';

  @override
  String get resubmit => 'Отправить';

  @override
  String get rollbackHistoryToStep => 'Откатить историю и код к этому шагу';

  @override
  String get confirmRollback => 'Подтверждение отката';

  @override
  String get rollbackConfirmationText =>
      'Все изменения кода, сделанные после этого сообщения, будут отменены, а последующие сообщения удалены. Продолжить?';

  @override
  String get yesRollback => 'Да, откатить';

  @override
  String get changesApplied => 'Изменения применены';

  @override
  String get codeCopied => 'Код скопирован в буфер';

  @override
  String get outOfScope => 'Вне проекта!';

  @override
  String get low => 'Низкий';

  @override
  String get medium => 'Средний';

  @override
  String get high => 'Высокий';

  @override
  String get applied => 'Применено';

  @override
  String get resolveConflictTooltip => 'Разрешить конфликт';

  @override
  String get panel1 => 'ПАНЕЛЬ 1';

  @override
  String get panel2 => 'ПАНЕЛЬ 2';

  @override
  String get localWebServer => 'Локальный веб-сервер';

  @override
  String get webServerDesc =>
      'Запустите веб-сервер, чтобы просматривать результаты сборки вашего проекта прямо внутри IDE.';

  @override
  String get startWebServer => 'Запустить веб-сервер';

  @override
  String get stopWebServer => 'Остановить веб-сервер';

  @override
  String get copyAll => 'Копировать всё';

  @override
  String get clearTerminal => 'Очистить терминал';

  @override
  String get openInExternalBrowser => 'Открыть во внешнем браузере';

  @override
  String get search => 'Поиск';

  @override
  String get structure => 'Структура';

  @override
  String get disk => 'Диск';

  @override
  String get plugins => 'Плагины';

  @override
  String get added => 'добавлено';

  @override
  String get removed => 'удалено';

  @override
  String get modified => 'изменено';

  @override
  String selectedObjectsCount(int count) {
    return 'Выбрано объектов: $count';
  }

  @override
  String get explainFolderPreset =>
      'Объясни назначение и структуру этой папки.';

  @override
  String get explainFilePreset =>
      'Подробно объясни назначение и логику работы этого файла.';

  @override
  String get addDocFolderPreset =>
      'Добавь документацию, docstrings и подробные комментарии к коду во всех файлах этой папки.';

  @override
  String get addDocFilePreset =>
      'Добавь понятную документацию, docstrings и подробные комментарии к коду в этом файле.';

  @override
  String get generateTestsFolderPreset =>
      'Напиши unit-тесты для файлов в этой папке.';

  @override
  String get generateTestsFilePreset =>
      'Напиши комплексные unit-тесты для кода в этом файле.';

  @override
  String get optimizeFolderPreset =>
      'Проанализируй код в этой папке и предложи оптимизацию производительности и читаемости.';

  @override
  String get optimizeFilePreset =>
      'Проанализируй код в этом файле и предложи варианты оптимизации производительности, читаемости и архитектуры.';

  @override
  String get deleteSelected => 'Удалить выбранные';

  @override
  String get manual => 'Ручной';

  @override
  String get autoSafe => 'Авто:Безопасный';

  @override
  String get autoFull => 'Авто:Полный';

  @override
  String filesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count файлов',
      few: '$count файла',
      one: '$count файл',
    );
    return '$count $_temp0';
  }

  @override
  String get localAiEngineTitle => 'ДВИЖОК ЛОКАЛЬНОГО ИИ';

  @override
  String get ollamaRunningLocally => 'Ollama запущен локально';

  @override
  String get ollamaRunningLocallyDesc =>
      'Убедитесь, что Ollama запущена на вашей системе. Вы можете запустить её командой \"ollama serve\" и загрузить нужные модели командой \"ollama pull <модель>\".';

  @override
  String get lmStudioRunningLocally => 'LM Studio запущен локально';

  @override
  String get lmStudioRunningLocallyDesc =>
      'Убедитесь, что сервер LM Studio запущен. Вы можете включить Local Server в приложении LM Studio и загрузить нужную модель.';

  @override
  String get ollamaNotDetected => 'Ollama не обнаружен';

  @override
  String get ollamaNotDetectedDesc =>
      'Установите Ollama на устройстве и убедитесь что он запущен. URL можно изменить выше.';

  @override
  String get checkConnection => 'Проверить подключение';

  @override
  String get availableOllamaModels => 'ДОСТУПНЫЕ OLLAMA МОДЕЛИ';

  @override
  String get llamaServerInstallRequired => 'Требуется установка llama-server';

  @override
  String get llamaServerInstallRequiredDesc =>
      'Для запуска локальных моделей ИИ необходим движок llama-server. Нажмите кнопку ниже, чтобы установить его автоматически.';

  @override
  String get installing => 'Установка...';

  @override
  String get installLlamaServerRuntime => 'Установить Llama Server Runtime';

  @override
  String get ollamaModelsTitle => 'OLLAMA МОДЕЛИ';

  @override
  String get localAiModelsTitle => 'ЛОКАЛЬНЫЕ ИИ МОДЕЛИ';

  @override
  String get serverStatusAndControl => 'СТАТУС И УПРАВЛЕНИЕ СЕРВЕРОМ';

  @override
  String get downloadOllamaModelPrompt =>
      'Скачайте хотя бы одну Ollama-модель, чтобы начать работу.';

  @override
  String get downloadModelToStartServerPrompt =>
      'Загрузите хотя бы одну модель выше, чтобы запустить локальный сервер.';

  @override
  String get localLlamaServerLabel => 'Локальный сервер llama-server';

  @override
  String get connected => 'Подключён';

  @override
  String get runningPort8080 => 'Запущен (порт 8080)';

  @override
  String get starting => 'Запуск...';

  @override
  String get stopped => 'Остановлен';

  @override
  String get start => 'Старт';

  @override
  String gbFormat(String size) {
    return '$size ГБ';
  }

  @override
  String ramGbFormat(String size) {
    return '~$size ГБ ОЗУ';
  }

  @override
  String get select => 'Выбрать';

  @override
  String get download => 'Скачать';

  @override
  String get refreshPreview => 'Обновить предпросмотр';

  @override
  String inFolder(String folder) {
    return 'в $folder';
  }

  @override
  String get llamaServerBuiltIn => 'llama-server (встроенный)';

  @override
  String get localAiDisplayName => 'Локальный ИИ';

  @override
  String get notRequired => 'не требуется';

  @override
  String get mcpGithubDesc =>
      'Интеграция с репозиториями, тикетами (issues) и PR на GitHub.';

  @override
  String get mcpGoogleSearchDesc =>
      'Позволяет ИИ-агенту производить живой поиск в Google.';

  @override
  String get mcpFetchDesc =>
      'Скачивание веб-страниц и автоматический перевод их в Markdown.';

  @override
  String get mcpPostgresDesc =>
      'Подключение, чтение структуры таблиц и выполнение SQL-запросов к PostgreSQL.';

  @override
  String get mcpPostgresArg => 'Ссылка для подключения (postgresql://...)';

  @override
  String get mcpSqliteDesc =>
      'Подключение и инспектирование баз данных SQLite в вашем проекте.';

  @override
  String get mcpSqliteArg => 'Путь к файлу БД SQLite (например: db.sqlite)';

  @override
  String get mcpMemoryDesc =>
      'Семантическое хранилище долговременной памяти для вашего ИИ-агента.';

  @override
  String get mcpBraveSearchDesc =>
      'Позволяет ИИ-агенту выполнять веб-поиск с использованием Brave API.';

  @override
  String get mcpPuppeteerDesc =>
      'Автоматизация браузера, создание скриншотов, клики по элементам и скрапинг веб-страниц.';

  @override
  String get mcpFirecrawlDesc =>
      'Преобразование любого веб-сайта в чистый Markdown или структурированный JSON.';

  @override
  String get mcpNotionDesc =>
      'Позволяет читать, изменять страницы, базы данных и комментарии в Notion.';

  @override
  String get mcpSlackDesc =>
      'Предоставляет возможность читать каналы, общаться и отправлять уведомления в Slack.';

  @override
  String get mcpGitDesc =>
      'Просмотр коммитов, сравнение версий, поиск по коммитам и файлам Git локально.';

  @override
  String get mcpGitlabDesc =>
      'Управление проектами GitLab, тикетами, PR и CI/CD пайплайнами.';

  @override
  String get mcpSentryDesc =>
      'Получение логов ошибок и инспектирование сбоев вашего приложения на Sentry.';

  @override
  String get mcpAirtableDesc =>
      'Чтение, создание и обновление записей в базах данных и таблицах Airtable.';

  @override
  String get mcpSequentialThinkingDesc =>
      'Организация размышлений ИИ-агента для структурированного решения сложных задач.';

  @override
  String get phantomProcessesTitle => 'Фантомные процессы (Android 12/13+)';

  @override
  String get phantomProcessesVersion =>
      'Требуется ADB-настройка для стабильной компиляции';

  @override
  String get phantomProcessesError =>
      'В Android 12+ системный убийца процессов (Phantom Process Killer) принудительно убивает сборки (Gradle/Java/Node/Dart), если лимит превышает 32 активных процесса.\n\nДля отключения выполните через ADB на ПК:\n\nadb shell \"/system/bin/device_config put activity_manager max_phantom_processes 2147483647\"\n\nadb shell \"/system/bin/settings put global settings_enable_monitor_phantom_procs false\"';

  @override
  String androidJarCorruptError(String api) {
    return 'android.jar повреждён ($api). Нажмите «Исправить окружение» для переустановки.';
  }

  @override
  String get androidSdkPlatformsHealthy => 'android-35 / android-36 — исправны';

  @override
  String checkFailed(String error) {
    return 'Проверка не удалась: $error';
  }

  @override
  String get analyzingTaskAndPlanning => 'Анализ задачи и планирование...';

  @override
  String agentStepLimitExceeded(int limit) {
    return '🤖 Превышен лимит шагов агента ($limit). Автопилот остановлен.';
  }

  @override
  String get generatingCodeChanges => 'Генерация изменений кода...';

  @override
  String get executionPlanConstructed =>
      '📝 Составлен план выполнения задачи. Перехожу к роли Кодера...';

  @override
  String get verifyingImplementation => 'Проверка корректности реализации...';

  @override
  String blockedUnsafeActions(String blockedText) {
    return '❌ Заблокированы небезопасные действия вне рабочей области:\n$blockedText';
  }

  @override
  String get awaitingApprovalHighRisk =>
      '⚠️ Ожидание одобрения: Обнаружены действия с высоким риском или выключен автопилот. Подтвердите выполнение в панели ИИ.';

  @override
  String autopilotStepSummary(
    int step,
    String actionsListText,
    String results,
  ) {
    return '🤖 Автопилот (шаг $step): Автоматическое одобрение действий:\n$actionsListText\n\nРезультаты:\n$results';
  }

  @override
  String get runningStaticAnalysis =>
      'Запуск статического анализа проекта (dart analyze)...';

  @override
  String agentFailedToFixErrors(int maxAttempts, String errorReport) {
    return '⚠️ Агент не смог автоматически устранить ошибки после $maxAttempts попыток.\n\n**Оставшиеся ошибки:**\n$errorReport\n\nПожалуйста, опишите проблему или исправьте вручную.';
  }

  @override
  String get fixingCompilationErrors => 'Исправление ошибок компиляции...';

  @override
  String readingFile(String path) {
    return 'Чтение файла $path...';
  }

  @override
  String savingFile(String path) {
    return 'Сохранение файла $path...';
  }

  @override
  String deletingFile(String path) {
    return 'Удаление файла $path...';
  }

  @override
  String runningCommandStatus(String command) {
    return 'Запуск команды \"$command\"...';
  }

  @override
  String searchingCode(String query) {
    return 'Поиск в коде: \"$query\"...';
  }

  @override
  String listingDirectory(String path) {
    return 'Получение списка папки $path...';
  }

  @override
  String findingSymbols(String query) {
    return 'Поиск символов: \"$query\"...';
  }

  @override
  String searchingWeb(String query) {
    return 'Поиск в интернете: \"$query\"...';
  }

  @override
  String fetchingWebPage(String path) {
    return 'Загрузка веб-страницы: $path...';
  }

  @override
  String get executingAction => 'Выполнение действия...';

  @override
  String runningCommandLabel(String command) {
    return '🤖 Выполняю команду: $command...';
  }

  @override
  String applyingChangeLabel(String path) {
    return '🤖 Применяю изменение: $path...';
  }

  @override
  String commandSentToTerminalLabel(String command) {
    return '🤖 Команда \"$command\" отправлена в терминал.';
  }

  @override
  String runningCommandResultLabel(String command, String result) {
    return 'Команда \"$command\" выполнена. Результат:\n$result';
  }

  @override
  String fileNotFound(String path) {
    return 'Файл не найден: $path';
  }

  @override
  String fileContentsHeader(String path, int lineCount, String truncated) {
    return 'Содержимое файла `$path` ($lineCount строк):\n\n```\n$truncated\n```';
  }

  @override
  String fileTruncatedSuffix(int lineCount) {
    return '... [обрезано до 8000 символов из $lineCount строк]';
  }

  @override
  String get safetyGuardFileOutsideWorkspace =>
      'Ошибка: Попытка изменения файла за пределами проекта.';

  @override
  String get commandRefPathOutsideWorkspace =>
      'Ошибка безопасности: Команда ссылается на путь вне проекта.';

  @override
  String commandBlockedUnsafe(String blocked) {
    return 'Ошибка безопасности: Команда содержит заблокированную инструкцию \"$blocked\".';
  }

  @override
  String aiSearchNoMatches(String query) {
    return 'Совпадений для \"$query\" не найдено.';
  }

  @override
  String aiSearchMatchesFound(int matchCount, String query, String results) {
    return 'Найдено $matchCount совпадений для \"$query\":\n\n$results';
  }

  @override
  String searchSymbolsNoMatches(String query) {
    return 'Символов по запросу \"$query\" не найдено.';
  }

  @override
  String searchSymbolsMatchesFound(int count, String query, String results) {
    return 'Найдено $count символов по запросу \"$query\":\n\n$results';
  }

  @override
  String searchSymbolsItem(String type, String name, String path, int line) {
    return '- [$type] $name (файл: $path, строка: $line)';
  }

  @override
  String directoryNotFound(String path) {
    return 'Директория не найдена: $path';
  }

  @override
  String get directoryEmpty => 'Диретория пуста.';

  @override
  String directoryContentsHeader(String items) {
    return 'Содержимое директории:\n\n$items';
  }

  @override
  String get mcpMissingParams =>
      'Ошибка: Имя сервера или инструмента MCP не указано.';

  @override
  String unknownAction(String type) {
    return 'Неизвестный тип действия: $type';
  }

  @override
  String failedToApplyActionWithError(String error) {
    return 'Не удалось применить действие: $error';
  }

  @override
  String get searchQueryEmpty => 'Ошибка: Запрос для поиска пуст.';

  @override
  String get workspaceNotFound => 'Ошибка: Рабочая область не найдена.';

  @override
  String get webPreviewStopped => 'Веб-превью остановлено';

  @override
  String get webPreviewStartInstructions =>
      'Запустите сервер и нажмите кнопку Play.';
}
