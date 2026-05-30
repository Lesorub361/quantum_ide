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
  String get newFile => 'New File';

  @override
  String get newFolder => 'New Folder';

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
  String get buildLogs => 'Registres de création';

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
  String get aboutApp => 'À propos de l\'application';

  @override
  String get aboutAppSubtitle => 'Quantum IDE v1.0.0';

  @override
  String get selectPalette => 'Select Palette';

  @override
  String get close => 'Close';

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
  String get activeCaps => 'ACTIF';

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

  @override
  String get wasmPlugins => 'Extensions WASM';

  @override
  String get installPlugin => 'Installer l\'extension (.wasm)';

  @override
  String get noPluginsInstalled => 'Aucun plugin WASM installé';

  @override
  String get pluginEnabled => 'Extension activée';

  @override
  String get pluginDisabled => 'Extension désactivée';

  @override
  String get runWasmAction => 'Exécuter l\'action WASM';

  @override
  String get noActiveSelection =>
      'Aucun texte sélectionné. Appliquer à tout le fichier ?';

  @override
  String get applyToSelection => 'Appliquer à la sélection';

  @override
  String get applyToDocument => 'Appliquer au document';

  @override
  String get logs => 'Journaux';

  @override
  String get clearLogs => 'Effacer les logs';

  @override
  String get deletePlugin => 'Supprimer le plugin';

  @override
  String get resetToDefaults => 'Réinitialiser';

  @override
  String get welcomeTitle => 'Bienvenue !';

  @override
  String get welcomeSubtitle =>
      'Choisissez un projet sur lequel travailler ou créez-en un nouveau';

  @override
  String get lastActiveProject => 'Dernier projet actif';

  @override
  String get runTooltip => 'Lancer';

  @override
  String get actionsTooltip => 'Actions';

  @override
  String get packagesTooltip => 'Packages';

  @override
  String get extensionsAndTools => 'Extensions et Outils';

  @override
  String get searchExtensionsHint => 'Rechercher des extensions...';

  @override
  String get searchPubdevHint =>
      'Rechercher des bibliothèques sur pub.dev (ex. dio)...';

  @override
  String get tabAll => 'Tout';

  @override
  String get tabInstalled => 'Installé';

  @override
  String get tabLanguagesAndAi => 'Langues et IA';

  @override
  String get tabTools => 'Outils';

  @override
  String get tabBuild => 'Compiler';

  @override
  String get tabSdkPlatforms => 'Plateformes SDK';

  @override
  String get tabPubLibraries => 'Bibliothèques Pub';

  @override
  String get readyToBuildApk => 'Prêt à compiler l\'APK?';

  @override
  String get installAndroidSdkJava => 'Installer Android SDK et Java 17';

  @override
  String get sdkSetupDescription =>
      'Cela configurera le SDK, les compilateurs, zipalign, apksigner, optimisera les paramètres réseau de Gradle et préparera votre environnement pour la compilation de projets.';

  @override
  String get initializingDevEnvironment =>
      'Initialisation de l\'environnement de développement...';

  @override
  String get viewAction => 'Voir';

  @override
  String get startSdkSetup => 'Démarrer la configuration de l\'environnement';

  @override
  String get buildIssues => 'Problèmes de compilation?';

  @override
  String get restoreAndroidGradleEnv =>
      'Restaurer l\'environnement Android et Gradle';

  @override
  String get wrenchFixDescription =>
      'Corrige automatiquement les erreurs du démon AAPT2, définit les autorisations de projet correctes, restaure le binaire du compilateur de ressources et configure les threads Gradle.';

  @override
  String get runningWrenchFix =>
      'Exécution de la correction de l\'environnement de compilation...';

  @override
  String get startWrenchFix => 'Exécuter la correction (Wrench Fix)';

  @override
  String get statusInstalledCaps => 'INSTALLÉ';

  @override
  String get reinstallOrUpdateTooltip => 'Réinstaller / Mettre à jour';

  @override
  String updatingPackage(String name) {
    return 'Mise à jour de $name...';
  }

  @override
  String installingPackage(String name) {
    return 'Installation de $name...';
  }

  @override
  String get installAction => 'Installer';

  @override
  String get searchPubdevTitle => 'Rechercher des bibliothèques Flutter';

  @override
  String get searchPubdevDescription =>
      'Entrez le nom de la bibliothèque (ex. dio, bloc, riverpod) dans la recherche ci-dessus et appuyez sur Entrée';

  @override
  String loadError(String error) {
    return 'Erreur de chargement: $error';
  }

  @override
  String get addAction => 'Ajouter';

  @override
  String get openProjectToInstallLibraries =>
      'Veuillez d\'abord ouvrir un projet pour ajouter des bibliothèques.';

  @override
  String installingLibrary(String name) {
    return 'Installation de la bibliothèque $name...';
  }

  @override
  String importError(String error) {
    return 'Erreur d\'importation: $error';
  }

  @override
  String get filesImportedSuccessfully => 'Fichiers importés avec succès';

  @override
  String get dragFilesHereToImport =>
      'Faites glisser des fichiers ici pour les importer';

  @override
  String selectedCount(int count) {
    return 'Sélectionné: $count';
  }

  @override
  String get selectAllTooltip => 'Tout sélectionner';

  @override
  String get copyTooltip => 'Copier';

  @override
  String copiedCount(int count) {
    return 'Objets copiés: $count';
  }

  @override
  String get cutTooltip => 'Couper';

  @override
  String cutCount(int count) {
    return 'Objets coupés: $count';
  }

  @override
  String get zipTooltip => 'Compresser en ZIP';

  @override
  String get deleteTooltip => 'Supprimer';

  @override
  String foldersCount(int count) {
    return 'Dossiers: $count';
  }

  @override
  String get askAiAction => 'Demander à l\'IA';

  @override
  String get explainAiAction => 'IA: Expliquer';

  @override
  String get documentAiAction => 'IA: Documenter';

  @override
  String get testAiAction => 'IA: Générer des tests';

  @override
  String get optimizeAiAction => 'IA: Optimiser';

  @override
  String pasteCount(int count) {
    return 'Coller ($count)';
  }

  @override
  String get archiveNameHint => 'Nom de l\'archive';

  @override
  String get compressAction => 'Compresser';

  @override
  String get archiveCreatedSuccessfully => 'Archive créée avec succès !';

  @override
  String compressionError(String error) {
    return 'Erreur de compression: $error';
  }

  @override
  String get archiveExtractedSuccessfully => 'Archive extraite avec succès !';

  @override
  String extractionError(String error) {
    return 'Erreur d\'extraction: $error';
  }

  @override
  String get deleteSelectedTitle => 'Supprimer la sélection ?';

  @override
  String deleteSelectedConfirmation(int count) {
    return 'Êtes-vous sûr de vouloir supprimer $count éléments ?';
  }

  @override
  String get selectedElementsDeleted => 'Éléments sélectionnés supprimés !';

  @override
  String deleteError(String error) {
    return 'Erreur de suppression: $error';
  }

  @override
  String get filesPastedSuccessfully => 'Fichiers collés avec succès !';

  @override
  String pasteError(String error) {
    return 'Erreur de collage: $error';
  }

  @override
  String get repositoryNotFound => 'Dépôt non trouvé';

  @override
  String get initGitRepoDescription =>
      'Initialisez un dépôt Git local pour suivre les modifications.';

  @override
  String get initGitAction => 'Initialiser Git';

  @override
  String get gitConflicted => 'CONFLITS';

  @override
  String get gitStaged => 'INDEXÉ';

  @override
  String get gitModified => 'MODIFIÉ';

  @override
  String get gitUntracked => 'NON SUIVI';

  @override
  String get commitMessageHint => 'Message de commit...';

  @override
  String get resetChangesTitle => 'Réinitialiser les modifications ?';

  @override
  String get resetChangesConfirmation =>
      'Êtes-vous sûr de vouloir réinitialiser définitivement toutes les modifications non validées dans ce fichier ?';

  @override
  String get resetAction => 'Réinitialiser';

  @override
  String get changesReset => 'Modifications réinitialisées';

  @override
  String resetError(String error) {
    return 'Erreur de réinitialisation: $error';
  }

  @override
  String get normalView => 'Vue normale';

  @override
  String get splitView => 'Vue fractionnée (Side-by-Side)';

  @override
  String get stagedMessage => 'Fichier indexé';

  @override
  String get unstagedMessage => 'Fichier désindexé';

  @override
  String stageError(String error) {
    return 'Erreur d\'indexation: $error';
  }

  @override
  String get failedToLoadChanges => 'Échec du chargement des modifications';

  @override
  String get noChanges => 'Aucune modification';

  @override
  String get fileIdenticalToHead => 'Ce fichier est identique à HEAD';

  @override
  String get runTerminalTooltip => 'Lancer';

  @override
  String get restartTerminalTooltip => 'Redémarrer';

  @override
  String get consoleSubTab => 'Console';

  @override
  String get signApkSubTab => 'Signer l\'APK';

  @override
  String get copiedToClipboard => 'Copié dans le presse-papiers';

  @override
  String get back => 'Retour';

  @override
  String get tryChangingSearchQuery =>
      'Essayez de modifier la requête de recherche';

  @override
  String get incomingBranch => 'Branche entrante';

  @override
  String get resolveConflictsBeforeSaving =>
      'Veuillez résoudre tous les conflits avant d\'enregistrer !';

  @override
  String get fileSavedAndStaged =>
      'Fichier enregistré avec succès et indexé dans Git';

  @override
  String saveError(String error) {
    return 'Erreur d\'enregistrement : $error';
  }

  @override
  String get acceptMerge => 'Accepter la fusion';

  @override
  String get errorLoadingConflictFile =>
      'Erreur lors du chargement du fichier de conflit';

  @override
  String get conflictsNotFound => 'Aucun conflit trouvé';

  @override
  String get noConflictMarkersFound =>
      'Aucun marqueur de conflit Git standard trouvé dans ce fichier.';

  @override
  String get backToGit => 'Retour à Git';

  @override
  String get conflictBlock => 'Bloc de conflit';

  @override
  String get currentChangesOurs => 'Modifications actuelles (Ours / HEAD)';

  @override
  String incomingChanges(String branch) {
    return 'Modifications entrantes ($branch)';
  }

  @override
  String get useThisVersion => 'Utiliser cette version';

  @override
  String get mergeResultEditable => 'Résultat de la fusion (Modifiable)';

  @override
  String get chooseVersionOrWriteHint =>
      'Choisissez l\'une des versions ci-dessus ou écrivez votre propre résolution...';

  @override
  String get markAsResolvedHint =>
      '* Pour marquer ce bloc comme résolu, saisissez ou choisissez du texte.';

  @override
  String get emptyLabel => '(Vide)';

  @override
  String get stageAction => 'Index';

  @override
  String get unstageAction => 'Désindexer';

  @override
  String get cursorColor => 'COULEUR DU CURSEUR';

  @override
  String get or => 'OU';

  @override
  String get ipCopiedToClipboard => 'IP copiée dans le presse-papiers';

  @override
  String editingFile(String file) {
    return 'Modification : $file';
  }

  @override
  String get viewingProject => 'Visualisation du projet';

  @override
  String get noProblemsFound =>
      'Aucun problème trouvé dans l\'espace de travail';

  @override
  String get problemsList => 'Liste des problèmes';

  @override
  String get sendToAi => 'Envoyer à l\'IA';

  @override
  String get helpMeFixErrors =>
      'Veuillez m\'aider à corriger les erreurs de compilation suivantes dans mon projet :';

  @override
  String lineColumn(int line, int col) {
    return 'Ligne $line, Colonne $col';
  }

  @override
  String get decreaseFontSize => 'Diminuer la taille de la police';

  @override
  String get increaseFontSize => 'Augmenter la taille de la police';

  @override
  String get undo => 'Annuler';

  @override
  String get redo => 'Rétablir';

  @override
  String get moveLeft => 'Déplacer à gauche';

  @override
  String get moveUp => 'Déplacer vers le haut';

  @override
  String get moveDown => 'Déplacer vers le bas';

  @override
  String get moveRight => 'Déplacer à droite';

  @override
  String get edit => 'Modifier';

  @override
  String get packagesAndEnv => 'Packages & Env';

  @override
  String packagesInstalledCount(int count, int total) {
    return 'Installés : $count/$total';
  }

  @override
  String get flutterProject => 'Projet Flutter';

  @override
  String get pythonProject => 'Projet Python';

  @override
  String get nodejsProject => 'Projet Node.js';

  @override
  String get dartProject => 'Projet Dart';

  @override
  String get webProject => 'Projet Web';

  @override
  String get androidProject => 'Projet Android';

  @override
  String get genericProject => 'Projet';

  @override
  String get runPC => 'Exécuter (PC)';

  @override
  String get runMob => 'Exécuter (Mobile)';

  @override
  String get startServer => 'Démarrer le serveur';

  @override
  String get buildAPK => 'Créer l\'APK';

  @override
  String get startTheProject => 'Démarrer le projet';

  @override
  String get outputCopied => 'Sortie copiée';

  @override
  String get console => 'Console';

  @override
  String get signApk => 'Signer l\'APK';

  @override
  String get buildPC => 'Créer (PC)';

  @override
  String get resetPlugins => 'Réinitialiser les plugins';

  @override
  String get resetPluginsConfirmation =>
      'Cela supprimera tous les plugins personnalisés installés et restaurera les plugins par défaut. Continuer ?';

  @override
  String get resetPluginsTitle => 'Réinitialiser les plugins ?';

  @override
  String get installWasm => 'Installer .wasm';

  @override
  String get availableActions => 'Actions disponibles :';

  @override
  String get logsTerminal => 'Terminal de logs';

  @override
  String get noLogsCaptured => 'Aucun log capturé pour le moment';

  @override
  String get installWasmPluginTitle => 'Installer le plugin WASM';

  @override
  String get selectWasmFile => 'Sélectionner le fichier .wasm';

  @override
  String get pluginName => 'Nom du plugin';

  @override
  String get nameRequired => 'Le nom est obligatoire';

  @override
  String get pluginDescription => 'Description';

  @override
  String get descriptionRequired => 'La description est obligatoire';

  @override
  String get exposedActions => 'Actions exposées';

  @override
  String get add => 'Ajouter';

  @override
  String get pickWasmFileFirst => 'Veuillez d\'abord choisir un fichier .wasm';

  @override
  String get pluginInstalledSuccessfully => 'Plugin installé avec succès';

  @override
  String failedToInstall(String error) {
    return 'Échec de l\'installation : $error';
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
  String get search => 'Rechercher';

  @override
  String get structure => 'Structure';

  @override
  String get disk => 'Disque';

  @override
  String get plugins => 'Plugins';

  @override
  String get added => 'ajouté';

  @override
  String get removed => 'supprimé';

  @override
  String get modified => 'modifié';

  @override
  String selectedObjectsCount(int count) {
    return 'Objets sélectionnés: $count';
  }

  @override
  String get explainFolderPreset =>
      'Expliquer le but et la structure de ce dossier.';

  @override
  String get explainFilePreset =>
      'Expliquer en détail le but et la logique de fonctionnement de ce fichier.';

  @override
  String get addDocFolderPreset =>
      'Ajouter de la documentation, des docstrings et des commentaires détaillés au code dans tous les fichiers de ce dossier.';

  @override
  String get addDocFilePreset =>
      'Ajouter une documentation claire, des docstrings et des commentaires détaillés au code dans ce fichier.';

  @override
  String get generateTestsFolderPreset =>
      'Écrire des tests unitaires pour les fichiers de ce dossier.';

  @override
  String get generateTestsFilePreset =>
      'Écrire des tests unitaires complets pour le code de ce fichier.';

  @override
  String get optimizeFolderPreset =>
      'Analyser le code de ce dossier et suggérer des optimisations de performances et de lisibilité.';

  @override
  String get optimizeFilePreset =>
      'Analyser le code de ce fichier et suggérer des options pour optimiser les performances, la lisibilité et l\'architecture.';

  @override
  String get deleteSelected => 'Supprimer la sélection';

  @override
  String get manual => 'Manuel';

  @override
  String get autoSafe => 'Auto:Sécurisé';

  @override
  String get autoFull => 'Auto:Complet';

  @override
  String filesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'fichiers',
      one: 'fichier',
    );
    return '$count $_temp0';
  }

  @override
  String get localAiEngineTitle => 'MOTEUR D\'IA LOCALE';

  @override
  String get ollamaRunningLocally => 'Ollama fonctionne localement';

  @override
  String get ollamaRunningLocallyDesc =>
      'Assurez-vous qu\'Ollama fonctionne sur votre système. Vous pouvez le démarrer avec \"ollama serve\" et télécharger les modèles requis avec \"ollama pull <modèle>\".';

  @override
  String get lmStudioRunningLocally => 'LM Studio fonctionne localement';

  @override
  String get lmStudioRunningLocallyDesc =>
      'Assurez-vous que le serveur LM Studio fonctionne. Vous pouvez activer le Serveur Local dans l\'application LM Studio et charger le modèle requis.';

  @override
  String get ollamaNotDetected => 'Ollama non détecté';

  @override
  String get ollamaNotDetectedDesc =>
      'Installez Ollama sur votre appareil et assurez-vous qu\'il fonctionne. L\'URL peut être modifiée ci-dessus.';

  @override
  String get checkConnection => 'Vérifier la connexion';

  @override
  String get availableOllamaModels => 'MODÈLES OLLAMA DISPONIBLES';

  @override
  String get llamaServerInstallRequired =>
      'Installation de llama-server requise';

  @override
  String get llamaServerInstallRequiredDesc =>
      'Le moteur llama-server est requis pour exécuter des modèles d\'IA locaux. Cliquez sur le bouton ci-dessous pour l\'installer automatiquement.';

  @override
  String get installing => 'Installation...';

  @override
  String get installLlamaServerRuntime => 'Installer Llama Server Runtime';

  @override
  String get ollamaModelsTitle => 'MODÈLES OLLAMA';

  @override
  String get localAiModelsTitle => 'MODÈLES D\'IA LOCAUX';

  @override
  String get serverStatusAndControl => 'STATUT ET CONTRÔLE DU SERVEUR';

  @override
  String get downloadOllamaModelPrompt =>
      'Téléchargez au moins un modèle Ollama pour commencer.';

  @override
  String get downloadModelToStartServerPrompt =>
      'Téléchargez au moins un modèle ci-dessus pour démarrer le serveur local.';

  @override
  String get localLlamaServerLabel => 'Serveur local llama-server';

  @override
  String get connected => 'Connecté';

  @override
  String get runningPort8080 => 'En cours d\'exécution (port 8080)';

  @override
  String get starting => 'Démarrage...';

  @override
  String get stopped => 'Arrêté';

  @override
  String get start => 'Démarrer';

  @override
  String gbFormat(String size) {
    return '$size Go';
  }

  @override
  String ramGbFormat(String size) {
    return '~$size Go de RAM';
  }

  @override
  String get select => 'Sélectionner';

  @override
  String get download => 'Télécharger';

  @override
  String get refreshPreview => 'Actualiser l\'aperçu';

  @override
  String inFolder(String folder) {
    return 'dans $folder';
  }

  @override
  String get llamaServerBuiltIn => 'llama-server (intégré)';

  @override
  String get localAiDisplayName => 'IA locale';

  @override
  String get notRequired => 'non requis';

  @override
  String get mcpGithubDesc =>
      'Intégration avec les dépôts, tickets (issues) et PR sur GitHub.';

  @override
  String get mcpGoogleSearchDesc =>
      'Permet à l\'agent IA d\'effectuer des recherches Google en direct.';

  @override
  String get mcpFetchDesc =>
      'Télécharge des pages Web et les convertit automatiquement en Markdown.';

  @override
  String get mcpPostgresDesc =>
      'Connecter, lire la structure des tables et exécuter des requêtes SQL sur PostgreSQL.';

  @override
  String get mcpPostgresArg => 'Chaîne de connexion (postgresql://...)';

  @override
  String get mcpSqliteDesc =>
      'Connecter et inspecter les bases de données SQLite dans votre projet.';

  @override
  String get mcpSqliteArg => 'Chemin vers le fichier DB SQLite (ex: db.sqlite)';

  @override
  String get mcpMemoryDesc =>
      'Stockage sémantique de mémoire à long terme pour votre agent IA.';

  @override
  String get mcpBraveSearchDesc =>
      'Permet à l\'agent IA d\'effectuer des recherches Web à l\'aide de l\'API Brave.';

  @override
  String get mcpPuppeteerDesc =>
      'Automatisation du navigateur, génération de captures d\'écran, clics et scraping Web.';

  @override
  String get mcpFirecrawlDesc =>
      'Convertit n\'importe quel site Web en Markdown propre ou en JSON structuré.';

  @override
  String get mcpNotionDesc =>
      'Lire et modifier des pages, bases de données et commentaires dans Notion.';

  @override
  String get mcpSlackDesc =>
      'Permet de lire des canaux, de discuter et d\'envoyer des notifications dans Slack.';

  @override
  String get mcpGitDesc =>
      'Afficher les commits, comparer les versions, rechercher des commits et inspecter les fichiers localement via Git.';

  @override
  String get mcpGitlabDesc =>
      'Gérer les projets GitLab, les tickets, les PR et les pipelines de CI/CD.';

  @override
  String get mcpSentryDesc =>
      'Récupérer les journaux d\'erreurs et inspecter les plantages de votre application sur Sentry.';

  @override
  String get mcpAirtableDesc =>
      'Lire, créer et mettre à jour des enregistrements dans les bases de datos et tables Airtable.';

  @override
  String get mcpSequentialThinkingDesc =>
      'Organiser les réflexions de l\'agent IA pour une résolution structurée des problèmes.';

  @override
  String get phantomProcessesTitle => 'Processus fantômes (Android 12/13+)';

  @override
  String get phantomProcessesVersion =>
      'Configuration ADB requise pour une compilation stable';

  @override
  String get phantomProcessesError =>
      'Dans Android 12+, le tueur de processus système (Phantom Process Killer) interrompt les builds (Gradle/Java/Node/Dart) si la limite dépasse 32 processus actifs.\n\nPour le désactiver, exécutez via ADB sur votre PC :\n\nadb shell \"/system/bin/device_config put activity_manager max_phantom_processes 2147483647\"\n\nadb shell \"/system/bin/settings put global settings_enable_monitor_phantom_procs false\"';

  @override
  String androidJarCorruptError(String api) {
    return 'android.jar est corrompu ($api). Cliquez sur \"Corriger l\'environnement\" pour réinstaller.';
  }

  @override
  String get androidSdkPlatformsHealthy => 'android-35 / android-36 — sains';

  @override
  String checkFailed(String error) {
    return 'Échec de la vérification : $error';
  }

  @override
  String get analyzingTaskAndPlanning =>
      'Analyse de la tâche et planification...';

  @override
  String agentStepLimitExceeded(int limit) {
    return '🤖 Limite d\'étapes de l\'agent ($limit) dépassée. Autopilote arrêté.';
  }

  @override
  String get generatingCodeChanges => 'Génération des modifications de code...';

  @override
  String get executionPlanConstructed =>
      '📝 Plan d\'exécution construit. Transition vers le rôle de Coder...';

  @override
  String get verifyingImplementation =>
      'Vérification de la correction de l\'implémentation...';

  @override
  String blockedUnsafeActions(String blockedText) {
    return '❌ Actions non sécurisées bloquées hors de la portée de l\'espace de travail:\n$blockedText';
  }

  @override
  String get awaitingApprovalHighRisk =>
      '⚠️ En attente d\'approbation: Actions à haut risque détectées ou l\'autopilote est restreint. Veuillez les approuver dans le panneau IA.';

  @override
  String autopilotStepSummary(
    int step,
    String actionsListText,
    String results,
  ) {
    return '🤖 Autopilote (étape $step): Auto-approbation des actions:\n$actionsListText\n\nRésultats:\n$results';
  }

  @override
  String get runningStaticAnalysis =>
      'Exécution de l\'analyse statique du projet (dart analyze)...';

  @override
  String agentFailedToFixErrors(int maxAttempts, String errorReport) {
    return '⚠️ L\'agent n\'a pas réussi à corriger les erreurs après $maxAttempts tentatives.\n\n**Erreurs restantes:**\n$errorReport\n\nVeuillez décrire le problème ou le corriger manuellement.';
  }

  @override
  String get fixingCompilationErrors =>
      'Correction des erreurs de compilation...';

  @override
  String readingFile(String path) {
    return 'Lecture du fichier $path...';
  }

  @override
  String savingFile(String path) {
    return 'Enregistrement du fichier $path...';
  }

  @override
  String deletingFile(String path) {
    return 'Suppression du fichier $path...';
  }

  @override
  String runningCommandStatus(String command) {
    return 'Exécution de la commande \"$command\"...';
  }

  @override
  String searchingCode(String query) {
    return 'Recherche dans le code: \"$query\"...';
  }

  @override
  String listingDirectory(String path) {
    return 'Affichage du répertoire $path...';
  }

  @override
  String findingSymbols(String query) {
    return 'Recherche de symboles: \"$query\"...';
  }

  @override
  String searchingWeb(String query) {
    return 'Recherche sur le web: \"$query\"...';
  }

  @override
  String fetchingWebPage(String path) {
    return 'Téléchargement de la page web: $path...';
  }

  @override
  String get executingAction => 'Exécution de l\'action...';

  @override
  String runningCommandLabel(String command) {
    return '🤖 Exécution de la commande: $command...';
  }

  @override
  String applyingChangeLabel(String path) {
    return '🤖 Application du changement: $path...';
  }

  @override
  String commandSentToTerminalLabel(String command) {
    return '🤖 Commande \"$command\" envoyée au terminal.';
  }

  @override
  String runningCommandResultLabel(String command, String result) {
    return 'Commande \"$command\" exécutée. Résultat:\n$result';
  }

  @override
  String fileNotFound(String path) {
    return 'Fichier non trouvé: $path';
  }

  @override
  String fileContentsHeader(String path, int lineCount, String truncated) {
    return 'Contenu du fichier `$path` ($lineCount lignes):\n\n```\n$truncated\n```';
  }

  @override
  String fileTruncatedSuffix(int lineCount) {
    return '... [tronqué à 8000 caractères de $lineCount lignes]';
  }

  @override
  String get safetyGuardFileOutsideWorkspace =>
      'Erreur: Tentative de modification de fichier en dehors de la portée du projet.';

  @override
  String get commandRefPathOutsideWorkspace =>
      'Erreur de sécurité: La commande fait référence à un chemin en dehors de la portée du projet.';

  @override
  String commandBlockedUnsafe(String blocked) {
    return 'Erreur de sécurité: La commande contient une instruction bloquée \"$blocked\".';
  }

  @override
  String aiSearchNoMatches(String query) {
    return 'Aucune correspondance trouvée pour \"$query\".';
  }

  @override
  String aiSearchMatchesFound(int matchCount, String query, String results) {
    return 'Trouvé $matchCount correspondances pour \"$query\":\n\n$results';
  }

  @override
  String searchSymbolsNoMatches(String query) {
    return 'Aucun symbole trouvé correspondant à \"$query\".';
  }

  @override
  String searchSymbolsMatchesFound(int count, String query, String results) {
    return 'Trouvé $count symboles correspondant à \"$query\":\n\n$results';
  }

  @override
  String searchSymbolsItem(String type, String name, String path, int line) {
    return '- [$type] $name (fichier: $path, ligne: $line)';
  }

  @override
  String directoryNotFound(String path) {
    return 'Répertoire non trouvé: $path';
  }

  @override
  String get directoryEmpty => 'Le répertoire est vide.';

  @override
  String directoryContentsHeader(String items) {
    return 'Contenu du répertoire:\n\n$items';
  }

  @override
  String get mcpMissingParams =>
      'Erreur: Le nom du serveur MCP ou de l\'outil n\'est pas spécifié.';

  @override
  String unknownAction(String type) {
    return 'Type d\'action inconnu: $type';
  }

  @override
  String failedToApplyActionWithError(String error) {
    return 'Échec de l\'application de l\'action: $error';
  }

  @override
  String get searchQueryEmpty => 'Erreur: La requête de recherche est vide.';

  @override
  String get workspaceNotFound => 'Erreur: Espace de travail introuvable.';

  @override
  String get webPreviewStopped => 'Aperçu Web arrêté';

  @override
  String get webPreviewStartInstructions =>
      'Démarrez le serveur et cliquez sur le bouton de lecture.';
}
