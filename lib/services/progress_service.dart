import 'package:shared_preferences/shared_preferences.dart';

class ProgressStats {
  const ProgressStats({
    required this.totalCalls,
    required this.totalTalked,
    required this.currentStreak,
    required this.longestStreak,
  });

  final int totalCalls;
  final Duration totalTalked;
  final int currentStreak;
  final int longestStreak;

  bool get firstCall => totalCalls >= 1;
  bool get tenCalls => totalCalls >= 10;
  bool get fiftyCalls => totalCalls >= 50;
  bool get oneHourTalked => totalTalked >= const Duration(hours: 1);
  bool get fiveHoursTalked => totalTalked >= const Duration(hours: 5);
  bool get threeDayStreak => longestStreak >= 3;
  bool get sevenDayStreak => longestStreak >= 7;
  bool get thirtyDayStreak => longestStreak >= 30;
}

/// Tracks call history on-device only — there's no login, so this is the
/// only place progress can live. A call only counts once it's run for a
/// few real seconds, so an instant misfire/retry doesn't inflate the
/// numbers.
class ProgressService {
  static const _kTotalCalls = 'progress.total_calls';
  static const _kTotalSeconds = 'progress.total_seconds';
  static const _kCurrentStreak = 'progress.current_streak';
  static const _kLongestStreak = 'progress.longest_streak';
  static const _kLastCallDate = 'progress.last_call_date';

  static const _minCountableDuration = Duration(seconds: 5);

  Future<void> recordCallCompleted(Duration elapsed) async {
    if (elapsed < _minCountableDuration) return;

    final prefs = await SharedPreferences.getInstance();
    final totalCalls = (prefs.getInt(_kTotalCalls) ?? 0) + 1;
    final totalSeconds = (prefs.getInt(_kTotalSeconds) ?? 0) + elapsed.inSeconds;

    final today = _dateKey(DateTime.now());
    final yesterday = _dateKey(DateTime.now().subtract(const Duration(days: 1)));
    final lastDate = prefs.getString(_kLastCallDate);
    int currentStreak = prefs.getInt(_kCurrentStreak) ?? 0;
    final longestStreak = prefs.getInt(_kLongestStreak) ?? 0;

    if (lastDate == null) {
      currentStreak = 1;
    } else if (lastDate == today) {
      // already counted today — streak unchanged
    } else if (lastDate == yesterday) {
      currentStreak += 1;
    } else {
      currentStreak = 1; // gap of more than a day — streak resets
    }

    await prefs.setInt(_kTotalCalls, totalCalls);
    await prefs.setInt(_kTotalSeconds, totalSeconds);
    await prefs.setInt(_kCurrentStreak, currentStreak);
    await prefs.setInt(
      _kLongestStreak,
      currentStreak > longestStreak ? currentStreak : longestStreak,
    );
    await prefs.setString(_kLastCallDate, today);
  }

  Future<ProgressStats> getStats() async {
    final prefs = await SharedPreferences.getInstance();

    // If the last call wasn't today or yesterday, the streak has already
    // lapsed even though the stored value only updates on the next
    // completed call — reflect that lapse here when just reading stats.
    final lastDate = prefs.getString(_kLastCallDate);
    final today = _dateKey(DateTime.now());
    final yesterday = _dateKey(DateTime.now().subtract(const Duration(days: 1)));
    int currentStreak = prefs.getInt(_kCurrentStreak) ?? 0;
    if (lastDate != null && lastDate != today && lastDate != yesterday) {
      currentStreak = 0;
    }

    return ProgressStats(
      totalCalls: prefs.getInt(_kTotalCalls) ?? 0,
      totalTalked: Duration(seconds: prefs.getInt(_kTotalSeconds) ?? 0),
      currentStreak: currentStreak,
      longestStreak: prefs.getInt(_kLongestStreak) ?? 0,
    );
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
