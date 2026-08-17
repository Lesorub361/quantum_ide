enum AIToolRisk { low, medium, high }

class AIToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final AIToolRisk risk;
  final bool requiresConfirmation;

  const AIToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
    this.risk = AIToolRisk.low,
    this.requiresConfirmation = false,
  });

  Map<String, dynamic> toOpenAIFormat() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': inputSchema,
    },
  };

  Map<String, dynamic> toAnthropicFormat() => {
    'name': name,
    'description': description,
    'input_schema': inputSchema,
  };

  Map<String, dynamic> toGeminiFormat() => {
    'name': name,
    'description': description,
    'parameters': inputSchema,
  };
}

class AIToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  const AIToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  factory AIToolCall.fromJson(Map<String, dynamic> json) {
    return AIToolCall(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      arguments: json['arguments'] as Map<String, dynamic>? ?? {},
    );
  }
}

class AIToolResult {
  final String toolCallId;
  final String content;
  final bool isError;

  const AIToolResult({
    required this.toolCallId,
    required this.content,
    this.isError = false,
  });

  Map<String, dynamic> toOpenAIMessage() => {
    'role': 'tool',
    'tool_call_id': toolCallId,
    'content': content,
  };

  Map<String, dynamic> toAnthropicMessage() => {
    'type': 'tool_result',
    'tool_use_id': toolCallId,
    'content': content,
  };
}

class AIStreamChunk {
  final String? textDelta;
  final AIToolCall? toolCall;
  final bool isDone;

  const AIStreamChunk({
    this.textDelta,
    this.toolCall,
    this.isDone = false,
  });
}

class AIToolResponse {
  final String text;
  final List<AIToolCall> toolCalls;
  final bool hasMoreTools;

  const AIToolResponse({
    this.text = '',
    this.toolCalls = const [],
    this.hasMoreTools = false,
  });
}

final List<AIToolDefinition> defaultAITools = [
  const AIToolDefinition(
    name: 'read_file',
    description: 'Read the contents of a file. Use before editing when you need current content.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': 'File path relative to workspace root'},
      },
      'required': ['path'],
    },
    risk: AIToolRisk.low,
  ),
  const AIToolDefinition(
    name: 'write_file',
    description: 'Create or completely replace a file with new content.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': 'File path relative to workspace root'},
        'content': {'type': 'string', 'description': 'Full file content to write'},
      },
      'required': ['path', 'content'],
    },
    risk: AIToolRisk.medium,
    requiresConfirmation: true,
  ),
  const AIToolDefinition(
    name: 'edit_file',
    description: 'Apply a search-and-replace edit to a file. Provide the exact old_string to find and the new_string to replace it with. The old_string must be unique in the file.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': 'File path relative to workspace root'},
        'old_string': {'type': 'string', 'description': 'Exact text to find (must be unique in file)'},
        'new_string': {'type': 'string', 'description': 'Replacement text'},
      },
      'required': ['path', 'old_string', 'new_string'],
    },
    risk: AIToolRisk.medium,
    requiresConfirmation: true,
  ),
  const AIToolDefinition(
    name: 'create_file',
    description: 'Create a new file with the given content.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': 'File path relative to workspace root'},
        'content': {'type': 'string', 'description': 'File content'},
      },
      'required': ['path', 'content'],
    },
    risk: AIToolRisk.medium,
    requiresConfirmation: true,
  ),
  const AIToolDefinition(
    name: 'delete_file',
    description: 'Delete a file. This action cannot be undone.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': 'File path relative to workspace root'},
      },
      'required': ['path'],
    },
    risk: AIToolRisk.high,
    requiresConfirmation: true,
  ),
  const AIToolDefinition(
    name: 'run_command',
    description: 'Execute a shell command. Use for building, testing, installing packages. Returns stdout and stderr.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'command': {'type': 'string', 'description': 'Shell command to execute'},
        'working_directory': {'type': 'string', 'description': 'Working directory (optional)'},
      },
      'required': ['command'],
    },
    risk: AIToolRisk.medium,
    requiresConfirmation: true,
  ),
  const AIToolDefinition(
    name: 'search_code',
    description: 'Search for text patterns across the codebase using regex.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Regex pattern to search for'},
        'file_pattern': {'type': 'string', 'description': 'Glob pattern to filter files (e.g. "*.dart")'},
      },
      'required': ['query'],
    },
    risk: AIToolRisk.low,
  ),
  const AIToolDefinition(
    name: 'semantic_search',
    description: 'Hybrid semantic search: search symbols, files, and code snippets by meaning. Prefer this over search_code for questions like "where is auth handled" or "find UserRepository".',
    inputSchema: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Natural language query or symbol name'},
      },
      'required': ['query'],
    },
    risk: AIToolRisk.low,
  ),
  const AIToolDefinition(
    name: 'list_directory',
    description: 'List files and subdirectories in a directory.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'description': 'Directory path (relative to workspace or absolute)'},
      },
      'required': ['path'],
    },
    risk: AIToolRisk.low,
  ),
  const AIToolDefinition(
    name: 'search_web',
    description: 'Search the web for information. Returns search results with titles and URLs.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'query': {'type': 'string', 'description': 'Search query'},
      },
      'required': ['query'],
    },
    risk: AIToolRisk.low,
  ),
  const AIToolDefinition(
    name: 'fetch_url',
    description: 'Fetch content from a URL. Returns the text content of the page.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'url': {'type': 'string', 'description': 'URL to fetch'},
      },
      'required': ['url'],
    },
    risk: AIToolRisk.low,
  ),
  const AIToolDefinition(
    name: 'git_status',
    description: 'Get the current git status of the repository.',
    inputSchema: {
      'type': 'object',
      'properties': {},
    },
    risk: AIToolRisk.low,
  ),
  const AIToolDefinition(
    name: 'git_diff',
    description: 'Show git diff for staged or unstaged changes.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'file_path': {'type': 'string', 'description': 'Optional file path to diff'},
        'staged': {'type': 'boolean', 'description': 'Show staged changes instead of unstaged'},
      },
    },
    risk: AIToolRisk.low,
  ),
  const AIToolDefinition(
    name: 'git_commit',
    description: 'Stage all changes and create a git commit.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'message': {'type': 'string', 'description': 'Commit message'},
      },
      'required': ['message'],
    },
    risk: AIToolRisk.medium,
    requiresConfirmation: true,
  ),
  const AIToolDefinition(
    name: 'git_log',
    description: 'Show recent git commit history.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'count': {'type': 'integer', 'description': 'Number of commits to show (default 10)'},
      },
    },
    risk: AIToolRisk.low,
  ),
  const AIToolDefinition(
    name: 'apply_diff',
    description: 'Apply a unified diff patch to a file.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'file_path': {'type': 'string', 'description': 'File to patch'},
        'diff': {'type': 'string', 'description': 'Unified diff content'},
      },
      'required': ['file_path', 'diff'],
    },
    risk: AIToolRisk.high,
    requiresConfirmation: true,
  ),
];
