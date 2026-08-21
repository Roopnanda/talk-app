import 'dart:io';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob only for now. Meta Audience Network was pulled out temporarily —
/// the plugin (facebook_audience_network) hasn't been updated by its
/// maintainer in ~4 years and risks a second wave of build failures
/// (stale Android embedding/Gradle assumptions) on top of the version
/// mismatch that caused the first one. Re-add it once the rest of the
/// pipeline is confirmed working, ideally testing it in isolation so any
/// failure is easy to attribute.
///
/// ⚠️ Replace every ad unit ID below with your own from the AdMob
/// console before release. The ones here are Google's public TEST ids —
/// safe to leave in during development, but they will not earn anything
/// and must not ship to production.
class AdsService {
  AdsService._();
  static final AdsService instance = AdsService._();

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;

  // --- Test IDs (Google's official test units) ---------------------------
  static String get _bannerUnitId => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-3940256099942544/2934735716';

  static String get _interstitialUnitId => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/1033173712'
      : 'ca-app-pub-3940256099942544/4411468910';

  static String get _rewardedUnitId => Platform.isAndroid
      ? 'ca-app-pub-3940256099942544/5224354917'
      : 'ca-app-pub-3940256099942544/1712485313';

  Future<void> init() async {
    await MobileAds.instance.initialize();
    _loadInterstitial();
    _loadRewarded();
  }

  BannerAd createBannerAd({required void Function(Ad) onLoaded}) {
    final banner = BannerAd(
      adUnitId: _bannerUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(onAdLoaded: onLoaded),
    );
    banner.load();
    return banner;
  }

  // --- Interstitial: shown between calls (natural break, not mid-call) ---
  void _loadInterstitial() {
    InterstitialAd.load(
      adUnitId: _interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) => _interstitial = null,
      ),
    );
  }

  /// Call after a call ends / before returning to the queue.
  Future<void> showInterstitialBetweenCalls() async {
    if (_interstitial == null) return;
    _interstitial!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
      },
    );
    await _interstitial!.show();
    _interstitial = null;
  }

  // --- Rewarded: optional "skip the wait" or "reveal translation" perk ---
  void _loadRewarded() {
    RewardedAd.load(
      adUnitId: _rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (_) => _rewarded = null,
      ),
    );
  }

  Future<void> showRewarded({required void Function() onEarned}) async {
    if (_rewarded == null) return;
    await _rewarded!.show(
      onUserEarnedReward: (ad, reward) => onEarned(),
    );
    _rewarded!.dispose();
    _rewarded = null;
    _loadRewarded();
  }
}
