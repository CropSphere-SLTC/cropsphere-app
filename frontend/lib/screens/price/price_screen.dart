// lib/screens/price/price_screen.dart

import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../services/service_factory.dart';
import '../../models/api_models.dart';
import '../../widgets/app_theme.dart';

class PriceScreen extends StatefulWidget {
  const PriceScreen({super.key});
  @override
  State<PriceScreen> createState() => _PriceScreenState();
}

class _PriceScreenState extends State<PriceScreen> {
  String _selectedCrop = 'Carrot';
  String _selectedDistrict = 'Nuwara Eliya';
  String _selectedSeason = 'Maha';
  double _inflationIndex = 1.2;
  double _fuelPriceIndex = 1.1;
  double _supplyIndex = 85.0;
  double _demandIndex = 75.0;
  int _holidayFlag = 0;
  int _festivalFlag = 0;
  bool _isLoading = false;
  PriceResponse? _result;
  String? _errorMessage;

  final List<String> _crops = [
    'Carrot',
    'Maize',
    'Green gram',
    'Cowpea',
    'Finger millet',
    'Groundnut',
  ];
  final List<String> _districts = [
    'Nuwara Eliya',
    'Badulla',
    'Anuradhapura',
    'Monaragala',
    'Ampara',
    'Hambantota',
    'Batticaloa',
    'Jaffna',
  ];
  final List<String> _seasons = ['Maha', 'Yala', 'Inter'];

  Future<void> _predict() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
    });
    try {
      final service = ServiceFactory.getService();
      final basePrice = {
        'Carrot': 58.0,
        'Maize': 48.0,
        'Green gram': 145.0,
        'Cowpea': 142.0,
        'Finger millet': 98.0,
        'Groundnut': 195.0,
      };
      final base = basePrice[_selectedCrop] ?? 80.0;
      final response = await service.predictPrice(
        PriceRequest(
          crop: _selectedCrop,
          district: _selectedDistrict,
          season: _selectedSeason,
          weekOfYear: 10,
          inflationIndex: _inflationIndex,
          fuelPriceIndex: _fuelPriceIndex,
          transportCostIndex: 1.1,
          supplyIndex: _supplyIndex,
          demandIndex: _demandIndex,
          holidayFlag: _holidayFlag,
          festivalFlag: _festivalFlag,
          farmgatePriceLag1: base,
          farmgatePriceLag2: base * 0.98,
          farmgatePriceLag4: base * 0.95,
        ),
      );
      setState(() => _result = response);
    } catch (e) {
      setState(() => _errorMessage = 'Prediction failed: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildSelectionCard(),
            const SizedBox(height: 16),
            _buildEconomicCard(),
            const SizedBox(height: 16),
            _buildFlagsCard(),
            const SizedBox(height: 20),
            _buildPredictButton(),
            const SizedBox(height: 20),
            if (_errorMessage != null) _buildErrorCard(),
            if (_result != null) _buildResultCard(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF2E7D32), const Color(0xFF43A047)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.trending_up, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Price Predictor',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                AppConfig.useMockServices ? 'Mock Mode' : 'Live Model',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildDropdown(
              'Crop',
              _selectedCrop,
              _crops,
              Icons.eco,
              (v) => setState(() => _selectedCrop = v!),
            ),
            const SizedBox(height: 12),
            _buildDropdown(
              'District',
              _selectedDistrict,
              _districts,
              Icons.location_on,
              (v) => setState(() => _selectedDistrict = v!),
            ),
            const SizedBox(height: 12),
            _buildDropdown(
              'Season',
              _selectedSeason,
              _seasons,
              Icons.calendar_month,
              (v) => setState(() => _selectedSeason = v!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEconomicCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Economic Conditions',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildSlider(
              'Inflation Index',
              _inflationIndex,
              0.5,
              3.0,
              '',
              Colors.red,
              (v) => setState(() => _inflationIndex = v),
            ),
            _buildSlider(
              'Fuel Price Index',
              _fuelPriceIndex,
              0.5,
              3.0,
              '',
              Colors.orange,
              (v) => setState(() => _fuelPriceIndex = v),
            ),
            _buildSlider(
              'Supply Index',
              _supplyIndex,
              20,
              200,
              '',
              Colors.blue,
              (v) => setState(() => _supplyIndex = v),
            ),
            _buildSlider(
              'Demand Index',
              _demandIndex,
              0,
              200,
              '',
              Colors.green,
              (v) => setState(() => _demandIndex = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlagsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Market Signals',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Holiday Week'),
              subtitle: const Text('Public holiday this week'),
              value: _holidayFlag == 1,
              onChanged: (v) => setState(() => _holidayFlag = v ? 1 : 0),
              activeThumbColor: AppTheme.primary,
            ),
            SwitchListTile(
              title: const Text('Festival Week'),
              subtitle: const Text('Major festival (Avurudu, Vesak, etc.)'),
              value: _festivalFlag == 1,
              onChanged: (v) => setState(() => _festivalFlag = v ? 1 : 0),
              activeThumbColor: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPredictButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _predict,
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.price_check),
        label: Text(
          _isLoading ? 'Predicting...' : 'Predict Price',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: const Color(0xFF2E7D32),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Price Prediction',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                if (_result!.isMock)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: const Text(
                      'MOCK DATA',
                      style: TextStyle(color: Colors.orange, fontSize: 10),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildPriceBox(
                  'Farmgate Price',
                  _result!.predictedFarmgatePriceLkrKg,
                  Colors.greenAccent,
                ),
                Container(width: 1, height: 60, color: Colors.white24),
                _buildPriceBox(
                  'Retail Price',
                  _result!.predictedRetailPriceLkrKg,
                  Colors.lightGreenAccent,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildResultStat('Crop', _result!.crop),
                  _buildResultStat(
                    'Confidence',
                    _result!.confidence.toUpperCase(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceBox(String label, double price, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          'Rs. ${price.toStringAsFixed(0)}',
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Text(
          '/kg',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildResultStat(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(
    String label,
    String value,
    List<String> items,
    IconData icon,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items:
          items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
    String unit,
    Color color,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  value.toStringAsFixed(max <= 3 ? 2 : 0),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.2),
              inactiveTrackColor: color.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
