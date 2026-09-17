/// Home screen ad banner
///
/// This is the **ONLY ad in the entire app** — deliberately tiny and
/// non-intrusive, following a simple contract:
///
/// * One small banner (320x50), bottom of the home screen. Nowhere else.
/// * No pop-ups, no interstitials, no video ads, no rewarded ads. Ever.
/// * If the phone is offline (or no ad is available), the banner simply
///   does not appear — no error, no blank box, no layout jump.
///
/// It never touches chats, file transfers, or the Bluetooth layer.
library;

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class HomeAdBanner extends StatefulWidget {
  const HomeAdBanner({super.key});

  /// ⚠️ This is Google's public TEST banner ad unit ID.
  ///
  /// Replace it with your real AdMob banner ad unit ID before release,
  /// or no revenue is generated:
  ///   1. Create a free account at https://admob.com
  ///   2. Register this app, then create a "Banner" ad unit
  ///   3. Paste its ID here (and your App ID in AndroidManifest.xml)
  static const String _adUnitId = 'ca-app-pub-3940256099942544/6300978111';

  @override
  State<HomeAdBanner> createState() => _HomeAdBannerState();
}

class _HomeAdBannerState extends State<HomeAdBanner> {
  BannerAd? _banner;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _banner = BannerAd(
      adUnitId: HomeAdBanner._adUnitId,
      size: AdSize.banner, // Standard 320x50 — the smallest common format
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          // Offline / no fill: stay completely invisible.
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _banner;
    if (!_loaded || ad == null) {
      // Zero height — the user sees nothing when there is no ad.
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      color: const Color(0xFF121212), // Match app background
      alignment: Alignment.center,
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
