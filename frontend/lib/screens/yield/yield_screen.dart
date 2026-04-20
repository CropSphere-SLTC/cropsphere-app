// lib/screens/yield/yield_screen.dart

import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../services/service_factory.dart';
import '../../models/api_models.dart';
import '../../widgets/app_theme.dart';

class YieldScreen extends StatefulWidget {
  const YieldScreen({super.key});

  @override
  State<YieldScreen> createState() => _YieldScreenState();
}

class _YieldScreenState extends State<YieldScreen> {
  // Form state
  String _selectedCrop = 'Carrot';
  String _selectedDistrict = 'Nuwara Eliya';
  String _selectedSeason = 'Maha';
  String _selectedIrrigation = 'drip';

  double _rainfall = 45.0;
  double _tempMin = 12.0;
  double _tempMax = 22.0;
  double _humidity = 78.0;
  double _soilPh = 6.2;
  double _soilMoisture = 55.0;
  double _fertilizerIndex = 0.75;
  double _nIndex = 0.6;
  double _pIndex = 0.5;
  double _kIndex = 0.7;

  bool _isLoading = false;
  Map<String, dynamic>? _result;
  String? _errorMessage;

  final List<String> _crops = [
    'Carrot', 'Maize', 'Green gram', 'Cowpea', 'Finger millet', 'Groundnut'
  ];

  final Map<String, List<String>> _cropDistricts = {
    'Carrot': ['Nuwara Eliya', 'Badulla', 'Jaffna'],
    'Maize': ['Anuradhapura', 'Monaragala', 'Ampara'],
    'Green gram': ['Hambantota', 'Monaragala', 'Jaffna'],
    'Cowpea': ['Anuradhapura', 'Monaragala', 'Ampara'],
    'Finger millet': ['Anuradhapura', 'Monaragala', 'Ampara'],
    'Groundnut': ['Monaragala', 'Ampara', 'Batticaloa', 'Jaffna'],
  };

  final List<String> _seasons = ['Maha', 'Yala', 'Inter'];
  final List<String> _irrigationTypes = ['drip', 'sprinkler', 'flood', 'rainfed'];

  List<String> get _availableDistricts =>
      _cropDistricts[_selectedCrop] ?? ['Nuwara Eliya'];

  Future<void> _predict() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
    });

    try {
      final service = ServiceFactory.getService();
      final request = YieldRequest(
        crop: _selectedCrop,
        district: _selectedDistrict,
        season: _selectedSeason,
        weekOfYear: 10,
        rainfallMm: _rainfall,
        tempMinC: _tempMin,
        tempMaxC: _tempMax,
        humidityPct: _humidity,
        windSpeedKmh: 12.0,
        solarRadiationMj: 16.0,
        soilPh: _soilPh,
        soilMoisturePct: _soilMoisture,
        cultivatedAreaHa: 1.0,
        seedVariety: 'HORDI ${_selectedCrop} 1',
        fertilizerIndex: _fertilizerIndex,
        pesticideIndex: 0.6,
        irrigationType: _selectedIrrigation,
        nIndex: _nIndex,
        pIndex: _pIndex,
        kIndex: _kIndex,
        prevCrop: 'Green gram',
        demandIndex: 85.0,
        inflationIndex: 1.2,
        holidayFlag: 0,
        festivalFlag: 0,
      );

      final response = await service.predictYield(request);
      setState(() => _result = {
        'yield': response.predictedYieldKgPerHa,
        'confidence': response.confidence,
        'model': response.modelUsed,
        'isMock': response.isMock,
      });
    } catch (e) {
      setState(() => _errorMessage = 'Prediction failed: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Color _confidenceColor(String confidence) {
    switch (confidence.toLowerCase()) {
      case 'high': return Colors.green;
      case 'medium': return Colors.orange;
      default: return Colors.red;
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
            // Header
            _buildHeader(),
            const SizedBox(height: 20),

            // Crop & Location
            _buildSectionTitle('Crop & Location'),
            const SizedBox(height: 12),
            _buildCropLocationCard(),
            const SizedBox(height: 20),

            // Weather Conditions
            _buildSectionTitle('Weather Conditions'),
            const SizedBox(height: 12),
            _buildWeatherCard(),
            const SizedBox(height: 20),

            // Soil & Management
            _buildSectionTitle('Soil & Management'),
            const SizedBox(height: 12),
            _buildSoilCard(),
            const SizedBox(height: 24),

            // Predict Button
            _buildPredictButton(),
            const SizedBox(height: 20),

            // Result
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
          colors: [AppTheme.primaryDark, AppTheme.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.grass, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Yield Predictor',
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppTheme.primaryDark,
      ),
    );
  }

  Widget _buildCropLocationCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Crop dropdown
            _buildDropdown(
              label: 'Crop',
              value: _selectedCrop,
              items: _crops,
              icon: Icons.eco,
              onChanged: (val) {
                setState(() {
                  _selectedCrop = val!;
                  _selectedDistrict = _availableDistricts.first;
                });
              },
            ),
            const SizedBox(height: 12),

            // District dropdown
            _buildDropdown(
              label: 'District',
              value: _selectedDistrict,
              items: _availableDistricts,
              icon: Icons.location_on,
              onChanged: (val) => setState(() => _selectedDistrict = val!),
            ),
            const SizedBox(height: 12),

            // Season dropdown
            _buildDropdown(
              label: 'Season',
              value: _selectedSeason,
              items: _seasons,
              icon: Icons.calendar_month,
              onChanged: (val) => setState(() => _selectedSeason = val!),
            ),
            const SizedBox(height: 12),

            // Irrigation dropdown
            _buildDropdown(
              label: 'Irrigation Type',
              value: _selectedIrrigation,
              items: _irrigationTypes,
              icon: Icons.water_drop,
              onChanged: (val) => setState(() => _selectedIrrigation = val!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSlider(
              label: 'Rainfall',
              value: _rainfall,
              min: 0,
              max: 300,
              unit: 'mm',
              icon: Icons.water,
              color: Colors.blue,
              onChanged: (v) => setState(() => _rainfall = v),
            ),
            _buildSlider(
              label: 'Min Temperature',
              value: _tempMin,
              min: 5,
              max: 35,
              unit: '°C',
              icon: Icons.thermostat,
              color: Colors.lightBlue,
              onChanged: (v) => setState(() => _tempMin = v),
            ),
            _buildSlider(
              label: 'Max Temperature',
              value: _tempMax,
              min: 10,
              max: 45,
              unit: '°C',
              icon: Icons.thermostat,
              color: Colors.orange,
              onChanged: (v) => setState(() => _tempMax = v),
            ),
            _buildSlider(
              label: 'Humidity',
              value: _humidity,
              min: 20,
              max: 100,
              unit: '%',
              icon: Icons.opacity,
              color: Colors.teal,
              onChanged: (v) => setState(() => _humidity = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSoilCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildSlider(
              label: 'Soil pH',
              value: _soilPh,
              min: 3.5,
              max: 9.0,
              unit: 'pH',
              icon: Icons.science,
              color: Colors.purple,
              onChanged: (v) => setState(() => _soilPh = v),
            ),
            _buildSlider(
              label: 'Soil Moisture',
              value: _soilMoisture,
              min: 10,
              max: 100,
              unit: '%',
              icon: Icons.water_drop_outlined,
              color: Colors.cyan,
              onChanged: (v) => setState(() => _soilMoisture = v),
            ),
            _buildSlider(
              label: 'Fertilizer Index',
              value: _fertilizerIndex,
              min: 0,
              max: 1,
              unit: '',
              icon: Icons.grass,
              color: Colors.green,
              onChanged: (v) => setState(() => _fertilizerIndex = v),
            ),
            _buildSlider(
              label: 'Nitrogen (N)',
              value: _nIndex,
              min: 0,
              max: 1,
              unit: '',
              icon: Icons.bubble_chart,
              color: Colors.indigo,
              onChanged: (v) => setState(() => _nIndex = v),
            ),
            _buildSlider(
              label: 'Phosphorus (P)',
              value: _pIndex,
              min: 0,
              max: 1,
              unit: '',
              icon: Icons.bubble_chart,
              color: Colors.deepOrange,
              onChanged: (v) => setState(() => _pIndex = v),
            ),
            _buildSlider(
              label: 'Potassium (K)',
              value: _kIndex,
              min: 0,
              max: 1,
              unit: '',
              icon: Icons.bubble_chart,
              color: Colors.amber,
              onChanged: (v) => setState(() => _kIndex = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String unit,
    required IconData icon,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${value.toStringAsFixed(unit == 'pH' || unit == '' ? 2 : 0)}$unit',
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

  Widget _buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required IconData icon,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
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
            : const Icon(Icons.analytics),
        label: Text(
          _isLoading ? 'Predicting...' : 'Predict Yield',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryDark,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final yield_ = _result!['yield'] as double;
    final confidence = _result!['confidence'] as String;
    final isMock = _result!['isMock'] as bool? ?? false;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: AppTheme.primaryDark,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Predicted Yield',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                if (isMock)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
            const SizedBox(height: 8),
            Text(
              '${yield_.toStringAsFixed(0)} kg/ha',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: _confidenceColor(confidence),
                ),
                const SizedBox(width: 6),
                Text(
                  '${confidence.toUpperCase()} CONFIDENCE',
                  style: TextStyle(
                    color: _confidenceColor(confidence),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
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
                  _buildResultStat('Crop', _selectedCrop),
                  _buildResultStat('District', _selectedDistrict),
                  _buildResultStat('Season', _selectedSeason),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultStat(String label, String value) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
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
