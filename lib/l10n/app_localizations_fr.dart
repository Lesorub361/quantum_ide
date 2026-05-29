// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'QuantumIDE';

  @override
  String get explorer => 'Explorateur';

  @override
  String get newFile => 'Nouveau fichier';

  @override
  String get newFolder => 'Nouveau dossier';

  @override
  String get refresh => 'Actualiser';

  @override
  String get rename => 'Renommer';

  @override
  String get delete => 'Supprimer';

  @override
  String get cancel => 'Annuler';

  @override
  String get save => 'Enregistrer';

  @override
  String get create => 'Créer';

  @override
  String get projectNotOpened => 'Projet non ouvert';

  @override
  String get selectFileToStart =>
      'Sélectionnez un fichier dans l\'explorateur pour commencer';

  @override
  String get openExplorer => 'Ouvrir l\'explorateur';

  @override
  String get confirmDelete => 'Confirmer la suppression';

  @override
  String areYouSureDelete(String name) {
    return 'Are you sure you want to delete $name?';
  }

  @override
  String get terminal => 'Terminal';

  @override
  String get run => 'Exécuter';

  @override
  String get build => 'Bâtir';

  @override
  String get aiAgent => 'Agent IA';

  @override
  String get servers => 'Serveurs';

  @override
  String get buildLogs => 'Build Logs';

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
  String get settings => 'Paramètres';

  @override
  String get interfaceAndLocalization => 'Interface & Localisation';

  @override
  String get language => 'Langue';

  @override
  String get theme => 'Thème';

  @override
  String get darkTheme => 'Thème sombre';

  @override
  String get lightTheme => 'Thème clair';

  @override
  String get colorPalette => 'Palette de couleurs';

  @override
  String get customColor => 'Custom Color';

  @override
  String get accentColor => 'Couleur d\'accentuation';

  @override
  String get projectIcon => 'Project Icon';

  @override
  String get defaultAccent => 'Default';

  @override
  String get codeEditor => 'Éditeur de code';

  @override
  String get editorFontSize => 'Taille de police de l\'éditeur';

  @override
  String get autoCompletion => 'Saisie automatique';

  @override
  String get showCodeHints => 'Show code hints';

  @override
  String get aiAutoCompletion => 'AI Auto-completion';

  @override
  String get geminiCodeGeneration => 'Gemini code generation';

  @override
  String get wordWrap => 'Retour à la ligne';

  @override
  String get wordWrapDescription => 'Soft wrap lines in editor';

  @override
  String get lineNumbers => 'Numéros de ligne';

  @override
  String get showLineNumbers => 'Show line numbers';

  @override
  String get minimap => 'Minicarte';

  @override
  String get showMinimap => 'Show editor minimap';

  @override
  String get autoSave => 'Sauvegarde automatique';

  @override
  String get autoSaveDescription => 'Save changes after 2s';

  @override
  String get terminalFontSize => 'Taille de police du terminal';

  @override
  String get terminalTheme => 'Thème du terminal';

  @override
  String get toolsAndAi => 'Outils & IA';

  @override
  String get aiProviders => 'Fournisseurs d\'IA';

  @override
  String get aiProvidersSubtitle => 'Gemini, OpenAI, Ollama etc.';

  @override
  String get ubuntuPackages => 'Paquets Ubuntu';

  @override
  String get manageCliTools => 'Manage CLI tools';

  @override
  String get hosts => 'Hosts';

  @override
  String get localRemoteHosts => 'Local/remote hosts';

  @override
  String get system => 'Système';

  @override
  String get showHiddenFiles => 'Show Hidden Files';

  @override
  String get showHiddenFilesDescription => 'Show .* files';

  @override
  String get vibration => 'Vibration';

  @override
  String get hapticFeedback => 'Haptic feedback';

  @override
  String get aboutApp => 'À propos de l\'application';

  @override
  String get aboutAppSubtitle => 'Quantum IDE v1.0.0';

  @override
  String get selectPalette => 'Select Palette';

  @override
  String get close => 'Fermer';

  @override
  String get resetToDefault => 'Réinitialiser';

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
  String get noProjects => 'Aucun projet';

  @override
  String get nothingFound => 'Nothing found';

  @override
  String get createFirstProject => 'Créer le premier projet';

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
    return 'Delete \"$name\"?';
  }

  @override
  String get confirmDeleteMessage =>
      'Delete only from the list or delete files as well?';

  @override
  String get deleteFromListOnly => 'From list';

  @override
  String get deleteFromDisk => 'From disk';

  @override
  String get projectSettings => 'Paramètres du projet';

  @override
  String get createProject => 'Créer un projet';

  @override
  String get projectName => 'Nom du projet';

  @override
  String get projectType => 'TYPE DE PROJET';

  @override
  String get androidCompileSdkVersion => 'ANDROID compileSdk VERSION';

  @override
  String get defaultSdkVersion => 'Default: 35';

  @override
  String get targetPlatforms => 'TARGET DEVICES / PLATFORMS';

  @override
  String get saveAction => 'Enregistrer';

  @override
  String get code => 'Code';

  @override
  String get preview => 'Aperçu';

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
  String get activeCaps => 'ACTIVE';

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
  String get send => 'Envoyer';

  @override
  String get acceptAll => 'Accept All';

  @override
  String get rejectAll => 'Reject All';

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
  String get problems => 'Problèmes';

  @override
  String get packages => 'Paquets';

  @override
  String get tools => 'Outils';

  @override
  String get searchFiles => 'Rechercher des fichiers...';

  @override
  String get imageLoadError => 'Error loading image';

  @override
  String get unsaved => 'Non enregistré';

  @override
  String get saved => 'Enregistré';

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
  String get glassmorphismEffects => 'Effets de verre (Glassmorphism)';

  @override
  String get glassOpacity => 'Opacité du verre';

  @override
  String get backdropBlur => 'Flou d\'arrière-plan';

  @override
  String get editorFontFamily => 'Police de l\'éditeur';

  @override
  String get fontLigatures => 'Ligatures de police';

  @override
  String get fontLigaturesDescription =>
      'Activer les ligatures de police dans le code';

  @override
  String get selectFontFamily => 'Sélectionner la police';

  @override
  String get selectLanguage => 'Sélectionner la langue';

  @override
  String get format => 'Formater';

  @override
  String get liveShare => 'Partage en Direct';

  @override
  String get hostSession => 'Créer une Session';

  @override
  String get joinSession => 'Rejoindre la Session';

  @override
  String get stopSession => 'Arrêter la Session';

  @override
  String get disconnectSession => 'Se déconnecter';

  @override
  String get sessionActive => 'Session Active';

  @override
  String get hostingAt => 'Hébergé sur :';

  @override
  String get connectedTo => 'Connecté à :';

  @override
  String get userName => 'Votre Nom';

  @override
  String get usersList => 'Participants';

  @override
  String get messagePlaceholder => 'Tapez un message...';

  @override
  String get connectError => 'Erreur de connexion';

  @override
  String get invalidAddress => 'Adresse invalide';

  @override
  String get joinLink => 'Adresse IP de la session';

  @override
  String get localIps => 'IPs Locales :';
}
