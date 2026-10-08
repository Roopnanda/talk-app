import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';

/// Everything about "don't ask again" lives here — onboarding, and now
/// a one-time tip about keeping the screen on during connecting.
class LocalStorageService {
  static const _kGender = 'profile.gender';
  static const _kIsAdult = 'profile.is_adult';
  static const _kOnboarded = 'profile.onboarded';
  static const _kBlockedIds = 'safety.blocked_ids';
  static const _kSeenScreenOnTip = 'tips.seen_screen_on_tip';

  Future<bool> hasOnboarded() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kOnboarded) ?? false;
  }

  Future<void> saveOnboarding({required Gender gender, required bool isAdult}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kGender, gender.storageValue);
    await prefs.setBool(_kIsAdult, isAdult);
    await prefs.setBool(_kOnboarded, true);
  }

  Future<Gender> getGender() async {
    final prefs = await SharedPreferences.getInstance();
    return GenderLabel.fromStorage(prefs.getString(_kGender) ?? 'other');
  }

  Future<bool> getIsAdult() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kIsAdult) ?? false;
  }

  Future<List<String>> getBlockedIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kBlockedIds) ?? <String>[];
  }

  Future<void> addBlockedId(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_kBlockedIds) ?? <String>[];
    if (!current.contains(uid)) {
      current.add(uid);
      await prefs.setStringList(_kBlockedIds, current);
    }
  }

  Future<bool> hasSeenScreenOnTip() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kSeenScreenOnTip) ?? false;
  }

  Future<void> markScreenOnTipSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSeenScreenOnTip, true);
  }
}
