import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_zh.dart';

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
    Locale('es'),
    Locale('fr'),
    Locale('ru'),
    Locale('zh'),
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
  /// **'Build logs'**
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
  /// **'Confirm Delete'**
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
  /// **'Accept all'**
  String get acceptAll;

  /// No description provided for @rejectAll.
  ///
  /// In en, this message translates to:
  /// **'Reject all'**
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

  /// No description provided for @unsaved.
  ///
  /// In en, this message translates to:
  /// **'Unsaved'**
  String get unsaved;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @lineCol.
  ///
  /// In en, this message translates to:
  /// **'Ln {line}, Col {col}'**
  String lineCol(int line, int col);

  /// No description provided for @noOpenFiles.
  ///
  /// In en, this message translates to:
  /// **'No open files in editor'**
  String get noOpenFiles;

  /// No description provided for @fileNotFoundOnDisk.
  ///
  /// In en, this message translates to:
  /// **'File not found on disk'**
  String get fileNotFoundOnDisk;

  /// No description provided for @parsingError.
  ///
  /// In en, this message translates to:
  /// **'Parsing error: {error}'**
  String parsingError(String error);

  /// No description provided for @outlineEmptyOrUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Outline empty or unsupported'**
  String get outlineEmptyOrUnsupported;

  /// No description provided for @outlineHeader.
  ///
  /// In en, this message translates to:
  /// **'Structure: {filename}'**
  String outlineHeader(String filename);

  /// No description provided for @projectFolderNotFound.
  ///
  /// In en, this message translates to:
  /// **'Project folder not found'**
  String get projectFolderNotFound;

  /// No description provided for @rootFiles.
  ///
  /// In en, this message translates to:
  /// **'[Files in root]'**
  String get rootFiles;

  /// No description provided for @scanningError.
  ///
  /// In en, this message translates to:
  /// **'Scanning error: {error}'**
  String scanningError(String error);

  /// No description provided for @deleteFileConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete File'**
  String get deleteFileConfirmTitle;

  /// No description provided for @deleteFileConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to permanently delete file:\n\n{name}\nSize: {size}?'**
  String deleteFileConfirmMessage(String name, String size);

  /// No description provided for @fileDeletedSuccess.
  ///
  /// In en, this message translates to:
  /// **'File deleted successfully'**
  String get fileDeletedSuccess;

  /// No description provided for @deleteFileError.
  ///
  /// In en, this message translates to:
  /// **'Delete error: {error}'**
  String deleteFileError(String error);

  /// No description provided for @diskSpaceAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Disk space analysis...'**
  String get diskSpaceAnalysis;

  /// No description provided for @projectFolderEmpty.
  ///
  /// In en, this message translates to:
  /// **'Project folder empty'**
  String get projectFolderEmpty;

  /// No description provided for @projectSize.
  ///
  /// In en, this message translates to:
  /// **'Project size:'**
  String get projectSize;

  /// No description provided for @folderDistribution.
  ///
  /// In en, this message translates to:
  /// **'Folder Distribution'**
  String get folderDistribution;

  /// No description provided for @topHeavyFiles.
  ///
  /// In en, this message translates to:
  /// **'Top 10 Heavy Files'**
  String get topHeavyFiles;

  /// No description provided for @noHeavyFiles.
  ///
  /// In en, this message translates to:
  /// **'No heavy files'**
  String get noHeavyFiles;

  /// No description provided for @searchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search contents...'**
  String get searchPlaceholder;

  /// No description provided for @searchCaseSensitive.
  ///
  /// In en, this message translates to:
  /// **'Case sensitive'**
  String get searchCaseSensitive;

  /// No description provided for @searchWholeWord.
  ///
  /// In en, this message translates to:
  /// **'Whole word'**
  String get searchWholeWord;

  /// No description provided for @searchRegex.
  ///
  /// In en, this message translates to:
  /// **'Regular expression'**
  String get searchRegex;

  /// No description provided for @searchInvalidRegex.
  ///
  /// In en, this message translates to:
  /// **'Invalid regular expression'**
  String get searchInvalidRegex;

  /// No description provided for @searchNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches found'**
  String get searchNoMatches;

  /// No description provided for @searchMatchesFound.
  ///
  /// In en, this message translates to:
  /// **'Found {matches} matches in {files} files'**
  String searchMatchesFound(int matches, int files);

  /// No description provided for @searchError.
  ///
  /// In en, this message translates to:
  /// **'Search error: {error}'**
  String searchError(String error);

  /// No description provided for @searchingInProgress.
  ///
  /// In en, this message translates to:
  /// **'Searching...'**
  String get searchingInProgress;

  /// No description provided for @searchPrompt.
  ///
  /// In en, this message translates to:
  /// **'Enter query to search'**
  String get searchPrompt;

  /// No description provided for @apkSigner.
  ///
  /// In en, this message translates to:
  /// **'APK Signer'**
  String get apkSigner;

  /// No description provided for @createKeystore.
  ///
  /// In en, this message translates to:
  /// **'Create Keystore'**
  String get createKeystore;

  /// No description provided for @stepSelectApk.
  ///
  /// In en, this message translates to:
  /// **'Step 1: Select APK to sign'**
  String get stepSelectApk;

  /// No description provided for @selectApk.
  ///
  /// In en, this message translates to:
  /// **'Select APK'**
  String get selectApk;

  /// No description provided for @selectCustomPath.
  ///
  /// In en, this message translates to:
  /// **'Specify custom path...'**
  String get selectCustomPath;

  /// No description provided for @apkPathHint.
  ///
  /// In en, this message translates to:
  /// **'Full path to APK file on device'**
  String get apkPathHint;

  /// No description provided for @stepSelectKeystore.
  ///
  /// In en, this message translates to:
  /// **'Step 2: Select Keystore'**
  String get stepSelectKeystore;

  /// No description provided for @selectKeystore.
  ///
  /// In en, this message translates to:
  /// **'Select Keystore'**
  String get selectKeystore;

  /// No description provided for @keystorePathHint.
  ///
  /// In en, this message translates to:
  /// **'Full path to .jks/.keystore file'**
  String get keystorePathHint;

  /// No description provided for @stepSignSettings.
  ///
  /// In en, this message translates to:
  /// **'Step 3: Signing settings'**
  String get stepSignSettings;

  /// No description provided for @keystorePassword.
  ///
  /// In en, this message translates to:
  /// **'Keystore password'**
  String get keystorePassword;

  /// No description provided for @keyAlias.
  ///
  /// In en, this message translates to:
  /// **'Key Alias'**
  String get keyAlias;

  /// No description provided for @keyAliasPassword.
  ///
  /// In en, this message translates to:
  /// **'Key Alias password'**
  String get keyAliasPassword;

  /// No description provided for @outputApkName.
  ///
  /// In en, this message translates to:
  /// **'Output APK filename'**
  String get outputApkName;

  /// No description provided for @signApkButton.
  ///
  /// In en, this message translates to:
  /// **'Sign APK'**
  String get signApkButton;

  /// No description provided for @install.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get install;

  /// No description provided for @refreshProjectFiles.
  ///
  /// In en, this message translates to:
  /// **'Refresh project files list'**
  String get refreshProjectFiles;

  /// No description provided for @newKeystoreParams.
  ///
  /// In en, this message translates to:
  /// **'New Keystore parameters'**
  String get newKeystoreParams;

  /// No description provided for @keystoreFilenameHint.
  ///
  /// In en, this message translates to:
  /// **'Filename (e.g. release.jks)'**
  String get keystoreFilenameHint;

  /// No description provided for @storePasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Keystore password (min 6 chars)'**
  String get storePasswordHint;

  /// No description provided for @keyAliasHint.
  ///
  /// In en, this message translates to:
  /// **'Key alias (e.g. key)'**
  String get keyAliasHint;

  /// No description provided for @developerInfoDn.
  ///
  /// In en, this message translates to:
  /// **'Developer Info (DN)'**
  String get developerInfoDn;

  /// No description provided for @devNameCn.
  ///
  /// In en, this message translates to:
  /// **'First and last name (CN)'**
  String get devNameCn;

  /// No description provided for @devUnitOu.
  ///
  /// In en, this message translates to:
  /// **'Organizational Unit (OU)'**
  String get devUnitOu;

  /// No description provided for @devOrgO.
  ///
  /// In en, this message translates to:
  /// **'Organization (O)'**
  String get devOrgO;

  /// No description provided for @devCityL.
  ///
  /// In en, this message translates to:
  /// **'City or Locality (L)'**
  String get devCityL;

  /// No description provided for @devStateS.
  ///
  /// In en, this message translates to:
  /// **'State or Province (S)'**
  String get devStateS;

  /// No description provided for @devCountryC.
  ///
  /// In en, this message translates to:
  /// **'Country Code (C)'**
  String get devCountryC;

  /// No description provided for @genKeystoreButton.
  ///
  /// In en, this message translates to:
  /// **'Generate Keystore'**
  String get genKeystoreButton;

  /// No description provided for @logSignGen.
  ///
  /// In en, this message translates to:
  /// **'SIGNING & GENERATION LOG'**
  String get logSignGen;

  /// No description provided for @clearLog.
  ///
  /// In en, this message translates to:
  /// **'Clear Log'**
  String get clearLog;

  /// No description provided for @logPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Signing and generation log will be displayed here.'**
  String get logPlaceholder;

  /// No description provided for @signProjectScanError.
  ///
  /// In en, this message translates to:
  /// **'Project scan error: {error}'**
  String signProjectScanError(String error);

  /// No description provided for @signKeystoreSelected.
  ///
  /// In en, this message translates to:
  /// **'Keystore selected: {path}'**
  String signKeystoreSelected(String path);

  /// No description provided for @signFilePickError.
  ///
  /// In en, this message translates to:
  /// **'File pick error: {error}'**
  String signFilePickError(String error);

  /// No description provided for @signNoOpenProject.
  ///
  /// In en, this message translates to:
  /// **'No open project'**
  String get signNoOpenProject;

  /// No description provided for @signNoApkSelected.
  ///
  /// In en, this message translates to:
  /// **'No APK selected'**
  String get signNoApkSelected;

  /// No description provided for @signNoKeystoreSelected.
  ///
  /// In en, this message translates to:
  /// **'No Keystore selected'**
  String get signNoKeystoreSelected;

  /// No description provided for @signFillAllFields.
  ///
  /// In en, this message translates to:
  /// **'Fill all signing fields'**
  String get signFillAllFields;

  /// No description provided for @signApkProgress.
  ///
  /// In en, this message translates to:
  /// **'Signing APK: {apk}...'**
  String signApkProgress(String apk);

  /// No description provided for @signKeyFile.
  ///
  /// In en, this message translates to:
  /// **'Key file: {key} (alias: {alias})'**
  String signKeyFile(String key, String alias);

  /// No description provided for @signRunningApksigner.
  ///
  /// In en, this message translates to:
  /// **'Running apksigner...'**
  String get signRunningApksigner;

  /// No description provided for @signVerifying.
  ///
  /// In en, this message translates to:
  /// **'Verifying signature...'**
  String get signVerifying;

  /// No description provided for @signSuccess.
  ///
  /// In en, this message translates to:
  /// **'APK signed and verified successfully!'**
  String get signSuccess;

  /// No description provided for @signVerifyFailed.
  ///
  /// In en, this message translates to:
  /// **'Signature verification failed or error occurred.'**
  String get signVerifyFailed;

  /// No description provided for @signError.
  ///
  /// In en, this message translates to:
  /// **'Error signing APK: {error}'**
  String signError(String error);

  /// No description provided for @genKeystoreFillFields.
  ///
  /// In en, this message translates to:
  /// **'Fill key generation fields'**
  String get genKeystoreFillFields;

  /// No description provided for @genKeystoreProgress.
  ///
  /// In en, this message translates to:
  /// **'Generating Keystore: {name}...'**
  String genKeystoreProgress(String name);

  /// No description provided for @genKeystoreSuccess.
  ///
  /// In en, this message translates to:
  /// **'Keystore created successfully at: {name}'**
  String genKeystoreSuccess(String name);

  /// No description provided for @genKeystoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create Keystore.'**
  String get genKeystoreFailed;

  /// No description provided for @genKeystoreError.
  ///
  /// In en, this message translates to:
  /// **'Error generating Keystore: {error}'**
  String genKeystoreError(String error);

  /// No description provided for @installApkProgress.
  ///
  /// In en, this message translates to:
  /// **'Starting APK installation: {apk}'**
  String installApkProgress(String apk);

  /// No description provided for @installApkResult.
  ///
  /// In en, this message translates to:
  /// **'Installation result: {msg}'**
  String installApkResult(String msg);

  /// No description provided for @installApkNotFound.
  ///
  /// In en, this message translates to:
  /// **'APK file not found: {path}'**
  String installApkNotFound(String path);

  /// No description provided for @installApkError.
  ///
  /// In en, this message translates to:
  /// **'Installation error: {error}'**
  String installApkError(String error);

  /// No description provided for @glassmorphismEffects.
  ///
  /// In en, this message translates to:
  /// **'Glassmorphism Effects'**
  String get glassmorphismEffects;

  /// No description provided for @glassOpacity.
  ///
  /// In en, this message translates to:
  /// **'Glass Opacity'**
  String get glassOpacity;

  /// No description provided for @backdropBlur.
  ///
  /// In en, this message translates to:
  /// **'Backdrop Blur'**
  String get backdropBlur;

  /// No description provided for @editorFontFamily.
  ///
  /// In en, this message translates to:
  /// **'Editor Font Family'**
  String get editorFontFamily;

  /// No description provided for @fontLigatures.
  ///
  /// In en, this message translates to:
  /// **'Font Ligatures'**
  String get fontLigatures;

  /// No description provided for @fontLigaturesDescription.
  ///
  /// In en, this message translates to:
  /// **'Enable font ligatures in code (e.g., -> or !=)'**
  String get fontLigaturesDescription;

  /// No description provided for @selectFontFamily.
  ///
  /// In en, this message translates to:
  /// **'Select Font Family'**
  String get selectFontFamily;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// No description provided for @format.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get format;

  /// No description provided for @liveShare.
  ///
  /// In en, this message translates to:
  /// **'Live Share'**
  String get liveShare;

  /// No description provided for @hostSession.
  ///
  /// In en, this message translates to:
  /// **'Host Session'**
  String get hostSession;

  /// No description provided for @joinSession.
  ///
  /// In en, this message translates to:
  /// **'Join Session'**
  String get joinSession;

  /// No description provided for @stopSession.
  ///
  /// In en, this message translates to:
  /// **'Stop Session'**
  String get stopSession;

  /// No description provided for @disconnectSession.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnectSession;

  /// No description provided for @sessionActive.
  ///
  /// In en, this message translates to:
  /// **'Session Active'**
  String get sessionActive;

  /// No description provided for @hostingAt.
  ///
  /// In en, this message translates to:
  /// **'Hosting at:'**
  String get hostingAt;

  /// No description provided for @connectedTo.
  ///
  /// In en, this message translates to:
  /// **'Connected to:'**
  String get connectedTo;

  /// No description provided for @userName.
  ///
  /// In en, this message translates to:
  /// **'Your Name'**
  String get userName;

  /// No description provided for @usersList.
  ///
  /// In en, this message translates to:
  /// **'Participants'**
  String get usersList;

  /// No description provided for @messagePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Type a message...'**
  String get messagePlaceholder;

  /// No description provided for @connectError.
  ///
  /// In en, this message translates to:
  /// **'Connection error'**
  String get connectError;

  /// No description provided for @invalidAddress.
  ///
  /// In en, this message translates to:
  /// **'Invalid address'**
  String get invalidAddress;

  /// No description provided for @joinLink.
  ///
  /// In en, this message translates to:
  /// **'Session IP address'**
  String get joinLink;

  /// No description provided for @localIps.
  ///
  /// In en, this message translates to:
  /// **'Local IPs:'**
  String get localIps;

  /// No description provided for @wasmPlugins.
  ///
  /// In en, this message translates to:
  /// **'WASM Plugins'**
  String get wasmPlugins;

  /// No description provided for @installPlugin.
  ///
  /// In en, this message translates to:
  /// **'Install Plugin (.wasm)'**
  String get installPlugin;

  /// No description provided for @noPluginsInstalled.
  ///
  /// In en, this message translates to:
  /// **'No WASM plugins installed'**
  String get noPluginsInstalled;

  /// No description provided for @pluginEnabled.
  ///
  /// In en, this message translates to:
  /// **'Plugin enabled'**
  String get pluginEnabled;

  /// No description provided for @pluginDisabled.
  ///
  /// In en, this message translates to:
  /// **'Plugin disabled'**
  String get pluginDisabled;

  /// No description provided for @runWasmAction.
  ///
  /// In en, this message translates to:
  /// **'Run WASM Action'**
  String get runWasmAction;

  /// No description provided for @noActiveSelection.
  ///
  /// In en, this message translates to:
  /// **'No text selected. Apply to the entire file?'**
  String get noActiveSelection;

  /// No description provided for @applyToSelection.
  ///
  /// In en, this message translates to:
  /// **'Apply to Selection'**
  String get applyToSelection;

  /// No description provided for @applyToDocument.
  ///
  /// In en, this message translates to:
  /// **'Apply to Document'**
  String get applyToDocument;

  /// No description provided for @logs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logs;

  /// No description provided for @clearLogs.
  ///
  /// In en, this message translates to:
  /// **'Clear Logs'**
  String get clearLogs;

  /// No description provided for @deletePlugin.
  ///
  /// In en, this message translates to:
  /// **'Delete Plugin'**
  String get deletePlugin;

  /// No description provided for @resetToDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to Defaults'**
  String get resetToDefaults;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome!'**
  String get welcomeTitle;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a project to work on or create a new one'**
  String get welcomeSubtitle;

  /// No description provided for @lastActiveProject.
  ///
  /// In en, this message translates to:
  /// **'Last Active Project'**
  String get lastActiveProject;

  /// No description provided for @runTooltip.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get runTooltip;

  /// No description provided for @actionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actionsTooltip;

  /// No description provided for @packagesTooltip.
  ///
  /// In en, this message translates to:
  /// **'Packages'**
  String get packagesTooltip;

  /// No description provided for @extensionsAndTools.
  ///
  /// In en, this message translates to:
  /// **'Extensions & Tools'**
  String get extensionsAndTools;

  /// No description provided for @searchExtensionsHint.
  ///
  /// In en, this message translates to:
  /// **'Search extensions...'**
  String get searchExtensionsHint;

  /// No description provided for @searchPubdevHint.
  ///
  /// In en, this message translates to:
  /// **'Search libraries on pub.dev (e.g., dio)...'**
  String get searchPubdevHint;

  /// No description provided for @tabAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get tabAll;

  /// No description provided for @tabInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get tabInstalled;

  /// No description provided for @tabLanguagesAndAi.
  ///
  /// In en, this message translates to:
  /// **'Languages & AI'**
  String get tabLanguagesAndAi;

  /// No description provided for @tabTools.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get tabTools;

  /// No description provided for @tabBuild.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get tabBuild;

  /// No description provided for @tabSdkPlatforms.
  ///
  /// In en, this message translates to:
  /// **'SDK Platforms'**
  String get tabSdkPlatforms;

  /// No description provided for @tabPubLibraries.
  ///
  /// In en, this message translates to:
  /// **'Pub Libraries'**
  String get tabPubLibraries;

  /// No description provided for @readyToBuildApk.
  ///
  /// In en, this message translates to:
  /// **'Ready to build APK?'**
  String get readyToBuildApk;

  /// No description provided for @installAndroidSdkJava.
  ///
  /// In en, this message translates to:
  /// **'Install Android SDK & Java 17'**
  String get installAndroidSdkJava;

  /// No description provided for @sdkSetupDescription.
  ///
  /// In en, this message translates to:
  /// **'This will setup SDK, compilers, zipalign, apksigner, optimize Gradle network settings and prepare your environment for compiling projects.'**
  String get sdkSetupDescription;

  /// No description provided for @initializingDevEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Initializing development environment...'**
  String get initializingDevEnvironment;

  /// No description provided for @viewAction.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get viewAction;

  /// No description provided for @startSdkSetup.
  ///
  /// In en, this message translates to:
  /// **'Start environment setup'**
  String get startSdkSetup;

  /// No description provided for @buildIssues.
  ///
  /// In en, this message translates to:
  /// **'Build issues?'**
  String get buildIssues;

  /// No description provided for @restoreAndroidGradleEnv.
  ///
  /// In en, this message translates to:
  /// **'Restore Android & Gradle environment'**
  String get restoreAndroidGradleEnv;

  /// No description provided for @wrenchFixDescription.
  ///
  /// In en, this message translates to:
  /// **'Automatically fixes AAPT2 daemon errors, sets correct project permissions, restores the resource compiler binary, and configures Gradle threads.'**
  String get wrenchFixDescription;

  /// No description provided for @runningWrenchFix.
  ///
  /// In en, this message translates to:
  /// **'Running build environment fix...'**
  String get runningWrenchFix;

  /// No description provided for @startWrenchFix.
  ///
  /// In en, this message translates to:
  /// **'Run fix (Wrench Fix)'**
  String get startWrenchFix;

  /// No description provided for @statusInstalledCaps.
  ///
  /// In en, this message translates to:
  /// **'INSTALLED'**
  String get statusInstalledCaps;

  /// No description provided for @reinstallOrUpdateTooltip.
  ///
  /// In en, this message translates to:
  /// **'Reinstall / Update'**
  String get reinstallOrUpdateTooltip;

  /// No description provided for @updatingPackage.
  ///
  /// In en, this message translates to:
  /// **'Updating {name}...'**
  String updatingPackage(String name);

  /// No description provided for @installingPackage.
  ///
  /// In en, this message translates to:
  /// **'Installing {name}...'**
  String installingPackage(String name);

  /// No description provided for @installAction.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get installAction;

  /// No description provided for @searchPubdevTitle.
  ///
  /// In en, this message translates to:
  /// **'Search Flutter libraries'**
  String get searchPubdevTitle;

  /// No description provided for @searchPubdevDescription.
  ///
  /// In en, this message translates to:
  /// **'Enter a library name (e.g. dio, bloc, riverpod) in the search field above and press Enter'**
  String get searchPubdevDescription;

  /// No description provided for @loadError.
  ///
  /// In en, this message translates to:
  /// **'Load error: {error}'**
  String loadError(String error);

  /// No description provided for @addAction.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addAction;

  /// No description provided for @openProjectToInstallLibraries.
  ///
  /// In en, this message translates to:
  /// **'Please open a project first to add libraries.'**
  String get openProjectToInstallLibraries;

  /// No description provided for @installingLibrary.
  ///
  /// In en, this message translates to:
  /// **'Installing library {name}...'**
  String installingLibrary(String name);

  /// No description provided for @importError.
  ///
  /// In en, this message translates to:
  /// **'Import error: {error}'**
  String importError(String error);

  /// No description provided for @filesImportedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Files successfully imported'**
  String get filesImportedSuccessfully;

  /// No description provided for @dragFilesHereToImport.
  ///
  /// In en, this message translates to:
  /// **'Drag files here to import'**
  String get dragFilesHereToImport;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'Selected: {count}'**
  String selectedCount(int count);

  /// No description provided for @selectAllTooltip.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAllTooltip;

  /// No description provided for @copyTooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyTooltip;

  /// No description provided for @copiedCount.
  ///
  /// In en, this message translates to:
  /// **'Copied objects: {count}'**
  String copiedCount(int count);

  /// No description provided for @cutTooltip.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get cutTooltip;

  /// No description provided for @cutCount.
  ///
  /// In en, this message translates to:
  /// **'Cut objects: {count}'**
  String cutCount(int count);

  /// No description provided for @zipTooltip.
  ///
  /// In en, this message translates to:
  /// **'Compress to ZIP'**
  String get zipTooltip;

  /// No description provided for @deleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteTooltip;

  /// No description provided for @foldersCount.
  ///
  /// In en, this message translates to:
  /// **'Folders: {count}'**
  String foldersCount(int count);

  /// No description provided for @askAiAction.
  ///
  /// In en, this message translates to:
  /// **'Ask AI'**
  String get askAiAction;

  /// No description provided for @explainAiAction.
  ///
  /// In en, this message translates to:
  /// **'AI: Explain'**
  String get explainAiAction;

  /// No description provided for @documentAiAction.
  ///
  /// In en, this message translates to:
  /// **'AI: Document'**
  String get documentAiAction;

  /// No description provided for @testAiAction.
  ///
  /// In en, this message translates to:
  /// **'AI: Generate Tests'**
  String get testAiAction;

  /// No description provided for @optimizeAiAction.
  ///
  /// In en, this message translates to:
  /// **'AI: Optimize'**
  String get optimizeAiAction;

  /// No description provided for @pasteCount.
  ///
  /// In en, this message translates to:
  /// **'Paste ({count})'**
  String pasteCount(int count);

  /// No description provided for @archiveNameHint.
  ///
  /// In en, this message translates to:
  /// **'Archive name'**
  String get archiveNameHint;

  /// No description provided for @compressAction.
  ///
  /// In en, this message translates to:
  /// **'Compress'**
  String get compressAction;

  /// No description provided for @archiveCreatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Archive successfully created!'**
  String get archiveCreatedSuccessfully;

  /// No description provided for @compressionError.
  ///
  /// In en, this message translates to:
  /// **'Compression error: {error}'**
  String compressionError(String error);

  /// No description provided for @archiveExtractedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Archive successfully extracted!'**
  String get archiveExtractedSuccessfully;

  /// No description provided for @extractionError.
  ///
  /// In en, this message translates to:
  /// **'Extraction error: {error}'**
  String extractionError(String error);

  /// No description provided for @deleteSelectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete selected?'**
  String get deleteSelectedTitle;

  /// No description provided for @deleteSelectedConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete {count} items?'**
  String deleteSelectedConfirmation(int count);

  /// No description provided for @selectedElementsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Selected items deleted!'**
  String get selectedElementsDeleted;

  /// No description provided for @deleteError.
  ///
  /// In en, this message translates to:
  /// **'Delete error: {error}'**
  String deleteError(String error);

  /// No description provided for @filesPastedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Files successfully pasted!'**
  String get filesPastedSuccessfully;

  /// No description provided for @pasteError.
  ///
  /// In en, this message translates to:
  /// **'Paste error: {error}'**
  String pasteError(String error);

  /// No description provided for @repositoryNotFound.
  ///
  /// In en, this message translates to:
  /// **'Repository not found'**
  String get repositoryNotFound;

  /// No description provided for @initGitRepoDescription.
  ///
  /// In en, this message translates to:
  /// **'Initialize a local Git repository to track changes.'**
  String get initGitRepoDescription;

  /// No description provided for @initGitAction.
  ///
  /// In en, this message translates to:
  /// **'Initialize Git'**
  String get initGitAction;

  /// No description provided for @gitConflicted.
  ///
  /// In en, this message translates to:
  /// **'CONFLICTS'**
  String get gitConflicted;

  /// No description provided for @gitStaged.
  ///
  /// In en, this message translates to:
  /// **'STAGED'**
  String get gitStaged;

  /// No description provided for @gitModified.
  ///
  /// In en, this message translates to:
  /// **'MODIFIED'**
  String get gitModified;

  /// No description provided for @gitUntracked.
  ///
  /// In en, this message translates to:
  /// **'UNTRACKED'**
  String get gitUntracked;

  /// No description provided for @commitMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Commit message...'**
  String get commitMessageHint;

  /// No description provided for @resetChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset changes?'**
  String get resetChangesTitle;

  /// No description provided for @resetChangesConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to permanently reset all uncommitted changes in this file?'**
  String get resetChangesConfirmation;

  /// No description provided for @resetAction.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetAction;

  /// No description provided for @changesReset.
  ///
  /// In en, this message translates to:
  /// **'Changes reset'**
  String get changesReset;

  /// No description provided for @resetError.
  ///
  /// In en, this message translates to:
  /// **'Reset error: {error}'**
  String resetError(String error);

  /// No description provided for @normalView.
  ///
  /// In en, this message translates to:
  /// **'Normal view'**
  String get normalView;

  /// No description provided for @splitView.
  ///
  /// In en, this message translates to:
  /// **'Split view (Side-by-Side)'**
  String get splitView;

  /// No description provided for @stagedMessage.
  ///
  /// In en, this message translates to:
  /// **'File staged'**
  String get stagedMessage;

  /// No description provided for @unstagedMessage.
  ///
  /// In en, this message translates to:
  /// **'File unstaged'**
  String get unstagedMessage;

  /// No description provided for @stageError.
  ///
  /// In en, this message translates to:
  /// **'Staging error: {error}'**
  String stageError(String error);

  /// No description provided for @failedToLoadChanges.
  ///
  /// In en, this message translates to:
  /// **'Failed to load changes'**
  String get failedToLoadChanges;

  /// No description provided for @noChanges.
  ///
  /// In en, this message translates to:
  /// **'No changes'**
  String get noChanges;

  /// No description provided for @fileIdenticalToHead.
  ///
  /// In en, this message translates to:
  /// **'This file is identical to HEAD'**
  String get fileIdenticalToHead;

  /// No description provided for @runTerminalTooltip.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get runTerminalTooltip;

  /// No description provided for @restartTerminalTooltip.
  ///
  /// In en, this message translates to:
  /// **'Restart'**
  String get restartTerminalTooltip;

  /// No description provided for @consoleSubTab.
  ///
  /// In en, this message translates to:
  /// **'Console'**
  String get consoleSubTab;

  /// No description provided for @signApkSubTab.
  ///
  /// In en, this message translates to:
  /// **'Sign APK'**
  String get signApkSubTab;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @tryChangingSearchQuery.
  ///
  /// In en, this message translates to:
  /// **'Try changing search query'**
  String get tryChangingSearchQuery;

  /// No description provided for @incomingBranch.
  ///
  /// In en, this message translates to:
  /// **'Incoming branch'**
  String get incomingBranch;

  /// No description provided for @resolveConflictsBeforeSaving.
  ///
  /// In en, this message translates to:
  /// **'Please resolve all conflicts before saving!'**
  String get resolveConflictsBeforeSaving;

  /// No description provided for @fileSavedAndStaged.
  ///
  /// In en, this message translates to:
  /// **'File successfully saved and staged to Git index'**
  String get fileSavedAndStaged;

  /// No description provided for @saveError.
  ///
  /// In en, this message translates to:
  /// **'Error saving: {error}'**
  String saveError(String error);

  /// No description provided for @acceptMerge.
  ///
  /// In en, this message translates to:
  /// **'Accept Merge'**
  String get acceptMerge;

  /// No description provided for @errorLoadingConflictFile.
  ///
  /// In en, this message translates to:
  /// **'Error loading conflict file'**
  String get errorLoadingConflictFile;

  /// No description provided for @conflictsNotFound.
  ///
  /// In en, this message translates to:
  /// **'Conflicts not found'**
  String get conflictsNotFound;

  /// No description provided for @noConflictMarkersFound.
  ///
  /// In en, this message translates to:
  /// **'No standard Git merge markers found in this file.'**
  String get noConflictMarkersFound;

  /// No description provided for @backToGit.
  ///
  /// In en, this message translates to:
  /// **'Back to Git'**
  String get backToGit;

  /// No description provided for @conflictBlock.
  ///
  /// In en, this message translates to:
  /// **'Conflict block'**
  String get conflictBlock;

  /// No description provided for @currentChangesOurs.
  ///
  /// In en, this message translates to:
  /// **'Current changes (Ours / HEAD)'**
  String get currentChangesOurs;

  /// No description provided for @incomingChanges.
  ///
  /// In en, this message translates to:
  /// **'Incoming changes ({branch})'**
  String incomingChanges(String branch);

  /// No description provided for @useThisVersion.
  ///
  /// In en, this message translates to:
  /// **'Use this version'**
  String get useThisVersion;

  /// No description provided for @mergeResultEditable.
  ///
  /// In en, this message translates to:
  /// **'Merge result (Editable)'**
  String get mergeResultEditable;

  /// No description provided for @chooseVersionOrWriteHint.
  ///
  /// In en, this message translates to:
  /// **'Choose one of the versions above or write your own merge resolution...'**
  String get chooseVersionOrWriteHint;

  /// No description provided for @markAsResolvedHint.
  ///
  /// In en, this message translates to:
  /// **'* To mark this block as resolved, enter or choose text.'**
  String get markAsResolvedHint;

  /// No description provided for @emptyLabel.
  ///
  /// In en, this message translates to:
  /// **'(Empty)'**
  String get emptyLabel;

  /// No description provided for @stageAction.
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get stageAction;

  /// No description provided for @unstageAction.
  ///
  /// In en, this message translates to:
  /// **'Unstage'**
  String get unstageAction;

  /// No description provided for @cursorColor.
  ///
  /// In en, this message translates to:
  /// **'CURSOR COLOR'**
  String get cursorColor;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get or;

  /// No description provided for @ipCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'IP copied to clipboard'**
  String get ipCopiedToClipboard;

  /// No description provided for @editingFile.
  ///
  /// In en, this message translates to:
  /// **'Editing: {file}'**
  String editingFile(String file);

  /// No description provided for @viewingProject.
  ///
  /// In en, this message translates to:
  /// **'Viewing project'**
  String get viewingProject;

  /// No description provided for @noProblemsFound.
  ///
  /// In en, this message translates to:
  /// **'No problems found in workspace'**
  String get noProblemsFound;

  /// No description provided for @problemsList.
  ///
  /// In en, this message translates to:
  /// **'Problems List'**
  String get problemsList;

  /// No description provided for @sendToAi.
  ///
  /// In en, this message translates to:
  /// **'Send to AI'**
  String get sendToAi;

  /// No description provided for @helpMeFixErrors.
  ///
  /// In en, this message translates to:
  /// **'Please help me fix the following compilation errors in my project:'**
  String get helpMeFixErrors;

  /// No description provided for @lineColumn.
  ///
  /// In en, this message translates to:
  /// **'Line {line}, Column {col}'**
  String lineColumn(int line, int col);

  /// No description provided for @decreaseFontSize.
  ///
  /// In en, this message translates to:
  /// **'Decrease Font Size'**
  String get decreaseFontSize;

  /// No description provided for @increaseFontSize.
  ///
  /// In en, this message translates to:
  /// **'Increase Font Size'**
  String get increaseFontSize;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @moveLeft.
  ///
  /// In en, this message translates to:
  /// **'Move Left'**
  String get moveLeft;

  /// No description provided for @moveUp.
  ///
  /// In en, this message translates to:
  /// **'Move Up'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In en, this message translates to:
  /// **'Move Down'**
  String get moveDown;

  /// No description provided for @moveRight.
  ///
  /// In en, this message translates to:
  /// **'Move Right'**
  String get moveRight;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @packagesAndEnv.
  ///
  /// In en, this message translates to:
  /// **'Packages & Env'**
  String get packagesAndEnv;

  /// No description provided for @packagesInstalledCount.
  ///
  /// In en, this message translates to:
  /// **'Installed: {count}/{total}'**
  String packagesInstalledCount(int count, int total);

  /// No description provided for @flutterProject.
  ///
  /// In en, this message translates to:
  /// **'Flutter Project'**
  String get flutterProject;

  /// No description provided for @pythonProject.
  ///
  /// In en, this message translates to:
  /// **'Python Project'**
  String get pythonProject;

  /// No description provided for @nodejsProject.
  ///
  /// In en, this message translates to:
  /// **'Node.js Project'**
  String get nodejsProject;

  /// No description provided for @dartProject.
  ///
  /// In en, this message translates to:
  /// **'Dart Project'**
  String get dartProject;

  /// No description provided for @webProject.
  ///
  /// In en, this message translates to:
  /// **'Web Project'**
  String get webProject;

  /// No description provided for @androidProject.
  ///
  /// In en, this message translates to:
  /// **'Android Project'**
  String get androidProject;

  /// No description provided for @genericProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get genericProject;

  /// No description provided for @runPC.
  ///
  /// In en, this message translates to:
  /// **'Run (PC)'**
  String get runPC;

  /// No description provided for @runMob.
  ///
  /// In en, this message translates to:
  /// **'Run (Mob)'**
  String get runMob;

  /// No description provided for @startServer.
  ///
  /// In en, this message translates to:
  /// **'Start Server'**
  String get startServer;

  /// No description provided for @buildAPK.
  ///
  /// In en, this message translates to:
  /// **'Build APK'**
  String get buildAPK;

  /// No description provided for @startTheProject.
  ///
  /// In en, this message translates to:
  /// **'Start the project'**
  String get startTheProject;

  /// No description provided for @outputCopied.
  ///
  /// In en, this message translates to:
  /// **'Output copied'**
  String get outputCopied;

  /// No description provided for @console.
  ///
  /// In en, this message translates to:
  /// **'Console'**
  String get console;

  /// No description provided for @signApk.
  ///
  /// In en, this message translates to:
  /// **'Sign APK'**
  String get signApk;

  /// No description provided for @buildPC.
  ///
  /// In en, this message translates to:
  /// **'Build (PC)'**
  String get buildPC;

  /// No description provided for @resetPlugins.
  ///
  /// In en, this message translates to:
  /// **'Reset Plugins'**
  String get resetPlugins;

  /// No description provided for @resetPluginsConfirmation.
  ///
  /// In en, this message translates to:
  /// **'This will remove all installed custom plugins and restore default plugins. Continue?'**
  String get resetPluginsConfirmation;

  /// No description provided for @resetPluginsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset Plugins?'**
  String get resetPluginsTitle;

  /// No description provided for @installWasm.
  ///
  /// In en, this message translates to:
  /// **'Install .wasm'**
  String get installWasm;

  /// No description provided for @availableActions.
  ///
  /// In en, this message translates to:
  /// **'Available Actions:'**
  String get availableActions;

  /// No description provided for @logsTerminal.
  ///
  /// In en, this message translates to:
  /// **'Logs Terminal'**
  String get logsTerminal;

  /// No description provided for @noLogsCaptured.
  ///
  /// In en, this message translates to:
  /// **'No logs captured yet'**
  String get noLogsCaptured;

  /// No description provided for @installWasmPluginTitle.
  ///
  /// In en, this message translates to:
  /// **'Install WASM Plugin'**
  String get installWasmPluginTitle;

  /// No description provided for @selectWasmFile.
  ///
  /// In en, this message translates to:
  /// **'Select .wasm file'**
  String get selectWasmFile;

  /// No description provided for @pluginName.
  ///
  /// In en, this message translates to:
  /// **'Plugin Name'**
  String get pluginName;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameRequired;

  /// No description provided for @pluginDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get pluginDescription;

  /// No description provided for @descriptionRequired.
  ///
  /// In en, this message translates to:
  /// **'Description is required'**
  String get descriptionRequired;

  /// No description provided for @exposedActions.
  ///
  /// In en, this message translates to:
  /// **'Exposed Actions'**
  String get exposedActions;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @pickWasmFileFirst.
  ///
  /// In en, this message translates to:
  /// **'Please pick a .wasm file first'**
  String get pickWasmFileFirst;

  /// No description provided for @pluginInstalledSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Plugin installed successfully'**
  String get pluginInstalledSuccessfully;

  /// No description provided for @failedToInstall.
  ///
  /// In en, this message translates to:
  /// **'Failed to install: {error}'**
  String failedToInstall(String error);

  /// No description provided for @mcpServersTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Modules: MCP Servers'**
  String get mcpServersTitle;

  /// No description provided for @activeServers.
  ///
  /// In en, this message translates to:
  /// **'Active Servers ({count})'**
  String activeServers(int count);

  /// No description provided for @repository.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get repository;

  /// No description provided for @noMcpServers.
  ///
  /// In en, this message translates to:
  /// **'No MCP servers added'**
  String get noMcpServers;

  /// No description provided for @goToRepository.
  ///
  /// In en, this message translates to:
  /// **'Go to Repository'**
  String get goToRepository;

  /// No description provided for @addManually.
  ///
  /// In en, this message translates to:
  /// **'Add Manually'**
  String get addManually;

  /// No description provided for @addServerManually.
  ///
  /// In en, this message translates to:
  /// **'Add Server Manually'**
  String get addServerManually;

  /// No description provided for @installed.
  ///
  /// In en, this message translates to:
  /// **'INSTALLED'**
  String get installed;

  /// No description provided for @packageDetail.
  ///
  /// In en, this message translates to:
  /// **'Package: {detail}'**
  String packageDetail(String detail);

  /// No description provided for @authParam.
  ///
  /// In en, this message translates to:
  /// **'Auth parameter: {key}'**
  String authParam(String key);

  /// No description provided for @enterValueFor.
  ///
  /// In en, this message translates to:
  /// **'Enter value for {key}'**
  String enterValueFor(String key);

  /// No description provided for @enterLabel.
  ///
  /// In en, this message translates to:
  /// **'Enter {label}'**
  String enterLabel(String label);

  /// No description provided for @installPreset.
  ///
  /// In en, this message translates to:
  /// **'Install: {name}'**
  String installPreset(String name);

  /// No description provided for @serverName.
  ///
  /// In en, this message translates to:
  /// **'Server Name'**
  String get serverName;

  /// No description provided for @exampleLocalSearch.
  ///
  /// In en, this message translates to:
  /// **'For example: local-search'**
  String get exampleLocalSearch;

  /// No description provided for @connectionType.
  ///
  /// In en, this message translates to:
  /// **'Connection Type'**
  String get connectionType;

  /// No description provided for @stdioLocal.
  ///
  /// In en, this message translates to:
  /// **'Stdio (Local process)'**
  String get stdioLocal;

  /// No description provided for @sseHttp.
  ///
  /// In en, this message translates to:
  /// **'SSE (HTTP stream)'**
  String get sseHttp;

  /// No description provided for @startCommand.
  ///
  /// In en, this message translates to:
  /// **'Start Command'**
  String get startCommand;

  /// No description provided for @exampleStartCommand.
  ///
  /// In en, this message translates to:
  /// **'For example: node or npx or python3'**
  String get exampleStartCommand;

  /// No description provided for @argsSpace.
  ///
  /// In en, this message translates to:
  /// **'Arguments (separated by space)'**
  String get argsSpace;

  /// No description provided for @searchFilesHint.
  ///
  /// In en, this message translates to:
  /// **'Search files... (type \"#\" for symbols)'**
  String get searchFilesHint;

  /// No description provided for @searchSymbolsHint.
  ///
  /// In en, this message translates to:
  /// **'Search symbols in code...'**
  String get searchSymbolsHint;

  /// No description provided for @modeFiles.
  ///
  /// In en, this message translates to:
  /// **'MODE: FILES'**
  String get modeFiles;

  /// No description provided for @modeSymbols.
  ///
  /// In en, this message translates to:
  /// **'MODE: SYMBOLS'**
  String get modeSymbols;

  /// No description provided for @resultsCount.
  ///
  /// In en, this message translates to:
  /// **'Results: {count}'**
  String resultsCount(int count);

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResults;

  /// No description provided for @confirmDeleteMultiple.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete {count} items?'**
  String confirmDeleteMultiple(int count);

  /// No description provided for @archiveExtracted.
  ///
  /// In en, this message translates to:
  /// **'Archive successfully extracted!'**
  String get archiveExtracted;

  /// No description provided for @archiveCreated.
  ///
  /// In en, this message translates to:
  /// **'Archive successfully created!'**
  String get archiveCreated;

  /// No description provided for @compressToZip.
  ///
  /// In en, this message translates to:
  /// **'Compress to ZIP'**
  String get compressToZip;

  /// No description provided for @folderLabel.
  ///
  /// In en, this message translates to:
  /// **'Folder: {name}'**
  String folderLabel(String name);

  /// No description provided for @fileLabel.
  ///
  /// In en, this message translates to:
  /// **'File: {name}'**
  String fileLabel(String name);

  /// No description provided for @whatShouldAiDoFolder.
  ///
  /// In en, this message translates to:
  /// **'What should AI do with this folder?'**
  String get whatShouldAiDoFolder;

  /// No description provided for @whatShouldAiDoFile.
  ///
  /// In en, this message translates to:
  /// **'What should AI do with this file?'**
  String get whatShouldAiDoFile;

  /// No description provided for @askAi.
  ///
  /// In en, this message translates to:
  /// **'Ask AI'**
  String get askAi;

  /// No description provided for @askAiDesc.
  ///
  /// In en, this message translates to:
  /// **'Interactive chat with AI assistant'**
  String get askAiDesc;

  /// No description provided for @explainStructure.
  ///
  /// In en, this message translates to:
  /// **'AI: Explain Structure'**
  String get explainStructure;

  /// No description provided for @explainStructureDesc.
  ///
  /// In en, this message translates to:
  /// **'Detailed summary of code or folders'**
  String get explainStructureDesc;

  /// No description provided for @addDoc.
  ///
  /// In en, this message translates to:
  /// **'AI: Add Documentation'**
  String get addDoc;

  /// No description provided for @addDocDesc.
  ///
  /// In en, this message translates to:
  /// **'Generate docstrings and comments'**
  String get addDocDesc;

  /// No description provided for @generateTests.
  ///
  /// In en, this message translates to:
  /// **'AI: Generate Tests'**
  String get generateTests;

  /// No description provided for @generateTestsDesc.
  ///
  /// In en, this message translates to:
  /// **'Write unit tests for the code'**
  String get generateTestsDesc;

  /// No description provided for @optimizeCode.
  ///
  /// In en, this message translates to:
  /// **'AI: Optimize'**
  String get optimizeCode;

  /// No description provided for @optimizeCodeDesc.
  ///
  /// In en, this message translates to:
  /// **'Suggest performance improvements'**
  String get optimizeCodeDesc;

  /// No description provided for @newFileDesc.
  ///
  /// In en, this message translates to:
  /// **'Create a file in this folder'**
  String get newFileDesc;

  /// No description provided for @newFolderDesc.
  ///
  /// In en, this message translates to:
  /// **'Create a subfolder'**
  String get newFolderDesc;

  /// No description provided for @removeFromBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Remove from Bookmarks'**
  String get removeFromBookmarks;

  /// No description provided for @removeFromBookmarksDesc.
  ///
  /// In en, this message translates to:
  /// **'Remove file from quick access'**
  String get removeFromBookmarksDesc;

  /// No description provided for @addToBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Add to Bookmarks'**
  String get addToBookmarks;

  /// No description provided for @addToBookmarksDesc.
  ///
  /// In en, this message translates to:
  /// **'Pin file for quick access'**
  String get addToBookmarksDesc;

  /// No description provided for @copyDesc.
  ///
  /// In en, this message translates to:
  /// **'Add to clipboard'**
  String get copyDesc;

  /// No description provided for @cutDesc.
  ///
  /// In en, this message translates to:
  /// **'Move files'**
  String get cutDesc;

  /// No description provided for @pasteDesc.
  ///
  /// In en, this message translates to:
  /// **'Paste copied items'**
  String get pasteDesc;

  /// No description provided for @renameDesc.
  ///
  /// In en, this message translates to:
  /// **'Change item name'**
  String get renameDesc;

  /// No description provided for @extractZip.
  ///
  /// In en, this message translates to:
  /// **'Extract ZIP'**
  String get extractZip;

  /// No description provided for @extractZipDesc.
  ///
  /// In en, this message translates to:
  /// **'Extract files from archive'**
  String get extractZipDesc;

  /// No description provided for @compressZip.
  ///
  /// In en, this message translates to:
  /// **'Compress to ZIP'**
  String get compressZip;

  /// No description provided for @compressZipDesc.
  ///
  /// In en, this message translates to:
  /// **'Create ZIP archive'**
  String get compressZipDesc;

  /// No description provided for @compressSelectedZip.
  ///
  /// In en, this message translates to:
  /// **'Compress selected to ZIP'**
  String get compressSelectedZip;

  /// No description provided for @compressSelectedZipDesc.
  ///
  /// In en, this message translates to:
  /// **'Create archive from selected items'**
  String get compressSelectedZipDesc;

  /// No description provided for @deleteDesc.
  ///
  /// In en, this message translates to:
  /// **'Permanent delete'**
  String get deleteDesc;

  /// No description provided for @empty.
  ///
  /// In en, this message translates to:
  /// **'empty'**
  String get empty;

  /// No description provided for @nameFolderHint.
  ///
  /// In en, this message translates to:
  /// **'folder_name'**
  String get nameFolderHint;

  /// No description provided for @nameFileHint.
  ///
  /// In en, this message translates to:
  /// **'file_name.txt'**
  String get nameFileHint;

  /// No description provided for @itemMoved.
  ///
  /// In en, this message translates to:
  /// **'Item successfully moved'**
  String get itemMoved;

  /// No description provided for @moveError.
  ///
  /// In en, this message translates to:
  /// **'Move error: {error}'**
  String moveError(String error);

  /// No description provided for @image.
  ///
  /// In en, this message translates to:
  /// **'IMAGE'**
  String get image;

  /// No description provided for @document.
  ///
  /// In en, this message translates to:
  /// **'DOCUMENT'**
  String get document;

  /// No description provided for @failedToLoadImage.
  ///
  /// In en, this message translates to:
  /// **'Failed to load image'**
  String get failedToLoadImage;

  /// No description provided for @failedToReadFile.
  ///
  /// In en, this message translates to:
  /// **'Failed to read file: {error}'**
  String failedToReadFile(String error);

  /// No description provided for @aiSettings.
  ///
  /// In en, this message translates to:
  /// **'AI Settings'**
  String get aiSettings;

  /// No description provided for @provider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get provider;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @apiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get apiKey;

  /// No description provided for @customBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Custom Base URL'**
  String get customBaseUrl;

  /// No description provided for @defaultHint.
  ///
  /// In en, this message translates to:
  /// **'Default: {url}'**
  String defaultHint(String url);

  /// No description provided for @chatWithAi.
  ///
  /// In en, this message translates to:
  /// **'CHAT WITH AI'**
  String get chatWithAi;

  /// No description provided for @chatHistory.
  ///
  /// In en, this message translates to:
  /// **'Chat History'**
  String get chatHistory;

  /// No description provided for @newChat.
  ///
  /// In en, this message translates to:
  /// **'New Chat'**
  String get newChat;

  /// No description provided for @internetAccess.
  ///
  /// In en, this message translates to:
  /// **'Internet Access'**
  String get internetAccess;

  /// No description provided for @mcpServers.
  ///
  /// In en, this message translates to:
  /// **'MCP Servers'**
  String get mcpServers;

  /// No description provided for @manualMode.
  ///
  /// In en, this message translates to:
  /// **'Manual Mode'**
  String get manualMode;

  /// No description provided for @safeAutopilot.
  ///
  /// In en, this message translates to:
  /// **'Safe Autopilot'**
  String get safeAutopilot;

  /// No description provided for @fullAutonomy.
  ///
  /// In en, this message translates to:
  /// **'Full Autonomy'**
  String get fullAutonomy;

  /// No description provided for @agentsNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'Agents not installed'**
  String get agentsNotInstalled;

  /// No description provided for @installGeminiCliInSettings.
  ///
  /// In en, this message translates to:
  /// **'Install gemini-cli in settings'**
  String get installGeminiCliInSettings;

  /// No description provided for @stopAgent.
  ///
  /// In en, this message translates to:
  /// **'STOP AGENT'**
  String get stopAgent;

  /// No description provided for @withChanges.
  ///
  /// In en, this message translates to:
  /// **'with changes'**
  String get withChanges;

  /// No description provided for @attachOpenFile.
  ///
  /// In en, this message translates to:
  /// **'Attach open file'**
  String get attachOpenFile;

  /// No description provided for @noHistoryFound.
  ///
  /// In en, this message translates to:
  /// **'No history found'**
  String get noHistoryFound;

  /// No description provided for @untitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get untitled;

  /// No description provided for @messagesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} messages'**
  String messagesCount(int count);

  /// No description provided for @systemEnv.
  ///
  /// In en, this message translates to:
  /// **'System Environment'**
  String get systemEnv;

  /// No description provided for @fixEnvironmentArm64.
  ///
  /// In en, this message translates to:
  /// **'Fix Environment (ARM64)'**
  String get fixEnvironmentArm64;

  /// No description provided for @environment.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get environment;

  /// No description provided for @collapseAll.
  ///
  /// In en, this message translates to:
  /// **'Collapse All'**
  String get collapseAll;

  /// No description provided for @elementMovedToRoot.
  ///
  /// In en, this message translates to:
  /// **'Element moved to root'**
  String get elementMovedToRoot;

  /// No description provided for @bookmarks.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get bookmarks;

  /// No description provided for @noActiveWasmPlugins.
  ///
  /// In en, this message translates to:
  /// **'No active WASM plugins'**
  String get noActiveWasmPlugins;

  /// No description provided for @selectPluginAction.
  ///
  /// In en, this message translates to:
  /// **'Select Plugin Action'**
  String get selectPluginAction;

  /// No description provided for @noSelection.
  ///
  /// In en, this message translates to:
  /// **'No selection'**
  String get noSelection;

  /// No description provided for @applyPluginToFile.
  ///
  /// In en, this message translates to:
  /// **'Apply plugin action to the entire file?'**
  String get applyPluginToFile;

  /// No description provided for @pluginExecutedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Plugin executed successfully'**
  String get pluginExecutedSuccess;

  /// No description provided for @executionError.
  ///
  /// In en, this message translates to:
  /// **'Execution error: {error}'**
  String executionError(String error);

  /// No description provided for @quickSearch.
  ///
  /// In en, this message translates to:
  /// **'Quick Search (Ctrl+P)'**
  String get quickSearch;

  /// No description provided for @saveTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveTooltip;

  /// No description provided for @runWasmPlugin.
  ///
  /// In en, this message translates to:
  /// **'Run WASM Plugin'**
  String get runWasmPlugin;

  /// No description provided for @aiChat.
  ///
  /// In en, this message translates to:
  /// **'AI Chat'**
  String get aiChat;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @pendingDiff.
  ///
  /// In en, this message translates to:
  /// **'Pending Diff'**
  String get pendingDiff;

  /// No description provided for @keep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keep;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @keepAll.
  ///
  /// In en, this message translates to:
  /// **'Keep all'**
  String get keepAll;

  /// No description provided for @ranAction.
  ///
  /// In en, this message translates to:
  /// **'Ran: {content}'**
  String ranAction(String content);

  /// No description provided for @created.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get created;

  /// No description provided for @deleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get deleted;

  /// No description provided for @edited.
  ///
  /// In en, this message translates to:
  /// **'Edited'**
  String get edited;

  /// No description provided for @taskExecution.
  ///
  /// In en, this message translates to:
  /// **'Task Execution'**
  String get taskExecution;

  /// No description provided for @stepNumber.
  ///
  /// In en, this message translates to:
  /// **'Step {step}/{total}'**
  String stepNumber(int step, int total);

  /// No description provided for @filesChangedCount.
  ///
  /// In en, this message translates to:
  /// **'Files changed: {count} (+{additions} -{deletions})'**
  String filesChangedCount(int count, int additions, int deletions);

  /// No description provided for @commandsExecutedCount.
  ///
  /// In en, this message translates to:
  /// **'Executed {count} commands'**
  String commandsExecutedCount(int count);

  /// No description provided for @changesAccepted.
  ///
  /// In en, this message translates to:
  /// **'Changes accepted and stashed'**
  String get changesAccepted;

  /// No description provided for @undoneChanges.
  ///
  /// In en, this message translates to:
  /// **'Undid {count} file changes'**
  String undoneChanges(int count);

  /// No description provided for @discardedFileChanges.
  ///
  /// In en, this message translates to:
  /// **'Discarded changes in {file}'**
  String discardedFileChanges(String file);

  /// No description provided for @thinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking...'**
  String get thinking;

  /// No description provided for @planner.
  ///
  /// In en, this message translates to:
  /// **'PLANNER'**
  String get planner;

  /// No description provided for @coder.
  ///
  /// In en, this message translates to:
  /// **'CODER'**
  String get coder;

  /// No description provided for @validator.
  ///
  /// In en, this message translates to:
  /// **'VALIDATOR'**
  String get validator;

  /// No description provided for @aiAgentRole.
  ///
  /// In en, this message translates to:
  /// **'AI-AGENT'**
  String get aiAgentRole;

  /// No description provided for @resubmit.
  ///
  /// In en, this message translates to:
  /// **'Resubmit'**
  String get resubmit;

  /// No description provided for @rollbackHistoryToStep.
  ///
  /// In en, this message translates to:
  /// **'Rollback history and code to this step'**
  String get rollbackHistoryToStep;

  /// No description provided for @confirmRollback.
  ///
  /// In en, this message translates to:
  /// **'Confirm Rollback'**
  String get confirmRollback;

  /// No description provided for @rollbackConfirmationText.
  ///
  /// In en, this message translates to:
  /// **'All code changes made after this message will be reverted, and subsequent messages deleted. Continue?'**
  String get rollbackConfirmationText;

  /// No description provided for @yesRollback.
  ///
  /// In en, this message translates to:
  /// **'Yes, rollback'**
  String get yesRollback;

  /// No description provided for @changesApplied.
  ///
  /// In en, this message translates to:
  /// **'Changes applied'**
  String get changesApplied;

  /// No description provided for @codeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied to clipboard'**
  String get codeCopied;

  /// No description provided for @outOfScope.
  ///
  /// In en, this message translates to:
  /// **'Out of scope!'**
  String get outOfScope;

  /// No description provided for @low.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get low;

  /// No description provided for @medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get medium;

  /// No description provided for @high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get high;

  /// No description provided for @applied.
  ///
  /// In en, this message translates to:
  /// **'Applied'**
  String get applied;

  /// No description provided for @resolveConflictTooltip.
  ///
  /// In en, this message translates to:
  /// **'Resolve conflict'**
  String get resolveConflictTooltip;

  /// No description provided for @panel1.
  ///
  /// In en, this message translates to:
  /// **'PANEL 1'**
  String get panel1;

  /// No description provided for @panel2.
  ///
  /// In en, this message translates to:
  /// **'PANEL 2'**
  String get panel2;

  /// No description provided for @localWebServer.
  ///
  /// In en, this message translates to:
  /// **'Local Web Server'**
  String get localWebServer;

  /// No description provided for @webServerDesc.
  ///
  /// In en, this message translates to:
  /// **'Start web server to preview your project\'s build results right inside the IDE.'**
  String get webServerDesc;

  /// No description provided for @startWebServer.
  ///
  /// In en, this message translates to:
  /// **'Start Web Server'**
  String get startWebServer;

  /// No description provided for @stopWebServer.
  ///
  /// In en, this message translates to:
  /// **'Stop Web Server'**
  String get stopWebServer;

  /// No description provided for @copyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy All'**
  String get copyAll;

  /// No description provided for @clearTerminal.
  ///
  /// In en, this message translates to:
  /// **'Clear Terminal'**
  String get clearTerminal;

  /// No description provided for @openInExternalBrowser.
  ///
  /// In en, this message translates to:
  /// **'Open in external browser'**
  String get openInExternalBrowser;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @structure.
  ///
  /// In en, this message translates to:
  /// **'Structure'**
  String get structure;

  /// No description provided for @disk.
  ///
  /// In en, this message translates to:
  /// **'Disk'**
  String get disk;

  /// No description provided for @plugins.
  ///
  /// In en, this message translates to:
  /// **'Plugins'**
  String get plugins;

  /// No description provided for @added.
  ///
  /// In en, this message translates to:
  /// **'added'**
  String get added;

  /// No description provided for @removed.
  ///
  /// In en, this message translates to:
  /// **'removed'**
  String get removed;

  /// No description provided for @modified.
  ///
  /// In en, this message translates to:
  /// **'modified'**
  String get modified;

  /// No description provided for @selectedObjectsCount.
  ///
  /// In en, this message translates to:
  /// **'Selected objects: {count}'**
  String selectedObjectsCount(int count);

  /// No description provided for @explainFolderPreset.
  ///
  /// In en, this message translates to:
  /// **'Explain the purpose and structure of this folder.'**
  String get explainFolderPreset;

  /// No description provided for @explainFilePreset.
  ///
  /// In en, this message translates to:
  /// **'Explain in detail the purpose and operational logic of this file.'**
  String get explainFilePreset;

  /// No description provided for @addDocFolderPreset.
  ///
  /// In en, this message translates to:
  /// **'Add documentation, docstrings, and detailed comments to the code in all files of this folder.'**
  String get addDocFolderPreset;

  /// No description provided for @addDocFilePreset.
  ///
  /// In en, this message translates to:
  /// **'Add clear documentation, docstrings, and detailed comments to the code in this file.'**
  String get addDocFilePreset;

  /// No description provided for @generateTestsFolderPreset.
  ///
  /// In en, this message translates to:
  /// **'Write unit tests for the files in this folder.'**
  String get generateTestsFolderPreset;

  /// No description provided for @generateTestsFilePreset.
  ///
  /// In en, this message translates to:
  /// **'Write comprehensive unit tests for the code in this file.'**
  String get generateTestsFilePreset;

  /// No description provided for @optimizeFolderPreset.
  ///
  /// In en, this message translates to:
  /// **'Analyze the code in this folder and suggest optimizations for performance and readability.'**
  String get optimizeFolderPreset;

  /// No description provided for @optimizeFilePreset.
  ///
  /// In en, this message translates to:
  /// **'Analyze the code in this file and suggest options for optimizing performance, readability, and architecture.'**
  String get optimizeFilePreset;

  /// No description provided for @deleteSelected.
  ///
  /// In en, this message translates to:
  /// **'Delete Selected'**
  String get deleteSelected;

  /// No description provided for @manual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manual;

  /// No description provided for @autoSafe.
  ///
  /// In en, this message translates to:
  /// **'Auto:Safe'**
  String get autoSafe;

  /// No description provided for @autoFull.
  ///
  /// In en, this message translates to:
  /// **'Auto:Full'**
  String get autoFull;

  /// No description provided for @filesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{file} other{files}}'**
  String filesCount(int count);

  /// No description provided for @localAiEngineTitle.
  ///
  /// In en, this message translates to:
  /// **'LOCAL AI ENGINE'**
  String get localAiEngineTitle;

  /// No description provided for @ollamaRunningLocally.
  ///
  /// In en, this message translates to:
  /// **'Ollama is running locally'**
  String get ollamaRunningLocally;

  /// No description provided for @ollamaRunningLocallyDesc.
  ///
  /// In en, this message translates to:
  /// **'Make sure Ollama is running on your system. You can start it with \"ollama serve\" and pull models with \"ollama pull <model>\".'**
  String get ollamaRunningLocallyDesc;

  /// No description provided for @lmStudioRunningLocally.
  ///
  /// In en, this message translates to:
  /// **'LM Studio is running locally'**
  String get lmStudioRunningLocally;

  /// No description provided for @lmStudioRunningLocallyDesc.
  ///
  /// In en, this message translates to:
  /// **'Make sure LM Studio server is running. You can enable Local Server in the LM Studio application and load the required model.'**
  String get lmStudioRunningLocallyDesc;

  /// No description provided for @ollamaNotDetected.
  ///
  /// In en, this message translates to:
  /// **'Ollama not detected'**
  String get ollamaNotDetected;

  /// No description provided for @ollamaNotDetectedDesc.
  ///
  /// In en, this message translates to:
  /// **'Install Ollama on your device and make sure it is running. The URL can be modified above.'**
  String get ollamaNotDetectedDesc;

  /// No description provided for @checkConnection.
  ///
  /// In en, this message translates to:
  /// **'Check Connection'**
  String get checkConnection;

  /// No description provided for @availableOllamaModels.
  ///
  /// In en, this message translates to:
  /// **'AVAILABLE OLLAMA MODELS'**
  String get availableOllamaModels;

  /// No description provided for @llamaServerInstallRequired.
  ///
  /// In en, this message translates to:
  /// **'llama-server Installation Required'**
  String get llamaServerInstallRequired;

  /// No description provided for @llamaServerInstallRequiredDesc.
  ///
  /// In en, this message translates to:
  /// **'Llama-server engine is required to run local AI models. Click the button below to install it automatically.'**
  String get llamaServerInstallRequiredDesc;

  /// No description provided for @installing.
  ///
  /// In en, this message translates to:
  /// **'Installing...'**
  String get installing;

  /// No description provided for @installLlamaServerRuntime.
  ///
  /// In en, this message translates to:
  /// **'Install Llama Server Runtime'**
  String get installLlamaServerRuntime;

  /// No description provided for @ollamaModelsTitle.
  ///
  /// In en, this message translates to:
  /// **'OLLAMA MODELS'**
  String get ollamaModelsTitle;

  /// No description provided for @localAiModelsTitle.
  ///
  /// In en, this message translates to:
  /// **'LOCAL AI MODELS'**
  String get localAiModelsTitle;

  /// No description provided for @serverStatusAndControl.
  ///
  /// In en, this message translates to:
  /// **'SERVER STATUS & CONTROL'**
  String get serverStatusAndControl;

  /// No description provided for @downloadOllamaModelPrompt.
  ///
  /// In en, this message translates to:
  /// **'Download at least one Ollama model to get started.'**
  String get downloadOllamaModelPrompt;

  /// No description provided for @downloadModelToStartServerPrompt.
  ///
  /// In en, this message translates to:
  /// **'Download at least one model above to launch the local server.'**
  String get downloadModelToStartServerPrompt;

  /// No description provided for @localLlamaServerLabel.
  ///
  /// In en, this message translates to:
  /// **'Local llama-server'**
  String get localLlamaServerLabel;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connected;

  /// No description provided for @runningPort8080.
  ///
  /// In en, this message translates to:
  /// **'Running (port 8080)'**
  String get runningPort8080;

  /// No description provided for @starting.
  ///
  /// In en, this message translates to:
  /// **'Starting...'**
  String get starting;

  /// No description provided for @stopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get stopped;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @gbFormat.
  ///
  /// In en, this message translates to:
  /// **'{size} GB'**
  String gbFormat(String size);

  /// No description provided for @ramGbFormat.
  ///
  /// In en, this message translates to:
  /// **'~{size} GB RAM'**
  String ramGbFormat(String size);

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// No description provided for @refreshPreview.
  ///
  /// In en, this message translates to:
  /// **'Refresh Preview'**
  String get refreshPreview;

  /// No description provided for @inFolder.
  ///
  /// In en, this message translates to:
  /// **'in {folder}'**
  String inFolder(String folder);

  /// No description provided for @llamaServerBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'llama-server (built-in)'**
  String get llamaServerBuiltIn;

  /// No description provided for @localAiDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Local AI'**
  String get localAiDisplayName;

  /// No description provided for @notRequired.
  ///
  /// In en, this message translates to:
  /// **'not required'**
  String get notRequired;

  /// No description provided for @mcpGithubDesc.
  ///
  /// In en, this message translates to:
  /// **'Integration with GitHub repositories, issues, and PRs.'**
  String get mcpGithubDesc;

  /// No description provided for @mcpGoogleSearchDesc.
  ///
  /// In en, this message translates to:
  /// **'Allows the AI agent to perform live Google searches.'**
  String get mcpGoogleSearchDesc;

  /// No description provided for @mcpFetchDesc.
  ///
  /// In en, this message translates to:
  /// **'Download web pages and automatically translate them to Markdown.'**
  String get mcpFetchDesc;

  /// No description provided for @mcpPostgresDesc.
  ///
  /// In en, this message translates to:
  /// **'Connect, read table structure, and run SQL queries on PostgreSQL.'**
  String get mcpPostgresDesc;

  /// No description provided for @mcpPostgresArg.
  ///
  /// In en, this message translates to:
  /// **'Connection string (postgresql://...)'**
  String get mcpPostgresArg;

  /// No description provided for @mcpSqliteDesc.
  ///
  /// In en, this message translates to:
  /// **'Connect and inspect SQLite databases in your project.'**
  String get mcpSqliteDesc;

  /// No description provided for @mcpSqliteArg.
  ///
  /// In en, this message translates to:
  /// **'Path to SQLite DB file (e.g. db.sqlite)'**
  String get mcpSqliteArg;

  /// No description provided for @mcpMemoryDesc.
  ///
  /// In en, this message translates to:
  /// **'Semantic long-term memory storage for your AI agent.'**
  String get mcpMemoryDesc;

  /// No description provided for @mcpBraveSearchDesc.
  ///
  /// In en, this message translates to:
  /// **'Allows the AI agent to perform web searches using the Brave API.'**
  String get mcpBraveSearchDesc;

  /// No description provided for @mcpPuppeteerDesc.
  ///
  /// In en, this message translates to:
  /// **'Browser automation, screenshot generation, element clicking, and web scraping.'**
  String get mcpPuppeteerDesc;

  /// No description provided for @mcpFirecrawlDesc.
  ///
  /// In en, this message translates to:
  /// **'Convert any website into clean Markdown or structured JSON.'**
  String get mcpFirecrawlDesc;

  /// No description provided for @mcpNotionDesc.
  ///
  /// In en, this message translates to:
  /// **'Read and modify Notion pages, databases, and comments.'**
  String get mcpNotionDesc;

  /// No description provided for @mcpSlackDesc.
  ///
  /// In en, this message translates to:
  /// **'Provides the ability to read channels, chat, and send notifications in Slack.'**
  String get mcpSlackDesc;

  /// No description provided for @mcpGitDesc.
  ///
  /// In en, this message translates to:
  /// **'View commits, compare versions, search commits, and inspect files locally via Git.'**
  String get mcpGitDesc;

  /// No description provided for @mcpGitlabDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage GitLab projects, issues, PRs, and CI/CD pipelines.'**
  String get mcpGitlabDesc;

  /// No description provided for @mcpSentryDesc.
  ///
  /// In en, this message translates to:
  /// **'Retrieve error logs and inspect crashes of your application on Sentry.'**
  String get mcpSentryDesc;

  /// No description provided for @mcpAirtableDesc.
  ///
  /// In en, this message translates to:
  /// **'Read, create, and update records in Airtable databases and tables.'**
  String get mcpAirtableDesc;

  /// No description provided for @mcpSequentialThinkingDesc.
  ///
  /// In en, this message translates to:
  /// **'Organize AI agent thoughts for structured problem solving.'**
  String get mcpSequentialThinkingDesc;

  /// No description provided for @phantomProcessesTitle.
  ///
  /// In en, this message translates to:
  /// **'Phantom Processes (Android 12/13+)'**
  String get phantomProcessesTitle;

  /// No description provided for @phantomProcessesVersion.
  ///
  /// In en, this message translates to:
  /// **'ADB configuration required for stable compilation'**
  String get phantomProcessesVersion;

  /// No description provided for @phantomProcessesError.
  ///
  /// In en, this message translates to:
  /// **'In Android 12+, the system process killer (Phantom Process Killer) terminates builds (Gradle/Java/Node/Dart) if the limit exceeds 32 active processes.\n\nTo disable, run via ADB on your PC:\n\nadb shell \"/system/bin/device_config put activity_manager max_phantom_processes 2147483647\"\n\nadb shell \"/system/bin/settings put global settings_enable_monitor_phantom_procs false\"'**
  String get phantomProcessesError;

  /// No description provided for @androidJarCorruptError.
  ///
  /// In en, this message translates to:
  /// **'android.jar is corrupt ({api}). Click \"Fix Environment\" to reinstall.'**
  String androidJarCorruptError(String api);

  /// No description provided for @androidSdkPlatformsHealthy.
  ///
  /// In en, this message translates to:
  /// **'android-35 / android-36 — healthy'**
  String get androidSdkPlatformsHealthy;

  /// No description provided for @checkFailed.
  ///
  /// In en, this message translates to:
  /// **'Check failed: {error}'**
  String checkFailed(String error);

  /// No description provided for @analyzingTaskAndPlanning.
  ///
  /// In en, this message translates to:
  /// **'Analyzing task & planning...'**
  String get analyzingTaskAndPlanning;

  /// No description provided for @agentStepLimitExceeded.
  ///
  /// In en, this message translates to:
  /// **'🤖 Agent step limit ({limit}) exceeded. Autopilot stopped.'**
  String agentStepLimitExceeded(int limit);

  /// No description provided for @generatingCodeChanges.
  ///
  /// In en, this message translates to:
  /// **'Generating code changes...'**
  String get generatingCodeChanges;

  /// No description provided for @executionPlanConstructed.
  ///
  /// In en, this message translates to:
  /// **'📝 Execution plan constructed. Transitioning to Coder role...'**
  String get executionPlanConstructed;

  /// No description provided for @verifyingImplementation.
  ///
  /// In en, this message translates to:
  /// **'Verifying implementation correctness...'**
  String get verifyingImplementation;

  /// No description provided for @blockedUnsafeActions.
  ///
  /// In en, this message translates to:
  /// **'❌ Blocked unsafe actions outside workspace scope:\n{blockedText}'**
  String blockedUnsafeActions(String blockedText);

  /// No description provided for @awaitingApprovalHighRisk.
  ///
  /// In en, this message translates to:
  /// **'⚠️ Awaiting approval: High-risk actions detected or autopilot is restricted. Please approve them in the AI panel.'**
  String get awaitingApprovalHighRisk;

  /// No description provided for @autopilotStepSummary.
  ///
  /// In en, this message translates to:
  /// **'🤖 Autopilot (step {step}): Auto-Approval of actions:\n{actionsListText}\n\nResults:\n{results}'**
  String autopilotStepSummary(int step, String actionsListText, String results);

  /// No description provided for @runningStaticAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Running project static analysis (dart analyze)...'**
  String get runningStaticAnalysis;

  /// No description provided for @agentFailedToFixErrors.
  ///
  /// In en, this message translates to:
  /// **'⚠️ Agent failed to fix errors after {maxAttempts} attempts.\n\n**Remaining errors:**\n{errorReport}\n\nPlease describe the issue or fix manually.'**
  String agentFailedToFixErrors(int maxAttempts, String errorReport);

  /// No description provided for @fixingCompilationErrors.
  ///
  /// In en, this message translates to:
  /// **'Fixing compilation errors...'**
  String get fixingCompilationErrors;

  /// No description provided for @readingFile.
  ///
  /// In en, this message translates to:
  /// **'Reading file {path}...'**
  String readingFile(String path);

  /// No description provided for @savingFile.
  ///
  /// In en, this message translates to:
  /// **'Saving file {path}...'**
  String savingFile(String path);

  /// No description provided for @deletingFile.
  ///
  /// In en, this message translates to:
  /// **'Deleting file {path}...'**
  String deletingFile(String path);

  /// No description provided for @runningCommandStatus.
  ///
  /// In en, this message translates to:
  /// **'Running command \"{command}\"...'**
  String runningCommandStatus(String command);

  /// No description provided for @searchingCode.
  ///
  /// In en, this message translates to:
  /// **'Searching code: \"{query}\"...'**
  String searchingCode(String query);

  /// No description provided for @listingDirectory.
  ///
  /// In en, this message translates to:
  /// **'Listing directory {path}...'**
  String listingDirectory(String path);

  /// No description provided for @findingSymbols.
  ///
  /// In en, this message translates to:
  /// **'Finding symbols: \"{query}\"...'**
  String findingSymbols(String query);

  /// No description provided for @searchingWeb.
  ///
  /// In en, this message translates to:
  /// **'Searching web: \"{query}\"...'**
  String searchingWeb(String query);

  /// No description provided for @fetchingWebPage.
  ///
  /// In en, this message translates to:
  /// **'Fetching web page: {path}...'**
  String fetchingWebPage(String path);

  /// No description provided for @executingAction.
  ///
  /// In en, this message translates to:
  /// **'Executing action...'**
  String get executingAction;

  /// No description provided for @runningCommandLabel.
  ///
  /// In en, this message translates to:
  /// **'🤖 Running command: {command}...'**
  String runningCommandLabel(String command);

  /// No description provided for @applyingChangeLabel.
  ///
  /// In en, this message translates to:
  /// **'🤖 Applying change: {path}...'**
  String applyingChangeLabel(String path);

  /// No description provided for @commandSentToTerminalLabel.
  ///
  /// In en, this message translates to:
  /// **'🤖 Command \"{command}\" sent to terminal.'**
  String commandSentToTerminalLabel(String command);

  /// No description provided for @runningCommandResultLabel.
  ///
  /// In en, this message translates to:
  /// **'Command \"{command}\" executed. Result:\n{result}'**
  String runningCommandResultLabel(String command, String result);

  /// No description provided for @fileNotFound.
  ///
  /// In en, this message translates to:
  /// **'File not found: {path}'**
  String fileNotFound(String path);

  /// No description provided for @fileContentsHeader.
  ///
  /// In en, this message translates to:
  /// **'File contents of `{path}` ({lineCount} lines):\n\n```\n{truncated}\n```'**
  String fileContentsHeader(String path, int lineCount, String truncated);

  /// No description provided for @fileTruncatedSuffix.
  ///
  /// In en, this message translates to:
  /// **'... [truncated to 8000 chars from {lineCount} lines]'**
  String fileTruncatedSuffix(int lineCount);

  /// No description provided for @safetyGuardFileOutsideWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Error: Attempted file modification outside the project scope.'**
  String get safetyGuardFileOutsideWorkspace;

  /// No description provided for @commandRefPathOutsideWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Security error: Command references path outside project scope.'**
  String get commandRefPathOutsideWorkspace;

  /// No description provided for @commandBlockedUnsafe.
  ///
  /// In en, this message translates to:
  /// **'Security error: Command contains blocked instruction \"{blocked}\".'**
  String commandBlockedUnsafe(String blocked);

  /// No description provided for @aiSearchNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches found for \"{query}\".'**
  String aiSearchNoMatches(String query);

  /// No description provided for @aiSearchMatchesFound.
  ///
  /// In en, this message translates to:
  /// **'Found {matchCount} matches for \"{query}\":\n\n{results}'**
  String aiSearchMatchesFound(int matchCount, String query, String results);

  /// No description provided for @searchSymbolsNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No symbols found matching \"{query}\".'**
  String searchSymbolsNoMatches(String query);

  /// No description provided for @searchSymbolsMatchesFound.
  ///
  /// In en, this message translates to:
  /// **'Found {count} symbols matching \"{query}\":\n\n{results}'**
  String searchSymbolsMatchesFound(int count, String query, String results);

  /// No description provided for @searchSymbolsItem.
  ///
  /// In en, this message translates to:
  /// **'- [{type}] {name} (file: {path}, line: {line})'**
  String searchSymbolsItem(String type, String name, String path, int line);

  /// No description provided for @directoryNotFound.
  ///
  /// In en, this message translates to:
  /// **'Directory not found: {path}'**
  String directoryNotFound(String path);

  /// No description provided for @directoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Directory is empty.'**
  String get directoryEmpty;

  /// No description provided for @directoryContentsHeader.
  ///
  /// In en, this message translates to:
  /// **'Directory contents:\n\n{items}'**
  String directoryContentsHeader(String items);

  /// No description provided for @mcpMissingParams.
  ///
  /// In en, this message translates to:
  /// **'Error: MCP server or tool name is not specified.'**
  String get mcpMissingParams;

  /// No description provided for @unknownAction.
  ///
  /// In en, this message translates to:
  /// **'Unknown action type: {type}'**
  String unknownAction(String type);

  /// No description provided for @failedToApplyActionWithError.
  ///
  /// In en, this message translates to:
  /// **'Failed to apply action: {error}'**
  String failedToApplyActionWithError(String error);

  /// No description provided for @searchQueryEmpty.
  ///
  /// In en, this message translates to:
  /// **'Error: Search query is empty.'**
  String get searchQueryEmpty;

  /// No description provided for @workspaceNotFound.
  ///
  /// In en, this message translates to:
  /// **'Error: Workspace not found.'**
  String get workspaceNotFound;

  /// No description provided for @webPreviewStopped.
  ///
  /// In en, this message translates to:
  /// **'Web Preview Stopped'**
  String get webPreviewStopped;

  /// No description provided for @webPreviewStartInstructions.
  ///
  /// In en, this message translates to:
  /// **'Start server and click Play button.'**
  String get webPreviewStartInstructions;
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
      <String>['en', 'es', 'fr', 'ru', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'ru':
      return AppLocalizationsRu();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
