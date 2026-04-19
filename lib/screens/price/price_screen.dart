// lib/screens/price/price_screen.dart

import 'package:flutter/material.dart';
import '../../widgets/app_theme.dart';
import '../../models/api_models.dart';
import '../../services/service_factory.dart';

class PriceScreen extends StatefulWidget {
  const PriceScreen({super.key});
  @override
  State<PriceScreen> createState() => _PriceScreenState();
}

class _PriceScreenState extends State<PriceScreen> {
  final _service = ServiceFactory();
  String? _crop = 'Carrot';
  String? _district = 'Nuwara Eliya';
  String? _season = 'Maha';
  double _inflationIndex = 1.2;
  double _fuelPriceIndex = 1.3;
  double _transportIndex = 1.1;
  double _supplyIndex = 90;
  double _demandIndex = 80;
  double _lag1 = 60;
  double _lag2 = 58;
  double _lag4 = 55;
  bool _isLoading = false;
  PriceResponse? _result;
  String? _error;

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
      final response = await _service.predictPrice(
        PriceRequest(
          crop: _crop!,
          district: _district!,
          season: _season!,
          weekOfYear: 20,
          inflationIndex: _inflationIndex,
          fuelPriceIndex: _fuelPriceIndex,
          transportCostIndex: _transportIndex,
          supplyIndex: _supplyIndex,
          demandIndex: _demandIndex,
          holidayFlag: 0,
          festivalFlag: 0,
          farmgatePriceLag1: _lag1,
          farmgatePriceLag2: _lag2,
          farmgatePriceLag4: _lag4,
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
        title: const Text('Price Prediction'),
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
                color: AppTheme.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
              ),
              child: const Text(
                'Model 3 · LSTM per-crop · tested on real HARTI data · R²=0.693-0.918',
                style: TextStyle(fontSize: 12, color: AppTheme.accent),
              ),
            ),
            const SizedBox(height: 16),
            CsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Crop & Location',
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
                    'Historical Prices (LKR/kg)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CsSlider(
                    label: 'Last week price',
                    value: _lag1,
                    min: 10,
                    max: 500,
                    unit: 'LKR',
                    onChanged: (v) => setState(() => _lag1 = v),
                  ),
                  CsSlider(
                    label: '2 weeks ago',
                    value: _lag2,
                    min: 10,
                    max: 500,
                    unit: 'LKR',
                    onChanged: (v) => setState(() => _lag2 = v),
                  ),
                  CsSlider(
                    label: '4 weeks ago',
                    value: _lag4,
                    min: 10,
                    max: 500,
                    unit: 'LKR',
                    onChanged: (v) => setState(() => _lag4 = v),
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
                    'Economic Indicators',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CsSlider(
                    label: 'Inflation index',
                    value: _inflationIndex,
                    min: 0.5,
                    max: 3.0,
                    unit: '',
                    divisions: 25,
                    onChanged: (v) => setState(() => _inflationIndex = v),
                  ),
                  CsSlider(
                    label: 'Supply index',
                    value: _supplyIndex,
                    min: 20,
                    max: 200,
                    unit: '',
                    onChanged: (v) => setState(() => _supplyIndex = v),
                  ),
                  CsSlider(
                    label: 'Demand index',
                    value: _demandIndex,
                    min: 0,
                    max: 200,
                    unit: '',
                    onChanged: (v) => setState(() => _demandIndex = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppTheme.error)),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _predict,
              icon: const Icon(Icons.trending_up),
              label: const Text('Predict Price'),
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

  Widget _buildResult(PriceResponse result) {
    return CsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Price Forecast',
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
          Row(
            children: [
              Expanded(
                child: _priceBox(
                  'Farmgate',
                  result.predictedFarmgatePriceLkrKg,
                  AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _priceBox(
                  'Retail',
                  result.predictedRetailPriceLkrKg,
                  AppTheme.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${result.crop} · ${result.district}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _priceBox(String label, double price, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'LKR ${price.toStringAsFixed(1)}',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const Text(
            '/kg',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}
