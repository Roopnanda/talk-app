import 'package:flutter/material.dart';
import '../../services/progress_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/gradient_background.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final _service = ProgressService();
  ProgressStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final stats = await _service.getStats();
    if (mounted) setState(() => _stats = stats);
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: stats == null
              ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Text('Progress', style: Theme.of(context).textTheme.headlineMedium),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GlassContainer(
                      child: Row(
                        children: [
                          _statTile(context, value: '${stats.totalCalls}', label: 'Calls'),
                          _divider(),
                          _statTile(context, value: _formatDuration(stats.totalTalked), label: 'Talked'),
                          _divider(),
                          _statTile(context, value: '${stats.currentStreak}', label: 'Day streak'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Badges', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      children: [
                        _badge(context, icon: Icons.emoji_events_rounded, label: 'First Call', unlocked: stats.firstCall),
                        _badge(context, icon: Icons.local_fire_department_rounded, label: '10 Calls', unlocked: stats.tenCalls),
                        _badge(context, icon: Icons.military_tech_rounded, label: '50 Calls', unlocked: stats.fiftyCalls),
                        _badge(context, icon: Icons.schedule_rounded, label: '1 Hour Talked', unlocked: stats.oneHourTalked),
                        _badge(context, icon: Icons.timelapse_rounded, label: '5 Hours Talked', unlocked: stats.fiveHoursTalked),
                        _badge(context, icon: Icons.bolt_rounded, label: '3-Day Streak', unlocked: stats.threeDayStreak),
                        _badge(context, icon: Icons.whatshot_rounded, label: '7-Day Streak', unlocked: stats.sevenDayStreak),
                        _badge(context, icon: Icons.workspace_premium_rounded, label: '30-Day Streak', unlocked: stats.thirtyDayStreak),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 36, color: AppColors.glassBorder);

  Widget _statTile(BuildContext context, {required String value, required String label}) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }

  Widget _badge(BuildContext context, {required IconData icon, required String label, required bool unlocked}) {
    return Opacity(
      opacity: unlocked ? 1 : 0.35,
      child: GlassContainer(
        borderRadius: 18,
        padding: const EdgeInsets.all(10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: unlocked ? AppColors.accent : AppColors.textMuted, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
