import 'package:flutter/material.dart';
import 'package:tripcrew/core/constants/app_constants.dart';

/// Interactive dialog for TripCrew AI Travel Assistant with confirmation safeguards.
class AiAssistantDialog extends StatefulWidget {
  const AiAssistantDialog({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const AiAssistantDialog(),
    );
  }

  @override
  State<AiAssistantDialog> createState() => _AiAssistantDialogState();
}

class _AiAssistantDialogState extends State<AiAssistantDialog> {
  final _inputController = TextEditingController();
  bool _isGenerating = false;
  String? _suggestion;

  final List<String> _quickPrompts = [
    'Recommend top 3 seafood spots in North Goa',
    'Suggest essential packing gear for monsoon trip',
    'Optimize itinerary order for beach & sunset',
  ];

  void _generateSuggestion(String prompt) async {
    setState(() {
      _isGenerating = true;
      _suggestion = null;
    });

    await Future.delayed(const Duration(milliseconds: 900));

    if (mounted) {
      setState(() {
        _isGenerating = false;
        if (prompt.toLowerCase().contains('seafood') ||
            prompt.toLowerCase().contains('food')) {
          _suggestion =
              "Here are 3 verified Goan seafood spots for your crew:\n"
              "1. Fisherman's Wharf (Panjim) - Celebrated Goan curry & crab xec xec\n"
              "2. Britto's (Baga) - Sunset seaside tables & fresh catch platter\n"
              "3. Martin's Corner (Betalbatim) - Legendary local cuisine & live music";
        } else if (prompt.toLowerCase().contains('pack')) {
          _suggestion =
              "Recommended smart packing additions for your crew:\n"
              "• Quick-dry microfiber towels (4x)\n"
              "• High-protection waterproof dry bags for electronics\n"
              "• Reef-safe sunscreen & insect repellent lotion";
        } else {
          _suggestion =
              "TripCrew AI Assistant Insight:\n"
              "To avoid midday crowds, visit Chapora Fort and Aguada early morning (8:00 AM - 10:30 AM), "
              "and schedule beach water sports before 3:00 PM.";
        }
      });
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppConstants.radiusXl),
          topRight: Radius.circular(AppConstants.radiusXl),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppConstants.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: theme.colorScheme.secondary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceSm),
                  Text(
                    'TripCrew AI Assistant',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF59E0B)),
                ),
                child: const Text(
                  'Prototype Mode • Cloud Function Gemini Endpoint Pending API Key',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92400E),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Powered by backend AI functions. Never alters your trip without your explicit confirmation.',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: AppConstants.spaceMd),

              // Quick prompt chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _quickPrompts.map((p) {
                  return ActionChip(
                    label: Text(p, style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      _inputController.text = p;
                      _generateSuggestion(p);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: AppConstants.spaceMd),

              if (_isGenerating)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_suggestion != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppConstants.spaceMd),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _suggestion!,
                        style: const TextStyle(height: 1.4, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton(
                            onPressed: () => setState(() => _suggestion = null),
                            child: const Text('Dismiss'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'AI suggestions accepted & added!',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Confirm & Apply'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppConstants.spaceMd),
              ],

              // Input row
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      decoration: const InputDecoration(
                        hintText: 'Ask AI about places, schedule, or tips...',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                      onSubmitted: _generateSuggestion,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spaceSm),
                  IconButton.filled(
                    onPressed: () => _generateSuggestion(_inputController.text),
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
              const SizedBox(height: AppConstants.spaceSm),
            ],
          ),
        ),
      ),
    );
  }
}
