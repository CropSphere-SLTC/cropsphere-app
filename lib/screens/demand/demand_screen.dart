// lib/screens/demand/demand_screen.dart

import 'package:flutter/material.dart';
import '../../widgets/app_theme.dart';
import '../../models/api_models.dart';
import '../../services/service_factory.dart';

class DemandScreen extends StatefulWidget {
  const DemandScreen({super.key});
  @override
  State<DemandScreen> createState() => _DemandScreenState();
}

class _DemandScreenState extends State<DemandScreen> {
  final _service = ServiceFactory();
  String? _crop = 'Carrot';
  String? _season = 'Maha';
  double _lag1 = 78;
  double _lag2 = 75;
  double _lag4 = 72;
  double _retailPrice = 89;
  double _inflationIndex = 1.2;
  int _holidayFlag = 0;
  int _festivalFlag = 0;
  bool _isLoading = false;
  DemandResponse? _result;
  String? _error;

  Future<void> _predict() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });
    try {
      final response = await _service.predictDemand(
        DemandRequest(
          crop: _crop!,
          season: _season!,
          weekOfYear: 20,
          demandLag1: _lag1,
          demandLag2: _lag2,
          demandLag4: _lag4,
          retailPriceLkrKg: _retailPrice,
          inflationIndex: _inflationIndex,
          holidayFlag: _holidayFlag,
          festivalFlag: _festivalFlag,
          consumerPrefIndex: 65,
          searchTrendIndex: 55,
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
        title: const Text('Demand Forecast'),
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
                color: const Color(0xFF7B1FA2).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF7B1FA2).withOpacity(0.3),
                ),
              ),
              child: const Text(
                'Model 4 · XGBoost · avg R²=0.758 · MAPE=4.1% · festival spike detection',
                style: TextStyle(fontSize: 12, color: Color(0xFF7B1FA2)),
              ),
            ),
            const SizedBox(height: 16),
            CsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Crop & Season',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CsDropdown(
                    label: 'Crop',
                    value: _crop,
                    items: CropSphereConstants.crops,
                    onChanged: (v) => setState(() => _crop = v),
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
                    'Demand History',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CsSlider(
                    label: 'Demand last week',
                    value: _lag1,
                    min: 0,
                    max: 200,
                    unit: '',
                    onChanged: (v) => setState(() => _lag1 = v),
                  ),
                  CsSlider(
                    label: 'Demand 2 weeks ago',
                    value: _lag2,
                    min: 0,
                    max: 200,
                    unit: '',
                    onChanged: (v) => setState(() => _lag2 = v),
                  ),
                  CsSlider(
                    label: 'Retail price',
                    value: _retailPrice,
                    min: 10,
                    max: 500,
                    unit: 'LKR',
                    onChanged: (v) => setState(() => _retailPrice = v),
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
                    'Cultural Events',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('This is a holiday week'),
                    value: _holidayFlag == 1,
                    activeColor: AppTheme.primary,
                    onChanged: (v) => setState(() => _holidayFlag = v ? 1 : 0),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Festival this week (Avurudu/Vesak/etc)'),
                    subtitle: const Text(
                      'Demand typically spikes 15-25%',
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _festivalFlag == 1,
                    activeColor: AppTheme.primary,
                    onChanged: (v) => setState(() => _festivalFlag = v ? 1 : 0),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppTheme.error)),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _predict,
              icon: const Icon(Icons.bar_chart),
              label: const Text('Forecast Demand'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 16),
            if (_result != null) _buildResult(_result!),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(DemandResponse result) {
    final trendColor = AppTheme.trendColor(result.trend);
    final trendIcon = result.trend == 'rising'
        ? Icons.trending_up
        : result.trend == 'falling'
        ? Icons.trending_down
        : Icons.trending_flat;

    return CsCard(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Demand Forecast',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (result.isMock) const CsMockBadge(),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  Text(
                    result.predictedDemandIndex.round().toString(),
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                  const Text(
                    'Demand index',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              Column(
                children: [
                  Icon(trendIcon, color: trendColor, size: 40),
                  Text(
                    result.trend.toUpperCase(),
                    style: TextStyle(
                      color: trendColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${result.crop} · ${result.confidence} confidence',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
