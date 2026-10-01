import 'package:flutter/material.dart';
import '../../data/topics_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/gradient_background.dart';

class TopicsScreen extends StatelessWidget {
  const TopicsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text('Topics', style: Theme.of(context).textTheme.headlineMedium),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 8, top: 4),
                child: Text(
                  'Conversation starters for your next call.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              for (final category in kTopicCategories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => _TopicDetailScreen(category: category)),
                    ),
                    child: GlassContainer(
                      borderRadius: 20,
                      child: Row(
                        children: [
                          Icon(category.icon, color: AppColors.accent, size: 24),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(category.name, style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 2),
                                Text(
                                  '${category.prompts.length} prompts',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicDetailScreen extends StatelessWidget {
  const _TopicDetailScreen({required this.category});
  final TopicCategory category;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(category.name, style: Theme.of(context).textTheme.headlineMedium),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final prompt in category.prompts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassContainer(
                    borderRadius: 18,
                    child: Text(prompt, style: Theme.of(context).textTheme.bodyLarge),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
