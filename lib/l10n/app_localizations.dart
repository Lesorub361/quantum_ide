import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'QuantumIDE'**
  String get appTitle;

  /// No description provided for @explorer.
  ///
  /// In en, this message translates to:
  /// **'Explorer'**
  String get explorer;

  /// No description provided for @newFile.
  ///
  /// In en, this message translates to:
  /// **'New File'**
  String get newFile;

  /// No description provided for @newFolder.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get newFolder;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @projectNotOpened.
  ///
  /// In en, this message translates to:
  /// **'Project not opened'**
  String get projectNotOpened;

  /// No description provided for @selectFileToStart.
  ///
  /// In en, this message translates to:
  /// **'Select a file in the explorer to start working'**
  String get selectFileToStart;

  /// No description provided for @openExplorer.
  ///
  /// In en, this message translates to:
  /// **'Open Explorer'**
  String get openExplorer;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Confirm Delete'**
  String get confirmDelete;

  /// No description provided for @areYouSureDelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete {name}?'**
  String areYouSureDelete(String name);

  /// No description provided for @terminal.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get terminal;

  /// No description provided for @run.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get run;

  /// No description provided for @build.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get build;

  /// No description provided for @aiAgent.
  ///
  /// In en, this message translates to:
  /// **'AI Agent'**
  String get aiAgent;

  /// No description provided for @servers.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get servers;

  /// No description provided for @buildLogs.
  ///
  /// In en, this message translates to:
  /// **'Build Logs'**
  String get buildLogs;

  /// No description provided for @appLogs.
  ///
  /// In en, this message translates to:
  /// **'App Logs'**
  String get appLogs;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @hotReload.
  ///
  /// In en, this message translates to:
  /// **'Hot Reload'**
  String get hotReload;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @runProject.
  ///
  /// In en, this message translates to:
  /// **'Run Project'**
  String get runProject;

  /// No description provided for @pubGet.
  ///
  /// In en, this message translates to:
  /// **'Pub Get'**
  String get pubGet;

  /// No description provided for @setupSdk.
  ///
  /// In en, this message translates to:
  /// **'Setup SDK'**
  String get setupSdk;

  /// No description provided for @clean.
  ///
  /// In en, this message translates to:
  /// **'Clean'**
  String get clean;

  /// No description provided for @buildApk.
  ///
  /// In en, this message translates to:
  /// **'Build APK'**
  String get buildApk;

  /// No description provided for @welcomeMessage.
  ///
  /// In en, this message translates to:
  /// **'Welcome to your premium environment.'**
  String get welcomeMessage;

  /// No description provided for @typeRunToStart.
  ///
  /// In en, this message translates to:
  /// **'Type run to start your project.'**
  String get typeRunToStart;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @interfaceAndLocalization.
  ///
  /// In en, this message translates to:
  /// **'Interface & Localization'**
  String get interfaceAndLocalization;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @darkTheme.
  ///
  /// In en, this message translates to:
  /// **'Dark Theme'**
  String get darkTheme;

  /// No description provided for @lightTheme.
  ///
  /// In en, this message translates to:
  /// **'Light Theme'**
  String get lightTheme;

  /// No description provided for @colorPalette.
  ///
  /// In en, this message translates to:
  /// **'Color Palette'**
  String get colorPalette;

  /// No description provided for @customColor.
  ///
  /// In en, this message translates to:
  /// **'Custom Color'**
  String get customColor;

  /// No description provided for @accentColor.
  ///
  /// In en, this message translates to:
  /// **'Accent Color'**
  String get accentColor;

  /// No description provided for @projectIcon.
  ///
  /// In en, this message translates to:
  /// **'Project Icon'**
  String get projectIcon;

  /// No description provided for @defaultAccent.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultAccent;

  /// No description provided for @codeEditor.
  ///
  /// In en, this message translates to:
  /// **'Code Editor'**
  String get codeEditor;

  /// No description provided for @editorFontSize.
  ///
  /// In en, this message translates to:
  /// **'Editor Font Size'**
  String get editorFontSize;

  /// No description provided for @autoCompletion.
  ///
  /// In en, this message translates to:
  /// **'Auto-completion'**
  String get autoCompletion;

  /// No description provided for @showCodeHints.
  ///
  /// In en, this message translates to:
  /// **'Show code hints'**
  String get showCodeHints;

  /// No description provided for @aiAutoCompletion.
  ///
  /// In en, this message translates to:
  /// **'AI Auto-completion'**
  String get aiAutoCompletion;

  /// No description provided for @geminiCodeGeneration.
  ///
  /// In en, this message translates to:
  /// **'Gemini code generation'**
  String get geminiCodeGeneration;

  /// No description provided for @wordWrap.
  ///
  /// In en, this message translates to:
  /// **'Word Wrap'**
  String get wordWrap;

  /// No description provided for @wordWrapDescription.
  ///
  /// In en, this message translates to:
  /// **'Soft wrap lines in editor'**
  String get wordWrapDescription;

  /// No description provided for @lineNumbers.
  ///
  /// In en, this message translates to:
  /// **'Line Numbers'**
  String get lineNumbers;

  /// No description provided for @showLineNumbers.
  ///
  /// In en, this message translates to:
  /// **'Show line numbers'**
  String get showLineNumbers;

  /// No description provided for @minimap.
  ///
  /// In en, this message translates to:
  /// **'Minimap'**
  String get minimap;

  /// No description provided for @showMinimap.
  ///
  /// In en, this message translates to:
  /// **'Show editor minimap'**
  String get showMinimap;

  /// No description provided for @autoSave.
  ///
  /// In en, this message translates to:
  /// **'Auto-save'**
  String get autoSave;

  /// No description provided for @autoSaveDescription.
  ///
  /// In en, this message translates to:
  /// **'Save changes after 2s'**
  String get autoSaveDescription;

  /// No description provided for @terminalFontSize.
  ///
  /// In en, this message translates to:
  /// **'Terminal Font Size'**
  String get terminalFontSize;

  /// No description provided for @terminalTheme.
  ///
  /// In en, this message translates to:
  /// **'Terminal Theme'**
  String get terminalTheme;

  /// No description provided for @toolsAndAi.
  ///
  /// In en, this message translates to:
  /// **'Tools & AI'**
  String get toolsAndAi;

  /// No description provided for @aiProviders.
  ///
  /// In en, this message translates to:
  /// **'AI Providers'**
  String get aiProviders;

  /// No description provided for @aiProvidersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Gemini, OpenAI, Ollama etc.'**
  String get aiProvidersSubtitle;

  /// No description provided for @ubuntuPackages.
  ///
  /// In en, this message translates to:
  /// **'Ubuntu Packages'**
  String get ubuntuPackages;

  /// No description provided for @manageCliTools.
  ///
  /// In en, this message translates to:
  /// **'Manage CLI tools'**
  String get manageCliTools;

  /// No description provided for @hosts.
  ///
  /// In en, this message translates to:
  /// **'Hosts'**
  String get hosts;

  /// No description provided for @localRemoteHosts.
  ///
  /// In en, this message translates to:
  /// **'Local/remote hosts'**
  String get localRemoteHosts;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @showHiddenFiles.
  ///
  /// In en, this message translates to:
  /// **'Show Hidden Files'**
  String get showHiddenFiles;

  /// No description provided for @showHiddenFilesDescription.
  ///
  /// In en, this message translates to:
  /// **'Show .* files'**
  String get showHiddenFilesDescription;

  /// No description provided for @vibration.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get vibration;

  /// No description provided for @hapticFeedback.
  ///
  /// In en, this message translates to:
  /// **'Haptic feedback'**
  String get hapticFeedback;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About App'**
  String get aboutApp;

  /// No description provided for @aboutAppSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Quantum IDE v1.0.0'**
  String get aboutAppSubtitle;

  /// No description provided for @selectPalette.
  ///
  /// In en, this message translates to:
  /// **'Select Palette'**
  String get selectPalette;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @resetToDefault.
  ///
  /// In en, this message translates to:
  /// **'Reset to Default'**
  String get resetToDefault;

  /// No description provided for @aboutDialogContent.
  ///
  /// In en, this message translates to:
  /// **'AI-powered mobile IDE built with Flutter.\n© 2026 Quantum IDE'**
  String get aboutDialogContent;

  /// No description provided for @ubuntuDarkPurple.
  ///
  /// In en, this message translates to:
  /// **'Ubuntu Dark Purple'**
  String get ubuntuDarkPurple;

  /// No description provided for @pureDark.
  ///
  /// In en, this message translates to:
  /// **'Pure Dark'**
  String get pureDark;

  /// No description provided for @searchProjects.
  ///
  /// In en, this message translates to:
  /// **'Search projects...'**
  String get searchProjects;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @market.
  ///
  /// In en, this message translates to:
  /// **'Market'**
  String get market;

  /// No description provided for @projectsHeader.
  ///
  /// In en, this message translates to:
  /// **'Projects ({count})'**
  String projectsHeader(int count);

  /// No description provided for @noProjects.
  ///
  /// In en, this message translates to:
  /// **'No projects'**
  String get noProjects;

  /// No description provided for @nothingFound.
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get nothingFound;

  /// No description provided for @createFirstProject.
  ///
  /// In en, this message translates to:
  /// **'Create first project'**
  String get createFirstProject;

  /// No description provided for @projectActions.
  ///
  /// In en, this message translates to:
  /// **'Project Actions'**
  String get projectActions;

  /// No description provided for @fixAndroidBuild.
  ///
  /// In en, this message translates to:
  /// **'Fix Android Build (AGP + compileSdk)'**
  String get fixAndroidBuild;

  /// No description provided for @patchAndroidBuildDescription.
  ///
  /// In en, this message translates to:
  /// **'Patch android-36 / AGP 8.7.3 / compileSdk 35'**
  String get patchAndroidBuildDescription;

  /// No description provided for @buildApkDescription.
  ///
  /// In en, this message translates to:
  /// **'flutter build apk --debug'**
  String get buildApkDescription;

  /// No description provided for @apkBuildFixed.
  ///
  /// In en, this message translates to:
  /// **'✅ Android build files fixed for \"{name}\"'**
  String apkBuildFixed(String name);

  /// No description provided for @confirmDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String confirmDeleteTitle(String name);

  /// No description provided for @confirmDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete only from the list or delete files as well?'**
  String get confirmDeleteMessage;

  /// No description provided for @deleteFromListOnly.
  ///
  /// In en, this message translates to:
  /// **'From list'**
  String get deleteFromListOnly;

  /// No description provided for @deleteFromDisk.
  ///
  /// In en, this message translates to:
  /// **'From disk'**
  String get deleteFromDisk;

  /// No description provided for @projectSettings.
  ///
  /// In en, this message translates to:
  /// **'Project Settings'**
  String get projectSettings;

  /// No description provided for @createProject.
  ///
  /// In en, this message translates to:
  /// **'Create Project'**
  String get createProject;

  /// No description provided for @projectName.
  ///
  /// In en, this message translates to:
  /// **'Project Name'**
  String get projectName;

  /// No description provided for @projectType.
  ///
  /// In en, this message translates to:
  /// **'PROJECT TYPE'**
  String get projectType;

  /// No description provided for @androidCompileSdkVersion.
  ///
  /// In en, this message translates to:
  /// **'ANDROID compileSdk VERSION'**
  String get androidCompileSdkVersion;

  /// No description provided for @defaultSdkVersion.
  ///
  /// In en, this message translates to:
  /// **'Default: 35'**
  String get defaultSdkVersion;

  /// No description provided for @targetPlatforms.
  ///
  /// In en, this message translates to:
  /// **'TARGET DEVICES / PLATFORMS'**
  String get targetPlatforms;

  /// No description provided for @saveAction.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveAction;

  /// No description provided for @code.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get code;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @fastCommands.
  ///
  /// In en, this message translates to:
  /// **'QUICK COMMANDS'**
  String get fastCommands;

  /// No description provided for @serverAddress.
  ///
  /// In en, this message translates to:
  /// **'Server Address'**
  String get serverAddress;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied: {value}'**
  String copied(String value);

  /// No description provided for @stopServer.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stopServer;

  /// No description provided for @command.
  ///
  /// In en, this message translates to:
  /// **'COMMAND'**
  String get command;

  /// No description provided for @serverStarted.
  ///
  /// In en, this message translates to:
  /// **'Server Started'**
  String get serverStarted;

  /// No description provided for @openAddressInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open this address in Android browser'**
  String get openAddressInBrowser;

  /// No description provided for @copyUrl.
  ///
  /// In en, this message translates to:
  /// **'Copy URL'**
  String get copyUrl;

  /// No description provided for @openProjectToSeeCommands.
  ///
  /// In en, this message translates to:
  /// **'Open a project to see run commands'**
  String get openProjectToSeeCommands;

  /// No description provided for @running.
  ///
  /// In en, this message translates to:
  /// **'Running...'**
  String get running;

  /// No description provided for @chat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// No description provided for @agents.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get agents;

  /// No description provided for @askAiHint.
  ///
  /// In en, this message translates to:
  /// **'Ask {provider}...'**
  String askAiHint(String provider);

  /// No description provided for @selectModel.
  ///
  /// In en, this message translates to:
  /// **'Select Model'**
  String get selectModel;

  /// No description provided for @clearHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear History'**
  String get clearHistory;

  /// No description provided for @askAboutCode.
  ///
  /// In en, this message translates to:
  /// **'Ask about the code'**
  String get askAboutCode;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @workingOnFile.
  ///
  /// In en, this message translates to:
  /// **'I\'m working on the file: {file}. \nHere is its content:\n```\n{code}\n```\n\nMy question: {question}'**
  String workingOnFile(String file, String code, String question);

  /// No description provided for @aiAskDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Agent Query'**
  String get aiAskDialogTitle;

  /// No description provided for @aiAskFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder: {name}'**
  String aiAskFolder(String name);

  /// No description provided for @aiAskFile.
  ///
  /// In en, this message translates to:
  /// **'File: {name}'**
  String aiAskFile(String name);

  /// No description provided for @aiAskFolderHint.
  ///
  /// In en, this message translates to:
  /// **'Describe the task (e.g. \"create a controller\", \"add a data model\"...)'**
  String get aiAskFolderHint;

  /// No description provided for @aiAskFileHint.
  ///
  /// In en, this message translates to:
  /// **'What needs to be done? (e.g. \"add email validation\", \"optimize method\"...)'**
  String get aiAskFileHint;

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @showChanges.
  ///
  /// In en, this message translates to:
  /// **'Show changes'**
  String get showChanges;

  /// No description provided for @changesInFile.
  ///
  /// In en, this message translates to:
  /// **'Changes in {name}'**
  String changesInFile(String name);

  /// No description provided for @noFilesFound.
  ///
  /// In en, this message translates to:
  /// **'No files found'**
  String get noFilesFound;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @errorOccurred.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorOccurred(String error);

  /// No description provided for @aiProvidersInfo.
  ///
  /// In en, this message translates to:
  /// **'Add API keys for different AI providers. Local models (Ollama/LM Studio) do not require a key.'**
  String get aiProvidersInfo;

  /// No description provided for @activeProvider.
  ///
  /// In en, this message translates to:
  /// **'Active Provider'**
  String get activeProvider;

  /// No description provided for @requiresApiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'Requires API Key'**
  String get requiresApiKeyLabel;

  /// No description provided for @localNoKey.
  ///
  /// In en, this message translates to:
  /// **'Local — no key'**
  String get localNoKey;

  /// No description provided for @activeCaps.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get activeCaps;

  /// No description provided for @apiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get apiKeyLabel;

  /// No description provided for @keySaved.
  ///
  /// In en, this message translates to:
  /// **'API key saved'**
  String get keySaved;

  /// No description provided for @urlSaved.
  ///
  /// In en, this message translates to:
  /// **'URL saved'**
  String get urlSaved;

  /// No description provided for @serverUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get serverUrlLabel;

  /// No description provided for @ollamaPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'💡 To connect from a phone, use your computer\'s IP (e.g. http://192.168.1.10:11434)'**
  String get ollamaPhoneHint;

  /// No description provided for @modelLabel.
  ///
  /// In en, this message translates to:
  /// **'MODEL'**
  String get modelLabel;

  /// No description provided for @searching.
  ///
  /// In en, this message translates to:
  /// **'Searching...'**
  String get searching;

  /// No description provided for @findModels.
  ///
  /// In en, this message translates to:
  /// **'Find Models'**
  String get findModels;

  /// No description provided for @searchModelHint.
  ///
  /// In en, this message translates to:
  /// **'Search by model name...'**
  String get searchModelHint;

  /// No description provided for @customModelHint.
  ///
  /// In en, this message translates to:
  /// **'Or enter model name manually...'**
  String get customModelHint;

  /// No description provided for @modelInstalled.
  ///
  /// In en, this message translates to:
  /// **'Model set to {name}'**
  String modelInstalled(String name);

  /// No description provided for @modelsNotFound.
  ///
  /// In en, this message translates to:
  /// **'No models found. Click \"Find Models\".'**
  String get modelsNotFound;

  /// No description provided for @available.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get available;

  /// No description provided for @quotaLimit.
  ///
  /// In en, this message translates to:
  /// **'Quota limit / high load'**
  String get quotaLimit;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailable;

  /// No description provided for @availableCaps.
  ///
  /// In en, this message translates to:
  /// **'AVAILABLE'**
  String get availableCaps;

  /// No description provided for @activateProvider.
  ///
  /// In en, this message translates to:
  /// **'Activate Provider'**
  String get activateProvider;

  /// No description provided for @providerActivated.
  ///
  /// In en, this message translates to:
  /// **'{name} activated'**
  String providerActivated(String name);

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @acceptAll.
  ///
  /// In en, this message translates to:
  /// **'Accept All'**
  String get acceptAll;

  /// No description provided for @rejectAll.
  ///
  /// In en, this message translates to:
  /// **'Reject All'**
  String get rejectAll;

  /// No description provided for @projectAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Project Analysis'**
  String get projectAnalysis;

  /// No description provided for @problemsFound.
  ///
  /// In en, this message translates to:
  /// **'Problems found: {count} ({errors} errors, {warnings} warnings)'**
  String problemsFound(int count, int errors, int warnings);

  /// No description provided for @fixWithAi.
  ///
  /// In en, this message translates to:
  /// **'Fix with AI'**
  String get fixWithAi;

  /// No description provided for @runningCommand.
  ///
  /// In en, this message translates to:
  /// **'Running command: {command}...'**
  String runningCommand(String command);

  /// No description provided for @applyingChange.
  ///
  /// In en, this message translates to:
  /// **'Applying change: {path}...'**
  String applyingChange(String path);

  /// No description provided for @fileSuccessfullyWritten.
  ///
  /// In en, this message translates to:
  /// **'File {path} successfully written.'**
  String fileSuccessfullyWritten(String path);

  /// No description provided for @fileSuccessfullyDeleted.
  ///
  /// In en, this message translates to:
  /// **'File {path} successfully deleted.'**
  String fileSuccessfullyDeleted(String path);

  /// No description provided for @commandExecutedResult.
  ///
  /// In en, this message translates to:
  /// **'Command \"{command}\" executed. Result:\n{result}'**
  String commandExecutedResult(String command, String result);

  /// No description provided for @commandSentToTerminal.
  ///
  /// In en, this message translates to:
  /// **'Command \"{command}\" sent to terminal.'**
  String commandSentToTerminal(String command);

  /// No description provided for @unknownActionType.
  ///
  /// In en, this message translates to:
  /// **'Unknown action type: {type}'**
  String unknownActionType(String type);

  /// No description provided for @failedToApplyAction.
  ///
  /// In en, this message translates to:
  /// **'Failed to apply action: {error}'**
  String failedToApplyAction(String error);

  /// No description provided for @noErrorsFound.
  ///
  /// In en, this message translates to:
  /// **'No errors found'**
  String get noErrorsFound;

  /// No description provided for @noErrorsDescription.
  ///
  /// In en, this message translates to:
  /// **'Code analyzer checked your project. No issues or warnings found.'**
  String get noErrorsDescription;

  /// No description provided for @closeProject.
  ///
  /// In en, this message translates to:
  /// **'Close Project'**
  String get closeProject;

  /// No description provided for @closeProjectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to close this project?'**
  String get closeProjectConfirm;

  /// No description provided for @sortByName.
  ///
  /// In en, this message translates to:
  /// **'By Name'**
  String get sortByName;

  /// No description provided for @sortBySize.
  ///
  /// In en, this message translates to:
  /// **'By Size'**
  String get sortBySize;

  /// No description provided for @sortByDate.
  ///
  /// In en, this message translates to:
  /// **'By Date'**
  String get sortByDate;

  /// No description provided for @goToDefinition.
  ///
  /// In en, this message translates to:
  /// **'Go to Definition'**
  String get goToDefinition;

  /// No description provided for @documentation.
  ///
  /// In en, this message translates to:
  /// **'Documentation'**
  String get documentation;

  /// No description provided for @usages.
  ///
  /// In en, this message translates to:
  /// **'Usages'**
  String get usages;

  /// No description provided for @cut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get cut;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @line.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get line;

  /// No description provided for @column.
  ///
  /// In en, this message translates to:
  /// **'Column'**
  String get column;

  /// No description provided for @info.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get info;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @problems.
  ///
  /// In en, this message translates to:
  /// **'Problems'**
  String get problems;

  /// No description provided for @packages.
  ///
  /// In en, this message translates to:
  /// **'Packages'**
  String get packages;

  /// No description provided for @tools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get tools;

  /// No description provided for @searchFiles.
  ///
  /// In en, this message translates to:
  /// **'Search files...'**
  String get searchFiles;

  /// No description provided for @imageLoadError.
  ///
  /// In en, this message translates to:
  /// **'Error loading image'**
  String get imageLoadError;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
