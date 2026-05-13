// lib/screens/dashboard/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/app_theme.dart';
import '../../models/api_models.dart';

class DashboardScreen extends StatelessWidget {
  /// Called when user taps a model card — passes the bottom nav index to switch to
  final ValueChanged<int>? onNavigate;

  const DashboardScreen({super.key, this.onNavigate});

  // ── Season detection ───────────────────────────────────────────────────────
  // Maha: week 40–52 + 1–12  |  Yala: week 14–39  |  Inter: week 13 or leftover
  static String _currentSeason() {
    final week = _currentWeek();
    if (week >= 40 || week <= 12) return 'Maha';
    if (week >= 14 && week <= 39) return 'Yala';
    return 'Inter';
  }

  static int _currentWeek() {
    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 1, 1);
    final diff = now.difference(startOfYear).inDays;
    return ((diff + startOfYear.weekday - 1) / 7).ceil().clamp(1, 52);
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  static String _seasonIcon(String season) {
    switch (season) {
      case 'Maha':
        return '🌧️';
      case 'Yala':
        return '☀️';
      default:
        return '🌤️';
    }
  }

  static String _seasonDescription(String season) {
    switch (season) {
      case 'Maha':
        return 'North-east monsoon season · Oct – Mar';
      case 'Yala':
        return 'South-west monsoon season · Apr – Sep';
      default:
        return 'Inter-monsoon period';
    }
  }

  // ── Farming tips per season ────────────────────────────────────────────────
  static const Map<String, List<Map<String, String>>> _tips = {
    'Maha': [
      {
        'icon': '💧',
        'tip':
            'Maha season brings heavy rains — ensure proper drainage to avoid root rot in Carrot and Groundnut.',
      },
      {
        'icon': '🌱',
        'tip':
            'Good time to plant Maize and Cowpea in Anuradhapura and Monaragala districts.',
      },
      {
        'icon': '🛡️',
        'tip':
            'High humidity during Maha increases fungal disease risk. Apply preventive fungicide early.',
      },
    ],
    'Yala': [
      {
        'icon': '☀️',
        'tip':
            'Yala dry spells reduce water availability — prioritise drip irrigation for best Carrot yields.',
      },
      {
        'icon': '📈',
        'tip':
            'Vegetable prices typically rise mid-Yala due to supply drops. Plan harvests accordingly.',
      },
      {
        'icon': '🌿',
        'tip':
            'Green gram and Cowpea are drought-tolerant — ideal choices for Yala in low-rainfall districts.',
      },
    ],
    'Inter': [
      {
        'icon': '🔄',
        'tip':
            'Inter-monsoon is ideal for soil preparation and applying compost before the Maha season begins.',
      },
      {
        'icon': '📊',
        'tip':
            'Use this period to analyse last season\'s yield data and adjust inputs for the next planting.',
      },
      {
        'icon': '🌾',
        'tip':
            'Finger millet performs well in inter-monsoon conditions with minimal irrigation.',
      },
    ],
  };

  static Map<String, String> _currentTip() {
    final season = _currentSeason();
    final week = _currentWeek();
    final tips = _tips[season] ?? _tips['Inter']!;
    return tips[week % tips.length];
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final firstName = (user?.displayName ?? 'Farmer').split(' ').first;
    final season = _currentSeason();
    final week = _currentWeek();
    final tip = _currentTip();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          // ── Hero card ──────────────────────────────────────────────────────
          _buildHeroCard(firstName, season, week),
          const SizedBox(height: 16),

          // ── Quick tip ──────────────────────────────────────────────────────
          _buildTipCard(tip, season),
          const SizedBox(height: 20),

          // ── ML Models section ──────────────────────────────────────────────
          _buildSectionHeader('ML Models', '6 models ready'),
          const SizedBox(height: 12),
          _buildModelGrid(context),
          const SizedBox(height: 20),

          // ── Crops covered ──────────────────────────────────────────────────
          _buildSectionHeader('Crops Covered', '6 crops · 8 districts'),
          const SizedBox(height: 12),
          _buildCropGrid(),
          const SizedBox(height: 20),

          // ── Data sources ───────────────────────────────────────────────────
          _buildSectionHeader('Data Sources', 'Training data'),
          const SizedBox(height: 12),
          _buildSourcesCard(),
        ],
      ),
    );
  }

  // ── Hero card ──────────────────────────────────────────────────────────────
  Widget _buildHeroCard(String firstName, String season, int week) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDark.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting row
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_greeting()},',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    firstName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // CropSphere logo area
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.eco, color: Colors.white, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Season + week pill row
          Row(
            children: [
              _heroPill(
                '${_seasonIcon(season)} $season Season',
                AppTheme.primaryLight.withValues(alpha: 0.25),
              ),
              const SizedBox(width: 8),
              _heroPill(
                '📅 Week $week / 52',
                Colors.white.withValues(alpha: 0.15),
              ),
            ],
          ),
          const SizedBox(height: 6),

          Text(
            _seasonDescription(season),
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 16),

          // Model accuracy stats
          Row(
            children: [
              _statChip('R² 0.975', 'Yield'),
              const SizedBox(width: 8),
              _statChip('90.91%', 'Crop rec.'),
              const SizedBox(width: 8),
              _statChip('4.1% MAPE', 'Price'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroPill(String label, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _statChip(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }

  // ── Tip card ───────────────────────────────────────────────────────────────
  Widget _buildTipCard(Map<String, String> tip, String season) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(tip['icon']!, style: const TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$season Season Tip',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.accent,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tip['tip']!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textPrimary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Section header ─────────────────────────────────────────────────────────
  Widget _buildSectionHeader(String title, String subtitle) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // ── Model grid ─────────────────────────────────────────────────────────────
  Widget _buildModelGrid(BuildContext context) {
    // navIndex matches MainShell._screens list order:
    // 0=Dashboard, 1=Yield, 2=Price, 3=Weather, 4=Recommend, 5=Demand, 6=Chat
    final models = [
      _ModelInfo(
        title: 'Yield Prediction',
        subtitle: 'Random Forest · R²=0.975',
        icon: Icons.grass,
        color: AppTheme.success,
        navIndex: 1,
        badge: 'R² 0.975',
      ),
      _ModelInfo(
        title: 'Price Prediction',
        subtitle: 'LSTM · MAPE 4.4–8.1%',
        icon: Icons.trending_up,
        color: AppTheme.accent,
        navIndex: 2,
        badge: '4.4% MAPE',
      ),
      _ModelInfo(
        title: 'Weather Forecast',
        subtitle: 'LSTM · temp R²=0.974',
        icon: Icons.cloud,
        color: AppTheme.info,
        navIndex: 3,
        badge: '4 weeks',
      ),
      _ModelInfo(
        title: 'Crop Recommend',
        subtitle: 'Random Forest · 90.9%',
        icon: Icons.recommend,
        color: AppTheme.primary,
        navIndex: 4,
        badge: '90.9% acc.',
      ),
      _ModelInfo(
        title: 'Demand Forecast',
        subtitle: 'XGBoost · R²=0.758',
        icon: Icons.bar_chart,
        color: const Color(0xFF7B1FA2),
        navIndex: 5,
        badge: 'XGBoost',
      ),
      _ModelInfo(
        title: 'AI Chatbot',
        subtitle: 'LLaMA 3 · RAG',
        icon: Icons.chat,
        color: const Color(0xFF00695C),
        navIndex: 6,
        badge: 'RAG',
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: models
          .map((m) =>
              _ModelCard(info: m, onTap: () => onNavigate?.call(m.navIndex)))
          .toList(),
    );
  }

  // ── Crop grid ──────────────────────────────────────────────────────────────
  Widget _buildCropGrid() {
    // emoji per crop for visual identity
    const cropEmojis = {
      'Carrot': '🥕',
      'Maize': '🌽',
      'Green gram': '🫘',
      'Cowpea': '🌿',
      'Finger millet': '🌾',
      'Groundnut': '🥜',
    };

    const cropDistricts = {
      'Carrot': 'Nuwara Eliya · Badulla · Jaffna',
      'Maize': 'Anuradhapura · Monaragala · Ampara',
      'Green gram': 'Hambantota · Monaragala · Jaffna',
      'Cowpea': 'Anuradhapura · Monaragala · Ampara',
      'Finger millet': 'Anuradhapura · Monaragala · Ampara',
      'Groundnut': 'Monaragala · Ampara · Batticaloa · Jaffna',
    };

    return Column(
      children: CropSphereConstants.crops.map((crop) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.surfaceCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0EBE0)),
          ),
          child: Row(
            children: [
              Text(
                cropEmojis[crop] ?? '🌱',
                style: const TextStyle(fontSize: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      crop,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      cropDistricts[crop] ?? '',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: AppTheme.textMuted,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Data sources card ──────────────────────────────────────────────────────
  Widget _buildSourcesCard() {
    return CsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Training Data Sources',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          _sourceRow(
            Icons.science,
            'Synthetic dataset',
            '4,978 rows · 52 columns · 2021–2025',
            AppTheme.primary,
          ),
          _sourceRow(
            Icons.store,
            'HARTI prices',
            'Weekly producer + retail prices',
            AppTheme.accent,
          ),
          _sourceRow(
            Icons.satellite,
            'NASA POWER',
            '8 districts · bias-corrected',
            AppTheme.info,
          ),
          _sourceRow(
            Icons.agriculture,
            'DOA Agstat',
            'Yield baselines · crop requirements',
            AppTheme.success,
          ),
        ],
      ),
    );
  }

  Widget _sourceRow(IconData icon, String title, String subtitle, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Model card ────────────────────────────────────────────────────────────────
class _ModelInfo {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final int navIndex;
  final String badge;

  const _ModelInfo({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.navIndex,
    required this.badge,
  });
}

class _ModelCard extends StatelessWidget {
  final _ModelInfo info;
  final VoidCallback onTap;

  const _ModelCard({required this.info, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE0EBE0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon + badge row
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: info.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(info.icon, color: info.color, size: 20),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: info.color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      info.badge,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: info.color,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                info.title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                info.subtitle,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              // Tap indicator
              Row(
                children: [
                  Text(
                    'Open',
                    style: TextStyle(
                      fontSize: 11,
                      color: info.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_forward, size: 11, color: info.color),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
