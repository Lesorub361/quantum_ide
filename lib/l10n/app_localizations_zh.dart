// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'QuantumIDE';

  @override
  String get explorer => '资源管理器';

  @override
  String get newFile => '新建文件';

  @override
  String get newFolder => '新建文件夹';

  @override
  String get refresh => '刷新';

  @override
  String get rename => '重命名';

  @override
  String get delete => '删除';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get create => '创建';

  @override
  String get projectNotOpened => '项目未打开';

  @override
  String get selectFileToStart => '在资源管理器中选择文件以开始工作';

  @override
  String get openExplorer => '打开资源管理器';

  @override
  String get confirmDelete => '确认删除';

  @override
  String areYouSureDelete(String name) {
    return '您确定要删除 $name 吗？';
  }

  @override
  String get terminal => '终端';

  @override
  String get run => '运行';

  @override
  String get build => '构建';

  @override
  String get aiAgent => 'AI 代理';

  @override
  String get servers => '服务器';

  @override
  String get buildLogs => '构建日志';

  @override
  String get appLogs => '应用日志';

  @override
  String get copy => '复制';

  @override
  String get stop => '停止';

  @override
  String get hotReload => '热重载';

  @override
  String get clear => '清除';

  @override
  String get runProject => '运行项目';

  @override
  String get pubGet => 'Pub Get';

  @override
  String get setupSdk => '设置 SDK';

  @override
  String get clean => '清理';

  @override
  String get buildApk => '构建 APK';

  @override
  String get welcomeMessage => '欢迎使用您的优质环境。';

  @override
  String get typeRunToStart => '输入 run 启动您的项目。';

  @override
  String get settings => '设置';

  @override
  String get interfaceAndLocalization => '界面与本地化';

  @override
  String get language => '语言';

  @override
  String get theme => '主题';

  @override
  String get darkTheme => '深色主题';

  @override
  String get lightTheme => '浅色主题';

  @override
  String get colorPalette => '调色板';

  @override
  String get customColor => '自定义颜色';

  @override
  String get accentColor => '强调色';

  @override
  String get projectIcon => '项目图标';

  @override
  String get defaultAccent => '默认';

  @override
  String get codeEditor => '代码编辑器';

  @override
  String get editorFontSize => '编辑器字号';

  @override
  String get autoCompletion => '自动补全';

  @override
  String get showCodeHints => '显示代码提示';

  @override
  String get aiAutoCompletion => 'AI 自动补全';

  @override
  String get geminiCodeGeneration => 'Gemini 代码生成';

  @override
  String get wordWrap => '自动换行';

  @override
  String get wordWrapDescription => '在编辑器中自动换行';

  @override
  String get lineNumbers => '行号';

  @override
  String get showLineNumbers => '显示行号';

  @override
  String get minimap => '缩略图';

  @override
  String get showMinimap => '显示编辑器缩略图';

  @override
  String get autoSave => '自动保存';

  @override
  String get autoSaveDescription => '2秒后自动保存更改';

  @override
  String get terminalFontSize => '终端字号';

  @override
  String get terminalTheme => '终端主题';

  @override
  String get toolsAndAi => '工具与 AI';

  @override
  String get aiProviders => 'AI 提供商';

  @override
  String get aiProvidersSubtitle => 'Gemini、OpenAI、Ollama 等';

  @override
  String get ubuntuPackages => 'Ubuntu 软件包';

  @override
  String get manageCliTools => '管理命令行工具';

  @override
  String get hosts => '主机';

  @override
  String get localRemoteHosts => '本地/远程主机';

  @override
  String get system => '系统';

  @override
  String get showHiddenFiles => '显示隐藏文件';

  @override
  String get showHiddenFilesDescription => '显示 .* 文件';

  @override
  String get vibration => '震动';

  @override
  String get hapticFeedback => '触觉反馈';

  @override
  String get aboutApp => '关于应用';

  @override
  String get aboutAppSubtitle => 'Quantum IDE v1.0.0';

  @override
  String get selectPalette => '选择调色板';

  @override
  String get close => '关闭';

  @override
  String get resetToDefault => '重置为默认';

  @override
  String get aboutDialogContent =>
      '基于 Flutter 构建的 AI 驱动移动端 IDE。\n© 2026 Quantum IDE';

  @override
  String get ubuntuDarkPurple => 'Ubuntu 暗紫';

  @override
  String get pureDark => '纯黑';

  @override
  String get searchProjects => '搜索项目...';

  @override
  String get open => '打开';

  @override
  String get market => '市场';

  @override
  String projectsHeader(int count) {
    return '项目 ($count)';
  }

  @override
  String get noProjects => '无项目';

  @override
  String get nothingFound => '未找到任何内容';

  @override
  String get createFirstProject => '创建第一个项目';

  @override
  String get projectActions => '项目操作';

  @override
  String get fixAndroidBuild => '修复 Android 构建 (AGP + compileSdk)';

  @override
  String get patchAndroidBuildDescription =>
      '修复 android-36 / AGP 8.7.3 / compileSdk 35';

  @override
  String get buildApkDescription => 'flutter build apk --debug';

  @override
  String apkBuildFixed(String name) {
    return '已修复项目 \"$name\" 的 Android 构建文件';
  }

  @override
  String confirmDeleteTitle(String name) {
    return '确认删除';
  }

  @override
  String get confirmDeleteMessage => '仅从列表中删除，还是同时删除文件？';

  @override
  String get deleteFromListOnly => '仅从列表';

  @override
  String get deleteFromDisk => '从磁盘中删除';

  @override
  String get projectSettings => '项目设置';

  @override
  String get createProject => '创建项目';

  @override
  String get projectName => '项目名称';

  @override
  String get projectType => '项目类型';

  @override
  String get androidCompileSdkVersion => 'ANDROID compileSdk 版本';

  @override
  String get defaultSdkVersion => '默认: 35';

  @override
  String get targetPlatforms => '目标设备 / 平台';

  @override
  String get saveAction => '保存';

  @override
  String get code => '代码';

  @override
  String get preview => '预览';

  @override
  String get fastCommands => '快速命令';

  @override
  String get serverAddress => '服务器地址';

  @override
  String copied(String value) {
    return '已复制: $value';
  }

  @override
  String get stopServer => '停止';

  @override
  String get command => '命令';

  @override
  String get serverStarted => '服务器已启动';

  @override
  String get openAddressInBrowser => '在 Android 浏览器中打开此地址';

  @override
  String get copyUrl => '复制 URL';

  @override
  String get openProjectToSeeCommands => '打开项目以查看运行命令';

  @override
  String get running => '运行中...';

  @override
  String get chat => '聊天';

  @override
  String get agents => '代理';

  @override
  String askAiHint(String provider) {
    return '咨询 $provider...';
  }

  @override
  String get selectModel => '选择模型';

  @override
  String get clearHistory => '清除历史记录';

  @override
  String get askAboutCode => '咨询关于代码的问题';

  @override
  String get you => '您';

  @override
  String workingOnFile(String file, String code, String question) {
    return '我正在处理文件：$file。\n以下是其内容：\n```\n$code\n```\n\n我的问题：$question';
  }

  @override
  String get aiAskDialogTitle => 'AI 代理查询';

  @override
  String aiAskFolder(String name) {
    return '文件夹: $name';
  }

  @override
  String aiAskFile(String name) {
    return '文件: $name';
  }

  @override
  String get aiAskFolderHint => '描述任务 (例如 \"创建控制器\", \"添加数据模型\"...)';

  @override
  String get aiAskFileHint => '需要做什么？(例如 \"添加邮箱验证\", \"优化方法\"...)';

  @override
  String get decline => '拒绝';

  @override
  String get apply => '应用';

  @override
  String get showChanges => '显示更改';

  @override
  String changesInFile(String name) {
    return '文件 $name 中的更改';
  }

  @override
  String get noFilesFound => '未找到文件';

  @override
  String get retry => '重试';

  @override
  String errorOccurred(String error) {
    return '错误: $error';
  }

  @override
  String get aiProvidersInfo =>
      '添加不同 AI 提供商的 API 密钥。本地模型 (Ollama/LM Studio) 不需要密钥。';

  @override
  String get activeProvider => '激活的提供商';

  @override
  String get requiresApiKeyLabel => '需要 API 密钥';

  @override
  String get localNoKey => '本地 — 无需密钥';

  @override
  String get activeCaps => '激活';

  @override
  String get apiKeyLabel => 'API 密钥';

  @override
  String get keySaved => 'API 密钥已保存';

  @override
  String get urlSaved => 'URL 已保存';

  @override
  String get serverUrlLabel => '服务器 URL';

  @override
  String get ollamaPhoneHint =>
      '💡 要从手机连接，请使用电脑\'的 IP 地址 (例如 http://192.168.1.10:11434)';

  @override
  String get modelLabel => '模型';

  @override
  String get searching => '搜索中...';

  @override
  String get findModels => '查找模型';

  @override
  String get searchModelHint => '通过模型名称搜索...';

  @override
  String get customModelHint => '或手动输入模型名称...';

  @override
  String modelInstalled(String name) {
    return '模型设置为 $name';
  }

  @override
  String get modelsNotFound => '未找到模型。点击 \"查找模型\"。';

  @override
  String get available => '可用';

  @override
  String get quotaLimit => '配额限制 / 高负载';

  @override
  String get unavailable => '不可用';

  @override
  String get availableCaps => '可用';

  @override
  String get activateProvider => '激活提供商';

  @override
  String providerActivated(String name) {
    return '$name 已激活';
  }

  @override
  String get send => '发送';

  @override
  String get acceptAll => '全部接受';

  @override
  String get rejectAll => '全部拒绝';

  @override
  String get projectAnalysis => '项目分析';

  @override
  String problemsFound(int count, int errors, int warnings) {
    return '发现问题: $count ($errors 个错误, $warnings 个警告)';
  }

  @override
  String get fixWithAi => '使用 AI 修复';

  @override
  String runningCommand(String command) {
    return '正在运行命令: $command...';
  }

  @override
  String applyingChange(String path) {
    return '正在应用更改: $path...';
  }

  @override
  String fileSuccessfullyWritten(String path) {
    return '文件 $path 写入成功。';
  }

  @override
  String fileSuccessfullyDeleted(String path) {
    return '文件 $path 删除成功。';
  }

  @override
  String commandExecutedResult(String command, String result) {
    return '命令 \"$command\" 已执行。结果:\n$result';
  }

  @override
  String commandSentToTerminal(String command) {
    return '命令 \"$command\" 已发送至终端。';
  }

  @override
  String unknownActionType(String type) {
    return '未知操作类型: $type';
  }

  @override
  String failedToApplyAction(String error) {
    return '应用操作失败: $error';
  }

  @override
  String get noErrorsFound => '未发现错误';

  @override
  String get noErrorsDescription => '代码分析器已检查您的项目。未发现问题或警告。';

  @override
  String get closeProject => '关闭项目';

  @override
  String get closeProjectConfirm => '您确定要关闭此项目吗？';

  @override
  String get sortByName => '按名称';

  @override
  String get sortBySize => '按大小';

  @override
  String get sortByDate => '按日期';

  @override
  String get goToDefinition => '转到定义';

  @override
  String get documentation => '文档';

  @override
  String get usages => '使用情况';

  @override
  String get cut => '剪切';

  @override
  String get paste => '粘贴';

  @override
  String get selectAll => '全选';

  @override
  String get line => '行';

  @override
  String get column => '列';

  @override
  String get info => '信息';

  @override
  String get ok => '确定';

  @override
  String get problems => '问题';

  @override
  String get packages => '包';

  @override
  String get tools => '工具';

  @override
  String get searchFiles => '搜索文件...';

  @override
  String get imageLoadError => '加载图片出错';

  @override
  String get unsaved => '未保存';

  @override
  String get saved => '已保存';

  @override
  String lineCol(int line, int col) {
    return '第 $line 行，第 $col 列';
  }

  @override
  String get noOpenFiles => '编辑器中无打开的文件';

  @override
  String get fileNotFoundOnDisk => '磁盘上未找到文件';

  @override
  String parsingError(String error) {
    return '解析错误: $error';
  }

  @override
  String get outlineEmptyOrUnsupported => '大纲为空或不支持';

  @override
  String outlineHeader(String filename) {
    return '结构: $filename';
  }

  @override
  String get projectFolderNotFound => '未找到项目文件夹';

  @override
  String get rootFiles => '[根目录文件]';

  @override
  String scanningError(String error) {
    return '扫描错误: $error';
  }

  @override
  String get deleteFileConfirmTitle => '删除文件';

  @override
  String deleteFileConfirmMessage(String name, String size) {
    return '您确定要永久删除文件吗：\n\n$name\n大小: $size？';
  }

  @override
  String get fileDeletedSuccess => '文件删除成功';

  @override
  String deleteFileError(String error) {
    return '删除错误: $error';
  }

  @override
  String get diskSpaceAnalysis => '磁盘空间分析...';

  @override
  String get projectFolderEmpty => '项目文件夹为空';

  @override
  String get projectSize => '项目大小:';

  @override
  String get folderDistribution => '文件夹分布';

  @override
  String get topHeavyFiles => '前 10 大文件';

  @override
  String get noHeavyFiles => '没有大文件';

  @override
  String get searchPlaceholder => '搜索内容...';

  @override
  String get searchCaseSensitive => '区分大小写';

  @override
  String get searchWholeWord => '全字匹配';

  @override
  String get searchRegex => '正则表达式';

  @override
  String get searchInvalidRegex => '正则表达式无效';

  @override
  String get searchNoMatches => '未找到匹配项';

  @override
  String searchMatchesFound(int matches, int files) {
    return '在 $files 个文件中找到 $matches 处匹配';
  }

  @override
  String searchError(String error) {
    return '搜索出错: $error';
  }

  @override
  String get searchingInProgress => '搜索中...';

  @override
  String get searchPrompt => '输入查询进行搜索';

  @override
  String get apkSigner => 'APK 签名器';

  @override
  String get createKeystore => '创建密钥库';

  @override
  String get stepSelectApk => '步骤 1：选择要签名的 APK';

  @override
  String get selectApk => '选择 APK';

  @override
  String get selectCustomPath => '指定自定义路径...';

  @override
  String get apkPathHint => '设备上 APK 文件的完整路径';

  @override
  String get stepSelectKeystore => '步骤 2：选择密钥库';

  @override
  String get selectKeystore => '选择密钥库';

  @override
  String get keystorePathHint => '.jks/.keystore 文件的完整路径';

  @override
  String get stepSignSettings => '步骤 3：签名设置';

  @override
  String get keystorePassword => '密钥库密码';

  @override
  String get keyAlias => '密钥别名';

  @override
  String get keyAliasPassword => '密钥别名密码';

  @override
  String get outputApkName => '输出 APK 文件名';

  @override
  String get signApkButton => '签名 APK';

  @override
  String get install => '安装';

  @override
  String get refreshProjectFiles => '刷新项目文件列表';

  @override
  String get newKeystoreParams => '新建密钥库参数';

  @override
  String get keystoreFilenameHint => '文件名 (例如 release.jks)';

  @override
  String get storePasswordHint => '密钥库密码 (最少 6 个字符)';

  @override
  String get keyAliasHint => '密钥别名 (例如 key)';

  @override
  String get developerInfoDn => '开发者信息 (DN)';

  @override
  String get devNameCn => '名字与姓氏 (CN)';

  @override
  String get devUnitOu => '组织单位 (OU)';

  @override
  String get devOrgO => '组织 (O)';

  @override
  String get devCityL => '城市或地方 (L)';

  @override
  String get devStateS => '州或省 (S)';

  @override
  String get devCountryC => '国家代码 (C)';

  @override
  String get genKeystoreButton => '生成密钥库';

  @override
  String get logSignGen => '签名与生成日志';

  @override
  String get clearLog => '清除日志';

  @override
  String get logPlaceholder => '签名和生成日志将在此处显示。';

  @override
  String signProjectScanError(String error) {
    return '项目扫描错误: $error';
  }

  @override
  String signKeystoreSelected(String path) {
    return '已选择密钥库: $path';
  }

  @override
  String signFilePickError(String error) {
    return '文件选择错误: $error';
  }

  @override
  String get signNoOpenProject => '无打开的项目';

  @override
  String get signNoApkSelected => '未选择 APK';

  @override
  String get signNoKeystoreSelected => '未选择密钥库';

  @override
  String get signFillAllFields => '填写所有签名必填项';

  @override
  String signApkProgress(String apk) {
    return '正在签名 APK: $apk...';
  }

  @override
  String signKeyFile(String key, String alias) {
    return '密钥文件: $key (别名: $alias)';
  }

  @override
  String get signRunningApksigner => '正在运行 apksigner...';

  @override
  String get signVerifying => '正在验证签名...';

  @override
  String get signSuccess => 'APK 签名并验证成功！';

  @override
  String get signVerifyFailed => '签名验证失败或发生错误。';

  @override
  String signError(String error) {
    return '签名 APK 错误: $error';
  }

  @override
  String get genKeystoreFillFields => '填写密钥生成必填项';

  @override
  String genKeystoreProgress(String name) {
    return '正在生成密钥库: $name...';
  }

  @override
  String genKeystoreSuccess(String name) {
    return '密钥库成功创建于: $name';
  }

  @override
  String get genKeystoreFailed => '创建密钥库失败。';

  @override
  String genKeystoreError(String error) {
    return '生成密钥库错误: $error';
  }

  @override
  String installApkProgress(String apk) {
    return '开始安装 APK: $apk';
  }

  @override
  String installApkResult(String msg) {
    return '安装结果: $msg';
  }

  @override
  String installApkNotFound(String path) {
    return '未找到 APK 文件: $path';
  }

  @override
  String installApkError(String error) {
    return '安装错误: $error';
  }

  @override
  String get glassmorphismEffects => '毛玻璃特效';

  @override
  String get glassOpacity => '玻璃不透明度';

  @override
  String get backdropBlur => '背景模糊度';

  @override
  String get editorFontFamily => '编辑器字体';

  @override
  String get fontLigatures => '字体连字';

  @override
  String get fontLigaturesDescription => '启用代码中的字体连字 (例如 -> 或 !=)';

  @override
  String get selectFontFamily => '选择字体';

  @override
  String get selectLanguage => '选择语言';

  @override
  String get format => '格式化';

  @override
  String get liveShare => '实时共享';

  @override
  String get hostSession => '主持会话';

  @override
  String get joinSession => '加入会话';

  @override
  String get stopSession => '停止会话';

  @override
  String get disconnectSession => '断开连接';

  @override
  String get sessionActive => '会话激活';

  @override
  String get hostingAt => '主持地址：';

  @override
  String get connectedTo => '连接到：';

  @override
  String get userName => '您的姓名';

  @override
  String get usersList => '参与者';

  @override
  String get messagePlaceholder => '输入消息...';

  @override
  String get connectError => '连接错误';

  @override
  String get invalidAddress => '地址无效';

  @override
  String get joinLink => '会话 IP 地址';

  @override
  String get localIps => '本地 IP：';

  @override
  String get wasmPlugins => 'WASM 插件';

  @override
  String get installPlugin => '安装插件 (.wasm)';

  @override
  String get noPluginsInstalled => '未安装 WASM 插件';

  @override
  String get pluginEnabled => '插件已启用';

  @override
  String get pluginDisabled => '插件已禁用';

  @override
  String get runWasmAction => '运行 WASM 操作';

  @override
  String get noActiveSelection => '未选择文本。应用到整个文件吗？';

  @override
  String get applyToSelection => '应用到选区';

  @override
  String get applyToDocument => '应用到文档';

  @override
  String get logs => '日志';

  @override
  String get clearLogs => '清除日志';

  @override
  String get deletePlugin => '删除插件';

  @override
  String get resetToDefaults => '重置为默认';

  @override
  String get welcomeTitle => '欢迎使用！';

  @override
  String get welcomeSubtitle => '选择要工作的项目或新建项目';

  @override
  String get lastActiveProject => '上次活动的项目';

  @override
  String get runTooltip => '运行';

  @override
  String get actionsTooltip => '操作';

  @override
  String get packagesTooltip => '软件包';

  @override
  String get extensionsAndTools => '扩展与工具';

  @override
  String get searchExtensionsHint => '搜索扩展...';

  @override
  String get searchPubdevHint => '在 pub.dev 搜索库 (例如 dio)...';

  @override
  String get tabAll => '全部';

  @override
  String get tabInstalled => '已安装';

  @override
  String get tabLanguagesAndAi => '语言与 AI';

  @override
  String get tabTools => '工具';

  @override
  String get tabBuild => '构建';

  @override
  String get tabSdkPlatforms => 'SDK 平台';

  @override
  String get tabPubLibraries => 'Pub 依赖库';

  @override
  String get readyToBuildApk => '准备好构建 APK 了吗？';

  @override
  String get installAndroidSdkJava => '安装 Android SDK 和 Java 17';

  @override
  String get sdkSetupDescription =>
      '这将安装 SDK、编译器、zipalign、apksigner、优化 Gradle 网络设置，并准备您的环境以进行项目编译。';

  @override
  String get initializingDevEnvironment => '正在初始化开发环境...';

  @override
  String get viewAction => '查看';

  @override
  String get startSdkSetup => '启动环境设置';

  @override
  String get buildIssues => '构建遇到问题？';

  @override
  String get restoreAndroidGradleEnv => '修复 Android & Gradle 环境';

  @override
  String get wrenchFixDescription =>
      '自动修复 AAPT2 守护进程错误，设置正确的项目权限，恢复资源编译器二进制文件并配置 Gradle 线程。';

  @override
  String get runningWrenchFix => '正在运行构建环境修复...';

  @override
  String get startWrenchFix => '运行修复 (Wrench Fix)';

  @override
  String get statusInstalledCaps => '已安装';

  @override
  String get reinstallOrUpdateTooltip => '重新安装 / 更新';

  @override
  String updatingPackage(String name) {
    return '正在更新 $name...';
  }

  @override
  String installingPackage(String name) {
    return '正在安装 $name...';
  }

  @override
  String get installAction => '安装';

  @override
  String get searchPubdevTitle => '搜索 Flutter 依赖库';

  @override
  String get searchPubdevDescription =>
      '在上方搜索框输入库名称 (例如 dio, bloc, riverpod) 并回车';

  @override
  String loadError(String error) {
    return '加载出错: $error';
  }

  @override
  String get addAction => '添加';

  @override
  String get openProjectToInstallLibraries => '请先打开项目以添加依赖库。';

  @override
  String installingLibrary(String name) {
    return '正在安装依赖库 $name...';
  }

  @override
  String importError(String error) {
    return '导入错误: $error';
  }

  @override
  String get filesImportedSuccessfully => '文件成功导入';

  @override
  String get dragFilesHereToImport => '拖动文件到此处进行导入';

  @override
  String selectedCount(int count) {
    return '已选择: $count';
  }

  @override
  String get selectAllTooltip => '全选';

  @override
  String get copyTooltip => '复制';

  @override
  String copiedCount(int count) {
    return '已复制对象: $count';
  }

  @override
  String get cutTooltip => '剪切';

  @override
  String cutCount(int count) {
    return '已剪切对象: $count';
  }

  @override
  String get zipTooltip => '压缩为 ZIP';

  @override
  String get deleteTooltip => '删除';

  @override
  String foldersCount(int count) {
    return '文件夹: $count';
  }

  @override
  String get askAiAction => '询问 AI';

  @override
  String get explainAiAction => 'AI：解释';

  @override
  String get documentAiAction => 'AI：生成文档';

  @override
  String get testAiAction => 'AI：生成测试';

  @override
  String get optimizeAiAction => 'AI：优化';

  @override
  String pasteCount(int count) {
    return '粘贴 ($count)';
  }

  @override
  String get archiveNameHint => '归档名称';

  @override
  String get compressAction => '压缩';

  @override
  String get archiveCreatedSuccessfully => '归档成功创建！';

  @override
  String compressionError(String error) {
    return '压缩错误: $error';
  }

  @override
  String get archiveExtractedSuccessfully => '归档成功解压！';

  @override
  String extractionError(String error) {
    return '解压错误: $error';
  }

  @override
  String get deleteSelectedTitle => '删除所选？';

  @override
  String deleteSelectedConfirmation(int count) {
    return '您确定要删除这 $count 个项目吗？';
  }

  @override
  String get selectedElementsDeleted => '所选项目已删除！';

  @override
  String deleteError(String error) {
    return '删除错误: $error';
  }

  @override
  String get filesPastedSuccessfully => '文件成功粘贴！';

  @override
  String pasteError(String error) {
    return '粘贴错误: $error';
  }

  @override
  String get repositoryNotFound => '未找到代码仓库';

  @override
  String get initGitRepoDescription => '初始化本地 Git 代码仓库以跟踪更改。';

  @override
  String get initGitAction => '初始化 Git';

  @override
  String get gitConflicted => '冲突';

  @override
  String get gitStaged => '暂存';

  @override
  String get gitModified => '已修改';

  @override
  String get gitUntracked => '未跟踪';

  @override
  String get commitMessageHint => '提交消息...';

  @override
  String get resetChangesTitle => '重置更改？';

  @override
  String get resetChangesConfirmation => '您确定要永久重置此文件中所有未提交的更改吗？';

  @override
  String get resetAction => '重置';

  @override
  String get changesReset => '更改已重置';

  @override
  String resetError(String error) {
    return '重置错误: $error';
  }

  @override
  String get normalView => '普通视图';

  @override
  String get splitView => '分屏视图 (双排对比)';

  @override
  String get stagedMessage => '文件已暂存';

  @override
  String get unstagedMessage => '文件已取消暂存';

  @override
  String stageError(String error) {
    return '暂存错误: $error';
  }

  @override
  String get failedToLoadChanges => '加载更改失败';

  @override
  String get noChanges => '无更改';

  @override
  String get fileIdenticalToHead => '该文件与 HEAD 一致';

  @override
  String get runTerminalTooltip => '运行';

  @override
  String get restartTerminalTooltip => '重启';

  @override
  String get consoleSubTab => '控制台';

  @override
  String get signApkSubTab => '签名 APK';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get back => '返回';

  @override
  String get tryChangingSearchQuery => '尝试修改搜索词';

  @override
  String get incomingBranch => '传入分支';

  @override
  String get resolveConflictsBeforeSaving => '请在保存前解决所有冲突！';

  @override
  String get fileSavedAndStaged => '文件已成功保存并暂存到 Git 索引';

  @override
  String saveError(String error) {
    return '保存错误: $error';
  }

  @override
  String get acceptMerge => '接受合并';

  @override
  String get errorLoadingConflictFile => '加载冲突文件出错';

  @override
  String get conflictsNotFound => '未找到冲突';

  @override
  String get noConflictMarkersFound => '在此文件中未找到标准的 Git 合并标记。';

  @override
  String get backToGit => '返回 Git';

  @override
  String get conflictBlock => '冲突块';

  @override
  String get currentChangesOurs => '当前更改 (我们 / HEAD)';

  @override
  String incomingChanges(String branch) {
    return '传入更改 ($branch)';
  }

  @override
  String get useThisVersion => '使用此版本';

  @override
  String get mergeResultEditable => '合并结果 (可编辑)';

  @override
  String get chooseVersionOrWriteHint => '选择上述版本之一，或编写您自己的合并解决方案...';

  @override
  String get markAsResolvedHint => '* 要将此块标记为已解决，请输入或选择文本。';

  @override
  String get emptyLabel => '(空)';

  @override
  String get stageAction => '暂存';

  @override
  String get unstageAction => '取消暂存';

  @override
  String get cursorColor => '光标颜色';

  @override
  String get or => '或';

  @override
  String get ipCopiedToClipboard => 'IP 已复制到剪贴板';

  @override
  String editingFile(String file) {
    return '编辑中: $file';
  }

  @override
  String get viewingProject => '查看项目';

  @override
  String get noProblemsFound => '工作区未发现问题';

  @override
  String get problemsList => '问题列表';

  @override
  String get sendToAi => '发送至 AI';

  @override
  String get helpMeFixErrors => '请帮我修复以下项目中的编译错误：';

  @override
  String lineColumn(int line, int col) {
    return '第 $line 行，第 $col 列';
  }

  @override
  String get decreaseFontSize => '减小字号';

  @override
  String get increaseFontSize => '增大字号';

  @override
  String get undo => '撤销';

  @override
  String get redo => '重做';

  @override
  String get moveLeft => '向左移';

  @override
  String get moveUp => '向上移';

  @override
  String get moveDown => '向下移';

  @override
  String get moveRight => '向右移';

  @override
  String get edit => '编辑';

  @override
  String get packagesAndEnv => '包与环境';

  @override
  String packagesInstalledCount(int count, int total) {
    return '已安装: $count/$total';
  }

  @override
  String get flutterProject => 'Flutter 项目';

  @override
  String get pythonProject => 'Python 项目';

  @override
  String get nodejsProject => 'Node.js 项目';

  @override
  String get dartProject => 'Dart 项目';

  @override
  String get webProject => 'Web 项目';

  @override
  String get androidProject => 'Android 项目';

  @override
  String get genericProject => '项目';

  @override
  String get runPC => '运行 (PC)';

  @override
  String get runMob => '运行 (移动端)';

  @override
  String get startServer => '启动服务器';

  @override
  String get buildAPK => '构建 APK';

  @override
  String get startTheProject => '启动项目';

  @override
  String get outputCopied => '输出已复制';

  @override
  String get console => '控制台';

  @override
  String get signApk => '签名 APK';

  @override
  String get buildPC => '构建 (PC)';

  @override
  String get resetPlugins => '重置插件';

  @override
  String get resetPluginsConfirmation => '这将删除所有已安装的自定义插件并恢复默认插件。继续？';

  @override
  String get resetPluginsTitle => '重置插件？';

  @override
  String get installWasm => '安装 .wasm';

  @override
  String get availableActions => '可用操作：';

  @override
  String get logsTerminal => '日志终端';

  @override
  String get noLogsCaptured => '尚未捕获到日志';

  @override
  String get installWasmPluginTitle => '安装 WASM 插件';

  @override
  String get selectWasmFile => '选择 .wasm 文件';

  @override
  String get pluginName => '插件名称';

  @override
  String get nameRequired => '名称为必填项';

  @override
  String get pluginDescription => '描述';

  @override
  String get descriptionRequired => '描述为必填项';

  @override
  String get exposedActions => '公开的操作';

  @override
  String get add => '添加';

  @override
  String get pickWasmFileFirst => '请先选择一个 .wasm 文件';

  @override
  String get pluginInstalledSuccessfully => '插件安装成功';

  @override
  String failedToInstall(String error) {
    return '安装失败: $error';
  }

  @override
  String get mcpServersTitle => 'AI 模块：MCP 服务器';

  @override
  String activeServers(int count) {
    return '活动服务器 ($count)';
  }

  @override
  String get repository => '代码仓库';

  @override
  String get noMcpServers => '未添加 MCP 服务器';

  @override
  String get goToRepository => '前往代码仓库';

  @override
  String get addManually => '手动添加';

  @override
  String get addServerManually => '手动添加服务器';

  @override
  String get installed => '已安装';

  @override
  String packageDetail(String detail) {
    return '包: $detail';
  }

  @override
  String authParam(String key) {
    return '认证参数: $key';
  }

  @override
  String enterValueFor(String key) {
    return '输入 $key 的值';
  }

  @override
  String enterLabel(String label) {
    return '输入 $label';
  }

  @override
  String installPreset(String name) {
    return '安装: $name';
  }

  @override
  String get serverName => '服务器名称';

  @override
  String get exampleLocalSearch => '例如: local-search';

  @override
  String get connectionType => '连接类型';

  @override
  String get stdioLocal => 'Stdio (本地进程)';

  @override
  String get sseHttp => 'SSE (HTTP 流)';

  @override
  String get startCommand => '启动命令';

  @override
  String get exampleStartCommand => '例如: node 或 npx 或 python3';

  @override
  String get argsSpace => '参数 (用空格分隔)';

  @override
  String get searchFilesHint => '搜索文件... (输入 \"#\" 搜索符号)';

  @override
  String get searchSymbolsHint => '搜索代码中的符号...';

  @override
  String get modeFiles => '模式：文件';

  @override
  String get modeSymbols => '模式：符号';

  @override
  String resultsCount(int count) {
    return '结果: $count';
  }

  @override
  String get noResults => '未找到结果';

  @override
  String confirmDeleteMultiple(int count) {
    return '您确定要删除这 $count 个项目吗？';
  }

  @override
  String get archiveExtracted => '归档成功解压！';

  @override
  String get archiveCreated => '归档成功创建！';

  @override
  String get compressToZip => '压缩为 ZIP';

  @override
  String folderLabel(String name) {
    return '文件夹: $name';
  }

  @override
  String fileLabel(String name) {
    return '文件: $name';
  }

  @override
  String get whatShouldAiDoFolder => 'AI 应该对这个文件夹做什么？';

  @override
  String get whatShouldAiDoFile => 'AI 应该对这个文件做什么？';

  @override
  String get askAi => '询问 AI';

  @override
  String get askAiDesc => '与 AI 助手互动聊天';

  @override
  String get explainStructure => 'AI：解释结构';

  @override
  String get explainStructureDesc => '代码或文件夹的详细摘要';

  @override
  String get addDoc => 'AI：添加文档';

  @override
  String get addDocDesc => '生成 docstring 和注释';

  @override
  String get generateTests => 'AI：生成测试';

  @override
  String get generateTestsDesc => '编写代码的单元测试';

  @override
  String get optimizeCode => 'AI：优化';

  @override
  String get optimizeCodeDesc => '建议性能改进';

  @override
  String get newFileDesc => '在此文件夹中创建文件';

  @override
  String get newFolderDesc => '创建子文件夹';

  @override
  String get removeFromBookmarks => '从书签中移除';

  @override
  String get removeFromBookmarksDesc => '从快速访问中移除文件';

  @override
  String get addToBookmarks => '添加至书签';

  @override
  String get addToBookmarksDesc => '固定文件以进行快速访问';

  @override
  String get copyDesc => '添加至剪贴板';

  @override
  String get cutDesc => '移动文件';

  @override
  String get pasteDesc => '粘贴已复制项目';

  @override
  String get renameDesc => '更改项目名称';

  @override
  String get extractZip => '提取 ZIP';

  @override
  String get extractZipDesc => '从归档中解压文件';

  @override
  String get compressZip => '压缩为 ZIP';

  @override
  String get compressZipDesc => '创建 ZIP 归档';

  @override
  String get compressSelectedZip => '将所选压缩为 ZIP';

  @override
  String get compressSelectedZipDesc => '从所选项目创建归档';

  @override
  String get deleteDesc => '永久删除';

  @override
  String get empty => '空';

  @override
  String get nameFolderHint => 'folder_name';

  @override
  String get nameFileHint => 'file_name.txt';

  @override
  String get itemMoved => '项目成功移动';

  @override
  String moveError(String error) {
    return '移动错误: $error';
  }

  @override
  String get image => '图片';

  @override
  String get document => '文档';

  @override
  String get failedToLoadImage => '加载图片失败';

  @override
  String failedToReadFile(String error) {
    return '读取文件失败: $error';
  }

  @override
  String get aiSettings => 'AI 设置';

  @override
  String get provider => '提供商';

  @override
  String get model => '模型';

  @override
  String get apiKey => 'API 密钥';

  @override
  String get customBaseUrl => '自定义基准 URL';

  @override
  String defaultHint(String url) {
    return '默认: $url';
  }

  @override
  String get chatWithAi => '与 AI 聊天';

  @override
  String get chatHistory => '聊天历史记录';

  @override
  String get newChat => '新聊天';

  @override
  String get internetAccess => '互联网访问';

  @override
  String get mcpServers => 'MCP 服务器';

  @override
  String get manualMode => '手动模式';

  @override
  String get safeAutopilot => '安全自动驾驶';

  @override
  String get fullAutonomy => '完全自主';

  @override
  String get agentsNotInstalled => '代理未安装';

  @override
  String get installGeminiCliInSettings => '在设置中安装 gemini-cli';

  @override
  String get stopAgent => '停止代理';

  @override
  String get withChanges => '附带更改';

  @override
  String get attachOpenFile => '附加当前打开的文件';

  @override
  String get noHistoryFound => '未找到历史记录';

  @override
  String get untitled => '无标题';

  @override
  String messagesCount(int count) {
    return '$count 条消息';
  }

  @override
  String get systemEnv => '系统环境';

  @override
  String get fixEnvironmentArm64 => '修复环境 (ARM64)';

  @override
  String get environment => '环境';

  @override
  String get collapseAll => '折叠全部';

  @override
  String get elementMovedToRoot => '元素已移至根目录';

  @override
  String get bookmarks => '书签';

  @override
  String get noActiveWasmPlugins => '无活动的 WASM 插件';

  @override
  String get selectPluginAction => '选择插件操作';

  @override
  String get noSelection => '无选择';

  @override
  String get applyPluginToFile => '将插件操作应用到整个文件吗？';

  @override
  String get pluginExecutedSuccess => '插件执行成功';

  @override
  String executionError(String error) {
    return '执行错误: $error';
  }

  @override
  String get quickSearch => '快速搜索 (Ctrl+P)';

  @override
  String get saveTooltip => '保存';

  @override
  String get runWasmPlugin => '运行 WASM 插件';

  @override
  String get aiChat => 'AI 聊天';

  @override
  String get home => '主页';

  @override
  String get pendingDiff => '待处理的差异';

  @override
  String get keep => '保留';

  @override
  String get reject => '拒绝';

  @override
  String get keepAll => '全部保留';

  @override
  String ranAction(String content) {
    return '已运行: $content';
  }

  @override
  String get created => '已创建';

  @override
  String get deleted => '已删除';

  @override
  String get edited => '已编辑';

  @override
  String get taskExecution => '任务执行';

  @override
  String stepNumber(int step, int total) {
    return '步骤 $step/$total';
  }

  @override
  String filesChangedCount(int count, int additions, int deletions) {
    return '文件已更改: $count (+$additions -$deletions)';
  }

  @override
  String commandsExecutedCount(int count) {
    return '已执行 $count 条命令';
  }

  @override
  String get changesAccepted => '已接受更改并暂存';

  @override
  String undoneChanges(int count) {
    return '已撤销 $count 个文件更改';
  }

  @override
  String discardedFileChanges(String file) {
    return '已丢弃 $file 中的更改';
  }

  @override
  String get thinking => '思考中...';

  @override
  String get planner => '规划器';

  @override
  String get coder => '编码器';

  @override
  String get validator => '验证器';

  @override
  String get aiAgentRole => 'AI 代理';

  @override
  String get resubmit => '重新提交';

  @override
  String get rollbackHistoryToStep => '回滚历史和代码到该步骤';

  @override
  String get confirmRollback => '确认回滚';

  @override
  String get rollbackConfirmationText => '该消息之后做出的所有代码更改都将回滚，后续消息将被删除。确定要继续吗？';

  @override
  String get yesRollback => '是，回滚';

  @override
  String get changesApplied => '更改已应用';

  @override
  String get codeCopied => '代码已复制到剪贴板';

  @override
  String get outOfScope => '超出范围！';

  @override
  String get low => '低';

  @override
  String get medium => '中';

  @override
  String get high => '高';

  @override
  String get applied => '已应用';

  @override
  String get resolveConflictTooltip => '解决冲突';

  @override
  String get panel1 => '面板 1';

  @override
  String get panel2 => '面板 2';

  @override
  String get localWebServer => '本地 Web 服务器';

  @override
  String get webServerDesc => '启动 Web 服务器以在 IDE 内部预览项目的构建结果。';

  @override
  String get startWebServer => '启动 Web 服务器';

  @override
  String get stopWebServer => '停止 Web 服务器';

  @override
  String get copyAll => '复制全部';

  @override
  String get clearTerminal => '清空终端';

  @override
  String get openInExternalBrowser => '在外部浏览器中打开';

  @override
  String get search => '搜索';

  @override
  String get structure => '结构';

  @override
  String get disk => '磁盘';

  @override
  String get plugins => '插件';

  @override
  String get added => '已添加';

  @override
  String get removed => '已移除';

  @override
  String get modified => '已修改';

  @override
  String selectedObjectsCount(int count) {
    return '已选择对象: $count';
  }

  @override
  String get explainFolderPreset => '解释此文件夹的用途和结构。';

  @override
  String get explainFilePreset => '详细解释此文件的用途和运行逻辑。';

  @override
  String get addDocFolderPreset => '在此文件夹下的所有文件中为代码添加文档、docstring 和详细注释。';

  @override
  String get addDocFilePreset => '在此文件中为代码添加清晰的文档、docstring 和详细注释。';

  @override
  String get generateTestsFolderPreset => '为此文件夹中的文件编写单元测试。';

  @override
  String get generateTestsFilePreset => '为此文件中的代码编写全面的单元测试。';

  @override
  String get optimizeFolderPreset => '分析此文件夹中的代码，并针对性能和可读性提出优化建议。';

  @override
  String get optimizeFilePreset => '分析此文件中的代码，并针对优化性能、可读性和架构提出建议。';

  @override
  String get deleteSelected => '删除所选';

  @override
  String get manual => '手动';

  @override
  String get autoSafe => '自动:安全';

  @override
  String get autoFull => '自动:完全';

  @override
  String filesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '个文件',
      one: '个文件',
    );
    return '$count $_temp0';
  }

  @override
  String get localAiEngineTitle => '本地 AI 引擎';

  @override
  String get ollamaRunningLocally => 'Ollama 正在本地运行';

  @override
  String get ollamaRunningLocallyDesc =>
      '请确保 Ollama 已在您的系统上运行。您可以使用 \"ollama serve\" 启动它，并使用 \"ollama pull <model>\" 拉取模型。';

  @override
  String get lmStudioRunningLocally => 'LM Studio 正在本地运行';

  @override
  String get lmStudioRunningLocallyDesc =>
      '请确保 LM Studio 服务器正在运行。您可以在 LM Studio 应用程序中启用本地服务器并加载所需的模型。';

  @override
  String get ollamaNotDetected => '未检测到 Ollama';

  @override
  String get ollamaNotDetectedDesc => '在您的设备上安装 Ollama 并确保其正在运行。可以在上方修改 URL。';

  @override
  String get checkConnection => '检查连接';

  @override
  String get availableOllamaModels => '可用的 OLLAMA 模型';

  @override
  String get llamaServerInstallRequired => '需要安装 llama-server';

  @override
  String get llamaServerInstallRequiredDesc =>
      '运行本地 AI 模型需要 llama-server 引擎。点击下方按钮自动安装。';

  @override
  String get installing => '安装中...';

  @override
  String get installLlamaServerRuntime => '安装 Llama 服务器运行环境';

  @override
  String get ollamaModelsTitle => 'OLLAMA 模型';

  @override
  String get localAiModelsTitle => '本地 AI 模型';

  @override
  String get serverStatusAndControl => '服务器状态与控制';

  @override
  String get downloadOllamaModelPrompt => '下载至少一个 Ollama 模型以开始使用。';

  @override
  String get downloadModelToStartServerPrompt => '下载上方至少一个模型以启动本地服务器。';

  @override
  String get localLlamaServerLabel => '本地 llama-server';

  @override
  String get connected => '已连接';

  @override
  String get runningPort8080 => '运行中 (端口 8080)';

  @override
  String get starting => '启动中...';

  @override
  String get stopped => '已停止';

  @override
  String get start => '启动';

  @override
  String gbFormat(String size) {
    return '$size GB';
  }

  @override
  String ramGbFormat(String size) {
    return '~$size GB 内存';
  }

  @override
  String get select => '选择';

  @override
  String get download => '下载';

  @override
  String get refreshPreview => '刷新预览';

  @override
  String inFolder(String folder) {
    return '在 $folder 中';
  }

  @override
  String get llamaServerBuiltIn => 'llama-server (内置)';

  @override
  String get localAiDisplayName => '本地 AI';

  @override
  String get notRequired => '不需要';

  @override
  String get mcpGithubDesc => '与 GitHub 代码仓库、问题和拉取请求集成。';

  @override
  String get mcpGoogleSearchDesc => '允许 AI 代理进行实时谷歌搜索。';

  @override
  String get mcpFetchDesc => '下载网页并自动将其转换为 Markdown。';

  @override
  String get mcpPostgresDesc => '连接 PostgreSQL、读取表结构并运行 SQL 查询。';

  @override
  String get mcpPostgresArg => '连接字符串 (postgresql://...)';

  @override
  String get mcpSqliteDesc => '连接并检查项目中的 SQLite 数据库。';

  @override
  String get mcpSqliteArg => 'SQLite 数据库文件路径 (e.g. db.sqlite)';

  @override
  String get mcpMemoryDesc => '为您的 AI 代理提供语义化长期记忆存储。';

  @override
  String get mcpBraveSearchDesc => '允许 AI 代理使用 Brave API 执行网页搜索。';

  @override
  String get mcpPuppeteerDesc => '浏览器自动化、截图生成、元素点击和网页抓取。';

  @override
  String get mcpFirecrawlDesc => '将任何网站转换为干净的 Markdown 或结构化 JSON。';

  @override
  String get mcpNotionDesc => '读取和修改 Notion 页面、数据库和注释。';

  @override
  String get mcpSlackDesc => '提供读取频道、聊天并在 Slack 中发送通知的功能。';

  @override
  String get mcpGitDesc => '通过 Git 在本地查看提交、对比版本、搜索提交和检查文件。';

  @override
  String get mcpGitlabDesc => '管理 GitLab 项目、问题、拉取请求和 CI/CD 流水线。';

  @override
  String get mcpSentryDesc => '获取错误日志并在 Sentry 上检查应用程序的崩溃。';

  @override
  String get mcpAirtableDesc => '读取、创建和更新 Airtable 数据库和表中的记录。';

  @override
  String get mcpSequentialThinkingDesc => '为结构化问题解决组织 AI 代理的思路。';

  @override
  String get phantomProcessesTitle => '幽灵进程 (Android 12/13+)';

  @override
  String get phantomProcessesVersion => '需要 ADB 配置以保证稳定编译';

  @override
  String get phantomProcessesError =>
      '在 Android 12+ 中，如果超过 32 个活动进程，系统进程杀手 (Phantom Process Killer) 会终止构建进程 (Gradle/Java/Node/Dart)。\n\n要在 PC 上通过 ADB 禁用，请运行：\n\nadb shell \"/system/bin/device_config put activity_manager max_phantom_processes 2147483647\"\n\nadb shell \"/system/bin/settings put global settings_enable_monitor_phantom_procs false\"';

  @override
  String androidJarCorruptError(String api) {
    return 'android.jar 已损坏 ($api)。点击 \"修复环境\" 重新安装。';
  }

  @override
  String get androidSdkPlatformsHealthy => 'android-35 / android-36 — 健康';

  @override
  String checkFailed(String error) {
    return '检查失败: $error';
  }

  @override
  String get analyzingTaskAndPlanning => '分析任务并规划中...';

  @override
  String agentStepLimitExceeded(int limit) {
    return '🤖 超出代理步骤限制 ($limit)。自动驾驶停止。';
  }

  @override
  String get generatingCodeChanges => '正在生成代码更改...';

  @override
  String get executionPlanConstructed => '📝 执行计划已构建。正在转换到编码器角色...';

  @override
  String get verifyingImplementation => '正在验证实现正确性...';

  @override
  String blockedUnsafeActions(String blockedText) {
    return '❌ 在工作区范围之外阻止了不安全的操作：\n$blockedText';
  }

  @override
  String get awaitingApprovalHighRisk =>
      '⚠️ 等待批准：检测到高风险操作或自动驾驶受到限制。请在 AI 面板中批准它们。';

  @override
  String autopilotStepSummary(
    int step,
    String actionsListText,
    String results,
  ) {
    return '🤖 自动驾驶 (步骤 $step)：自动批准操作：\n$actionsListText\n\n结果：\n$results';
  }

  @override
  String get runningStaticAnalysis => '正在运行项目静态 analysis (dart analyze)...';

  @override
  String agentFailedToFixErrors(int maxAttempts, String errorReport) {
    return '⚠️ 代理在尝试 $maxAttempts 次后未能修复错误。\n\n**剩余错误：**\n$errorReport\n\n请描述问题或手动修复。';
  }

  @override
  String get fixingCompilationErrors => '正在修复编译错误...';

  @override
  String readingFile(String path) {
    return '正在读取文件 $path...';
  }

  @override
  String savingFile(String path) {
    return '正在保存文件 $path...';
  }

  @override
  String deletingFile(String path) {
    return '正在删除文件 $path...';
  }

  @override
  String runningCommandStatus(String command) {
    return '正在运行命令 \"$command\"...';
  }

  @override
  String searchingCode(String query) {
    return '正在搜索代码: \"$query\"...';
  }

  @override
  String listingDirectory(String path) {
    return '正在列出目录 $path...';
  }

  @override
  String findingSymbols(String query) {
    return '正在查找符号: \"$query\"...';
  }

  @override
  String searchingWeb(String query) {
    return '正在搜索网页: \"$query\"...';
  }

  @override
  String fetchingWebPage(String path) {
    return '正在获取网页: $path...';
  }

  @override
  String get executingAction => '正在执行操作...';

  @override
  String runningCommandLabel(String command) {
    return '🤖 正在运行命令: $command...';
  }

  @override
  String applyingChangeLabel(String path) {
    return '🤖 正在应用更改: $path...';
  }

  @override
  String commandSentToTerminalLabel(String command) {
    return '🤖 命令 \"$command\" 已发送到终端。';
  }

  @override
  String runningCommandResultLabel(String command, String result) {
    return '命令 \"$command\" 已执行。结果：\n$result';
  }

  @override
  String fileNotFound(String path) {
    return '未找到文件: $path';
  }

  @override
  String fileContentsHeader(String path, int lineCount, String truncated) {
    return '文件 `$path` 的内容 ($lineCount 行)：\n\n```\n$truncated\n```';
  }

  @override
  String fileTruncatedSuffix(int lineCount) {
    return '... [已从 $lineCount 行截断至 8000 个字符]';
  }

  @override
  String get safetyGuardFileOutsideWorkspace => '错误：尝试在项目范围外修改文件。';

  @override
  String get commandRefPathOutsideWorkspace => '安全错误：命令引用了项目范围外的路径。';

  @override
  String commandBlockedUnsafe(String blocked) {
    return '安全错误：命令包含被阻止的指令 \"$blocked\"。';
  }

  @override
  String aiSearchNoMatches(String query) {
    return '未找到与 \"$query\" 匹配的项。';
  }

  @override
  String aiSearchMatchesFound(int matchCount, String query, String results) {
    return '在 \"$query\" 中找到 $matchCount 处匹配：\n\n$results';
  }

  @override
  String searchSymbolsNoMatches(String query) {
    return '未找到与 \"$query\" 匹配的符号。';
  }

  @override
  String searchSymbolsMatchesFound(int count, String query, String results) {
    return '找到 $count 个与 \"$query\" 匹配的符号：\n\n$results';
  }

  @override
  String searchSymbolsItem(String type, String name, String path, int line) {
    return '- [$type] $name (文件: $path, 行: $line)';
  }

  @override
  String directoryNotFound(String path) {
    return '未找到目录: $path';
  }

  @override
  String get directoryEmpty => '目录为空。';

  @override
  String directoryContentsHeader(String items) {
    return '目录内容：\n\n$items';
  }

  @override
  String get mcpMissingParams => '错误：未指定 MCP 服务器或工具名称。';

  @override
  String unknownAction(String type) {
    return '未知操作类型: $type';
  }

  @override
  String failedToApplyActionWithError(String error) {
    return '无法应用操作：$error';
  }

  @override
  String get searchQueryEmpty => '错误：搜索查询为空。';

  @override
  String get workspaceNotFound => '错误：未找到工作区。';

  @override
  String get webPreviewStopped => '网页预览已停止';

  @override
  String get webPreviewStartInstructions => '启动服务器并点击 Play 按钮。';
}
