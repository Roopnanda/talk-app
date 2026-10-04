import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../theme/app_theme.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/gradient_background.dart';

class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key});

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _result;
  int _searchGeneration = 0;

  Future<void> _search(String word) async {
    if (word.trim().isEmpty) return;
    final myGeneration = ++_searchGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final res = await http
          .get(Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/${Uri.encodeComponent(word.trim())}'))
          .timeout(const Duration(seconds: 25));
      if (myGeneration != _searchGeneration) return;
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        setState(() => _result = list.first as Map<String, dynamic>);
      } else {
        // Shows the real status instead of a one-size-fits-all message —
        // a genuine 404 ("not in the dictionary") looks very different
        // from a 403/429/500, which would point to something else
        // entirely (rate limiting, a network-level block, etc).
        String detail = 'HTTP ${res.statusCode}';
        try {
          final body = jsonDecode(res.body);
          if (body is Map && body['message'] != null) {
            detail = '$detail — ${body['message']}';
          }
        } catch (_) {
          if (res.body.isNotEmpty) {
            final snippet = res.body.length > 150 ? res.body.substring(0, 150) : res.body;
            detail = '$detail — $snippet';
          }
        }
        setState(() => _error = 'No definition found for "$word".\n\n$detail');
      }
    } on TimeoutException {
      if (myGeneration != _searchGeneration) return;
      setState(() => _error = 'The dictionary is responding slowly right now. Try again in a moment.');
    } catch (e) {
      if (myGeneration != _searchGeneration) return;
      setState(() => _error = 'Could not reach the dictionary right now.\n\n$e');
    } finally {
      if (myGeneration == _searchGeneration) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Text('Dictionary', style: Theme.of(context).textTheme.headlineMedium),
                  ],
                ),
                const SizedBox(height: 12),
                GlassContainer(
                  borderRadius: 20,
                  padding: const EdgeInsets.only(left: 18, right: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                            hintText: 'Search a word…',
                            hintStyle: TextStyle(color: AppColors.textMuted),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 16),
                          ),
                          onSubmitted: _search,
                        ),
                      ),
                      IconButton(
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                              )
                            : const Icon(Icons.search_rounded, color: AppColors.accent),
                        onPressed: _loading ? null : () => _search(_controller.text),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_loading)
                  Text('Searching — this can take a little while…',
                      style: Theme.of(context).textTheme.bodyMedium),
                if (_error != null)
                  Text(_error!,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                if (_result != null) Expanded(child: _DefinitionCard(entry: _result!)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DefinitionCard extends StatelessWidget {
  const _DefinitionCard({required this.entry});
  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final word = entry['word'] as String? ?? '';
    final phonetic = entry['phonetic'] as String? ?? '';
    final meanings = (entry['meanings'] as List?) ?? [];

    return SingleChildScrollView(
      child: GlassContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(word, style: Theme.of(context).textTheme.headlineMedium),
            if (phonetic.isNotEmpty)
              Text(phonetic, style: const TextStyle(color: AppColors.accent)),
            const SizedBox(height: 12),
            for (final m in meanings) ...[
              Text(
                m['partOfSpeech'] ?? '',
                style: const TextStyle(color: AppColors.accentSoft, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              for (final def in (m['definitions'] as List? ?? []).take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('• ${def['definition']}', style: Theme.of(context).textTheme.bodyLarge),
                ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
