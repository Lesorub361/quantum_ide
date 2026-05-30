// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'QuantumIDE';

  @override
  String get explorer => 'Explorador';

  @override
  String get newFile => 'New File';

  @override
  String get newFolder => 'New Folder';

  @override
  String get refresh => 'Actualizar';

  @override
  String get rename => 'Renombrar';

  @override
  String get delete => 'Eliminar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get create => 'Crear';

  @override
  String get projectNotOpened => 'Proyecto no abierto';

  @override
  String get selectFileToStart =>
      'Selecciona un archivo en el explorador para empezar a trabajar';

  @override
  String get openExplorer => 'Abrir Explorador';

  @override
  String get confirmDelete => 'Confirmar eliminación';

  @override
  String areYouSureDelete(String name) {
    return 'Are you sure you want to delete $name?';
  }

  @override
  String get terminal => 'Terminal';

  @override
  String get run => 'Ejecutar';

  @override
  String get build => 'Compilar';

  @override
  String get aiAgent => 'Agente IA';

  @override
  String get servers => 'Servidores';

  @override
  String get buildLogs => 'Registros de compilación';

  @override
  String get appLogs => 'App Logs';

  @override
  String get copy => 'Copy';

  @override
  String get stop => 'Stop';

  @override
  String get hotReload => 'Hot Reload';

  @override
  String get clear => 'Clear';

  @override
  String get runProject => 'Run Project';

  @override
  String get pubGet => 'Pub Get';

  @override
  String get setupSdk => 'Setup SDK';

  @override
  String get clean => 'Clean';

  @override
  String get buildApk => 'Build APK';

  @override
  String get welcomeMessage => 'Welcome to your premium environment.';

  @override
  String get typeRunToStart => 'Type run to start your project.';

  @override
  String get settings => 'Ajustes';

  @override
  String get interfaceAndLocalization => 'Interfaz y localización';

  @override
  String get language => 'Idioma';

  @override
  String get theme => 'Tema';

  @override
  String get darkTheme => 'Tema oscuro';

  @override
  String get lightTheme => 'Tema claro';

  @override
  String get colorPalette => 'Paleta de colores';

  @override
  String get customColor => 'Custom Color';

  @override
  String get accentColor => 'Color de acento';

  @override
  String get projectIcon => 'Project Icon';

  @override
  String get defaultAccent => 'Default';

  @override
  String get codeEditor => 'Editor de código';

  @override
  String get editorFontSize => 'Tamaño de fuente del editor';

  @override
  String get autoCompletion => 'Autocompletado';

  @override
  String get showCodeHints => 'Show code hints';

  @override
  String get aiAutoCompletion => 'AI Auto-completion';

  @override
  String get geminiCodeGeneration => 'Gemini code generation';

  @override
  String get wordWrap => 'Ajuste de línea';

  @override
  String get wordWrapDescription => 'Soft wrap lines in editor';

  @override
  String get lineNumbers => 'Números de línea';

  @override
  String get showLineNumbers => 'Show line numbers';

  @override
  String get minimap => 'Minimapa';

  @override
  String get showMinimap => 'Show editor minimap';

  @override
  String get autoSave => 'Guardado automático';

  @override
  String get autoSaveDescription => 'Save changes after 2s';

  @override
  String get terminalFontSize => 'Tamaño de fuente de terminal';

  @override
  String get terminalTheme => 'Tema de terminal';

  @override
  String get toolsAndAi => 'Herramientas e IA';

  @override
  String get aiProviders => 'Proveedores de IA';

  @override
  String get aiProvidersSubtitle => 'Gemini, OpenAI, Ollama etc.';

  @override
  String get ubuntuPackages => 'Paquetes Ubuntu';

  @override
  String get manageCliTools => 'Manage CLI tools';

  @override
  String get hosts => 'Hosts';

  @override
  String get localRemoteHosts => 'Local/remote hosts';

  @override
  String get system => 'System';

  @override
  String get showHiddenFiles => 'Show Hidden Files';

  @override
  String get showHiddenFilesDescription => 'Show .* files';

  @override
  String get vibration => 'Vibration';

  @override
  String get hapticFeedback => 'Haptic feedback';

  @override
  String get aboutApp => 'Acerca de la aplicación';

  @override
  String get aboutAppSubtitle => 'Quantum IDE v1.0.0';

  @override
  String get selectPalette => 'Select Palette';

  @override
  String get close => 'Close';

  @override
  String get resetToDefault => 'Restablecer valores predeterminados';

  @override
  String get aboutDialogContent =>
      'AI-powered mobile IDE built with Flutter.\n© 2026 Quantum IDE';

  @override
  String get ubuntuDarkPurple => 'Ubuntu Dark Purple';

  @override
  String get pureDark => 'Pure Dark';

  @override
  String get searchProjects => 'Search projects...';

  @override
  String get open => 'Open';

  @override
  String get market => 'Market';

  @override
  String projectsHeader(int count) {
    return 'Projects ($count)';
  }

  @override
  String get noProjects => 'Sin proyectos';

  @override
  String get nothingFound => 'Nothing found';

  @override
  String get createFirstProject => 'Crear primer proyecto';

  @override
  String get projectActions => 'Project Actions';

  @override
  String get fixAndroidBuild => 'Fix Android Build (AGP + compileSdk)';

  @override
  String get patchAndroidBuildDescription =>
      'Patch android-36 / AGP 8.7.3 / compileSdk 35';

  @override
  String get buildApkDescription => 'flutter build apk --debug';

  @override
  String apkBuildFixed(String name) {
    return '✅ Android build files fixed for \"$name\"';
  }

  @override
  String confirmDeleteTitle(String name) {
    return 'Confirm Delete';
  }

  @override
  String get confirmDeleteMessage =>
      'Delete only from the list or delete files as well?';

  @override
  String get deleteFromListOnly => 'From list';

  @override
  String get deleteFromDisk => 'From disk';

  @override
  String get projectSettings => 'Ajustes del proyecto';

  @override
  String get createProject => 'Crear proyecto';

  @override
  String get projectName => 'Nombre del proyecto';

  @override
  String get projectType => 'TIPO DE PROYECTO';

  @override
  String get androidCompileSdkVersion => 'ANDROID compileSdk VERSION';

  @override
  String get defaultSdkVersion => 'Default: 35';

  @override
  String get targetPlatforms => 'TARGET DEVICES / PLATFORMS';

  @override
  String get saveAction => 'Guardar';

  @override
  String get code => 'Código';

  @override
  String get preview => 'Previsualización';

  @override
  String get fastCommands => 'QUICK COMMANDS';

  @override
  String get serverAddress => 'Server Address';

  @override
  String copied(String value) {
    return 'Copied: $value';
  }

  @override
  String get stopServer => 'Stop';

  @override
  String get command => 'COMMAND';

  @override
  String get serverStarted => 'Server Started';

  @override
  String get openAddressInBrowser => 'Open this address in Android browser';

  @override
  String get copyUrl => 'Copy URL';

  @override
  String get openProjectToSeeCommands => 'Open a project to see run commands';

  @override
  String get running => 'Running...';

  @override
  String get chat => 'Chat';

  @override
  String get agents => 'Agents';

  @override
  String askAiHint(String provider) {
    return 'Ask $provider...';
  }

  @override
  String get selectModel => 'Select Model';

  @override
  String get clearHistory => 'Clear History';

  @override
  String get askAboutCode => 'Ask about the code';

  @override
  String get you => 'You';

  @override
  String workingOnFile(String file, String code, String question) {
    return 'I\'m working on the file: $file. \nHere is its content:\n```\n$code\n```\n\nMy question: $question';
  }

  @override
  String get aiAskDialogTitle => 'AI Agent Query';

  @override
  String aiAskFolder(String name) {
    return 'Folder: $name';
  }

  @override
  String aiAskFile(String name) {
    return 'File: $name';
  }

  @override
  String get aiAskFolderHint =>
      'Describe the task (e.g. \"create a controller\", \"add a data model\"...)';

  @override
  String get aiAskFileHint =>
      'What needs to be done? (e.g. \"add email validation\", \"optimize method\"...)';

  @override
  String get decline => 'Decline';

  @override
  String get apply => 'Apply';

  @override
  String get showChanges => 'Show changes';

  @override
  String changesInFile(String name) {
    return 'Changes in $name';
  }

  @override
  String get noFilesFound => 'No files found';

  @override
  String get retry => 'Retry';

  @override
  String errorOccurred(String error) {
    return 'Error: $error';
  }

  @override
  String get aiProvidersInfo =>
      'Add API keys for different AI providers. Local models (Ollama/LM Studio) do not require a key.';

  @override
  String get activeProvider => 'Active Provider';

  @override
  String get requiresApiKeyLabel => 'Requires API Key';

  @override
  String get localNoKey => 'Local — no key';

  @override
  String get activeCaps => 'ACTIVO';

  @override
  String get apiKeyLabel => 'API Key';

  @override
  String get keySaved => 'API key saved';

  @override
  String get urlSaved => 'URL saved';

  @override
  String get serverUrlLabel => 'Server URL';

  @override
  String get ollamaPhoneHint =>
      '💡 To connect from a phone, use your computer\'s IP (e.g. http://192.168.1.10:11434)';

  @override
  String get modelLabel => 'MODEL';

  @override
  String get searching => 'Searching...';

  @override
  String get findModels => 'Find Models';

  @override
  String get searchModelHint => 'Search by model name...';

  @override
  String get customModelHint => 'Or enter model name manually...';

  @override
  String modelInstalled(String name) {
    return 'Model set to $name';
  }

  @override
  String get modelsNotFound => 'No models found. Click \"Find Models\".';

  @override
  String get available => 'Available';

  @override
  String get quotaLimit => 'Quota limit / high load';

  @override
  String get unavailable => 'Unavailable';

  @override
  String get availableCaps => 'AVAILABLE';

  @override
  String get activateProvider => 'Activate Provider';

  @override
  String providerActivated(String name) {
    return '$name activated';
  }

  @override
  String get send => 'Enviar';

  @override
  String get acceptAll => 'Accept all';

  @override
  String get rejectAll => 'Reject all';

  @override
  String get projectAnalysis => 'Project Analysis';

  @override
  String problemsFound(int count, int errors, int warnings) {
    return 'Problems found: $count ($errors errors, $warnings warnings)';
  }

  @override
  String get fixWithAi => 'Fix with AI';

  @override
  String runningCommand(String command) {
    return 'Running command: $command...';
  }

  @override
  String applyingChange(String path) {
    return 'Applying change: $path...';
  }

  @override
  String fileSuccessfullyWritten(String path) {
    return 'File $path successfully written.';
  }

  @override
  String fileSuccessfullyDeleted(String path) {
    return 'File $path successfully deleted.';
  }

  @override
  String commandExecutedResult(String command, String result) {
    return 'Command \"$command\" executed. Result:\n$result';
  }

  @override
  String commandSentToTerminal(String command) {
    return 'Command \"$command\" sent to terminal.';
  }

  @override
  String unknownActionType(String type) {
    return 'Unknown action type: $type';
  }

  @override
  String failedToApplyAction(String error) {
    return 'Failed to apply action: $error';
  }

  @override
  String get noErrorsFound => 'No errors found';

  @override
  String get noErrorsDescription =>
      'Code analyzer checked your project. No issues or warnings found.';

  @override
  String get closeProject => 'Close Project';

  @override
  String get closeProjectConfirm =>
      'Are you sure you want to close this project?';

  @override
  String get sortByName => 'By Name';

  @override
  String get sortBySize => 'By Size';

  @override
  String get sortByDate => 'By Date';

  @override
  String get goToDefinition => 'Go to Definition';

  @override
  String get documentation => 'Documentation';

  @override
  String get usages => 'Usages';

  @override
  String get cut => 'Cut';

  @override
  String get paste => 'Paste';

  @override
  String get selectAll => 'Select All';

  @override
  String get line => 'Line';

  @override
  String get column => 'Column';

  @override
  String get info => 'Info';

  @override
  String get ok => 'OK';

  @override
  String get problems => 'Problemas';

  @override
  String get packages => 'Paquetes';

  @override
  String get tools => 'Herramientas';

  @override
  String get searchFiles => 'Buscar archivos...';

  @override
  String get imageLoadError => 'Error loading image';

  @override
  String get unsaved => 'Sin guardar';

  @override
  String get saved => 'Guardado';

  @override
  String lineCol(int line, int col) {
    return 'Ln $line, Col $col';
  }

  @override
  String get noOpenFiles => 'No open files in editor';

  @override
  String get fileNotFoundOnDisk => 'File not found on disk';

  @override
  String parsingError(String error) {
    return 'Parsing error: $error';
  }

  @override
  String get outlineEmptyOrUnsupported => 'Outline empty or unsupported';

  @override
  String outlineHeader(String filename) {
    return 'Structure: $filename';
  }

  @override
  String get projectFolderNotFound => 'Project folder not found';

  @override
  String get rootFiles => '[Files in root]';

  @override
  String scanningError(String error) {
    return 'Scanning error: $error';
  }

  @override
  String get deleteFileConfirmTitle => 'Delete File';

  @override
  String deleteFileConfirmMessage(String name, String size) {
    return 'Are you sure you want to permanently delete file:\n\n$name\nSize: $size?';
  }

  @override
  String get fileDeletedSuccess => 'File deleted successfully';

  @override
  String deleteFileError(String error) {
    return 'Delete error: $error';
  }

  @override
  String get diskSpaceAnalysis => 'Disk space analysis...';

  @override
  String get projectFolderEmpty => 'Project folder empty';

  @override
  String get projectSize => 'Project size:';

  @override
  String get folderDistribution => 'Folder Distribution';

  @override
  String get topHeavyFiles => 'Top 10 Heavy Files';

  @override
  String get noHeavyFiles => 'No heavy files';

  @override
  String get searchPlaceholder => 'Search contents...';

  @override
  String get searchCaseSensitive => 'Case sensitive';

  @override
  String get searchWholeWord => 'Whole word';

  @override
  String get searchRegex => 'Regular expression';

  @override
  String get searchInvalidRegex => 'Invalid regular expression';

  @override
  String get searchNoMatches => 'No matches found';

  @override
  String searchMatchesFound(int matches, int files) {
    return 'Found $matches matches in $files files';
  }

  @override
  String searchError(String error) {
    return 'Search error: $error';
  }

  @override
  String get searchingInProgress => 'Searching...';

  @override
  String get searchPrompt => 'Enter query to search';

  @override
  String get apkSigner => 'APK Signer';

  @override
  String get createKeystore => 'Create Keystore';

  @override
  String get stepSelectApk => 'Step 1: Select APK to sign';

  @override
  String get selectApk => 'Select APK';

  @override
  String get selectCustomPath => 'Specify custom path...';

  @override
  String get apkPathHint => 'Full path to APK file on device';

  @override
  String get stepSelectKeystore => 'Step 2: Select Keystore';

  @override
  String get selectKeystore => 'Select Keystore';

  @override
  String get keystorePathHint => 'Full path to .jks/.keystore file';

  @override
  String get stepSignSettings => 'Step 3: Signing settings';

  @override
  String get keystorePassword => 'Keystore password';

  @override
  String get keyAlias => 'Key Alias';

  @override
  String get keyAliasPassword => 'Key Alias password';

  @override
  String get outputApkName => 'Output APK filename';

  @override
  String get signApkButton => 'Sign APK';

  @override
  String get install => 'Install';

  @override
  String get refreshProjectFiles => 'Refresh project files list';

  @override
  String get newKeystoreParams => 'New Keystore parameters';

  @override
  String get keystoreFilenameHint => 'Filename (e.g. release.jks)';

  @override
  String get storePasswordHint => 'Keystore password (min 6 chars)';

  @override
  String get keyAliasHint => 'Key alias (e.g. key)';

  @override
  String get developerInfoDn => 'Developer Info (DN)';

  @override
  String get devNameCn => 'First and last name (CN)';

  @override
  String get devUnitOu => 'Organizational Unit (OU)';

  @override
  String get devOrgO => 'Organization (O)';

  @override
  String get devCityL => 'City or Locality (L)';

  @override
  String get devStateS => 'State or Province (S)';

  @override
  String get devCountryC => 'Country Code (C)';

  @override
  String get genKeystoreButton => 'Generate Keystore';

  @override
  String get logSignGen => 'SIGNING & GENERATION LOG';

  @override
  String get clearLog => 'Clear Log';

  @override
  String get logPlaceholder =>
      'Signing and generation log will be displayed here.';

  @override
  String signProjectScanError(String error) {
    return 'Project scan error: $error';
  }

  @override
  String signKeystoreSelected(String path) {
    return 'Keystore selected: $path';
  }

  @override
  String signFilePickError(String error) {
    return 'File pick error: $error';
  }

  @override
  String get signNoOpenProject => 'No open project';

  @override
  String get signNoApkSelected => 'No APK selected';

  @override
  String get signNoKeystoreSelected => 'No Keystore selected';

  @override
  String get signFillAllFields => 'Fill all signing fields';

  @override
  String signApkProgress(String apk) {
    return 'Signing APK: $apk...';
  }

  @override
  String signKeyFile(String key, String alias) {
    return 'Key file: $key (alias: $alias)';
  }

  @override
  String get signRunningApksigner => 'Running apksigner...';

  @override
  String get signVerifying => 'Verifying signature...';

  @override
  String get signSuccess => 'APK signed and verified successfully!';

  @override
  String get signVerifyFailed =>
      'Signature verification failed or error occurred.';

  @override
  String signError(String error) {
    return 'Error signing APK: $error';
  }

  @override
  String get genKeystoreFillFields => 'Fill key generation fields';

  @override
  String genKeystoreProgress(String name) {
    return 'Generating Keystore: $name...';
  }

  @override
  String genKeystoreSuccess(String name) {
    return 'Keystore created successfully at: $name';
  }

  @override
  String get genKeystoreFailed => 'Failed to create Keystore.';

  @override
  String genKeystoreError(String error) {
    return 'Error generating Keystore: $error';
  }

  @override
  String installApkProgress(String apk) {
    return 'Starting APK installation: $apk';
  }

  @override
  String installApkResult(String msg) {
    return 'Installation result: $msg';
  }

  @override
  String installApkNotFound(String path) {
    return 'APK file not found: $path';
  }

  @override
  String installApkError(String error) {
    return 'Installation error: $error';
  }

  @override
  String get glassmorphismEffects => 'Efectos de vidrio (Glassmorphism)';

  @override
  String get glassOpacity => 'Opacidad del vidrio';

  @override
  String get backdropBlur => 'Desenfoque de fondo';

  @override
  String get editorFontFamily => 'Fuente del editor';

  @override
  String get fontLigatures => 'Ligaduras tipográficas';

  @override
  String get fontLigaturesDescription =>
      'Habilitar ligaduras tipográficas en el código';

  @override
  String get selectFontFamily => 'Seleccionar fuente';

  @override
  String get selectLanguage => 'Seleccionar idioma';

  @override
  String get format => 'Formatear';

  @override
  String get liveShare => 'Desarrollo Colaborativo';

  @override
  String get hostSession => 'Crear Sesión';

  @override
  String get joinSession => 'Unirse a la Sesión';

  @override
  String get stopSession => 'Detener Sesión';

  @override
  String get disconnectSession => 'Desconectar';

  @override
  String get sessionActive => 'Sesión Activa';

  @override
  String get hostingAt => 'Hospedado en:';

  @override
  String get connectedTo => 'Conectado a:';

  @override
  String get userName => 'Tu Nombre';

  @override
  String get usersList => 'Participantes';

  @override
  String get messagePlaceholder => 'Escribe un mensaje...';

  @override
  String get connectError => 'Error de conexión';

  @override
  String get invalidAddress => 'Dirección no válida';

  @override
  String get joinLink => 'Dirección IP de la sesión';

  @override
  String get localIps => 'IPs Locales:';

  @override
  String get wasmPlugins => 'Complementos WASM';

  @override
  String get installPlugin => 'Instalar complemento (.wasm)';

  @override
  String get noPluginsInstalled => 'No hay complementos WASM instalados';

  @override
  String get pluginEnabled => 'Complemento habilitado';

  @override
  String get pluginDisabled => 'Complemento deshabilitado';

  @override
  String get runWasmAction => 'Ejecutar acción WASM';

  @override
  String get noActiveSelection =>
      '¿No hay selección de texto. Aplicar a todo el archivo?';

  @override
  String get applyToSelection => 'Aplicar a la selección';

  @override
  String get applyToDocument => 'Aplicar al documento';

  @override
  String get logs => 'Registros';

  @override
  String get clearLogs => 'Limpiar registros';

  @override
  String get deletePlugin => 'Eliminar complemento';

  @override
  String get resetToDefaults => 'Restablecer';

  @override
  String get welcomeTitle => '¡Bienvenido!';

  @override
  String get welcomeSubtitle =>
      'Elija un proyecto para trabajar o cree uno nuevo';

  @override
  String get lastActiveProject => 'Último proyecto activo';

  @override
  String get runTooltip => 'Ejecutar';

  @override
  String get actionsTooltip => 'Acciones';

  @override
  String get packagesTooltip => 'Paquetes';

  @override
  String get extensionsAndTools => 'Extensiones y Herramientas';

  @override
  String get searchExtensionsHint => 'Buscar extensiones...';

  @override
  String get searchPubdevHint =>
      'Buscar librerías en pub.dev (por ejemplo, dio)...';

  @override
  String get tabAll => 'Todo';

  @override
  String get tabInstalled => 'Instalado';

  @override
  String get tabLanguagesAndAi => 'Idiomas e IA';

  @override
  String get tabTools => 'Herramientas';

  @override
  String get tabBuild => 'Compilar';

  @override
  String get tabSdkPlatforms => 'Plataformas SDK';

  @override
  String get tabPubLibraries => 'Librerías Pub';

  @override
  String get readyToBuildApk => '¿Listo para compilar el APK?';

  @override
  String get installAndroidSdkJava => 'Instalar Android SDK y Java 17';

  @override
  String get sdkSetupDescription =>
      'Esto configurará el SDK, compiladores, zipalign, apksigner, optimizará la configuración de red de Gradle y preparará su entorno para compilar proyectos.';

  @override
  String get initializingDevEnvironment =>
      'Inicializando el entorno de desarrollo...';

  @override
  String get viewAction => 'Ver';

  @override
  String get startSdkSetup => 'Iniciar configuración del entorno';

  @override
  String get buildIssues => '¿Problemas de compilación?';

  @override
  String get restoreAndroidGradleEnv => 'Restaurar entorno Android y Gradle';

  @override
  String get wrenchFixDescription =>
      'Corrige automáticamente los errores del demonio AAPT2, establece los permisos correctos del proyecto, restaura el binario del compilador de recursos y configura los hilos de Gradle.';

  @override
  String get runningWrenchFix =>
      'Ejecutando corrección del entorno de compilación...';

  @override
  String get startWrenchFix => 'Ejecutar corrección (Wrench Fix)';

  @override
  String get statusInstalledCaps => 'INSTALADO';

  @override
  String get reinstallOrUpdateTooltip => 'Reinstalar / Actualizar';

  @override
  String updatingPackage(String name) {
    return 'Actualizando $name...';
  }

  @override
  String installingPackage(String name) {
    return 'Instalando $name...';
  }

  @override
  String get installAction => 'Instalar';

  @override
  String get searchPubdevTitle => 'Buscar librerías Flutter';

  @override
  String get searchPubdevDescription =>
      'Ingrese el nombre de la librería (por ejemplo: dio, bloc, riverpod) en la búsqueda de arriba y presione Enter';

  @override
  String loadError(String error) {
    return 'Error de carga: $error';
  }

  @override
  String get addAction => 'Añadir';

  @override
  String get openProjectToInstallLibraries =>
      'Abra un proyecto primero para añadir librerías.';

  @override
  String installingLibrary(String name) {
    return 'Instalando librería $name...';
  }

  @override
  String importError(String error) {
    return 'Error de importación: $error';
  }

  @override
  String get filesImportedSuccessfully => 'Archivos importados con éxito';

  @override
  String get dragFilesHereToImport => 'Arrastre archivos aquí para importar';

  @override
  String selectedCount(int count) {
    return 'Seleccionado: $count';
  }

  @override
  String get selectAllTooltip => 'Seleccionar todo';

  @override
  String get copyTooltip => 'Copiar';

  @override
  String copiedCount(int count) {
    return 'Objetos copiados: $count';
  }

  @override
  String get cutTooltip => 'Cortar';

  @override
  String cutCount(int count) {
    return 'Objetos cortados: $count';
  }

  @override
  String get zipTooltip => 'Comprimir en ZIP';

  @override
  String get deleteTooltip => 'Eliminar';

  @override
  String foldersCount(int count) {
    return 'Carpetas: $count';
  }

  @override
  String get askAiAction => 'Preguntar a IA';

  @override
  String get explainAiAction => 'IA: Explicar';

  @override
  String get documentAiAction => 'IA: Documentar';

  @override
  String get testAiAction => 'IA: Generar pruebas';

  @override
  String get optimizeAiAction => 'IA: Optimizar';

  @override
  String pasteCount(int count) {
    return 'Pegar ($count)';
  }

  @override
  String get archiveNameHint => 'Nombre del archivo';

  @override
  String get compressAction => 'Comprimir';

  @override
  String get archiveCreatedSuccessfully => '¡Archivo creado con éxito!';

  @override
  String compressionError(String error) {
    return 'Error de compresión: $error';
  }

  @override
  String get archiveExtractedSuccessfully =>
      '¡Archivo descomprimido con éxito!';

  @override
  String extractionError(String error) {
    return 'Error de descompresión: $error';
  }

  @override
  String get deleteSelectedTitle => '¿Eliminar seleccionado?';

  @override
  String deleteSelectedConfirmation(int count) {
    return '¿Está seguro de que desea eliminar $count elementos?';
  }

  @override
  String get selectedElementsDeleted => '¡Elementos seleccionados eliminados!';

  @override
  String deleteError(String error) {
    return 'Error al eliminar: $error';
  }

  @override
  String get filesPastedSuccessfully => '¡Archivos pegados con éxito!';

  @override
  String pasteError(String error) {
    return 'Error al pegar: $error';
  }

  @override
  String get repositoryNotFound => 'Repositorio no encontrado';

  @override
  String get initGitRepoDescription =>
      'Inicialice un repositorio Git local para rastrear cambios.';

  @override
  String get initGitAction => 'Inicializar Git';

  @override
  String get gitConflicted => 'CONFLICTOS';

  @override
  String get gitStaged => 'PREPARADO';

  @override
  String get gitModified => 'MODIFICADO';

  @override
  String get gitUntracked => 'SIN SEGUIMIENTO';

  @override
  String get commitMessageHint => 'Mensaje de commit...';

  @override
  String get resetChangesTitle => '¿Restablecer cambios?';

  @override
  String get resetChangesConfirmation =>
      '¿Está seguro de que desea restablecer permanentemente todos los cambios no confirmados en este archivo?';

  @override
  String get resetAction => 'Restablecer';

  @override
  String get changesReset => 'Cambios restablecidos';

  @override
  String resetError(String error) {
    return 'Error al restablecer: $error';
  }

  @override
  String get normalView => 'Vista normal';

  @override
  String get splitView => 'Vista dividida (Side-by-Side)';

  @override
  String get stagedMessage => 'Archivo preparado';

  @override
  String get unstagedMessage => 'Archivo quitado de preparación';

  @override
  String stageError(String error) {
    return 'Error de preparación: $error';
  }

  @override
  String get failedToLoadChanges => 'Error al cargar los cambios';

  @override
  String get noChanges => 'Sin cambios';

  @override
  String get fileIdenticalToHead => 'Este archivo es idéntico a HEAD';

  @override
  String get runTerminalTooltip => 'Ejecutar';

  @override
  String get restartTerminalTooltip => 'Reiniciar';

  @override
  String get consoleSubTab => 'Consola';

  @override
  String get signApkSubTab => 'Firmar APK';

  @override
  String get copiedToClipboard => 'Copiado al portapapeles';

  @override
  String get back => 'Atrás';

  @override
  String get tryChangingSearchQuery =>
      'Intente cambiar la consulta de búsqueda';

  @override
  String get incomingBranch => 'Rama entrante';

  @override
  String get resolveConflictsBeforeSaving =>
      '¡Por favor, resuelva todos los conflictos antes de guardar!';

  @override
  String get fileSavedAndStaged =>
      '¡Archivo guardado con éxito y preparado en el índice de Git!';

  @override
  String saveError(String error) {
    return 'Error al guardar: $error';
  }

  @override
  String get acceptMerge => 'Aceptar fusión';

  @override
  String get errorLoadingConflictFile =>
      'Error al cargar el archivo de conflicto';

  @override
  String get conflictsNotFound => 'No se encontraron conflictos';

  @override
  String get noConflictMarkersFound =>
      'No se encontraron marcadores de conflicto de Git estándar en este archivo.';

  @override
  String get backToGit => 'Volver a Git';

  @override
  String get conflictBlock => 'Bloque de conflicto';

  @override
  String get currentChangesOurs => 'Cambios actuales (Ours / HEAD)';

  @override
  String incomingChanges(String branch) {
    return 'Cambios entrantes ($branch)';
  }

  @override
  String get useThisVersion => 'Usar esta versión';

  @override
  String get mergeResultEditable => 'Resultado de la fusión (Editable)';

  @override
  String get chooseVersionOrWriteHint =>
      'Elija una de las versiones anteriores o escriba su propia resolución de fusión...';

  @override
  String get markAsResolvedHint =>
      '* Para marcar este bloque como resuelto, ingrese o elija texto.';

  @override
  String get emptyLabel => '(Vacío)';

  @override
  String get stageAction => 'Preparar';

  @override
  String get unstageAction => 'Despreparar';

  @override
  String get cursorColor => 'COLOR DEL CURSOR';

  @override
  String get or => 'O';

  @override
  String get ipCopiedToClipboard => 'IP copiada al portapapeles';

  @override
  String editingFile(String file) {
    return 'Editando: $file';
  }

  @override
  String get viewingProject => 'Viendo el proyecto';

  @override
  String get noProblemsFound =>
      'No se encontraron problemas en el espacio de trabajo';

  @override
  String get problemsList => 'Lista de problemas';

  @override
  String get sendToAi => 'Enviar a la IA';

  @override
  String get helpMeFixErrors =>
      'Por favor, ayúdame a corregir los siguientes errores de compilación en mi proyecto:';

  @override
  String lineColumn(int line, int col) {
    return 'Línea $line, Columna $col';
  }

  @override
  String get decreaseFontSize => 'Disminuir tamaño de fuente';

  @override
  String get increaseFontSize => 'Aumentar tamaño de fuente';

  @override
  String get undo => 'Deshacer';

  @override
  String get redo => 'Rehacer';

  @override
  String get moveLeft => 'Mover a la izquierda';

  @override
  String get moveUp => 'Mover arriba';

  @override
  String get moveDown => 'Mover abajo';

  @override
  String get moveRight => 'Mover a la derecha';

  @override
  String get edit => 'Editar';

  @override
  String get packagesAndEnv => 'Paquetes y entorno';

  @override
  String packagesInstalledCount(int count, int total) {
    return 'Instalados: $count/$total';
  }

  @override
  String get flutterProject => 'Proyecto Flutter';

  @override
  String get pythonProject => 'Proyecto Python';

  @override
  String get nodejsProject => 'Proyecto Node.js';

  @override
  String get dartProject => 'Proyecto Dart';

  @override
  String get webProject => 'Proyecto Web';

  @override
  String get androidProject => 'Proyecto Android';

  @override
  String get genericProject => 'Proyecto';

  @override
  String get runPC => 'Ejecutar (PC)';

  @override
  String get runMob => 'Ejecutar (Móvil)';

  @override
  String get startServer => 'Iniciar Servidor';

  @override
  String get buildAPK => 'Compilar APK';

  @override
  String get startTheProject => 'Iniciar el proyecto';

  @override
  String get outputCopied => 'Salida copiada';

  @override
  String get console => 'Consola';

  @override
  String get signApk => 'Firmar APK';

  @override
  String get buildPC => 'Compilar (PC)';

  @override
  String get resetPlugins => 'Restablecer complementos';

  @override
  String get resetPluginsConfirmation =>
      'Esto eliminará todos los complementos personalizados instalados y restaurará los predeterminados. ¿Continuar?';

  @override
  String get resetPluginsTitle => '¿Restablecer complementos?';

  @override
  String get installWasm => 'Instalar .wasm';

  @override
  String get availableActions => 'Acciones disponibles:';

  @override
  String get logsTerminal => 'Terminal de registros';

  @override
  String get noLogsCaptured => 'Aún no se han capturado registros';

  @override
  String get installWasmPluginTitle => 'Instalar complemento WASM';

  @override
  String get selectWasmFile => 'Seleccionar archivo .wasm';

  @override
  String get pluginName => 'Nombre del complemento';

  @override
  String get nameRequired => 'El nombre es obligatorio';

  @override
  String get pluginDescription => 'Descripción';

  @override
  String get descriptionRequired => 'La descripción es obligatoria';

  @override
  String get exposedActions => 'Acciones expuestas';

  @override
  String get add => 'Añadir';

  @override
  String get pickWasmFileFirst => 'Por favor, elija un archivo .wasm primero';

  @override
  String get pluginInstalledSuccessfully => 'Complemento instalado con éxito';

  @override
  String failedToInstall(String error) {
    return 'Error al instalar: $error';
  }

  @override
  String get mcpServersTitle => 'AI Modules: MCP Servers';

  @override
  String activeServers(int count) {
    return 'Active Servers ($count)';
  }

  @override
  String get repository => 'Repository';

  @override
  String get noMcpServers => 'No MCP servers added';

  @override
  String get goToRepository => 'Go to Repository';

  @override
  String get addManually => 'Add Manually';

  @override
  String get addServerManually => 'Add Server Manually';

  @override
  String get installed => 'INSTALLED';

  @override
  String packageDetail(String detail) {
    return 'Package: $detail';
  }

  @override
  String authParam(String key) {
    return 'Auth parameter: $key';
  }

  @override
  String enterValueFor(String key) {
    return 'Enter value for $key';
  }

  @override
  String enterLabel(String label) {
    return 'Enter $label';
  }

  @override
  String installPreset(String name) {
    return 'Install: $name';
  }

  @override
  String get serverName => 'Server Name';

  @override
  String get exampleLocalSearch => 'For example: local-search';

  @override
  String get connectionType => 'Connection Type';

  @override
  String get stdioLocal => 'Stdio (Local process)';

  @override
  String get sseHttp => 'SSE (HTTP stream)';

  @override
  String get startCommand => 'Start Command';

  @override
  String get exampleStartCommand => 'For example: node or npx or python3';

  @override
  String get argsSpace => 'Arguments (separated by space)';

  @override
  String get searchFilesHint => 'Search files... (type \"#\" for symbols)';

  @override
  String get searchSymbolsHint => 'Search symbols in code...';

  @override
  String get modeFiles => 'MODE: FILES';

  @override
  String get modeSymbols => 'MODE: SYMBOLS';

  @override
  String resultsCount(int count) {
    return 'Results: $count';
  }

  @override
  String get noResults => 'No results found';

  @override
  String confirmDeleteMultiple(int count) {
    return 'Are you sure you want to delete $count items?';
  }

  @override
  String get archiveExtracted => 'Archive successfully extracted!';

  @override
  String get archiveCreated => 'Archive successfully created!';

  @override
  String get compressToZip => 'Compress to ZIP';

  @override
  String folderLabel(String name) {
    return 'Folder: $name';
  }

  @override
  String fileLabel(String name) {
    return 'File: $name';
  }

  @override
  String get whatShouldAiDoFolder => 'What should AI do with this folder?';

  @override
  String get whatShouldAiDoFile => 'What should AI do with this file?';

  @override
  String get askAi => 'Ask AI';

  @override
  String get askAiDesc => 'Interactive chat with AI assistant';

  @override
  String get explainStructure => 'AI: Explain Structure';

  @override
  String get explainStructureDesc => 'Detailed summary of code or folders';

  @override
  String get addDoc => 'AI: Add Documentation';

  @override
  String get addDocDesc => 'Generate docstrings and comments';

  @override
  String get generateTests => 'AI: Generate Tests';

  @override
  String get generateTestsDesc => 'Write unit tests for the code';

  @override
  String get optimizeCode => 'AI: Optimize';

  @override
  String get optimizeCodeDesc => 'Suggest performance improvements';

  @override
  String get newFileDesc => 'Create a file in this folder';

  @override
  String get newFolderDesc => 'Create a subfolder';

  @override
  String get removeFromBookmarks => 'Remove from Bookmarks';

  @override
  String get removeFromBookmarksDesc => 'Remove file from quick access';

  @override
  String get addToBookmarks => 'Add to Bookmarks';

  @override
  String get addToBookmarksDesc => 'Pin file for quick access';

  @override
  String get copyDesc => 'Add to clipboard';

  @override
  String get cutDesc => 'Move files';

  @override
  String get pasteDesc => 'Paste copied items';

  @override
  String get renameDesc => 'Change item name';

  @override
  String get extractZip => 'Extract ZIP';

  @override
  String get extractZipDesc => 'Extract files from archive';

  @override
  String get compressZip => 'Compress to ZIP';

  @override
  String get compressZipDesc => 'Create ZIP archive';

  @override
  String get compressSelectedZip => 'Compress selected to ZIP';

  @override
  String get compressSelectedZipDesc => 'Create archive from selected items';

  @override
  String get deleteDesc => 'Permanent delete';

  @override
  String get empty => 'empty';

  @override
  String get nameFolderHint => 'folder_name';

  @override
  String get nameFileHint => 'file_name.txt';

  @override
  String get itemMoved => 'Item successfully moved';

  @override
  String moveError(String error) {
    return 'Move error: $error';
  }

  @override
  String get image => 'IMAGE';

  @override
  String get document => 'DOCUMENT';

  @override
  String get failedToLoadImage => 'Failed to load image';

  @override
  String failedToReadFile(String error) {
    return 'Failed to read file: $error';
  }

  @override
  String get aiSettings => 'AI Settings';

  @override
  String get provider => 'Provider';

  @override
  String get model => 'Model';

  @override
  String get apiKey => 'API Key';

  @override
  String get customBaseUrl => 'Custom Base URL';

  @override
  String defaultHint(String url) {
    return 'Default: $url';
  }

  @override
  String get chatWithAi => 'CHAT WITH AI';

  @override
  String get chatHistory => 'Chat History';

  @override
  String get newChat => 'New Chat';

  @override
  String get internetAccess => 'Internet Access';

  @override
  String get mcpServers => 'MCP Servers';

  @override
  String get manualMode => 'Manual Mode';

  @override
  String get safeAutopilot => 'Safe Autopilot';

  @override
  String get fullAutonomy => 'Full Autonomy';

  @override
  String get agentsNotInstalled => 'Agents not installed';

  @override
  String get installGeminiCliInSettings => 'Install gemini-cli in settings';

  @override
  String get stopAgent => 'STOP AGENT';

  @override
  String get withChanges => 'with changes';

  @override
  String get attachOpenFile => 'Attach open file';

  @override
  String get noHistoryFound => 'No history found';

  @override
  String get untitled => 'Untitled';

  @override
  String messagesCount(int count) {
    return '$count messages';
  }

  @override
  String get systemEnv => 'System Environment';

  @override
  String get fixEnvironmentArm64 => 'Fix Environment (ARM64)';

  @override
  String get environment => 'Environment';

  @override
  String get collapseAll => 'Collapse All';

  @override
  String get elementMovedToRoot => 'Element moved to root';

  @override
  String get bookmarks => 'Bookmarks';

  @override
  String get noActiveWasmPlugins => 'No active WASM plugins';

  @override
  String get selectPluginAction => 'Select Plugin Action';

  @override
  String get noSelection => 'No selection';

  @override
  String get applyPluginToFile => 'Apply plugin action to the entire file?';

  @override
  String get pluginExecutedSuccess => 'Plugin executed successfully';

  @override
  String executionError(String error) {
    return 'Execution error: $error';
  }

  @override
  String get quickSearch => 'Quick Search (Ctrl+P)';

  @override
  String get saveTooltip => 'Save';

  @override
  String get runWasmPlugin => 'Run WASM Plugin';

  @override
  String get aiChat => 'AI Chat';

  @override
  String get home => 'Home';

  @override
  String get pendingDiff => 'Pending Diff';

  @override
  String get keep => 'Keep';

  @override
  String get reject => 'Reject';

  @override
  String get keepAll => 'Keep all';

  @override
  String ranAction(String content) {
    return 'Ran: $content';
  }

  @override
  String get created => 'Created';

  @override
  String get deleted => 'Deleted';

  @override
  String get edited => 'Edited';

  @override
  String get taskExecution => 'Task Execution';

  @override
  String stepNumber(int step, int total) {
    return 'Step $step/$total';
  }

  @override
  String filesChangedCount(int count, int additions, int deletions) {
    return 'Files changed: $count (+$additions -$deletions)';
  }

  @override
  String commandsExecutedCount(int count) {
    return 'Executed $count commands';
  }

  @override
  String get changesAccepted => 'Changes accepted and stashed';

  @override
  String undoneChanges(int count) {
    return 'Undid $count file changes';
  }

  @override
  String discardedFileChanges(String file) {
    return 'Discarded changes in $file';
  }

  @override
  String get thinking => 'Thinking...';

  @override
  String get planner => 'PLANNER';

  @override
  String get coder => 'CODER';

  @override
  String get validator => 'VALIDATOR';

  @override
  String get aiAgentRole => 'AI-AGENT';

  @override
  String get resubmit => 'Resubmit';

  @override
  String get rollbackHistoryToStep => 'Rollback history and code to this step';

  @override
  String get confirmRollback => 'Confirm Rollback';

  @override
  String get rollbackConfirmationText =>
      'All code changes made after this message will be reverted, and subsequent messages deleted. Continue?';

  @override
  String get yesRollback => 'Yes, rollback';

  @override
  String get changesApplied => 'Changes applied';

  @override
  String get codeCopied => 'Code copied to clipboard';

  @override
  String get outOfScope => 'Out of scope!';

  @override
  String get low => 'Low';

  @override
  String get medium => 'Medium';

  @override
  String get high => 'High';

  @override
  String get applied => 'Applied';

  @override
  String get resolveConflictTooltip => 'Resolve conflict';

  @override
  String get panel1 => 'PANEL 1';

  @override
  String get panel2 => 'PANEL 2';

  @override
  String get localWebServer => 'Local Web Server';

  @override
  String get webServerDesc =>
      'Start web server to preview your project\'s build results right inside the IDE.';

  @override
  String get startWebServer => 'Start Web Server';

  @override
  String get stopWebServer => 'Stop Web Server';

  @override
  String get copyAll => 'Copy All';

  @override
  String get clearTerminal => 'Clear Terminal';

  @override
  String get openInExternalBrowser => 'Open in external browser';

  @override
  String get search => 'Buscar';

  @override
  String get structure => 'Estructura';

  @override
  String get disk => 'Disco';

  @override
  String get plugins => 'Plugins';

  @override
  String get added => 'añadido';

  @override
  String get removed => 'eliminado';

  @override
  String get modified => 'modificado';

  @override
  String selectedObjectsCount(int count) {
    return 'Objetos seleccionados: $count';
  }

  @override
  String get explainFolderPreset =>
      'Explicar el propósito y la estructura de esta carpeta.';

  @override
  String get explainFilePreset =>
      'Explicar en detalle el propósito y la lógica de funcionamiento de este archivo.';

  @override
  String get addDocFolderPreset =>
      'Agregue documentación, cadenas de documentación y comentarios detallados al código en todos los archivos de esta carpeta.';

  @override
  String get addDocFilePreset =>
      'Agregue documentación clara, cadenas de documentación y comentarios detallados al código en este archivo.';

  @override
  String get generateTestsFolderPreset =>
      'Escribir pruebas unitarias para los archivos de esta carpeta.';

  @override
  String get generateTestsFilePreset =>
      'Escribir pruebas unitarias completas para el código de este archivo.';

  @override
  String get optimizeFolderPreset =>
      'Analice el código de esta carpeta y sugiera optimizaciones de rendimiento y legibilidad.';

  @override
  String get optimizeFilePreset =>
      'Analice el código de este archivo y sugiera opciones para optimizar el rendimiento, la legibilidad y la arquitectura.';

  @override
  String get deleteSelected => 'Eliminar seleccionados';

  @override
  String get manual => 'Manual';

  @override
  String get autoSafe => 'Auto:Seguro';

  @override
  String get autoFull => 'Auto:Completo';

  @override
  String filesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'archivos',
      one: 'archivo',
    );
    return '$count $_temp0';
  }

  @override
  String get localAiEngineTitle => 'MOTOR DE IA LOCAL';

  @override
  String get ollamaRunningLocally => 'Ollama se está ejecutando localmente';

  @override
  String get ollamaRunningLocallyDesc =>
      'Asegúrese de que Ollama se esté ejecutando en su sistema. Puede iniciarla con \"ollama serve\" y descargar los modelos necesarios con \"ollama pull <modelo>\".';

  @override
  String get lmStudioRunningLocally =>
      'LM Studio se está ejecutando localmente';

  @override
  String get lmStudioRunningLocallyDesc =>
      'Asegúrese de que el servidor de LM Studio se esté ejecutando. Puede activar el Servidor Local en la aplicación LM Studio y cargar el modelo requerido.';

  @override
  String get ollamaNotDetected => 'Ollama no detectado';

  @override
  String get ollamaNotDetectedDesc =>
      'Instale Ollama en su dispositivo y asegúrese de que se esté ejecutando. La URL se puede modificar arriba.';

  @override
  String get checkConnection => 'Verificar conexión';

  @override
  String get availableOllamaModels => 'MODELOS DE OLLAMA DISPONIBLES';

  @override
  String get llamaServerInstallRequired => 'Se requiere instalar llama-server';

  @override
  String get llamaServerInstallRequiredDesc =>
      'Se requiere el motor llama-server para ejecutar modelos de IA locales. Haga clic en el botón a continuación para instalarlo automáticamente.';

  @override
  String get installing => 'Instalando...';

  @override
  String get installLlamaServerRuntime => 'Instalar Llama Server Runtime';

  @override
  String get ollamaModelsTitle => 'MODELOS DE OLLAMA';

  @override
  String get localAiModelsTitle => 'MODELOS DE IA LOCALES';

  @override
  String get serverStatusAndControl => 'ESTADO Y CONTROL DEL SERVIDOR';

  @override
  String get downloadOllamaModelPrompt =>
      'Descargue al menos un modelo de Ollama para comenzar.';

  @override
  String get downloadModelToStartServerPrompt =>
      'Descargue al menos un modelo arriba para iniciar el servidor local.';

  @override
  String get localLlamaServerLabel => 'Servidor local llama-server';

  @override
  String get connected => 'Conectado';

  @override
  String get runningPort8080 => 'Ejecutándose (puerto 8080)';

  @override
  String get starting => 'Iniciando...';

  @override
  String get stopped => 'Detenido';

  @override
  String get start => 'Iniciar';

  @override
  String gbFormat(String size) {
    return '$size GB';
  }

  @override
  String ramGbFormat(String size) {
    return '~$size GB de RAM';
  }

  @override
  String get select => 'Seleccionar';

  @override
  String get download => 'Descargar';

  @override
  String get refreshPreview => 'Actualizar vista previa';

  @override
  String inFolder(String folder) {
    return 'en $folder';
  }

  @override
  String get llamaServerBuiltIn => 'llama-server (incorporado)';

  @override
  String get localAiDisplayName => 'IA Local';

  @override
  String get notRequired => 'no requerido';

  @override
  String get mcpGithubDesc =>
      'Integración con repositorios, problemas (issues) y PR en GitHub.';

  @override
  String get mcpGoogleSearchDesc =>
      'Permite al agente de IA realizar búsquedas en Google en tiempo real.';

  @override
  String get mcpFetchDesc =>
      'Descarga páginas web y las convierte automáticamente a Markdown.';

  @override
  String get mcpPostgresDesc =>
      'Conecta, lee la estructura de tablas y ejecuta consultas SQL en PostgreSQL.';

  @override
  String get mcpPostgresArg => 'Cadena de conexión (postgresql://...)';

  @override
  String get mcpSqliteDesc =>
      'Conecta e inspecciona bases de datos SQLite en tu proyecto.';

  @override
  String get mcpSqliteArg =>
      'Ruta al archivo DB SQLite (por ejemplo: db.sqlite)';

  @override
  String get mcpMemoryDesc =>
      'Almacenamiento de memoria semántica a largo plazo para tu agente de IA.';

  @override
  String get mcpBraveSearchDesc =>
      'Permite al agente de IA realizar búsquedas web utilizando la API de Brave.';

  @override
  String get mcpPuppeteerDesc =>
      'Automatización del navegador, generación de capturas de pantalla, clics y scraping web.';

  @override
  String get mcpFirecrawlDesc =>
      'Convierte cualquier sitio web en Markdown limpio o JSON estructurado.';

  @override
  String get mcpNotionDesc =>
      'Lee y modifica páginas, bases de datos y comentarios en Notion.';

  @override
  String get mcpSlackDesc =>
      'Permite leer canales, chatear y enviar notificaciones en Slack.';

  @override
  String get mcpGitDesc =>
      'Ver confirmaciones (commits), comparar versiones, buscar confirmaciones e inspeccionar archivos localmente vía Git.';

  @override
  String get mcpGitlabDesc =>
      'Administrar proyectos de GitLab, problemas, PR y pipelines de CI/CD.';

  @override
  String get mcpSentryDesc =>
      'Obtener registros de errores e inspeccionar fallos de tu aplicación en Sentry.';

  @override
  String get mcpAirtableDesc =>
      'Leer, crear y actualizar registros en bases de datos y tablas de Airtable.';

  @override
  String get mcpSequentialThinkingDesc =>
      'Organizar los pensamientos del agente de IA para la resolución estructurada de problemas.';

  @override
  String get phantomProcessesTitle => 'Procesos fantasma (Android 12/13+)';

  @override
  String get phantomProcessesVersion =>
      'Se requiere configuración de ADB para una compilación estable';

  @override
  String get phantomProcessesError =>
      'En Android 12+, el limitador de procesos del sistema (Phantom Process Killer) detiene las compilaciones (Gradle/Java/Node/Dart) si el límite supera los 32 procesos activos.\n\nPara desactivarlo, ejecute a través de ADB en su PC:\n\nadb shell \"/system/bin/device_config put activity_manager max_phantom_processes 2147483647\"\n\nadb shell \"/system/bin/settings put global settings_enable_monitor_phantom_procs false\"';

  @override
  String androidJarCorruptError(String api) {
    return 'android.jar está dañado ($api). Haga clic en \"Corregir entorno\" para reinstalar.';
  }

  @override
  String get androidSdkPlatformsHealthy =>
      'android-35 / android-36 — en buen estado';

  @override
  String checkFailed(String error) {
    return 'Comprobación fallida: $error';
  }

  @override
  String get analyzingTaskAndPlanning =>
      'Analizando la tarea y planificando...';

  @override
  String agentStepLimitExceeded(int limit) {
    return '🤖 Límite de pasos del agente ($limit) excedido. Piloto automático detenido.';
  }

  @override
  String get generatingCodeChanges => 'Generando cambios de código...';

  @override
  String get executionPlanConstructed =>
      '📝 Plan de ejecución construido. Transición al rol de Coder...';

  @override
  String get verifyingImplementation =>
      'Verificando la corrección de la implementación...';

  @override
  String blockedUnsafeActions(String blockedText) {
    return '❌ Acciones inseguras bloqueadas fuera del alcance del espacio de trabajo:\n$blockedText';
  }

  @override
  String get awaitingApprovalHighRisk =>
      '⚠️ Esperando aprobación: Se detectaron acciones de alto riesgo o el piloto automático está restringido. Por favor, apruébelas en el panel de IA.';

  @override
  String autopilotStepSummary(
    int step,
    String actionsListText,
    String results,
  ) {
    return '🤖 Piloto automático (paso $step): Autoaprobación de acciones:\n$actionsListText\n\nResultados:\n$results';
  }

  @override
  String get runningStaticAnalysis =>
      'Ejecutando análisis estático del proyecto (dart analyze)...';

  @override
  String agentFailedToFixErrors(int maxAttempts, String errorReport) {
    return '⚠️ El agente no pudo corregir los errores después de $maxAttempts intentos.\n\n**Errores restantes:**\n$errorReport\n\nPor favor, describa el problema o corríjalo manualmente.';
  }

  @override
  String get fixingCompilationErrors => 'Corrigiendo errores de compilación...';

  @override
  String readingFile(String path) {
    return 'Leyendo archivo $path...';
  }

  @override
  String savingFile(String path) {
    return 'Guardando archivo $path...';
  }

  @override
  String deletingFile(String path) {
    return 'Eliminando archivo $path...';
  }

  @override
  String runningCommandStatus(String command) {
    return 'Ejecutando comando \"$command\"...';
  }

  @override
  String searchingCode(String query) {
    return 'Buscando en el código: \"$query\"...';
  }

  @override
  String listingDirectory(String path) {
    return 'Listando directorio $path...';
  }

  @override
  String findingSymbols(String query) {
    return 'Buscando símbolos: \"$query\"...';
  }

  @override
  String searchingWeb(String query) {
    return 'Buscando en la web: \"$query\"...';
  }

  @override
  String fetchingWebPage(String path) {
    return 'Obteniendo página web: $path...';
  }

  @override
  String get executingAction => 'Ejecutando acción...';

  @override
  String runningCommandLabel(String command) {
    return '🤖 Ejecutando comando: $command...';
  }

  @override
  String applyingChangeLabel(String path) {
    return '🤖 Aplicando cambio: $path...';
  }

  @override
  String commandSentToTerminalLabel(String command) {
    return '🤖 Comando \"$command\" enviado a la terminal.';
  }

  @override
  String runningCommandResultLabel(String command, String result) {
    return 'Comando \"$command\" ejecutado. Resultado:\n$result';
  }

  @override
  String fileNotFound(String path) {
    return 'Archivo no encontrado: $path';
  }

  @override
  String fileContentsHeader(String path, int lineCount, String truncated) {
    return 'Contenido del archivo `$path` ($lineCount líneas):\n\n```\n$truncated\n```';
  }

  @override
  String fileTruncatedSuffix(int lineCount) {
    return '... [truncado a 8000 caracteres de $lineCount líneas]';
  }

  @override
  String get safetyGuardFileOutsideWorkspace =>
      'Error: Intento de modificación del archivo fuera del alcance del proyecto.';

  @override
  String get commandRefPathOutsideWorkspace =>
      'Error de seguridad: El comando hace referencia a una ruta fuera del alcance del proyecto.';

  @override
  String commandBlockedUnsafe(String blocked) {
    return 'Error de seguridad: El comando contiene una instrucción bloqueada \"$blocked\".';
  }

  @override
  String aiSearchNoMatches(String query) {
    return 'No se encontraron coincidencias para \"$query\".';
  }

  @override
  String aiSearchMatchesFound(int matchCount, String query, String results) {
    return 'Se encontraron $matchCount coincidencias para \"$query\":\n\n$results';
  }

  @override
  String searchSymbolsNoMatches(String query) {
    return 'No se encontraron símbolos que coincidan con \"$query\".';
  }

  @override
  String searchSymbolsMatchesFound(int count, String query, String results) {
    return 'Se encontraron $count símbolos que coinciden con \"$query\":\n\n$results';
  }

  @override
  String searchSymbolsItem(String type, String name, String path, int line) {
    return '- [$type] $name (archivo: $path, línea: $line)';
  }

  @override
  String directoryNotFound(String path) {
    return 'Directorio no encontrado: $path';
  }

  @override
  String get directoryEmpty => 'El directorio está vacío.';

  @override
  String directoryContentsHeader(String items) {
    return 'Contenido del directorio:\n\n$items';
  }

  @override
  String get mcpMissingParams =>
      'Error: El nombre del servidor MCP o de la herramienta no está especificado.';

  @override
  String unknownAction(String type) {
    return 'Tipo de acción desconocido: $type';
  }

  @override
  String failedToApplyActionWithError(String error) {
    return 'Error al aplicar la acción: $error';
  }

  @override
  String get searchQueryEmpty => 'Error: La consulta de búsqueda está vacía.';

  @override
  String get workspaceNotFound =>
      'Error: No se encontró el espacio de trabajo.';

  @override
  String get webPreviewStopped => 'Vista previa web detenida';

  @override
  String get webPreviewStartInstructions =>
      'Inicie el servidor y haga clic en el botón de reproducción.';
}
