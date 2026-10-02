import 'package:flutter/material.dart';
import '../../services/local_storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/gradient_background.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _storage = LocalStorageService();
  List<String> _blocked = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await _storage.getBlockedIds();
    setState(() => _blocked = b);
  }

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
                  Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
                ],
              ),
              const SizedBox(height: 16),
              GlassContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Blocked users (${_blocked.length})',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      _blocked.isEmpty
                          ? "You haven't blocked anyone."
                          : "You won't be matched with these people again.",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GlassContainer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('About', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Version 1.0.0 — Practice speaking with real people, anonymously.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
