// lib/screens/recommend/recommend_screen.dart

import 'package:flutter/material.dart';
import '../../widgets/app_theme.dart';
import '../../models/api_models.dart';
import '../../services/service_factory.dart';

class RecommendScreen extends StatefulWidget {
  const RecommendScreen({super.key});
  @override
  State<RecommendScreen> createState() => _RecommendScreenState();
}

class _RecommendScreenState extends State<RecommendScreen> {
  final _service = ServiceFactory();
  String? _district = 'Anuradhapura';
  String? _season = 'Maha';
  double _rainfall = 25;
  double _tempMin = 22;
  double _tempMax = 34;
  double _humidity = 68;
  double _soilPh = 6.2;
  double _soilMoisture = 55;
  double _nIndex = 0.6;
  double _pIndex = 0.5;
  double _kIndex = 0.6;
  String? _irrigation = 'rainfed';
  bool _isLoading = false;
  RecommendResponse? _result;
  String? _error;

  Future<void> _recommend() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });
    try {
      final response = await _service.recommendCrop(
        RecommendRequest(
          district: _district!,
          season: _season!,
          weekOfYear: 20,
          rainfallMm: _rainfall,
          tempMinC: _tempMin,
          tempMaxC: _tempMax,
          humidityPct: _humidity,
          soilPh: _soilPh,
          soilMoisturePct: _soilMoisture,
          nIndex: _nIndex,
          pIndex: _pIndex,
          kIndex: _kIndex,
          irrigationType: _irrigation!,
        ),
      );
      setState(() => _result = response);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crop Recommendation'),
        actions: const [CsMockBadge(), SizedBox(width: 12)],
      ),
      body: CsLoadingOverlay(
        isLoading: _isLoading,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
              ),
              child: const Text(
                'Model 5 · Random Forest Classifier · 90.91% accuracy · DOA crop-district constraints applied',
                style: TextStyle(fontSize: 12, color: AppTheme.primary),
              ),
            ),
            const SizedBox(height: 16),
            CsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Location & Season',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CsDropdown(
                    label: 'District',
                    value: _district,
                    items: CropSphereConstants.districts,
                    onChanged: (v) => setState(() => _district = v),
                  ),
                  const SizedBox(height: 12),
                  CsDropdown(
                    label: 'Season',
                    value: _season,
                    items: CropSphereConstants.seasons,
                    onChanged: (v) => setState(() => _season = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            CsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current Conditions',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CsSlider(
                    label: 'Rainfall',
                    value: _rainfall,
                    min: 0,
                    max: 250,
                    unit: 'mm/wk',
                    onChanged: (v) => setState(() => _rainfall = v),
                  ),
                  CsSlider(
                    label: 'Soil pH',
                    value: _soilPh,
                    min: 3.5,
                    max: 9.0,
                    unit: '',
                    divisions: 55,
                    onChanged: (v) => setState(() => _soilPh = v),
                  ),
                  CsSlider(
                    label: 'Soil moisture',
                    value: _soilMoisture,
                    min: 10,
                    max: 95,
                    unit: '%',
                    onChanged: (v) => setState(() => _soilMoisture = v),
                  ),
                  CsSlider(
                    label: 'N index',
                    value: _nIndex,
                    min: 0.1,
                    max: 1.0,
                    unit: '',
                    divisions: 9,
                    onChanged: (v) => setState(() => _nIndex = v),
                  ),
                  CsSlider(
                    label: 'P index',
                    value: _pIndex,
                    min: 0.1,
                    max: 1.0,
                    unit: '',
                    divisions: 9,
                    onChanged: (v) => setState(() => _pIndex = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppTheme.error)),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _recommend,
              icon: const Icon(Icons.recommend),
              label: const Text('Get Recommendations'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 16),
            if (_result != null) _buildResults(_result!),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildResults(RecommendResponse result) {
    if (result.recommendations.isEmpty) {
      return const CsEmptyState(
        title: 'No valid crops',
        subtitle:
            'No crops are suitable for the selected district and conditions.',
        icon: Icons.eco_outlined,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Top ${result.recommendations.length} recommendations',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppTheme.textPrimary,
              ),
            ),
            if (result.isMock) const CsMockBadge(),
          ],
        ),
        const SizedBox(height: 12),
        ...result.recommendations.map(
          (rec) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CsCard(
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: rec.rank == 1
                          ? AppTheme.primary
                          : AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '#${rec.rank}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: rec.rank == 1
                              ? Colors.white
                              : AppTheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rec.crop,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _recChip(
                              '${(rec.confidenceScore * 100).round()}% conf',
                              AppTheme.success,
                            ),
                            const SizedBox(width: 6),
                            _recChip(
                              '${rec.expectedYieldKgPerHa.round()} kg/ha',
                              AppTheme.info,
                            ),
                            const SizedBox(width: 6),
                            _recChip(
                              'LKR ${rec.expectedPriceLkrKg.round()}/kg',
                              AppTheme.accent,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _recChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
