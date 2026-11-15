import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/features/trips/models/trip_model.dart';

/// Available OpenRouter model option for switching
class OpenRouterModelOption {
  final String id;
  final String name;
  final String provider;
  final String tag;
  final String description;
  final bool isFree;

  const OpenRouterModelOption({
    required this.id,
    required this.name,
    required this.provider,
    required this.tag,
    required this.description,
    this.isFree = false,
  });
}

/// Result of OpenRouter LLM generation
class LangGraphAgentResult {
  final String answer;
  final String modelUsed;
  final List<String> reasoningSteps;

  const LangGraphAgentResult({
    required this.answer,
    this.modelUsed = 'nvidia/nemotron-3.5-super-vl',
    this.reasoningSteps = const [],
  });
}

/// Dedicated OpenRouter LLM Service powered by NVIDIA Nemotron 3.5 Super VL
/// with seamless switching across top OpenRouter models.
class LangChainAgentService {
  LangChainAgentService._();
  static final LangChainAgentService instance = LangChainAgentService._();

  static const String defaultModelId = 'nvidia/nemotron-3.5-super-vl';

  /// Curated list of high-performance OpenRouter models available for switching
  static const List<OpenRouterModelOption> availableModels = [
    OpenRouterModelOption(
      id: 'nvidia/nemotron-3.5-super-vl',
      name: 'NVIDIA Nemotron 3.5 Super VL',
      provider: 'NVIDIA',
      tag: 'Default • Vision & Reasoning',
      description: 'NVIDIA flagship multimodal reasoning model optimized for complex queries and planning.',
    ),
    OpenRouterModelOption(
      id: 'nvidia/nemotron-3.5-super-vl:free',
      name: 'NVIDIA Nemotron 3.5 Super VL (Free)',
      provider: 'NVIDIA',
      tag: 'Free Tier',
      description: 'Free access tier for NVIDIA Nemotron 3.5 Super VL on OpenRouter.',
      isFree: true,
    ),
    OpenRouterModelOption(
      id: 'nvidia/llama-3.1-nemotron-70b-instruct',
      name: 'NVIDIA Llama 3.1 Nemotron 70B',
      provider: 'NVIDIA',
      tag: 'Ultra Fast',
      description: 'High-speed 70B parameter model customized by NVIDIA for accurate instruction following.',
    ),
    OpenRouterModelOption(
      id: 'deepseek/deepseek-chat',
      name: 'DeepSeek V3 (671B)',
      provider: 'DeepSeek',
      tag: 'Top Performance',
      description: 'Powerful 671B parameter Mixture-of-Experts model with exceptional intelligence.',
    ),
    OpenRouterModelOption(
      id: 'deepseek/deepseek-r1',
      name: 'DeepSeek R1',
      provider: 'DeepSeek',
      tag: 'Deep Reasoning',
      description: 'Advanced reasoning model with chain-of-thought problem solving for travel itineraries.',
    ),
    OpenRouterModelOption(
      id: 'meta-llama/llama-3.3-70b-instruct',
      name: 'Meta Llama 3.3 70B Instruct',
      provider: 'Meta',
      tag: 'Open Source SOTA',
      description: 'Meta state-of-the-art 70B model with broad general knowledge and quick replies.',
    ),
    OpenRouterModelOption(
      id: 'anthropic/claude-3.5-sonnet',
      name: 'Anthropic Claude 3.5 Sonnet',
      provider: 'Anthropic',
      tag: 'Editorial Excellence',
      description: 'Exceptional natural tone, nuanced recommendations, and creative travel writing.',
    ),
    OpenRouterModelOption(
      id: 'openai/gpt-4o',
      name: 'OpenAI GPT-4o',
      provider: 'OpenAI',
      tag: 'Industry Benchmark',
      description: 'High-intelligence flagship model with deep general world knowledge and travel facts.',
    ),
    OpenRouterModelOption(
      id: 'openai/gpt-4o-mini',
      name: 'OpenAI GPT-4o Mini',
      provider: 'OpenAI',
      tag: 'Fast & Lightweight',
      description: 'Compact, cost-effective model delivering snappy responses for mobile travel queries.',
    ),
    OpenRouterModelOption(
      id: 'mistralai/mistral-small-24b-instruct-2501',
      name: 'Mistral Small 3 (24B)',
      provider: 'Mistral AI',
      tag: 'Snappy & Accurate',
      description: 'Precise European open model with high multilingual accuracy.',
    ),
  ];

  static const String _defaultOpenRouterKey = String.fromEnvironment(
    'OPENROUTER_API_KEY',
    defaultValue: '',
  );

  static String? _cachedOpenRouterKey;
  static String? _cachedSelectedModel;

  /// Retrieves the selected model ID (defaults to NVIDIA Nemotron 3.5 Super VL)
  static Future<String> getSelectedModel() async {
    if (_cachedSelectedModel != null && _cachedSelectedModel!.isNotEmpty) {
      return _cachedSelectedModel!;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('openrouter_selected_model');
      if (saved != null && saved.trim().isNotEmpty) {
        _cachedSelectedModel = saved.trim();
        return _cachedSelectedModel!;
      }
    } catch (_) {}
    _cachedSelectedModel = defaultModelId;
    return defaultModelId;
  }

  /// Sets and persists the selected model ID for OpenRouter
  static Future<void> setSelectedModel(String modelId) async {
    _cachedSelectedModel = modelId.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('openrouter_selected_model', modelId.trim());
    } catch (_) {}
  }

  /// Retrieves the configured OpenRouter API key
  static Future<String?> getOpenRouterApiKey() async {
    if (_cachedOpenRouterKey != null && _cachedOpenRouterKey!.isNotEmpty) {
      return _cachedOpenRouterKey;
    }
    if (_defaultOpenRouterKey.isNotEmpty) {
      _cachedOpenRouterKey = _defaultOpenRouterKey;
      return _defaultOpenRouterKey;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getString('openrouter_api_key');
      if (key != null && key.trim().isNotEmpty) {
        _cachedOpenRouterKey = key.trim();
        return _cachedOpenRouterKey;
      }
    } catch (_) {}
    return null;
  }

  /// Sets and persists a user-provided OpenRouter API key
  static Future<void> setOpenRouterApiKey(String key) async {
    _cachedOpenRouterKey = key.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('openrouter_api_key', key.trim());
    } catch (_) {}
  }

  /// Executes LLM query strictly via OpenRouter
  Future<LangGraphAgentResult> processQuery({
    required String query,
    required TripModel? trip,
    List<Map<String, String>> chatHistory = const [],
  }) async {
    final activeModel = await getSelectedModel();
    developer.log('Routing query to OpenRouter using model: $activeModel', name: 'OpenRouterAgent');

    // Build natural trip context for system prompt
    final dest = trip?.destination ?? 'your destination';
    final startPlace = trip?.startingPlace ?? 'Current Location';
    final budgetStr = trip != null ? '₹${trip.budget.toStringAsFixed(0)}' : 'Flexible';
    final crewCount = trip?.memberCount ?? 1;
    final startDateStr = trip != null ? trip.startDate.toIso8601String().split('T').first : '';
    final endDateStr = trip != null ? trip.endDate.toIso8601String().split('T').first : '';

    String itinerarySnippet = '';
    if (trip != null && SupabaseService.isInitialized) {
      try {
        final res = await SupabaseService.client
            .from('itinerary_items')
            .select('title, location, time, day_number')
            .eq('trip_id', trip.id)
            .order('day_number', ascending: true)
            .limit(10);
        if (res.isNotEmpty) {
          final buffer = StringBuffer('Existing Itinerary Stops:\n');
          for (final item in res) {
            buffer.writeln('- Day ${item['day_number']} (${item['time'] ?? ''}): ${item['title']} at ${item['location']}');
          }
          itinerarySnippet = buffer.toString();
        }
      } catch (_) {}
    }

    final systemPrompt = '''
You are the intelligent TripCrew AI Travel Assistant for the trip to "$dest".
You are powered directly by OpenRouter using $activeModel.

Live Trip Details:
- Destination: $dest
- Origin / Starting Point: $startPlace
- Dates: $startDateStr to $endDateStr
- Travel Crew: $crewCount member${crewCount > 1 ? 's' : ''}
- Total Pot Budget: $budgetStr
${itinerarySnippet.isNotEmpty ? '\n$itinerarySnippet' : ''}

Key Guidelines:
1. Provide direct, natural, highly informative, and intelligent answers specific to $dest.
2. If asked about costs or expenses, calculate estimated real-world prices in Indian Rupees (₹) for tickets, meals, local transport (Metro, auto, cab), and activities.
3. If asked about wake-up times or schedules, give exact local sunrise times, best morning hours, and ideal wake-up routines.
4. If asked for directions or transport, specify exact metro stations, bus routes, highway routes, and cab recommendations.
5. Format your output using elegant Markdown with bold headers, concise bullet points, and helpful travel emojis.
6. Speak as a friendly, expert local travel co-pilot.
''';

    // 1. Attempt primary query with selected model
    final response = await _callOpenRouter(
      model: activeModel,
      query: query,
      systemPrompt: systemPrompt,
      chatHistory: chatHistory,
    );

    if (response != null && response.trim().isNotEmpty) {
      return LangGraphAgentResult(
        answer: response.trim(),
        modelUsed: activeModel,
        reasoningSteps: ['OpenRouter: Model $activeModel responded successfully'],
      );
    }

    // 2. If the user selected an NVIDIA Nemotron model and it failed (e.g. rate limit), try fallback NVIDIA Nemotron variants
    if (activeModel.contains('nemotron')) {
      final nemotronFallbacks = [
        'nvidia/nemotron-3.5-super-vl:free',
        'nvidia/nemotron-3.5-super-vl',
        'nvidia/llama-3.1-nemotron-70b-instruct',
      ].where((m) => m != activeModel).toList();

      for (final fallbackModel in nemotronFallbacks) {
        developer.log('Trying NVIDIA fallback model: $fallbackModel', name: 'OpenRouterAgent');
        final fallbackRes = await _callOpenRouter(
          model: fallbackModel,
          query: query,
          systemPrompt: systemPrompt,
          chatHistory: chatHistory,
        );
        if (fallbackRes != null && fallbackRes.trim().isNotEmpty) {
          return LangGraphAgentResult(
            answer: fallbackRes.trim(),
            modelUsed: fallbackModel,
            reasoningSteps: ['OpenRouter: Fallback to $fallbackModel succeeded'],
          );
        }
      }
    }

    // 3. If OpenRouter returned no response (e.g. missing API key or network error)
    final apiKey = await getOpenRouterApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      return LangGraphAgentResult(
        answer: '🔑 **OpenRouter API Key Required**\n\n'
            'To get live AI answers from **$activeModel**:\n\n'
            '1. Tap the **Settings icon** (⚙️ / 🧠) at the top of this dialog.\n'
            '2. Enter your OpenRouter API key from [openrouter.ai/keys](https://openrouter.ai/keys).\n'
            '3. You can also switch between **NVIDIA Nemotron 3.5 Super VL**, **DeepSeek V3/R1**, **Claude 3.5 Sonnet**, and **Llama 3.3** anytime!',
        modelUsed: activeModel,
      );
    }

    return LangGraphAgentResult(
      answer: '⚠️ **Unable to connect to OpenRouter ($activeModel)**\n\n'
          'The model did not return a response. Please check:\n'
          '• Your OpenRouter API key quota and credits at [openrouter.ai](https://openrouter.ai)\n'
          '• Or tap the Settings icon at the top right to switch to **NVIDIA Nemotron 3.5 Super VL (Free)**, **DeepSeek V3**, or another model.',
      modelUsed: activeModel,
    );
  }

  /// Raw HTTP POST to OpenRouter API
  Future<String?> _callOpenRouter({
    required String model,
    required String query,
    required String systemPrompt,
    required List<Map<String, String>> chatHistory,
  }) async {
    try {
      final apiKey = await getOpenRouterApiKey();
      final url = Uri.parse('https://openrouter.ai/api/v1/chat/completions');

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://tripcrew-travel-2026.web.app',
        'X-Title': 'TripCrew AI Assistant',
      };
      if (apiKey != null && apiKey.isNotEmpty) {
        headers['Authorization'] = 'Bearer $apiKey';
      }

      final messages = <Map<String, String>>[
        {'role': 'system', 'content': systemPrompt},
      ];

      for (final m in chatHistory.take(8)) {
        final role = (m['role'] == 'user') ? 'user' : 'assistant';
        final text = (m['content'] ?? '').trim();
        if (text.isNotEmpty) {
          messages.add({'role': role, 'content': text});
        }
      }

      messages.add({'role': 'user', 'content': query});

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode({
          'model': model,
          'messages': messages,
          'temperature': 0.7,
          'max_tokens': 1400,
        }),
      ).timeout(const Duration(seconds: 14));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final msg = choices.first['message'] as Map<String, dynamic>?;
          final content = msg?['content'] as String?;
          if (content != null && content.trim().isNotEmpty) {
            developer.log('OpenRouter ($model) succeeded', name: 'OpenRouterAgent');
            return content.trim();
          }
        }
      } else {
        developer.log('OpenRouter ($model) HTTP ${response.statusCode}: ${response.body}', name: 'OpenRouterAgent');
      }
    } catch (e) {
      developer.log('OpenRouter ($model) exception: $e', name: 'OpenRouterAgent');
    }
    return null;
  }
}
