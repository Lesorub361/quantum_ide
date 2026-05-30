// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'QuantumIDE';

  @override
  String get explorer => 'Explorer';

  @override
  String get newFile => 'New File';

  @override
  String get newFolder => 'New Folder';

  @override
  String get refresh => 'Refresh';

  @override
  String get rename => 'Rename';

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get create => 'Create';

  @override
  String get projectNotOpened => 'Project not opened';

  @override
  String get selectFileToStart =>
      'Select a file in the explorer to start working';

  @override
  String get openExplorer => 'Open Explorer';

  @override
  String get confirmDelete => 'Confirm Delete';

  @override
  String areYouSureDelete(String name) {
    return 'Are you sure you want to delete $name?';
  }

  @override
  String get terminal => 'Terminal';

  @override
  String get run => 'Run';

  @override
  String get build => 'Build';

  @override
  String get aiAgent => 'AI Agent';

  @override
  String get servers => 'Servers';

  @override
  String get buildLogs => 'Build logs';

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
  String get settings => 'Settings';

  @override
  String get interfaceAndLocalization => 'Interface & Localization';

  @override
  String get language => 'Language';

  @override
  String get theme => 'Theme';

  @override
  String get darkTheme => 'Dark Theme';

  @override
  String get lightTheme => 'Light Theme';

  @override
  String get colorPalette => 'Color Palette';

  @override
  String get customColor => 'Custom Color';

  @override
  String get accentColor => 'Accent Color';

  @override
  String get projectIcon => 'Project Icon';

  @override
  String get defaultAccent => 'Default';

  @override
  String get codeEditor => 'Code Editor';

  @override
  String get editorFontSize => 'Editor Font Size';

  @override
  String get autoCompletion => 'Auto-completion';

  @override
  String get showCodeHints => 'Show code hints';

  @override
  String get aiAutoCompletion => 'AI Auto-completion';

  @override
  String get geminiCodeGeneration => 'Gemini code generation';

  @override
  String get wordWrap => 'Word Wrap';

  @override
  String get wordWrapDescription => 'Soft wrap lines in editor';

  @override
  String get lineNumbers => 'Line Numbers';

  @override
  String get showLineNumbers => 'Show line numbers';

  @override
  String get minimap => 'Minimap';

  @override
  String get showMinimap => 'Show editor minimap';

  @override
  String get autoSave => 'Auto-save';

  @override
  String get autoSaveDescription => 'Save changes after 2s';

  @override
  String get terminalFontSize => 'Terminal Font Size';

  @override
  String get terminalTheme => 'Terminal Theme';

  @override
  String get toolsAndAi => 'Tools & AI';

  @override
  String get aiProviders => 'AI Providers';

  @override
  String get aiProvidersSubtitle => 'Gemini, OpenAI, Ollama etc.';

  @override
  String get ubuntuPackages => 'Ubuntu Packages';

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
  String get aboutApp => 'About App';

  @override
  String get aboutAppSubtitle => 'Quantum IDE v1.0.0';

  @override
  String get selectPalette => 'Select Palette';

  @override
  String get close => 'Close';

  @override
  String get resetToDefault => 'Reset to Default';

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
  String get noProjects => 'No projects';

  @override
  String get nothingFound => 'Nothing found';

  @override
  String get createFirstProject => 'Create first project';

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
  String get projectSettings => 'Project Settings';

  @override
  String get createProject => 'Create Project';

  @override
  String get projectName => 'Project Name';

  @override
  String get projectType => 'PROJECT TYPE';

  @override
  String get androidCompileSdkVersion => 'ANDROID compileSdk VERSION';

  @override
  String get defaultSdkVersion => 'Default: 35';

  @override
  String get targetPlatforms => 'TARGET DEVICES / PLATFORMS';

  @override
  String get saveAction => 'Save';

  @override
  String get code => 'Code';

  @override
  String get preview => 'Preview';

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
  String get send => 'Send';

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
  String get problems => 'Problems';

  @override
  String get packages => 'Packages';

  @override
  String get tools => 'Tools';

  @override
  String get searchFiles => 'Search files...';

  @override
  String get imageLoadError => 'Error loading image';

  @override
  String get unsaved => 'Unsaved';

  @override
  String get saved => 'Saved';

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
  String get glassmorphismEffects => 'Glassmorphism Effects';

  @override
  String get glassOpacity => 'Glass Opacity';

  @override
  String get backdropBlur => 'Backdrop Blur';

  @override
  String get editorFontFamily => 'Editor Font Family';

  @override
  String get fontLigatures => 'Font Ligatures';

  @override
  String get fontLigaturesDescription =>
      'Enable font ligatures in code (e.g., -> or !=)';

  @override
  String get selectFontFamily => 'Select Font Family';

  @override
  String get selectLanguage => 'Select Language';

  @override
  String get format => 'Format';

  @override
  String get liveShare => 'Live Share';

  @override
  String get hostSession => 'Host Session';

  @override
  String get joinSession => 'Join Session';

  @override
  String get stopSession => 'Stop Session';

  @override
  String get disconnectSession => 'Disconnect';

  @override
  String get sessionActive => 'Session Active';

  @override
  String get hostingAt => 'Hosting at:';

  @override
  String get connectedTo => 'Connected to:';

  @override
  String get userName => 'Your Name';

  @override
  String get usersList => 'Participants';

  @override
  String get messagePlaceholder => 'Type a message...';

  @override
  String get connectError => 'Connection error';

  @override
  String get invalidAddress => 'Invalid address';

  @override
  String get joinLink => 'Session IP address';

  @override
  String get localIps => 'Local IPs:';

  @override
  String get wasmPlugins => 'WASM Plugins';

  @override
  String get installPlugin => 'Install Plugin (.wasm)';

  @override
  String get noPluginsInstalled => 'No WASM plugins installed';

  @override
  String get pluginEnabled => 'Plugin enabled';

  @override
  String get pluginDisabled => 'Plugin disabled';

  @override
  String get runWasmAction => 'Run WASM Action';

  @override
  String get noActiveSelection => 'No text selected. Apply to the entire file?';

  @override
  String get applyToSelection => 'Apply to Selection';

  @override
  String get applyToDocument => 'Apply to Document';

  @override
  String get logs => 'Logs';

  @override
  String get clearLogs => 'Clear Logs';

  @override
  String get deletePlugin => 'Delete Plugin';

  @override
  String get resetToDefaults => 'Reset to Defaults';

  @override
  String get welcomeTitle => 'Welcome!';

  @override
  String get welcomeSubtitle =>
      'Choose a project to work on or create a new one';

  @override
  String get lastActiveProject => 'Last Active Project';

  @override
  String get runTooltip => 'Run';

  @override
  String get actionsTooltip => 'Actions';

  @override
  String get packagesTooltip => 'Packages';

  @override
  String get extensionsAndTools => 'Extensions & Tools';

  @override
  String get searchExtensionsHint => 'Search extensions...';

  @override
  String get searchPubdevHint => 'Search libraries on pub.dev (e.g., dio)...';

  @override
  String get tabAll => 'All';

  @override
  String get tabInstalled => 'Installed';

  @override
  String get tabLanguagesAndAi => 'Languages & AI';

  @override
  String get tabTools => 'Tools';

  @override
  String get tabBuild => 'Build';

  @override
  String get tabSdkPlatforms => 'SDK Platforms';

  @override
  String get tabPubLibraries => 'Pub Libraries';

  @override
  String get readyToBuildApk => 'Ready to build APK?';

  @override
  String get installAndroidSdkJava => 'Install Android SDK & Java 17';

  @override
  String get sdkSetupDescription =>
      'This will setup SDK, compilers, zipalign, apksigner, optimize Gradle network settings and prepare your environment for compiling projects.';

  @override
  String get initializingDevEnvironment =>
      'Initializing development environment...';

  @override
  String get viewAction => 'View';

  @override
  String get startSdkSetup => 'Start environment setup';

  @override
  String get buildIssues => 'Build issues?';

  @override
  String get restoreAndroidGradleEnv => 'Restore Android & Gradle environment';

  @override
  String get wrenchFixDescription =>
      'Automatically fixes AAPT2 daemon errors, sets correct project permissions, restores the resource compiler binary, and configures Gradle threads.';

  @override
  String get runningWrenchFix => 'Running build environment fix...';

  @override
  String get startWrenchFix => 'Run fix (Wrench Fix)';

  @override
  String get statusInstalledCaps => 'INSTALLED';

  @override
  String get reinstallOrUpdateTooltip => 'Reinstall / Update';

  @override
  String updatingPackage(String name) {
    return 'Updating $name...';
  }

  @override
  String installingPackage(String name) {
    return 'Installing $name...';
  }

  @override
  String get installAction => 'Install';

  @override
  String get searchPubdevTitle => 'Search Flutter libraries';

  @override
  String get searchPubdevDescription =>
      'Enter a library name (e.g. dio, bloc, riverpod) in the search field above and press Enter';

  @override
  String loadError(String error) {
    return 'Load error: $error';
  }

  @override
  String get addAction => 'Add';

  @override
  String get openProjectToInstallLibraries =>
      'Please open a project first to add libraries.';

  @override
  String installingLibrary(String name) {
    return 'Installing library $name...';
  }

  @override
  String importError(String error) {
    return 'Import error: $error';
  }

  @override
  String get filesImportedSuccessfully => 'Files successfully imported';

  @override
  String get dragFilesHereToImport => 'Drag files here to import';

  @override
  String selectedCount(int count) {
    return 'Selected: $count';
  }

  @override
  String get selectAllTooltip => 'Select All';

  @override
  String get copyTooltip => 'Copy';

  @override
  String copiedCount(int count) {
    return 'Copied objects: $count';
  }

  @override
  String get cutTooltip => 'Cut';

  @override
  String cutCount(int count) {
    return 'Cut objects: $count';
  }

  @override
  String get zipTooltip => 'Compress to ZIP';

  @override
  String get deleteTooltip => 'Delete';

  @override
  String foldersCount(int count) {
    return 'Folders: $count';
  }

  @override
  String get askAiAction => 'Ask AI';

  @override
  String get explainAiAction => 'AI: Explain';

  @override
  String get documentAiAction => 'AI: Document';

  @override
  String get testAiAction => 'AI: Generate Tests';

  @override
  String get optimizeAiAction => 'AI: Optimize';

  @override
  String pasteCount(int count) {
    return 'Paste ($count)';
  }

  @override
  String get archiveNameHint => 'Archive name';

  @override
  String get compressAction => 'Compress';

  @override
  String get archiveCreatedSuccessfully => 'Archive successfully created!';

  @override
  String compressionError(String error) {
    return 'Compression error: $error';
  }

  @override
  String get archiveExtractedSuccessfully => 'Archive successfully extracted!';

  @override
  String extractionError(String error) {
    return 'Extraction error: $error';
  }

  @override
  String get deleteSelectedTitle => 'Delete selected?';

  @override
  String deleteSelectedConfirmation(int count) {
    return 'Are you sure you want to delete $count items?';
  }

  @override
  String get selectedElementsDeleted => 'Selected items deleted!';

  @override
  String deleteError(String error) {
    return 'Delete error: $error';
  }

  @override
  String get filesPastedSuccessfully => 'Files successfully pasted!';

  @override
  String pasteError(String error) {
    return 'Paste error: $error';
  }

  @override
  String get repositoryNotFound => 'Repository not found';

  @override
  String get initGitRepoDescription =>
      'Initialize a local Git repository to track changes.';

  @override
  String get initGitAction => 'Initialize Git';

  @override
  String get gitConflicted => 'CONFLICTS';

  @override
  String get gitStaged => 'STAGED';

  @override
  String get gitModified => 'MODIFIED';

  @override
  String get gitUntracked => 'UNTRACKED';

  @override
  String get commitMessageHint => 'Commit message...';

  @override
  String get resetChangesTitle => 'Reset changes?';

  @override
  String get resetChangesConfirmation =>
      'Are you sure you want to permanently reset all uncommitted changes in this file?';

  @override
  String get resetAction => 'Reset';

  @override
  String get changesReset => 'Changes reset';

  @override
  String resetError(String error) {
    return 'Reset error: $error';
  }

  @override
  String get normalView => 'Normal view';

  @override
  String get splitView => 'Split view (Side-by-Side)';

  @override
  String get stagedMessage => 'File staged';

  @override
  String get unstagedMessage => 'File unstaged';

  @override
  String stageError(String error) {
    return 'Staging error: $error';
  }

  @override
  String get failedToLoadChanges => 'Failed to load changes';

  @override
  String get noChanges => 'No changes';

  @override
  String get fileIdenticalToHead => 'This file is identical to HEAD';

  @override
  String get runTerminalTooltip => 'Run';

  @override
  String get restartTerminalTooltip => 'Restart';

  @override
  String get consoleSubTab => 'Console';

  @override
  String get signApkSubTab => 'Sign APK';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get back => 'Back';

  @override
  String get tryChangingSearchQuery => 'Try changing search query';

  @override
  String get incomingBranch => 'Incoming branch';

  @override
  String get resolveConflictsBeforeSaving =>
      'Please resolve all conflicts before saving!';

  @override
  String get fileSavedAndStaged =>
      'File successfully saved and staged to Git index';

  @override
  String saveError(String error) {
    return 'Error saving: $error';
  }

  @override
  String get acceptMerge => 'Accept Merge';

  @override
  String get errorLoadingConflictFile => 'Error loading conflict file';

  @override
  String get conflictsNotFound => 'Conflicts not found';

  @override
  String get noConflictMarkersFound =>
      'No standard Git merge markers found in this file.';

  @override
  String get backToGit => 'Back to Git';

  @override
  String get conflictBlock => 'Conflict block';

  @override
  String get currentChangesOurs => 'Current changes (Ours / HEAD)';

  @override
  String incomingChanges(String branch) {
    return 'Incoming changes ($branch)';
  }

  @override
  String get useThisVersion => 'Use this version';

  @override
  String get mergeResultEditable => 'Merge result (Editable)';

  @override
  String get chooseVersionOrWriteHint =>
      'Choose one of the versions above or write your own merge resolution...';

  @override
  String get markAsResolvedHint =>
      '* To mark this block as resolved, enter or choose text.';

  @override
  String get emptyLabel => '(Empty)';

  @override
  String get stageAction => 'Stage';

  @override
  String get unstageAction => 'Unstage';

  @override
  String get cursorColor => 'CURSOR COLOR';

  @override
  String get or => 'OR';

  @override
  String get ipCopiedToClipboard => 'IP copied to clipboard';

  @override
  String editingFile(String file) {
    return 'Editing: $file';
  }

  @override
  String get viewingProject => 'Viewing project';

  @override
  String get noProblemsFound => 'No problems found in workspace';

  @override
  String get problemsList => 'Problems List';

  @override
  String get sendToAi => 'Send to AI';

  @override
  String get helpMeFixErrors =>
      'Please help me fix the following compilation errors in my project:';

  @override
  String lineColumn(int line, int col) {
    return 'Line $line, Column $col';
  }

  @override
  String get decreaseFontSize => 'Decrease Font Size';

  @override
  String get increaseFontSize => 'Increase Font Size';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get moveLeft => 'Move Left';

  @override
  String get moveUp => 'Move Up';

  @override
  String get moveDown => 'Move Down';

  @override
  String get moveRight => 'Move Right';

  @override
  String get edit => 'Edit';

  @override
  String get packagesAndEnv => 'Packages & Env';

  @override
  String packagesInstalledCount(int count, int total) {
    return 'Installed: $count/$total';
  }

  @override
  String get flutterProject => 'Flutter Project';

  @override
  String get pythonProject => 'Python Project';

  @override
  String get nodejsProject => 'Node.js Project';

  @override
  String get dartProject => 'Dart Project';

  @override
  String get webProject => 'Web Project';

  @override
  String get androidProject => 'Android Project';

  @override
  String get genericProject => 'Project';

  @override
  String get runPC => 'Run (PC)';

  @override
  String get runMob => 'Run (Mob)';

  @override
  String get startServer => 'Start Server';

  @override
  String get buildAPK => 'Build APK';

  @override
  String get startTheProject => 'Start the project';

  @override
  String get outputCopied => 'Output copied';

  @override
  String get console => 'Console';

  @override
  String get signApk => 'Sign APK';

  @override
  String get buildPC => 'Build (PC)';

  @override
  String get resetPlugins => 'Reset Plugins';

  @override
  String get resetPluginsConfirmation =>
      'This will remove all installed custom plugins and restore default plugins. Continue?';

  @override
  String get resetPluginsTitle => 'Reset Plugins?';

  @override
  String get installWasm => 'Install .wasm';

  @override
  String get availableActions => 'Available Actions:';

  @override
  String get logsTerminal => 'Logs Terminal';

  @override
  String get noLogsCaptured => 'No logs captured yet';

  @override
  String get installWasmPluginTitle => 'Install WASM Plugin';

  @override
  String get selectWasmFile => 'Select .wasm file';

  @override
  String get pluginName => 'Plugin Name';

  @override
  String get nameRequired => 'Name is required';

  @override
  String get pluginDescription => 'Description';

  @override
  String get descriptionRequired => 'Description is required';

  @override
  String get exposedActions => 'Exposed Actions';

  @override
  String get add => 'Add';

  @override
  String get pickWasmFileFirst => 'Please pick a .wasm file first';

  @override
  String get pluginInstalledSuccessfully => 'Plugin installed successfully';

  @override
  String failedToInstall(String error) {
    return 'Failed to install: $error';
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
  String get search => 'Search';

  @override
  String get structure => 'Structure';

  @override
  String get disk => 'Disk';

  @override
  String get plugins => 'Plugins';

  @override
  String get added => 'added';

  @override
  String get removed => 'removed';

  @override
  String get modified => 'modified';

  @override
  String selectedObjectsCount(int count) {
    return 'Selected objects: $count';
  }

  @override
  String get explainFolderPreset =>
      'Explain the purpose and structure of this folder.';

  @override
  String get explainFilePreset =>
      'Explain in detail the purpose and operational logic of this file.';

  @override
  String get addDocFolderPreset =>
      'Add documentation, docstrings, and detailed comments to the code in all files of this folder.';

  @override
  String get addDocFilePreset =>
      'Add clear documentation, docstrings, and detailed comments to the code in this file.';

  @override
  String get generateTestsFolderPreset =>
      'Write unit tests for the files in this folder.';

  @override
  String get generateTestsFilePreset =>
      'Write comprehensive unit tests for the code in this file.';

  @override
  String get optimizeFolderPreset =>
      'Analyze the code in this folder and suggest optimizations for performance and readability.';

  @override
  String get optimizeFilePreset =>
      'Analyze the code in this file and suggest options for optimizing performance, readability, and architecture.';

  @override
  String get deleteSelected => 'Delete Selected';

  @override
  String get manual => 'Manual';

  @override
  String get autoSafe => 'Auto:Safe';

  @override
  String get autoFull => 'Auto:Full';

  @override
  String filesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'files',
      one: 'file',
    );
    return '$count $_temp0';
  }

  @override
  String get localAiEngineTitle => 'LOCAL AI ENGINE';

  @override
  String get ollamaRunningLocally => 'Ollama is running locally';

  @override
  String get ollamaRunningLocallyDesc =>
      'Make sure Ollama is running on your system. You can start it with \"ollama serve\" and pull models with \"ollama pull <model>\".';

  @override
  String get lmStudioRunningLocally => 'LM Studio is running locally';

  @override
  String get lmStudioRunningLocallyDesc =>
      'Make sure LM Studio server is running. You can enable Local Server in the LM Studio application and load the required model.';

  @override
  String get ollamaNotDetected => 'Ollama not detected';

  @override
  String get ollamaNotDetectedDesc =>
      'Install Ollama on your device and make sure it is running. The URL can be modified above.';

  @override
  String get checkConnection => 'Check Connection';

  @override
  String get availableOllamaModels => 'AVAILABLE OLLAMA MODELS';

  @override
  String get llamaServerInstallRequired => 'llama-server Installation Required';

  @override
  String get llamaServerInstallRequiredDesc =>
      'Llama-server engine is required to run local AI models. Click the button below to install it automatically.';

  @override
  String get installing => 'Installing...';

  @override
  String get installLlamaServerRuntime => 'Install Llama Server Runtime';

  @override
  String get ollamaModelsTitle => 'OLLAMA MODELS';

  @override
  String get localAiModelsTitle => 'LOCAL AI MODELS';

  @override
  String get serverStatusAndControl => 'SERVER STATUS & CONTROL';

  @override
  String get downloadOllamaModelPrompt =>
      'Download at least one Ollama model to get started.';

  @override
  String get downloadModelToStartServerPrompt =>
      'Download at least one model above to launch the local server.';

  @override
  String get localLlamaServerLabel => 'Local llama-server';

  @override
  String get connected => 'Connected';

  @override
  String get runningPort8080 => 'Running (port 8080)';

  @override
  String get starting => 'Starting...';

  @override
  String get stopped => 'Stopped';

  @override
  String get start => 'Start';

  @override
  String gbFormat(String size) {
    return '$size GB';
  }

  @override
  String ramGbFormat(String size) {
    return '~$size GB RAM';
  }

  @override
  String get select => 'Select';

  @override
  String get download => 'Download';

  @override
  String get refreshPreview => 'Refresh Preview';

  @override
  String inFolder(String folder) {
    return 'in $folder';
  }

  @override
  String get llamaServerBuiltIn => 'llama-server (built-in)';

  @override
  String get localAiDisplayName => 'Local AI';

  @override
  String get notRequired => 'not required';

  @override
  String get mcpGithubDesc =>
      'Integration with GitHub repositories, issues, and PRs.';

  @override
  String get mcpGoogleSearchDesc =>
      'Allows the AI agent to perform live Google searches.';

  @override
  String get mcpFetchDesc =>
      'Download web pages and automatically translate them to Markdown.';

  @override
  String get mcpPostgresDesc =>
      'Connect, read table structure, and run SQL queries on PostgreSQL.';

  @override
  String get mcpPostgresArg => 'Connection string (postgresql://...)';

  @override
  String get mcpSqliteDesc =>
      'Connect and inspect SQLite databases in your project.';

  @override
  String get mcpSqliteArg => 'Path to SQLite DB file (e.g. db.sqlite)';

  @override
  String get mcpMemoryDesc =>
      'Semantic long-term memory storage for your AI agent.';

  @override
  String get mcpBraveSearchDesc =>
      'Allows the AI agent to perform web searches using the Brave API.';

  @override
  String get mcpPuppeteerDesc =>
      'Browser automation, screenshot generation, element clicking, and web scraping.';

  @override
  String get mcpFirecrawlDesc =>
      'Convert any website into clean Markdown or structured JSON.';

  @override
  String get mcpNotionDesc =>
      'Read and modify Notion pages, databases, and comments.';

  @override
  String get mcpSlackDesc =>
      'Provides the ability to read channels, chat, and send notifications in Slack.';

  @override
  String get mcpGitDesc =>
      'View commits, compare versions, search commits, and inspect files locally via Git.';

  @override
  String get mcpGitlabDesc =>
      'Manage GitLab projects, issues, PRs, and CI/CD pipelines.';

  @override
  String get mcpSentryDesc =>
      'Retrieve error logs and inspect crashes of your application on Sentry.';

  @override
  String get mcpAirtableDesc =>
      'Read, create, and update records in Airtable databases and tables.';

  @override
  String get mcpSequentialThinkingDesc =>
      'Organize AI agent thoughts for structured problem solving.';

  @override
  String get phantomProcessesTitle => 'Phantom Processes (Android 12/13+)';

  @override
  String get phantomProcessesVersion =>
      'ADB configuration required for stable compilation';

  @override
  String get phantomProcessesError =>
      'In Android 12+, the system process killer (Phantom Process Killer) terminates builds (Gradle/Java/Node/Dart) if the limit exceeds 32 active processes.\n\nTo disable, run via ADB on your PC:\n\nadb shell \"/system/bin/device_config put activity_manager max_phantom_processes 2147483647\"\n\nadb shell \"/system/bin/settings put global settings_enable_monitor_phantom_procs false\"';

  @override
  String androidJarCorruptError(String api) {
    return 'android.jar is corrupt ($api). Click \"Fix Environment\" to reinstall.';
  }

  @override
  String get androidSdkPlatformsHealthy => 'android-35 / android-36 — healthy';

  @override
  String checkFailed(String error) {
    return 'Check failed: $error';
  }

  @override
  String get analyzingTaskAndPlanning => 'Analyzing task & planning...';

  @override
  String agentStepLimitExceeded(int limit) {
    return '🤖 Agent step limit ($limit) exceeded. Autopilot stopped.';
  }

  @override
  String get generatingCodeChanges => 'Generating code changes...';

  @override
  String get executionPlanConstructed =>
      '📝 Execution plan constructed. Transitioning to Coder role...';

  @override
  String get verifyingImplementation =>
      'Verifying implementation correctness...';

  @override
  String blockedUnsafeActions(String blockedText) {
    return '❌ Blocked unsafe actions outside workspace scope:\n$blockedText';
  }

  @override
  String get awaitingApprovalHighRisk =>
      '⚠️ Awaiting approval: High-risk actions detected or autopilot is restricted. Please approve them in the AI panel.';

  @override
  String autopilotStepSummary(
    int step,
    String actionsListText,
    String results,
  ) {
    return '🤖 Autopilot (step $step): Auto-Approval of actions:\n$actionsListText\n\nResults:\n$results';
  }

  @override
  String get runningStaticAnalysis =>
      'Running project static analysis (dart analyze)...';

  @override
  String agentFailedToFixErrors(int maxAttempts, String errorReport) {
    return '⚠️ Agent failed to fix errors after $maxAttempts attempts.\n\n**Remaining errors:**\n$errorReport\n\nPlease describe the issue or fix manually.';
  }

  @override
  String get fixingCompilationErrors => 'Fixing compilation errors...';

  @override
  String readingFile(String path) {
    return 'Reading file $path...';
  }

  @override
  String savingFile(String path) {
    return 'Saving file $path...';
  }

  @override
  String deletingFile(String path) {
    return 'Deleting file $path...';
  }

  @override
  String runningCommandStatus(String command) {
    return 'Running command \"$command\"...';
  }

  @override
  String searchingCode(String query) {
    return 'Searching code: \"$query\"...';
  }

  @override
  String listingDirectory(String path) {
    return 'Listing directory $path...';
  }

  @override
  String findingSymbols(String query) {
    return 'Finding symbols: \"$query\"...';
  }

  @override
  String searchingWeb(String query) {
    return 'Searching web: \"$query\"...';
  }

  @override
  String fetchingWebPage(String path) {
    return 'Fetching web page: $path...';
  }

  @override
  String get executingAction => 'Executing action...';

  @override
  String runningCommandLabel(String command) {
    return '🤖 Running command: $command...';
  }

  @override
  String applyingChangeLabel(String path) {
    return '🤖 Applying change: $path...';
  }

  @override
  String commandSentToTerminalLabel(String command) {
    return '🤖 Command \"$command\" sent to terminal.';
  }

  @override
  String runningCommandResultLabel(String command, String result) {
    return 'Command \"$command\" executed. Result:\n$result';
  }

  @override
  String fileNotFound(String path) {
    return 'File not found: $path';
  }

  @override
  String fileContentsHeader(String path, int lineCount, String truncated) {
    return 'File contents of `$path` ($lineCount lines):\n\n```\n$truncated\n```';
  }

  @override
  String fileTruncatedSuffix(int lineCount) {
    return '... [truncated to 8000 chars from $lineCount lines]';
  }

  @override
  String get safetyGuardFileOutsideWorkspace =>
      'Error: Attempted file modification outside the project scope.';

  @override
  String get commandRefPathOutsideWorkspace =>
      'Security error: Command references path outside project scope.';

  @override
  String commandBlockedUnsafe(String blocked) {
    return 'Security error: Command contains blocked instruction \"$blocked\".';
  }

  @override
  String aiSearchNoMatches(String query) {
    return 'No matches found for \"$query\".';
  }

  @override
  String aiSearchMatchesFound(int matchCount, String query, String results) {
    return 'Found $matchCount matches for \"$query\":\n\n$results';
  }

  @override
  String searchSymbolsNoMatches(String query) {
    return 'No symbols found matching \"$query\".';
  }

  @override
  String searchSymbolsMatchesFound(int count, String query, String results) {
    return 'Found $count symbols matching \"$query\":\n\n$results';
  }

  @override
  String searchSymbolsItem(String type, String name, String path, int line) {
    return '- [$type] $name (file: $path, line: $line)';
  }

  @override
  String directoryNotFound(String path) {
    return 'Directory not found: $path';
  }

  @override
  String get directoryEmpty => 'Directory is empty.';

  @override
  String directoryContentsHeader(String items) {
    return 'Directory contents:\n\n$items';
  }

  @override
  String get mcpMissingParams =>
      'Error: MCP server or tool name is not specified.';

  @override
  String unknownAction(String type) {
    return 'Unknown action type: $type';
  }

  @override
  String failedToApplyActionWithError(String error) {
    return 'Failed to apply action: $error';
  }

  @override
  String get searchQueryEmpty => 'Error: Search query is empty.';

  @override
  String get workspaceNotFound => 'Error: Workspace not found.';

  @override
  String get webPreviewStopped => 'Web Preview Stopped';

  @override
  String get webPreviewStartInstructions =>
      'Start server and click Play button.';
}
