import 'package:quantum_ide/core/models/ai_provider_config.dart';

class LocalModelMetadata {
  final String id;
  final String name;
  final String filename;
  final String url;
  final String sizeFormatted;
  final String ramRequiredFormatted;
  final String contextWindow;
  final String speedEstimate;
  final String speedRating; // e.g. 'Сверхбыстрая ⚡⚡⚡', 'Быстрая ⚡⚡', 'Средняя ⚡'
  final String capabilities; // e.g. 'Кодинг, автодополнение, фикс багов'
  final String category; // 'Код', 'Рассуждения', 'Чат', 'Зрение'
  final String quantization; // 'Q4_K_M', 'Int8', 'FP16'
  final LocalAiEngine engine;
  final bool isVision;

  const LocalModelMetadata({
    required this.id,
    required this.name,
    required this.filename,
    required this.url,
    required this.sizeFormatted,
    required this.ramRequiredFormatted,
    required this.contextWindow,
    required this.speedEstimate,
    required this.speedRating,
    required this.capabilities,
    required this.category,
    required this.quantization,
    required this.engine,
    this.isVision = false,
  });

  bool get isOllama => engine == LocalAiEngine.ollama;

  double get ramRequiredGb {
    final match = RegExp(r'([\d\.]+)').firstMatch(ramRequiredFormatted);
    if (match != null) {
      return double.tryParse(match.group(1)!) ?? 2.0;
    }
    return 2.0;
  }

  static const List<LocalModelMetadata> catalog = [
    // ── Qwen 2.5 Coder 1.5B ──────────────────────────────
    LocalModelMetadata(
      id: 'qwen2.5-coder:1.5b',
      name: 'Qwen 2.5 Coder 1.5B',
      filename: 'qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf',
      sizeFormatted: '1.16 GB',
      ramRequiredFormatted: '2.5 GB RAM',
      contextWindow: '32,768 токенов (32K)',
      speedEstimate: '~30–45 ток/с',
      speedRating: 'Сверхбыстрая ⚡⚡⚡',
      capabilities: 'Генерация кода на 92 языках, рефакторинг, автодополнение, поиск багов',
      category: 'Код',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.llamaServer,
    ),
    LocalModelMetadata(
      id: 'ollama:qwen2.5-coder:1.5b',
      name: 'Qwen 2.5 Coder 1.5B (Ollama)',
      filename: 'qwen2.5-coder:1.5b',
      url: 'qwen2.5-coder:1.5b',
      sizeFormatted: '0.98 GB',
      ramRequiredFormatted: '2.5 GB RAM',
      contextWindow: '32,768 токенов (32K)',
      speedEstimate: '~30–45 ток/с',
      speedRating: 'Сверхбыстрая ⚡⚡⚡',
      capabilities: 'Специализированная кодинг-модель. Мгновенный отклик на мобильных',
      category: 'Код',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.ollama,
    ),

    // ── DeepSeek R1 Distill Qwen 1.5B ───────────────────
    LocalModelMetadata(
      id: 'deepseek-r1-distill-qwen-1.5b-q4_k_m.gguf',
      name: 'DeepSeek R1 Distill 1.5B',
      filename: 'deepseek-r1-distill-qwen-1.5b-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF/resolve/main/DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf',
      sizeFormatted: '1.12 GB',
      ramRequiredFormatted: '2.5 GB RAM',
      contextWindow: '32,768 токенов (32K)',
      speedEstimate: '~28–42 ток/с',
      speedRating: 'Сверхбыстрая ⚡⚡⚡',
      capabilities: 'Глубокие пошаговые рассуждения (<think>), математика, сложные алгоритмы',
      category: 'Рассуждения',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.llamaServer,
    ),
    LocalModelMetadata(
      id: 'ollama:deepseek-r1:1.5b',
      name: 'DeepSeek R1 1.5B (Ollama)',
      filename: 'deepseek-r1:1.5b',
      url: 'deepseek-r1:1.5b',
      sizeFormatted: '1.10 GB',
      ramRequiredFormatted: '2.5 GB RAM',
      contextWindow: '32,768 токенов (32K)',
      speedEstimate: '~28–42 ток/с',
      speedRating: 'Сверхбыстрая ⚡⚡⚡',
      capabilities: 'Революционная цепочка мыслей (<think>), логика, архитектура кода',
      category: 'Рассуждения',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.ollama,
    ),

    // ── Qwen 2.5 Coder 3B ────────────────────────────────
    LocalModelMetadata(
      id: 'qwen2.5-3b-instruct-q4_k_m.gguf',
      name: 'Qwen 2.5 Coder 3B',
      filename: 'qwen2.5-3b-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf',
      sizeFormatted: '2.10 GB',
      ramRequiredFormatted: '4.0 GB RAM',
      contextWindow: '32,768 токенов (32K)',
      speedEstimate: '~18–26 ток/с',
      speedRating: 'Быстрая ⚡⚡',
      capabilities: 'Идеальный баланс точности и скорости для мобильных. Полные функции и классы',
      category: 'Код',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.llamaServer,
    ),
    LocalModelMetadata(
      id: 'ollama:qwen2.5-coder:3b',
      name: 'Qwen 2.5 Coder 3B (Ollama)',
      filename: 'qwen2.5-coder:3b',
      url: 'qwen2.5-coder:3b',
      sizeFormatted: '1.90 GB',
      ramRequiredFormatted: '4.0 GB RAM',
      contextWindow: '32,768 токенов (32K)',
      speedEstimate: '~18–26 ток/с',
      speedRating: 'Быстрая ⚡⚡',
      capabilities: 'Высокая точность синтаксиса, документация, тесты',
      category: 'Код',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.ollama,
    ),

    // ── Llama 3.2 1B ─────────────────────────────────────
    LocalModelMetadata(
      id: 'llama-3.2-1b-instruct-q4_k_m.gguf',
      name: 'Llama 3.2 1B',
      filename: 'llama-3.2-1b-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      sizeFormatted: '0.81 GB',
      ramRequiredFormatted: '1.8 GB RAM',
      contextWindow: '131,072 токенов (128K)',
      speedEstimate: '~35–50 ток/с',
      speedRating: 'Молниеносная ⚡⚡⚡',
      capabilities: 'Гигантский контекст 128K, быстрые ответы, суммаризация файлов',
      category: 'Чат',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.llamaServer,
    ),
    LocalModelMetadata(
      id: 'ollama:llama3.2:1b',
      name: 'Llama 3.2 1B (Ollama)',
      filename: 'llama3.2:1b',
      url: 'llama3.2:1b',
      sizeFormatted: '1.30 GB',
      ramRequiredFormatted: '2.0 GB RAM',
      contextWindow: '131,072 токенов (128K)',
      speedEstimate: '~35–50 ток/с',
      speedRating: 'Молниеносная ⚡⚡⚡',
      capabilities: 'Быстрый легкий чат от Meta, минимальное потребление батареи',
      category: 'Чат',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.ollama,
    ),

    // ── Llama 3.2 3B ─────────────────────────────────────
    LocalModelMetadata(
      id: 'llama-3.2-3b-instruct-uncensored-q4_k_m.gguf',
      name: 'Llama 3.2 3B (Uncensored)',
      filename: 'llama-3.2-3b-instruct-uncensored-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-uncensored-GGUF/resolve/main/Llama-3.2-3B-Instruct-uncensored-Q4_K_M.gguf',
      sizeFormatted: '2.02 GB',
      ramRequiredFormatted: '4.0 GB RAM',
      contextWindow: '131,072 токенов (128K)',
      speedEstimate: '~16–24 ток/с',
      speedRating: 'Быстрая ⚡⚡',
      capabilities: 'Без цензуры и ограничений, понимание сложного контекста, код и текст',
      category: 'Чат',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.llamaServer,
    ),
    LocalModelMetadata(
      id: 'ollama:llama3.2:3b',
      name: 'Llama 3.2 3B (Ollama)',
      filename: 'llama3.2:3b',
      url: 'llama3.2:3b',
      sizeFormatted: '2.00 GB',
      ramRequiredFormatted: '4.0 GB RAM',
      contextWindow: '131,072 токенов (128K)',
      speedEstimate: '~16–24 ток/с',
      speedRating: 'Быстрая ⚡⚡',
      capabilities: 'Отличный универсальный помощник от Meta для любых задач',
      category: 'Чат',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.ollama,
    ),

    // ── Qwen 2.5 Coder 7B ────────────────────────────────
    LocalModelMetadata(
      id: 'qwen2.5-coder-7b-instruct-q4_k_m.gguf',
      name: 'Qwen 2.5 Coder 7B',
      filename: 'qwen2.5-coder-7b-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/Qwen/Qwen2.5-Coder-7B-Instruct-GGUF/resolve/main/qwen2.5-coder-7b-instruct-q4_k_m.gguf',
      sizeFormatted: '4.68 GB',
      ramRequiredFormatted: '8.0 GB RAM',
      contextWindow: '32,768 токенов (32K)',
      speedEstimate: '~6–11 ток/с',
      speedRating: 'Тяжелая (Флагманы) ⚡',
      capabilities: 'Профессиональный уровень кодинга (уровень Claude 3.5 Sonnet / GPT-4o mini offline)',
      category: 'Код',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.llamaServer,
    ),
    LocalModelMetadata(
      id: 'ollama:qwen2.5-coder:7b',
      name: 'Qwen 2.5 Coder 7B (Ollama)',
      filename: 'qwen2.5-coder:7b',
      url: 'qwen2.5-coder:7b',
      sizeFormatted: '4.70 GB',
      ramRequiredFormatted: '8.0 GB RAM',
      contextWindow: '32,768 токенов (32K)',
      speedEstimate: '~6–11 ток/с',
      speedRating: 'Тяжелая (Флагманы) ⚡',
      capabilities: 'Мощнейшая автономная модель для сложных проектов и рефакторинга',
      category: 'Код',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.ollama,
    ),

    // ── DeepSeek R1 7B ───────────────────────────────────
    LocalModelMetadata(
      id: 'ollama:deepseek-r1:7b',
      name: 'DeepSeek R1 7B (Ollama)',
      filename: 'deepseek-r1:7b',
      url: 'deepseek-r1:7b',
      sizeFormatted: '4.70 GB',
      ramRequiredFormatted: '8.0 GB RAM',
      contextWindow: '32,768 токенов (32K)',
      speedEstimate: '~5–10 ток/с',
      speedRating: 'Тяжелая (Флагманы) ⚡',
      capabilities: 'Максимальная глубина рассуждений и доказательств без интернета',
      category: 'Рассуждения',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.ollama,
    ),

    // ── Gemma 2 2B ───────────────────────────────────────
    LocalModelMetadata(
      id: 'gemma-2-2b-it-q4_k_m.gguf',
      name: 'Gemma 2 2B Instruct',
      filename: 'gemma-2-2b-it-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
      sizeFormatted: '1.71 GB',
      ramRequiredFormatted: '3.0 GB RAM',
      contextWindow: '8,192 токенов (8K)',
      speedEstimate: '~22–32 ток/с',
      speedRating: 'Быстрая ⚡⚡',
      capabilities: 'Архитектура Google DeepMind, великолепная грамотность и понимание инструкций',
      category: 'Чат',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.llamaServer,
    ),
    LocalModelMetadata(
      id: 'ollama:gemma2:2b',
      name: 'Gemma 2 2B (Ollama)',
      filename: 'gemma2:2b',
      url: 'gemma2:2b',
      sizeFormatted: '1.60 GB',
      ramRequiredFormatted: '3.0 GB RAM',
      contextWindow: '8,192 токенов (8K)',
      speedEstimate: '~22–32 ток/с',
      speedRating: 'Быстрая ⚡⚡',
      capabilities: 'Компактная качественная модель от Google',
      category: 'Чат',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.ollama,
    ),

    // ── Phi-3.5 Mini 3.8B ────────────────────────────────
    LocalModelMetadata(
      id: 'phi-3.5-mini-instruct-q4_k_m.gguf',
      name: 'Phi-3.5 Mini Instruct',
      filename: 'phi-3.5-mini-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
      sizeFormatted: '2.20 GB',
      ramRequiredFormatted: '4.5 GB RAM',
      contextWindow: '131,072 токенов (128K)',
      speedEstimate: '~14–22 ток/с',
      speedRating: 'Быстрая ⚡⚡',
      capabilities: 'Синтетические датасеты Microsoft, высокая логика при малом весе',
      category: 'Рассуждения',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.llamaServer,
    ),

    // ── Qwen2-VL 2B (Vision) ─────────────────────────────
    LocalModelMetadata(
      id: 'qwen2-vl-2b-instruct-q4_k_m.gguf',
      name: 'Qwen2-VL 2B (Vision)',
      filename: 'qwen2-vl-2b-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf',
      sizeFormatted: '1.50 GB',
      ramRequiredFormatted: '3.5 GB RAM',
      contextWindow: '32,768 токенов (32K)',
      speedEstimate: '~16–25 ток/с',
      speedRating: 'Быстрая ⚡⚡',
      capabilities: 'Распознавание скриншотов, макетов UI, схем и фото прямо на телефоне',
      category: 'Зрение',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.llamaServer,
      isVision: true,
    ),

    // ── Dolphin 3.0 Qwen 1.5B (Uncensored) ───────────────
    LocalModelMetadata(
      id: 'dolphin-3.0-qwen2.5-1.5b-q4_k_m.gguf',
      name: 'Dolphin 3.0 Qwen 1.5B',
      filename: 'dolphin-3.0-qwen2.5-1.5b-q4_k_m.gguf',
      url: 'https://huggingface.co/bartowski/Dolphin3.0-Qwen2.5-1.5B-GGUF/resolve/main/Dolphin3.0-Qwen2.5-1.5B-Q4_K_M.gguf',
      sizeFormatted: '1.10 GB',
      ramRequiredFormatted: '2.5 GB RAM',
      contextWindow: '32,768 токенов (32K)',
      speedEstimate: '~30–45 ток/с',
      speedRating: 'Сверхбыстрая ⚡⚡⚡',
      capabilities: 'Полностью свободная модель без морализаторства, быстрый кодинг',
      category: 'Код',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.llamaServer,
    ),

    // ── DeepSeek Coder 1.3B (Ollama) ─────────────────────
    LocalModelMetadata(
      id: 'ollama:deepseek-coder:1.3b',
      name: 'DeepSeek Coder 1.3B (Ollama)',
      filename: 'deepseek-coder:1.3b',
      url: 'deepseek-coder:1.3b',
      sizeFormatted: '0.80 GB',
      ramRequiredFormatted: '2.0 GB RAM',
      contextWindow: '16,384 токенов (16K)',
      speedEstimate: '~35–50 ток/с',
      speedRating: 'Молниеносная ⚡⚡⚡',
      capabilities: 'Быстрый генератор скриптов и регулярных выражений',
      category: 'Код',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.ollama,
    ),

    // ── Mistral 7B (Ollama) ──────────────────────────────
    LocalModelMetadata(
      id: 'ollama:mistral:7b',
      name: 'Mistral 7B (Ollama)',
      filename: 'mistral:7b',
      url: 'mistral:7b',
      sizeFormatted: '4.10 GB',
      ramRequiredFormatted: '8.0 GB RAM',
      contextWindow: '32,768 токенов (32K)',
      speedEstimate: '~6–11 ток/с',
      speedRating: 'Тяжелая (Флагманы) ⚡',
      capabilities: 'Классическая европейская модель, уверенный код и связные тексты',
      category: 'Чат',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.ollama,
    ),

    // ── Phi-4 Mini 3.8B (Microsoft SOTA 2025/2026) ────────
    LocalModelMetadata(
      id: 'phi-4-mini-instruct-q4_k_m.gguf',
      name: 'Microsoft Phi-4 Mini 3.8B',
      filename: 'Phi-4-mini-instruct-Q4_K_M.gguf',
      url: 'https://huggingface.co/unsloth/Phi-4-mini-instruct-GGUF/resolve/main/Phi-4-mini-instruct-Q4_K_M.gguf',
      sizeFormatted: '2.40 GB',
      ramRequiredFormatted: '4.5 GB RAM',
      contextWindow: '131,072 токенов (128K)',
      speedEstimate: '~18–26 ток/с',
      speedRating: 'Быстрая ⚡⚡',
      capabilities: 'Новейшая модель Microsoft (2025). Превосходит GPT-4o mini по математике и логике',
      category: 'Рассуждения',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.llamaServer,
    ),
    LocalModelMetadata(
      id: 'ollama:phi4:mini',
      name: 'Microsoft Phi-4 Mini (Ollama)',
      filename: 'phi4:mini',
      url: 'phi4:mini',
      sizeFormatted: '2.30 GB',
      ramRequiredFormatted: '4.5 GB RAM',
      contextWindow: '131,072 токенов (128K)',
      speedEstimate: '~18–26 ток/с',
      speedRating: 'Быстрая ⚡⚡',
      capabilities: 'Топовая компактная логика и алгоритмы от Microsoft Research',
      category: 'Рассуждения',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.ollama,
    ),

    // ── Phi-4 14B (SOTA Reasoning) ────────────────────────
    LocalModelMetadata(
      id: 'ollama:phi4:14b',
      name: 'Microsoft Phi-4 14B (Ollama)',
      filename: 'phi4:14b',
      url: 'phi4:14b',
      sizeFormatted: '9.10 GB',
      ramRequiredFormatted: '14.0 GB RAM',
      contextWindow: '16,384 токенов (16K)',
      speedEstimate: '~3–6 ток/с',
      speedRating: 'Тяжелая (Мощные ПК/Флагманы) ⚡',
      capabilities: 'Флагманская модель рассуждений Microsoft, побеждающая многие 70B модели',
      category: 'Рассуждения',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.ollama,
    ),

    // ── DeepSeek R1 14B ──────────────────────────────────
    LocalModelMetadata(
      id: 'ollama:deepseek-r1:14b',
      name: 'DeepSeek R1 14B (Ollama)',
      filename: 'deepseek-r1:14b',
      url: 'deepseek-r1:14b',
      sizeFormatted: '9.00 GB',
      ramRequiredFormatted: '14.0 GB RAM',
      contextWindow: '32,768 токенов (32K)',
      speedEstimate: '~3–6 ток/с',
      speedRating: 'Тяжелая (Мощные устройства) ⚡',
      capabilities: 'Глубочайший анализ архитектуры, математические доказательства и пошаговый синтез',
      category: 'Рассуждения',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.ollama,
    ),

    // ── Qwen 2.5 Coder 14B ───────────────────────────────
    LocalModelMetadata(
      id: 'ollama:qwen2.5-coder:14b',
      name: 'Qwen 2.5 Coder 14B (Ollama)',
      filename: 'qwen2.5-coder:14b',
      url: 'qwen2.5-coder:14b',
      sizeFormatted: '9.00 GB',
      ramRequiredFormatted: '14.0 GB RAM',
      contextWindow: '32,768 токенов (32K)',
      speedEstimate: '~3–6 ток/с',
      speedRating: 'Тяжелая (Мощные устройства) ⚡',
      capabilities: 'Максимальное качество генерации сложных репозиториев и тестов',
      category: 'Код',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.ollama,
    ),

    // ── Mistral NeMo 12B (128K context) ──────────────────
    LocalModelMetadata(
      id: 'ollama:mistral-nemo:12b',
      name: 'Mistral NeMo 12B (Ollama)',
      filename: 'mistral-nemo:12b',
      url: 'mistral-nemo:12b',
      sizeFormatted: '7.10 GB',
      ramRequiredFormatted: '12.0 GB RAM',
      contextWindow: '131,072 токенов (128K)',
      speedEstimate: '~4–8 ток/с',
      speedRating: 'Тяжелая ⚡',
      capabilities: 'Совместная разработка Mistral AI и NVIDIA. 128K контекст для больших кодовых баз',
      category: 'Код',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.ollama,
    ),

    // ── SmolLM2 1.7B (HuggingFace Mobile) ────────────────
    LocalModelMetadata(
      id: 'smollm2-1.7b-instruct-q4_k_m.gguf',
      name: 'SmolLM2 1.7B (HuggingFace)',
      filename: 'smollm2-1.7b-instruct-q4_k_m.gguf',
      url: 'https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct-GGUF/resolve/main/smollm2-1.7b-instruct-q4_k_m.gguf',
      sizeFormatted: '1.05 GB',
      ramRequiredFormatted: '2.2 GB RAM',
      contextWindow: '8,192 токенов (8K)',
      speedEstimate: '~35–48 ток/с',
      speedRating: 'Молниеносная ⚡⚡⚡',
      capabilities: 'Сверхбыстрая компактная модель Hugging Face, обученная на качественных синтетических данных',
      category: 'Чат',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.llamaServer,
    ),
    LocalModelMetadata(
      id: 'ollama:smollm2:1.7b',
      name: 'SmolLM2 1.7B (Ollama)',
      filename: 'smollm2:1.7b',
      url: 'smollm2:1.7b',
      sizeFormatted: '1.00 GB',
      ramRequiredFormatted: '2.2 GB RAM',
      contextWindow: '8,192 токенов (8K)',
      speedEstimate: '~35–48 ток/с',
      speedRating: 'Молниеносная ⚡⚡⚡',
      capabilities: 'Мобильная легкая модель для слабых смартфонов',
      category: 'Чат',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.ollama,
    ),

    // ── MiniCPM-V 2.6 (SOTA Vision) ──────────────────────
    LocalModelMetadata(
      id: 'ollama:minicpm-v:8b',
      name: 'MiniCPM-V 2.6 (Vision)',
      filename: 'minicpm-v:8b',
      url: 'minicpm-v:8b',
      sizeFormatted: '5.50 GB',
      ramRequiredFormatted: '9.0 GB RAM',
      contextWindow: '32,768 токенов (32K)',
      speedEstimate: '~6–10 ток/с',
      speedRating: 'Тяжелая ⚡',
      capabilities: 'Лидер среди компактных мультимодальных моделей: распознавание видео, верстки и фото',
      category: 'Зрение',
      quantization: 'Q4_K_M',
      engine: LocalAiEngine.ollama,
      isVision: true,
    ),
  ];

  static LocalModelMetadata find(String query) {
    final clean = query.trim().toLowerCase().replaceAll(':latest', '');
    for (final m in catalog) {
      final mId = m.id.toLowerCase().replaceAll('ollama:', '');
      final mFile = m.filename.toLowerCase();
      final mName = m.name.toLowerCase();
      if (clean == mId || clean == mFile || clean == mName || clean.contains(mId) || mFile.contains(clean)) {
        return m;
      }
    }
    return deduceFallback(query);
  }

  static LocalModelMetadata deduceFallback(String rawName) {
    final nameLower = rawName.toLowerCase();
    final is7b = nameLower.contains('7b') || nameLower.contains('8b');
    final is3b = nameLower.contains('3b') || nameLower.contains('4b');
    final is1b = nameLower.contains('1b') || nameLower.contains('0.5b') || nameLower.contains('1.5b') || nameLower.contains('2b');
    final isCoding = nameLower.contains('code') || nameLower.contains('qwen');
    final isReasoning = nameLower.contains('r1') || nameLower.contains('reason') || nameLower.contains('think');
    final isVision = nameLower.contains('vl') || nameLower.contains('vision');

    final size = is7b ? '4.5 GB' : (is3b ? '2.1 GB' : (is1b ? '1.2 GB' : '2.0 GB'));
    final ram = is7b ? '8.0 GB RAM' : (is3b ? '4.0 GB RAM' : (is1b ? '2.5 GB RAM' : '4.0 GB RAM'));
    final speed = is7b ? '~6–10 ток/с' : (is3b ? '~16–25 ток/с' : (is1b ? '~30–45 ток/с' : '~18–25 ток/с'));
    final rating = is1b ? 'Сверхбыстрая ⚡⚡⚡' : (is3b ? 'Быстрая ⚡⚡' : (is7b ? 'Тяжелая ⚡' : 'Стандартная ⚡'));
    final cat = isVision ? 'Зрение' : (isReasoning ? 'Рассуждения' : (isCoding ? 'Код' : 'Чат'));
    final cap = isCoding
        ? 'Генерация кода, автодополнение и рефакторинг'
        : (isReasoning ? 'Пошаговые рассуждения и логика' : 'Диалог, ответы на вопросы, редактирование');

    return LocalModelMetadata(
      id: rawName,
      name: rawName,
      filename: rawName,
      url: rawName,
      sizeFormatted: size,
      ramRequiredFormatted: ram,
      contextWindow: '32,768 токенов (32K)',
      speedEstimate: speed,
      speedRating: rating,
      capabilities: cap,
      category: cat,
      quantization: 'Q4_K_M',
      engine: rawName.contains(':') ? LocalAiEngine.ollama : LocalAiEngine.llamaServer,
      isVision: isVision,
    );
  }
}
