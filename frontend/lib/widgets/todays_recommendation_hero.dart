// lib/widgets/todays_recommendation_hero.dart
// ─────────────────────────────────────────────────────────────────────────────
//  "Today's Recommendation" — the dashboard's visual centrepiece, filling
//  part of the space the old 6-card action grid used to occupy.
//
//  Two states, never an empty/broken one:
//    • Farm details set (district AND crop)  → live M5 call, hero card.
//    • Not set                               → friendly prompt card linking
//                                              to Account Settings.
//
//  M5 (/api/recommend) needs 13 fields the dashboard has no form for, so the
//  request is assembled from utils/farm_context.dart — the same district soil
//  profiles, NPK defaults and weather fetch the Crop Recommendation screen
//  uses, shared rather than duplicated so the two screens can't drift.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../models/api_models.dart';
import '../services/service_factory.dart';
import '../utils/farm_context.dart';
import 'app_theme.dart';
import 'skeleton_loading.dart';

class TodaysRecommendationHero extends StatefulWidget {
  /// Both must be non-null for the live recommendation; either being null
  /// shows the "set your farm details" prompt instead.
  final String? preferredDistrict;
  final String? preferredCrop;

  /// 'en' | 'si' | 'ta' — matches the dashboard's own _langKey.
  final String langKey;

  /// Opens Account Settings (where farm details are set).
  final VoidCallback onOpenSettings;

  /// Opens the full Crop Recommendation screen.
  final VoidCallback onSeeFull;

  const TodaysRecommendationHero({
    super.key,
    required this.preferredDistrict,
    required this.preferredCrop,
    required this.langKey,
    required this.onOpenSettings,
    required this.onSeeFull,
  });

  @override
  State<TodaysRecommendationHero> createState() =>
      _TodaysRecommendationHeroState();
}

class _TodaysRecommendationHeroState extends State<TodaysRecommendationHero> {
  CropRecommendation? _top;
  bool _loading = false;
  bool _failed = false;

  bool get _hasPrefs =>
      widget.preferredDistrict != null && widget.preferredCrop != null;

  @override
  void initState() {
    super.initState();
    if (_hasPrefs) _load();
  }

  @override
  void didUpdateWidget(TodaysRecommendationHero old) {
    super.didUpdateWidget(old);
    // Preferences can arrive after first build (the dashboard fetches them
    // asynchronously) or change while the dashboard is alive — refetch
    // rather than showing a stale district's recommendation.
    if (old.preferredDistrict != widget.preferredDistrict ||
        old.preferredCrop != widget.preferredCrop) {
      if (_hasPrefs) {
        _load();
      } else {
        setState(() {
          _top = null;
          _loading = false;
          _failed = false;
        });
      }
    }
  }

  Future<void> _load() async {
    final district = widget.preferredDistrict;
    if (district == null) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final weather = await fetchFarmWeather(district);
      final soil = soilDefaultsFor(district);
      final res = await ServiceFactory.getService().recommendCrop(
        RecommendRequest(
          district: district,
          season: farmCurrentSeason(),
          weekOfYear: farmWeekOfYear(),
          rainfallMm: weather.rainfallMm,
          tempMinC: weather.tempMinC,
          tempMaxC: weather.tempMaxC,
          humidityPct: weather.humidityPct,
          soilPh: soil.ph,
          soilMoisturePct: soil.moisturePct,
          nIndex: kDefaultNIndex,
          pIndex: kDefaultPIndex,
          kIndex: kDefaultKIndex,
          irrigationType: kDefaultIrrigation,
        ),
      );
      if (!mounted) return;
      setState(() {
        _top = res.recommendations.isEmpty ? null : res.recommendations.first;
        _loading = false;
        _failed = res.recommendations.isEmpty;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  String _t(Map<String, String> m) => m[widget.langKey] ?? m['en']!;

  @override
  Widget build(BuildContext context) {
    if (!_hasPrefs) return _buildPrompt();
    if (_loading) return _buildSkeleton();
    if (_failed || _top == null) return _buildUnavailable();
    return _buildHero(_top!);
  }

  // ── Live recommendation ────────────────────────────────────────────────
  Widget _buildHero(CropRecommendation top) {
    final season = farmCurrentSeason();
    final confidencePct = (top.confidenceScore * 100).round();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        // Deliberately the strongest surface on the dashboard — a filled
        // gradient rather than the white/tinted cards the weather and stats
        // sections use, so it reads as the page's centrepiece at a glance.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.login.primaryGreen,
            AppTheme.login.primaryDark,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppTheme.login.primaryDark.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: Colors.white70,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _t({
                    'en': "TODAY'S RECOMMENDATION",
                    'si': 'අද නිර්දේශය',
                    'ta': 'இன்றைய பரிந்துரை',
                  }).toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Colors.white70,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            top.crop,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _t({
              'en':
                  'Best match for ${widget.preferredDistrict} this $season '
                  'season — $confidencePct% confidence, around '
                  '${top.expectedYieldKgPerHa.round()} kg/ha expected.',
              'si':
                  '$season කන්නයේ ${widget.preferredDistrict} සඳහා හොඳම '
                  'තේරීම — $confidencePct% විශ්වාසය, ආසන්න වශයෙන් '
                  '${top.expectedYieldKgPerHa.round()} kg/ha.',
              'ta':
                  '$season பருவத்தில் ${widget.preferredDistrict} மாவட்டத்திற்கு '
                  'சிறந்த தேர்வு — $confidencePct% நம்பிக்கை, சுமார் '
                  '${top.expectedYieldKgPerHa.round()} kg/ha.',
            }),
            style: const TextStyle(
              fontSize: 12.5,
              color: Colors.white,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: widget.onSeeFull,
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.login.primaryDark,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 17),
              label: Text(
                _t({
                  'en': 'See full recommendation',
                  'si': 'සම්පූර්ණ නිර්දේශය බලන්න',
                  'ta': 'முழு பரிந்துரையைப் பார்க்க',
                }),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Prompt: farm details not set ───────────────────────────────────────
  Widget _buildPrompt() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.login.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.login.borderSubtle, width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppTheme.login.primaryGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.agriculture_rounded,
                  size: 21,
                  color: AppTheme.login.primaryGreen,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  _t({
                    'en': 'Set your farm details',
                    'si': 'ඔබේ ගොවිපල විස්තර සකසන්න',
                    'ta': 'உங்கள் பண்ணை விவரங்களை அமைக்கவும்',
                  }),
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.login.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _t({
              'en':
                  'Tell us your district and main crop to get personalised '
                  'recommendations and price comparisons here.',
              'si':
                  'පුද්ගලාරෝපිත නිර්දේශ සහ මිල සැසඳීම් සඳහා ඔබේ දිස්ත්‍රික්කය '
                  'සහ ප්‍රධාන භෝගය අපට කියන්න.',
              'ta':
                  'தனிப்பயன் பரிந்துரைகள் மற்றும் விலை ஒப்பீடுகளுக்கு உங்கள் '
                  'மாவட்டத்தையும் முக்கிய பயிரையும் தெரிவிக்கவும்.',
            }),
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppTheme.login.textSecondary,
            ),
          ),
          const SizedBox(height: 13),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: widget.onOpenSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.login.primaryGreen,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.tune_rounded, size: 17),
              label: Text(
                _t({
                  'en': 'Set farm details',
                  'si': 'විස්තර සකසන්න',
                  'ta': 'விவரங்களை அமைக்க',
                }),
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Couldn't load ──────────────────────────────────────────────────────
  Widget _buildUnavailable() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.login.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.login.borderSubtle, width: 1.4),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 20,
            color: AppTheme.login.textSecondary,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              _t({
                'en': "Couldn't load today's recommendation.",
                'si': 'අද නිර්දේශය ලබාගත නොහැකි විය.',
                'ta': 'இன்றைய பரிந்துரையை ஏற்ற முடியவில்லை.',
              }),
              style: TextStyle(
                fontSize: 12.5,
                color: AppTheme.login.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: _load,
            child: Text(
              _t({'en': 'Retry', 'si': 'නැවත', 'ta': 'மீண்டும்'}),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.login.primaryGreen,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Loading ────────────────────────────────────────────────────────────
  // Pulse pattern, matching the dashboard weather card — this sits on the
  // app's most-visited screen and waits on a network round-trip, so a live
  // pulse reads as "working" rather than "stuck".
  Widget _buildSkeleton() {
    return PulseFade(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.login.background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.login.borderSubtle, width: 1.4),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 130, height: 11),
            SizedBox(height: 12),
            SkeletonBox(width: 150, height: 26),
            SizedBox(height: 10),
            SkeletonBox(height: 12),
            SizedBox(height: 6),
            SkeletonBox(width: 200, height: 12),
            SizedBox(height: 16),
            SkeletonBox(height: 42, radius: 12),
          ],
        ),
      ),
    );
  }
}
