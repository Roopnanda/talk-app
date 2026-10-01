import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../services/ads_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/gradient_background.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/voice_orb.dart';
import '../dictionary/dictionary_screen.dart';
import '../match/matching_screen.dart';
import '../progress/progress_screen.dart';
import '../settings/settings_screen.dart';
import '../topics/topics_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  BannerAd? _banner;

  @override
  void initState() {
    super.initState();
    _banner = AdsService.instance.createBannerAd(onLoaded: (_) => setState(() {}));
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Talk', style: Theme.of(context).textTheme.headlineMedium),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined, color: AppColors.textMuted),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SettingsScreen()),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const VoiceOrb(size: 170),
                      const SizedBox(height: 36),
                      Text('Ready to practice?', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(
                        "You'll be matched with someone in seconds.",
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 28),
                      PrimaryButton(
                        label: 'Start talking',
                        icon: Icons.call_rounded,
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const MatchingScreen()),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _quickAction(
                      context,
                      icon: Icons.menu_book_rounded,
                      label: 'Dictionary',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const DictionaryScreen()),
                      ),
                    ),
                    _quickAction(
                      context,
                      icon: Icons.bar_chart_rounded,
                      label: 'Progress',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ProgressScreen()),
                      ),
                    ),
                    _quickAction(
                      context,
                      icon: Icons.forum_outlined,
                      label: 'Topics',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TopicsScreen()),
                      ),
                    ),
                  ],
                ),
              ),
              if (_banner != null)
                SizedBox(
                  width: _banner!.size.width.toDouble(),
                  height: _banner!.size.height.toDouble(),
                  child: AdWidget(ad: _banner!),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: GlassContainer(
        borderRadius: 18,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: AppColors.accent, size: 22),
            const SizedBox(height: 6),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
