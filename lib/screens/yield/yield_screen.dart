// lib/screens/yield/yield_screen.dart

import 'package:flutter/material.dart';
import '../../widgets/app_theme.dart';
import '../../models/api_models.dart';
import '../../services/service_factory.dart';

class YieldScreen extends StatefulWidget {
  const YieldScreen({super.key});

  @override
  State<YieldScreen> createState() => _YieldScreenState();
}

class _YieldScreenState extends State<YieldScreen> {
  final _service = ServiceFactory();

  // Form state
  String? _crop;
  String? _district;
  String? _season = 'Maha';
  String? _irrigationType = 'rainfed';
  String? _prevCrop;

  double _rainfallMm = 30;
  double _tempMin = 20;
  double _tempMax = 30;
  double _humidityPct = 70;
  double _soilPh = 6.0;
  double _soilMoisturePct = 55;
  double _fertilizerIndex = 0.7;
  double _pesticideIndex = 0.6;
  double _nIndex = 0.6;
  double _pIndex = 0.5;
  double _kIndex = 0.6;

  bool _isLoading = false;
  YieldResponse? _result;
  String? _error;

  List<String> get _validCrops => _district != null
      ? CropSphereConstants.validCropsForDistrict(_district!)
      : CropSphereConstants.crops;

  Future<void> _predict() async {
    if (_crop == null || _district == null) {
      setState(() => _error = 'Please select crop and district');
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });
    try {
      final response = await _service.predictYield(
        YieldRequest(
          crop: _crop!,
          district: _district!,
          season: _season!,
          weekOfYear: 20,
          rainfallMm: _rainfallMm,
          tempMinC: _tempMin,
          tempMaxC: _tempMax,
          humidityPct: _humidityPct,
          windSpeedKmh: 12,
          solarRadiationMj: 18,
          soilPh: _soilPh,
          soilMoisturePct: _soilMoisturePct,
          cultivatedAreaHa: 2.0,
          seedVariety: 'HORDI ${_crop!} 1',
          fertilizerIndex: _fertilizerIndex,
          pesticideIndex: _pesticideIndex,
          irrigationType: _irrigationType!,
          nIndex: _nIndex,
          pIndex: _pIndex,
          kIndex: _kIndex,
          prevCrop: _prevCrop ?? 'None',
          demandIndex: 80,
          inflationIndex: 1.2,
          holidayFlag: 0,
          festivalFlag: 0,
        ),
      );
      setState(() => _result = response);
    } catch (e) {
      setState(() => _error = 'Prediction failed: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yield Prediction'),
        actions: const [CsMockBadge(), SizedBox(width: 12)],
      ),
      body: CsLoadingOverlay(
        isLoading: _isLoading,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.success.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.success.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppTheme.success, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Model 1 · Random Forest · R²=0.975 · per-crop models',
                      style: TextStyle(fontSize: 12, color: AppTheme.success),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Location section
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
                    onChanged: (v) => setState(() {
                      _district = v;
                      _crop = null; // reset crop when district changes
                    }),
                  ),
                  const SizedBox(height: 12),
                  CsDropdown(
                    label: 'Crop',
                    value: _crop,
                    items: _validCrops,
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

            // Weather section
            CsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Weather Conditions',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CsSlider(
                    label: 'Rainfall',
                    value: _rainfallMm,
                    min: 0,
                    max: 250,
                    unit: 'mm/week',
                    onChanged: (v) => setState(() => _rainfallMm = v),
                  ),
                  CsSlider(
                    label: 'Min Temperature',
                    value: _tempMin,
                    min: 5,
                    max: 30,
                    unit: '°C',
                    onChanged: (v) => setState(() => _tempMin = v),
                  ),
                  CsSlider(
                    label: 'Max Temperature',
                    value: _tempMax,
                    min: 15,
                    max: 42,
                    unit: '°C',
                    onChanged: (v) => setState(() => _tempMax = v),
                  ),
                  CsSlider(
                    label: 'Humidity',
                    value: _humidityPct,
                    min: 30,
                    max: 100,
                    unit: '%',
                    onChanged: (v) => setState(() => _humidityPct = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Soil section
            CsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Soil & Agronomy',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
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
                    label: 'Soil Moisture',
                    value: _soilMoisturePct,
                    min: 10,
                    max: 95,
                    unit: '%',
                    onChanged: (v) => setState(() => _soilMoisturePct = v),
                  ),
                  CsSlider(
                    label: 'Fertilizer Index',
                    value: _fertilizerIndex,
                    min: 0,
                    max: 1,
                    unit: '',
                    divisions: 10,
                    onChanged: (v) => setState(() => _fertilizerIndex = v),
                  ),
                  CsSlider(
                    label: 'N Index (Nitrogen)',
                    value: _nIndex,
                    min: 0.1,
                    max: 1.0,
                    unit: '',
                    divisions: 9,
                    onChanged: (v) => setState(() => _nIndex = v),
                  ),
                  const SizedBox(height: 8),
                  CsDropdown(
                    label: 'Irrigation Type',
                    value: _irrigationType,
                    items: CropSphereConstants.irrigationTypes,
                    onChanged: (v) => setState(() => _irrigationType = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.error),
                ),
              ),

            ElevatedButton.icon(
              onPressed: _isLoading ? null : _predict,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Predict Yield'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 16),

            // Result card
            if (_result != null) _buildResultCard(_result!),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(YieldResponse result) {
    return CsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Prediction Result',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppTheme.textPrimary,
                ),
              ),
              Row(
                children: [
                  CsConfidenceBadge(confidence: result.confidence),
                  if (result.isMock) ...[
                    const SizedBox(width: 6),
                    const CsMockBadge(),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                const Icon(Icons.grass, color: AppTheme.primary, size: 48),
                const SizedBox(height: 8),
                Text(
                  '${result.predictedYieldKgPerHa.round().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} kg/ha',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${result.crop} · ${result.district}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          _resultRow('Model', result.modelUsed),
          _resultRow('Confidence', result.confidence.toUpperCase()),
          _resultRow('District', result.district),
          _resultRow('Season', _season ?? '-'),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
