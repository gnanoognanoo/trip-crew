import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tripcrew/app/theme.dart';
import 'package:tripcrew/core/services/langchain_agent_service.dart';
import 'package:tripcrew/core/services/notification_service.dart';
import 'package:tripcrew/core/services/supabase_service.dart';
import 'package:tripcrew/core/utils/currency_formatter.dart';
import 'package:tripcrew/features/trips/models/trip_model.dart';
import 'package:tripcrew/features/trips/providers/trips_provider.dart';

/// Web resource link attached to AI responses
class _WebSource {
  final String title;
  final String url;
  final IconData icon;

  const _WebSource({
    required this.title,
    required this.url,
    required this.icon,
  });
}

/// Package stop item for trip planning
class _PackageStop {
  final String title;
  final String placeName;
  final String time;
  final int dayNumber;
  final String description;
  final double rating;
  final int reviewCount;
  final String reviewHighlight;
  final String tip;

  const _PackageStop({
    required this.title,
    required this.placeName,
    required this.time,
    required this.dayNumber,
    required this.description,
    required this.rating,
    required this.reviewCount,
    required this.reviewHighlight,
    required this.tip,
  });
}

/// Curated trip package with pricing, ratings and stops
class _TripPackage {
  final String id;
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final double estimatedCost;
  final double rating;
  final int reviewCount;
  final String durationText;
  final List<_PackageStop> stops;

  const _TripPackage({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.estimatedCost,
    required this.rating,
    required this.reviewCount,
    required this.durationText,
    required this.stops,
  });
}

/// Chat message model
class _ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final _PackageStop? placeCard;
  final List<_WebSource> webSources;

  const _ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.placeCard,
    this.webSources = const [],
  });
}

/// Screen / Bottom Sheet: AI Travel Assistant with package generator and time-to-time place reviews Q&A.
class AiAssistantDialog extends ConsumerStatefulWidget {
  final bool isFullScreen;

  const AiAssistantDialog({
    super.key,
    this.isFullScreen = false,
  });

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const AiAssistantDialog(),
    );
  }

  @override
  ConsumerState<AiAssistantDialog> createState() => _AiAssistantDialogState();
}

class _AiAssistantDialogState extends ConsumerState<AiAssistantDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  bool _isGenerating = false;
  final List<_ChatMessage> _messages = [];
  String? _addingPackageId;
  String _activeModelId = LangChainAgentService.defaultModelId;

  String get _activeModelDisplayName {
    final match = LangChainAgentService.availableModels.firstWhere(
      (m) => m.id == _activeModelId,
      orElse: () => OpenRouterModelOption(
        id: _activeModelId,
        name: _activeModelId.split('/').last,
        provider: 'OpenRouter',
        tag: 'Custom',
        description: '',
      ),
    );
    return match.name;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    LangChainAgentService.getSelectedModel().then((m) {
      if (mounted) setState(() => _activeModelId = m);
    });

    // Initial greeting based on active trip
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final trip = ref.read(activeTripProvider);
      final dest = trip?.destination ?? 'your destination';
      setState(() {
        _messages.add(
          _ChatMessage(
            text:
                "👋 Hello! I'm your **TripCrew AI Travel Assistant** powered by **$_activeModelDisplayName** on OpenRouter.\n\n"
                "I can curate **complete customized packages**, provide **time-to-time daily itineraries**, and answer questions about **places, visitor reviews, timings & food** for **$dest**.\n\n"
                "💡 *Tap the ⚙️ tune icon at the top to switch between **NVIDIA Nemotron 3.5 Super VL**, **DeepSeek V3/R1**, **Claude 3.5**, or **Llama 3.3** anytime!*",
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _inputController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  List<_TripPackage> _generatePackages(TripModel? trip) {
    final dest = (trip?.destination != null && trip!.destination.isNotEmpty)
        ? trip.destination.trim()
        : 'Marina Beach, Chennai';
    final lower = dest.toLowerCase();
    final budget = (trip?.budget != null && trip!.budget > 0) ? trip.budget : 2500.0;

    if (lower.contains('marina') || lower.contains('chennai')) {
      return [
        _TripPackage(
          id: 'pkg_marina_sig',
          title: 'The Signature Marina Explorer',
          subtitle: 'Lighthouse panorama, beach promenade, heritage monuments & legendary seafood',
          badge: 'Most Popular ⭐',
          badgeColor: const Color(0xFF10B981),
          estimatedCost: math.min(budget * 0.45, 1200.0),
          rating: 4.8,
          reviewCount: 14820,
          durationText: '1 Full Day',
          stops: const [
            _PackageStop(
              title: 'Morning Coastal Breeze & Sunrise',
              placeName: 'Marina Beach Promenade',
              time: '06:00 AM',
              dayNumber: 1,
              description: 'Watch the sunrise over Bay of Bengal and take an invigorating 3km walk along the promenade.',
              rating: 4.7,
              reviewCount: 22100,
              reviewHighlight: '"Peaceful morning vibe, safe with joggers and morning walkers."',
              tip: 'Arrive before 6:30 AM to catch the pristine golden hour without midday humidity.',
            ),
            _PackageStop(
              title: 'Panoramic 360° View of Coastline',
              placeName: 'Chennai Marina Lighthouse',
              time: '10:00 AM',
              dayNumber: 1,
              description: 'Ascend to the observation deck of the only lighthouse with an elevator on Indian shores.',
              rating: 4.6,
              reviewCount: 8940,
              reviewHighlight: '"The top deck wind and sea view are unbeatable. ₹20 entry fee is totally worth it!"',
              tip: 'Photography permitted. Elevator queues are shortest in the early morning slot.',
            ),
            _PackageStop(
              title: 'Historic Heritage & Spiritual Peace',
              placeName: 'Santhome Cathedral Basilica',
              time: '01:30 PM',
              dayNumber: 1,
              description: 'Gothic-revival church built over the tomb of St. Thomas with tranquil museum and library.',
              rating: 4.8,
              reviewCount: 11200,
              reviewHighlight: '"Serene interior with striking stained glass windows and rich history."',
              tip: 'Modest attire appreciated. Air-conditioned museum offers great midday reprieve.',
            ),
            _PackageStop(
              title: 'Sunset Beach Carnival & Local Feasts',
              placeName: 'Marina Sundari Akka Stalls & Food Lane',
              time: '05:30 PM',
              dayNumber: 1,
              description: 'Relish freshly caught fried vanjaram fish, molaga bajji, roasted corn, and evening horse rides.',
              rating: 4.6,
              reviewCount: 16700,
              reviewHighlight: '"Crispy seer fish fry with spicy onion chutney right by the ocean breeze."',
              tip: 'Cash & UPI both accepted. Check that the fish is prepared fresh on the pan.',
            ),
          ],
        ),
        _TripPackage(
          id: 'pkg_marina_culture',
          title: 'Chennai Culture & Temple Foodie Trail',
          subtitle: 'Ancient Dravidian architecture, world-famous filter coffee & handicraft bazaars',
          badge: 'Cultural Choice 🏛️',
          badgeColor: const Color(0xFFF59E0B),
          estimatedCost: math.min(budget * 0.4, 950.0),
          rating: 4.9,
          reviewCount: 19400,
          durationText: '1 Full Day',
          stops: const [
            _PackageStop(
              title: 'Ancient 7th Century Dravidian Masterpiece',
              placeName: 'Kapaleeshwarar Temple (Mylapore)',
              time: '07:30 AM',
              dayNumber: 1,
              description: 'Stunning rainbow gopuram, holy temple tank, and tranquil morning chanting vibes.',
              rating: 4.9,
              reviewCount: 28500,
              reviewHighlight: '"Architectural wonder! Peaceful temple courtyard and traditional flower market."',
              tip: 'Footwear storage available outside. Morning darshan between 7 AM and 9 AM is calmest.',
            ),
            _PackageStop(
              title: 'Legendary Breakfast & Filter Coffee',
              placeName: 'Rayar\'s Mess / Ratna Cafe',
              time: '09:30 AM',
              dayNumber: 1,
              description: 'Piping hot ghee podi idli, crispy medu vada, and authentic Kumbakonam degree filter coffee.',
              rating: 4.7,
              reviewCount: 12400,
              reviewHighlight: '"Unmatched sambar flavor poured liberally over fluffy idlis. Pure heaven!"',
              tip: 'Expect a short 10-min wait during peak hours. Highly recommended for food lovers.',
            ),
            _PackageStop(
              title: 'Swami Vivekananda Ocean House',
              placeName: 'Vivekanandar Illam (Ice House)',
              time: '02:30 PM',
              dayNumber: 1,
              description: 'Victorian circular Ice House turned meditation center and historical gallery.',
              rating: 4.7,
              reviewCount: 7400,
              reviewHighlight: '"Inspiring museum directly opposite the beach with cool sea breezes."',
              tip: 'Entry fee is ₹20. Closed on Mondays.',
            ),
            _PackageStop(
              title: 'Sunset at Elliot\'s Beach & Cafes',
              placeName: 'Besant Nagar (Bessie Beach)',
              time: '05:30 PM',
              dayNumber: 1,
              description: 'Clean coastal sands, Schmidt Memorial, and vibrant cafes along the beach boulevard.',
              rating: 4.8,
              reviewCount: 24100,
              reviewHighlight: '"Much cleaner and less crowded than northern Marina. Great cafes & ice cream!"',
              tip: 'Try Cooum or Mash restro-cafe for seaside iced drinks.',
            ),
          ],
        ),
        _TripPackage(
          id: 'pkg_marina_saver',
          title: 'Budget Backpacker & Sunset Saver',
          subtitle: 'Best highlights of the coast under ₹500 per head with public transit convenience',
          badge: 'Budget Saver 💰',
          badgeColor: const Color(0xFF3B82F6),
          estimatedCost: math.min(budget * 0.25, 450.0),
          rating: 4.7,
          reviewCount: 9100,
          durationText: '1 Full Day',
          stops: const [
            _PackageStop(
              title: 'Free Coastal Promenade Exploration',
              placeName: 'Triumph of Labour & Gandhi Statue',
              time: '07:00 AM',
              dayNumber: 1,
              description: 'Historic bronze statues and expansive open sandy trails along the waterfront.',
              rating: 4.6,
              reviewCount: 8200,
              reviewHighlight: '"Great spot for photography, sea shells, and ocean morning breeze."',
              tip: 'Free public entry. Easy access via Metro and bus routes.',
            ),
            _PackageStop(
              title: 'Semmozhi Poonga Botanical Gardens',
              placeName: 'Cathedral Road Botanical Park',
              time: '11:00 AM',
              dayNumber: 1,
              description: '20-acre lush green park with exotic plants, duck pond, and shady walking pavilions.',
              rating: 4.5,
              reviewCount: 9300,
              reviewHighlight: '"Green oasis in the middle of the city. Very calming and affordable."',
              tip: 'Entry is ₹25. Great place to relax during afternoon heat.',
            ),
            _PackageStop(
              title: 'Evening Sunset & Street Food Treats',
              placeName: 'Marina Beachfront Stalls',
              time: '05:00 PM',
              dayNumber: 1,
              description: 'Enjoy raw mango slices, roasted peanuts, chilli bajji, and coastal sunset breeze.',
              rating: 4.6,
              reviewCount: 15400,
              reviewHighlight: '"Incredible atmosphere as thousands of people gather for the sunset breeze."',
              tip: 'Keep small change or UPI QR handy for quick payments.',
            ),
          ],
        ),
      ];
    } else if (lower.contains('goa')) {
      return [
        _TripPackage(
          id: 'pkg_goa_coastal',
          title: 'North Goa Coastal & Fort Package',
          subtitle: 'Scenic cliffs, Chapora Fort, beach watersports & legendary seaside cafes',
          badge: 'Top Pick 🌴',
          badgeColor: const Color(0xFF10B981),
          estimatedCost: math.min(budget * 0.5, 2200.0),
          rating: 4.9,
          reviewCount: 18900,
          durationText: '1-2 Days',
          stops: const [
            _PackageStop(
              title: 'Dil Chahta Hai Clifftop Fort',
              placeName: 'Chapora Fort (Vagator)',
              time: '08:30 AM',
              dayNumber: 1,
              description: 'Historic red-laterite fort offering breathtaking 360° views of Vagator Beach and Chapora river.',
              rating: 4.8,
              reviewCount: 24500,
              reviewHighlight: '"Iconic cliff view! Go early morning to avoid crowd and steep uphill sun."',
              tip: 'Wear comfortable walking shoes for the 10-minute stone pathway hike.',
            ),
            _PackageStop(
              title: 'Goan Coastal Seafood Lunch',
              placeName: 'Fisherman\'s Wharf / Britto\'s',
              time: '01:00 PM',
              dayNumber: 1,
              description: 'Savor traditional Goan fish curry rice, butter garlic prawns, and sea breeze mocktails.',
              rating: 4.7,
              reviewCount: 16800,
              reviewHighlight: '"Fresh kingfish fry and crab xec-xec right on the beach sand tables."',
              tip: 'Reserve beach-facing tables in advance for sunset.',
            ),
            _PackageStop(
              title: 'Golden Sunset & Beach Shacks',
              placeName: 'Anjuna & Curley\'s Beachfront',
              time: '05:30 PM',
              dayNumber: 1,
              description: 'Watch the sun sink into the Arabian sea surrounded by rocky coastlines and live ambient music.',
              rating: 4.7,
              reviewCount: 21000,
              reviewHighlight: '"Magical sunset vibes, cool waves, and lively atmosphere."',
              tip: 'Keep belongings safe if wading into the tides.',
            ),
          ],
        ),
      ];
    }

    // Default universal package for any entered destination
    return [
      _TripPackage(
        id: 'pkg_custom_explorer',
        title: '$dest Signature Highlights Package',
        subtitle: 'Curated 1-day itinerary with top rated sightseeing, scenic views & authentic dining',
        badge: 'Recommended ⭐',
        badgeColor: const Color(0xFF10B981),
        estimatedCost: math.min(budget * 0.4, 1500.0),
        rating: 4.8,
        reviewCount: 12500,
        durationText: '1 Full Day',
        stops: [
          _PackageStop(
            title: 'Morning Exploration & Best Photo Spots',
            placeName: '$dest Central Attractions',
            time: '08:30 AM',
            dayNumber: 1,
            description: 'Visit the landmark sights of $dest during quiet morning hours with cool weather.',
            rating: 4.8,
            reviewCount: 14200,
            reviewHighlight: '"Must visit early in the day. Breathtaking scenery and memorable photo spots."',
            tip: 'Wear sunscreen, stay hydrated, and bring a power bank for photos.',
          ),
          _PackageStop(
            title: 'Authentic Regional Dining Experience',
            placeName: '$dest Renowned Food Hub',
            time: '01:00 PM',
            dayNumber: 1,
            description: 'Indulge in top-rated local delicacies celebrated by travelers and locals alike.',
            rating: 4.7,
            reviewCount: 9800,
            reviewHighlight: '"Huge portions, flavorful traditional spices, and warm hospitality."',
            tip: 'Check for crowd favorites and signature specials on the menu.',
          ),
          _PackageStop(
            title: 'Sunset Viewpoint & Evening Stroll',
            placeName: '$dest Sunset Vista',
            time: '05:30 PM',
            dayNumber: 1,
            description: 'Relax with panoramic sunset views, shopping for local souvenirs, and street snacks.',
            rating: 4.9,
            reviewCount: 18400,
            reviewHighlight: '"Golden hour here is unforgettable! Lovely cool breeze in the evening."',
            tip: 'Arrive 30 minutes before sunset for the best viewing spots.',
          ),
        ],
      ),
      _TripPackage(
        id: 'pkg_custom_saver',
        title: '$dest Budget Crew Saver',
        subtitle: 'Discover the best free and low-cost attractions within your trip budget',
        badge: 'Budget Choice 💰',
        badgeColor: const Color(0xFF3B82F6),
        estimatedCost: math.min(budget * 0.25, 600.0),
        rating: 4.6,
        reviewCount: 7800,
        durationText: '1 Day',
        stops: [
          _PackageStop(
            title: 'Scenic Public Walkways & Heritage Spots',
            placeName: '$dest Public Plaza',
            time: '09:00 AM',
            dayNumber: 1,
            description: 'Explore walkable public historic monuments and gardens with zero admission fees.',
            rating: 4.6,
            reviewCount: 6500,
            reviewHighlight: '"Spacious, clean, and completely free to visit for everyone."',
            tip: 'Use public transport or shared cabs to save on commuting.',
          ),
          _PackageStop(
            title: 'Popular Local Street Bites & Night Bazaar',
            placeName: '$dest Night Market',
            time: '06:00 PM',
            dayNumber: 1,
            description: 'Sample authentic, budget-friendly street food delicacies and browse local crafts.',
            rating: 4.7,
            reviewCount: 11200,
            reviewHighlight: '"Delicious variety of budget snacks and lively bustling energy."',
            tip: 'Keep small cash denominations ready for vendors.',
          ),
        ],
      ),
    ];
  }

  Future<void> _addPackageToItinerary(_TripPackage package) async {
    final trip = ref.read(activeTripProvider);
    if (trip == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active trip selected.')),
      );
      return;
    }

    setState(() => _addingPackageId = package.id);

    try {
      int addedCount = 0;
      if (SupabaseService.isInitialized) {
        for (int i = 0; i < package.stops.length; i++) {
          final stop = package.stops[i];
          final itemId = 'itin_${DateTime.now().millisecondsSinceEpoch}_$i';

          try {
            await SupabaseService.client.from('itinerary_items').insert({
              'id': itemId,
              'trip_id': trip.id,
              'title': stop.title,
              'location': stop.placeName,
              'day_number': stop.dayNumber,
              'time': stop.time,
              'notes': '${stop.description}\n⭐ ${stop.rating} (${NumberFormat.compact().format(stop.reviewCount)} reviews)\n💡 Pro Tip: ${stop.tip}',
              'is_completed': false,
              'created_at': DateTime.now().toIso8601String(),
            });
            addedCount++;
          } catch (_) {
            try {
              await SupabaseService.client.from('itinerary_items').insert({
                'id': itemId,
                'trip_id': trip.id,
                'title': stop.title,
                'location': stop.placeName,
                'notes': '${stop.description}\n💡 Tip: ${stop.tip}',
                'is_completed': false,
              });
              addedCount++;
            } catch (_) {}
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '🎉 Added "${package.title}" ($addedCount stops) to your Smart Itinerary!',
            ),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add package: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _addingPackageId = null);
    }
  }

  Future<void> _handleUserMessage(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    _inputController.clear();
    final trip = ref.read(activeTripProvider);
    final dest = trip?.destination ?? 'Marina Beach, Chennai';

    setState(() {
      _messages.add(
        _ChatMessage(text: q, isUser: true, timestamp: DateTime.now()),
      );
      _isGenerating = true;
    });

    _scrollChatToBottom();

    // AI intelligent answer synthesis
    await Future.delayed(const Duration(milliseconds: 700));

    if (!mounted) return;

    final lower = q.toLowerCase();
    String answer = '';
    _PackageStop? placeCard;
    final List<_WebSource> sources = [];
    final encDest = Uri.encodeComponent(dest);
    final encQuery = Uri.encodeComponent('$dest $q');

    final isGreeting = RegExp(r'^(h+l+o+|h+e+y+|h+i+|hello|sup|hola|good\s*(morning|evening|afternoon)|greetings)\b', caseSensitive: false).hasMatch(lower);

    // 1. Execute LangChain & LangGraph RAG Agent Workflow
    try {
      final historyPayload = _messages.take(6).map((m) => {
        'role': m.isUser ? 'user' : 'assistant',
        'content': m.text,
      }).toList();

      final agentResult = await LangChainAgentService.instance.processQuery(
        query: q,
        trip: trip,
        chatHistory: historyPayload,
      );

      answer = agentResult.answer;
    } catch (e) {
      answer = 'Hey there! 👋 I\'m your TripCrew AI Assistant for **$dest**.\n\n'
          'Ask me about sunrise timings, wake-up schedules, itinerary stops, street food reviews, or directions!';
    }

    // 3. Attach Verified Web Sources
    if (!isGreeting) {
      sources.add(
        _WebSource(
          title: 'Google Search: $q',
          url: 'https://www.google.com/search?q=$encQuery',
          icon: Icons.search_rounded,
        ),
      );
      sources.add(
        _WebSource(
          title: 'Explore on Google Maps',
          url: 'https://www.google.com/maps/search/?api=1&query=$encQuery',
          icon: Icons.map_rounded,
        ),
      );
      sources.add(
        _WebSource(
          title: 'Wikipedia Travel Guide',
          url: 'https://en.wikipedia.org/wiki/Special:Search?search=$encDest',
          icon: Icons.language_rounded,
        ),
      );
    } else {
      sources.add(
        _WebSource(
          title: 'Explore $dest on Maps',
          url: 'https://www.google.com/maps/search/?api=1&query=$encDest',
          icon: Icons.place_rounded,
        ),
      );
    }

    setState(() {
      _isGenerating = false;
      _messages.add(
        _ChatMessage(
          text: answer,
          isUser: false,
          timestamp: DateTime.now(),
          placeCard: placeCard,
          webSources: sources,
        ),
      );
    });

    final plainText = answer.replaceAll(RegExp(r'[*_#`>]'), '').trim();
    final snippet = plainText.length > 95 ? '${plainText.substring(0, 95)}...' : plainText;
    NotificationService.instance.showNotification(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: '✨ NVIDIA Nemotron AI ($dest)',
      body: snippet,
      payload: '/ai',
      channelId: 'tripcrew_ai',
    );

    _scrollChatToBottom();
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _showOpenRouterSettings(BuildContext context) async {
    final currentKey = await LangChainAgentService.getOpenRouterApiKey() ?? '';
    final keyCtrl = TextEditingController(text: currentKey);
    String selectedModel = _activeModelId;
    final customModelCtrl = TextEditingController(
      text: LangChainAgentService.availableModels.any((m) => m.id == selectedModel)
          ? ''
          : selectedModel,
    );

    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;

        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final isCustomSelected = !LangChainAgentService.availableModels.any((m) => m.id == selectedModel);

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.85,
                ),
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.espressoSurfaceDark : Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border.all(color: isDark ? AppTheme.sandBorderDark : AppTheme.sand),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.warmBeige,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.sand),
                              ),
                              child: const Icon(Icons.psychology_rounded, color: AppTheme.espresso, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'OpenRouter Model Switcher',
                                    style: GoogleFonts.playfairDisplay(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: isDark ? Colors.white : AppTheme.espresso,
                                    ),
                                  ),
                                  Text(
                                    'Default: NVIDIA Nemotron 3.5 Super VL',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.caramel,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => Navigator.pop(modalCtx),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          children: [
                            Text(
                              'SELECT AI MODEL',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white54 : AppTheme.mocha,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...LangChainAgentService.availableModels.map((opt) {
                              final isSelected = selectedModel == opt.id;
                              return InkWell(
                                onTap: () {
                                  setModalState(() => selectedModel = opt.id);
                                },
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? (isDark ? AppTheme.espresso : AppTheme.warmBeige.withValues(alpha: 0.5))
                                        : (isDark ? Colors.white.withValues(alpha: 0.03) : AppTheme.cream.withValues(alpha: 0.4)),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isSelected ? AppTheme.caramel : (isDark ? AppTheme.sandBorderDark : AppTheme.sand),
                                      width: isSelected ? 1.8 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                        color: isSelected ? AppTheme.caramel : Colors.grey,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    opt.name,
                                                    style: GoogleFonts.inter(
                                                      fontSize: 13.5,
                                                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                                      color: isDark ? Colors.white : AppTheme.espresso,
                                                    ),
                                                  ),
                                                ),
                                                if (opt.isFree) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: const Color(0xFF10B981)),
                                                    ),
                                                    child: const Text(
                                                      'FREE',
                                                      style: TextStyle(
                                                        fontSize: 9.5,
                                                        fontWeight: FontWeight.w900,
                                                        color: Color(0xFF10B981),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${opt.provider} • ${opt.tag}',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: isSelected ? AppTheme.caramel : AppTheme.mocha,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              opt.description,
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: isDark ? Colors.white60 : Colors.black54,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                            // Custom Model Option
                            InkWell(
                              onTap: () {
                                setModalState(() {
                                  selectedModel = customModelCtrl.text.trim().isNotEmpty
                                      ? customModelCtrl.text.trim()
                                      : 'custom';
                                });
                              },
                              borderRadius: BorderRadius.circular(14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isCustomSelected
                                      ? (isDark ? AppTheme.espresso : AppTheme.warmBeige.withValues(alpha: 0.5))
                                      : (isDark ? Colors.white.withValues(alpha: 0.03) : AppTheme.cream.withValues(alpha: 0.4)),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isCustomSelected ? AppTheme.caramel : (isDark ? AppTheme.sandBorderDark : AppTheme.sand),
                                    width: isCustomSelected ? 1.8 : 1.0,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          isCustomSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                          color: isCustomSelected ? AppTheme.caramel : Colors.grey,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          'Custom OpenRouter Model ID',
                                          style: GoogleFonts.inter(
                                            fontSize: 13.5,
                                            fontWeight: isCustomSelected ? FontWeight.w800 : FontWeight.w600,
                                            color: isDark ? Colors.white : AppTheme.espresso,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (isCustomSelected) ...[
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: customModelCtrl,
                                        decoration: InputDecoration(
                                          hintText: 'e.g. qwen/qwen-2.5-72b-instruct',
                                          hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        onChanged: (val) {
                                          selectedModel = val.trim();
                                        },
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'OPENROUTER API KEY',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white54 : AppTheme.mocha,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: keyCtrl,
                              obscureText: true,
                              decoration: InputDecoration(
                                hintText: 'sk-or-v1-... (from openrouter.ai/keys)',
                                hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.grey),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                prefixIcon: const Icon(Icons.key_rounded, size: 18),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Free models work without a key or on free tier. For full rate limits, enter your key from openrouter.ai/keys.',
                              style: GoogleFonts.inter(fontSize: 11, color: isDark ? Colors.white54 : AppTheme.mocha),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.espresso,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                onPressed: () async {
                                  final finalModel = isCustomSelected
                                      ? customModelCtrl.text.trim()
                                      : selectedModel;

                                  if (finalModel.isNotEmpty) {
                                    await LangChainAgentService.setSelectedModel(finalModel);
                                  }
                                  await LangChainAgentService.setOpenRouterApiKey(keyCtrl.text);

                                  if (mounted) {
                                    setState(() {
                                      _activeModelId = finalModel.isNotEmpty
                                          ? finalModel
                                          : LangChainAgentService.defaultModelId;
                                    });
                                  }

                                  if (modalCtx.mounted) {
                                    Navigator.pop(modalCtx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Switched to $_activeModelDisplayName'),
                                        backgroundColor: const Color(0xFF10B981),
                                      ),
                                    );
                                  }
                                },
                                child: Text(
                                  'Save & Switch Model',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final trip = ref.watch(activeTripProvider);
    final packages = _generatePackages(trip);

    return Container(
      height: widget.isFullScreen ? double.infinity : MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F1B2B) : Colors.white,
        borderRadius: widget.isFullScreen
            ? BorderRadius.zero
            : const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: widget.isFullScreen
            ? null
            : const [
                BoxShadow(color: Colors.black45, blurRadius: 25, offset: Offset(0, -6)),
              ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top grab handle (only in modal bottom sheet mode)
            if (!widget.isFullScreen) ...[
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ] else
              const SizedBox(height: 8),

            // Dialog Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFE600), Color(0xFFF59E0B)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
                      ],
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: Colors.black, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TripCrew AI Travel Assistant',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          trip != null
                              ? '${trip.destination} • $_activeModelDisplayName'
                              : 'Powered by $_activeModelDisplayName (OpenRouter)',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF60A5FA), fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune_rounded, size: 20),
                    tooltip: 'Switch OpenRouter Model',
                    onPressed: () => _showOpenRouterSettings(context),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Tab Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C2A3A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: const Color(0xFFFFE600),
                  borderRadius: BorderRadius.circular(12),
                ),
                labelColor: Colors.black,
                unselectedLabelColor: isDark ? Colors.white70 : Colors.black87,
                labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                tabs: const [
                  Tab(icon: Icon(Icons.inventory_2_rounded, size: 18), text: 'Curated Packages'),
                  Tab(icon: Icon(Icons.chat_bubble_outline_rounded, size: 18), text: 'Ask AI Assistant'),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Tab Bar View
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // TAB 1: CURATED PACKAGES
                  _buildPackagesTab(packages, isDark),

                  // TAB 2: ASK AI ASSISTANT CHAT
                  _buildChatTab(isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPackagesTab(List<_TripPackage> packages, bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      itemCount: packages.length,
      itemBuilder: (context, index) {
        final pkg = packages[index];
        final isAdding = _addingPackageId == pkg.id;

        return Container(
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF162332) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Package Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2E42) : const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: pkg.badgeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: pkg.badgeColor, width: 1),
                          ),
                          child: Text(
                            pkg.badge,
                            style: TextStyle(
                              color: pkg.badgeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 18),
                            const SizedBox(width: 3),
                            Text(
                              '${pkg.rating} (${NumberFormat.compact().format(pkg.reviewCount)} reviews)',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      pkg.title,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pkg.subtitle,
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFE600),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Est. ${CurrencyFormatter.format(pkg.estimatedCost)} / person',
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Icon(Icons.schedule_rounded, size: 15, color: isDark ? Colors.white60 : Colors.black54),
                        const SizedBox(width: 4),
                        Text(
                          pkg.durationText,
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Package Timeline Stops
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Curated Day Timeline & Stops:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 10),
                    ...pkg.stops.map((stop) => _buildStopRow(stop, isDark)),
                  ],
                ),
              ),

              // Action button to apply package
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isAdding ? null : () => _addPackageToItinerary(pkg),
                    icon: isAdding
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.add_task_rounded, size: 18),
                    label: Text(
                      isAdding ? 'Adding Stops...' : 'Add Package to Itinerary',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFE600),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStopRow(_PackageStop stop, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              stop.time,
              style: const TextStyle(
                color: Color(0xFF3B82F6),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                Text(
                  '${stop.placeName} • ⭐ ${stop.rating}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stop.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black87,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTab(bool isDark) {
    return Column(
      children: [
        // Quick Prompt Pills
        Container(
          height: 38,
          margin: const EdgeInsets.only(top: 8, bottom: 6),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _buildPromptChip('📦 Suggest Packages', 'Recommend complete package options for our trip'),
              _buildPromptChip('⭐ Place Reviews', 'Top rated attractions with real visitor reviews'),
              _buildPromptChip('🌅 Sunset Spots', 'Best sunset viewpoints and quiet beach spots'),
              _buildPromptChip('🍲 Must-Try Food', 'Must-try legendary local food and seafood'),
              _buildPromptChip('⏱️ Daily Schedule', 'Optimal time-to-time schedule from morning to night'),
            ],
          ),
        ),

        // Messages list
        Expanded(
          child: ListView.builder(
            controller: _chatScrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              return _buildChatBubble(msg, isDark);
            },
          ),
        ),

        if (_isGenerating)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFE600)),
                ),
                SizedBox(width: 10),
                Text(
                  'TripCrew AI is thinking...',
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),

        // Input row
        Container(
          padding: EdgeInsets.fromLTRB(16, 8, 16, math.max(12, MediaQuery.of(context).viewInsets.bottom + 8)),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF131F2E) : const Color(0xFFF8FAFC),
            border: Border(top: BorderSide(color: isDark ? Colors.white12 : const Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _handleUserMessage,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Ask AI about places, packages, or reviews...',
                    hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1C2A3A) : Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _handleUserMessage(_inputController.text),
                icon: const Icon(Icons.send_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFFFE600),
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPromptChip(String label, String prompt) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        backgroundColor: const Color(0xFFFFE600).withValues(alpha: 0.15),
        side: const BorderSide(color: Color(0xFFFFE600), width: 0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onPressed: () => _handleUserMessage(prompt),
      ),
    );
  }

  Widget _buildChatBubble(_ChatMessage msg, bool isDark) {
    final align = msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final bubbleColor = msg.isUser
        ? const Color(0xFFFFE600)
        : (isDark ? const Color(0xFF1C2A3A) : const Color(0xFFF1F5F9));
    final textColor = msg.isUser ? Colors.black : (isDark ? Colors.white : Colors.black87);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
                bottomRight: Radius.circular(msg.isUser ? 4 : 16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              msg.text,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                height: 1.4,
                fontWeight: msg.isUser ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
          if (msg.placeCard != null) ...[
            const SizedBox(height: 8),
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF162332) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        msg.placeCard!.title,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 16),
                          const SizedBox(width: 2),
                          Text(
                            '${msg.placeCard!.rating}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    msg.placeCard!.reviewHighlight,
                    style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '💡 Tip: ${msg.placeCard!.tip}',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87),
                  ),
                ],
              ),
            ),
          ],
          if (msg.webSources.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: msg.webSources.map((source) {
                  return InkWell(
                    onTap: () async {
                      final uri = Uri.parse(source.url);
                      try {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } catch (_) {}
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(source.icon, size: 14, color: const Color(0xFF2563EB)),
                          const SizedBox(width: 5),
                          Text(
                            source.title,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2563EB),
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.arrow_outward_rounded, size: 12, color: Color(0xFF2563EB)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
