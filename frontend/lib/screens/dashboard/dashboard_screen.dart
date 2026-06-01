// lib/screens/dashboard/dashboard_screen.dart

import 'package:flutter/material.dart';
import '../../widgets/app_theme.dart';
import '../../models/api_models.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.eco, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('CropSphere'),
          ],
        ),
        actions: [
          const CsMockBadge(),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.person_outline, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Hero card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primaryDark, AppTheme.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Agricultural Intelligence',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'CropSphere',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '6 ML models · 6 crops · 8 districts · Sri Lanka',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _statChip('R² 0.975', 'Yield model'),
                    const SizedBox(width: 8),
                    _statChip('90.91%', 'Crop accuracy'),
                    const SizedBox(width: 8),
                    _statChip('4.1% MAPE', 'Price error'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'ML Models',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          // Model cards grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: const [
              _ModelCard(
                title: 'Yield Prediction',
                subtitle: 'Random Forest · R²=0.975',
                icon: Icons.grass,
                color: AppTheme.success,
                screenIndex: 1,
              ),
              _ModelCard(
                title: 'Price Prediction',
                subtitle: 'LSTM · MAPE 4.4-8.1%',
                icon: Icons.trending_up,
                color: AppTheme.accent,
                screenIndex: 2,
              ),
              _ModelCard(
                title: 'Weather Forecast',
                subtitle: 'LSTM · temp R²=0.974',
                icon: Icons.cloud,
                color: AppTheme.info,
                screenIndex: 3,
              ),
              _ModelCard(
                title: 'Crop Recommend',
                subtitle: 'Random Forest · 90.9%',
                icon: Icons.recommend,
                color: AppTheme.primary,
                screenIndex: 4,
              ),
              _ModelCard(
                title: 'Demand Forecast',
                subtitle: 'XGBoost · R²=0.758',
                icon: Icons.bar_chart,
                color: Color(0xFF7B1FA2),
                screenIndex: 5,
              ),
              _ModelCard(
                title: 'AI Chatbot',
                subtitle: 'LLaMA 3 · RAG 100%',
                icon: Icons.chat,
                color: Color(0xFF00695C),
                screenIndex: 6,
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Crops covered',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CropSphereConstants.crops
                .map((c) => _CropChip(name: c))
                .toList(),
          ),
          const SizedBox(height: 20),
          CsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Data sources',
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
                  '4,978 rows · 52 columns · 2021-2025',
                ),
                _sourceRow(
                  Icons.store,
                  'HARTI prices',
                  'Weekly producer + retail prices',
                ),
                _sourceRow(
                  Icons.satellite,
                  'NASA POWER',
                  '8 districts · corrected',
                ),
                _sourceRow(
                  Icons.agriculture,
                  'DOA Agstat',
                  'Yield baselines · crop requirements',
                ),
              ],
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _statChip(String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _sourceRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.primary),
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
                    fontSize: 12,
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

class _ModelCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final int screenIndex;

  const _ModelCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.screenIndex,
  });

  @override
  Widget build(BuildContext context) {
    return CsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const Spacer(),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _CropChip extends StatelessWidget {
  final String name;
  const _CropChip({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.eco, size: 14, color: AppTheme.primary),
          const SizedBox(width: 4),
          Text(
            name,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
