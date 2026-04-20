// lib/screens/recommend/recommend_screen.dart

import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../services/service_factory.dart';
import '../../models/api_models.dart';
import '../../widgets/app_theme.dart';

class RecommendScreen extends StatefulWidget {
  const RecommendScreen({super.key});
  @override
  State<RecommendScreen> createState() => _RecommendScreenState();
}

class _RecommendScreenState extends State<RecommendScreen> {
  String _selectedDistrict = 'Nuwara Eliya';
  String _selectedSeason = 'Maha';
  String _selectedIrrigation = 'drip';
  double _rainfall = 45.0;
  double _tempMin = 12.0;
  double _tempMax = 22.0;
  double _humidity = 78.0;
  double _soilPh = 6.2;
  double _soilMoisture = 55.0;
  double _nIndex = 0.6;
  double _pIndex = 0.5;
  double _kIndex = 0.7;
  bool _isLoading = false;
  RecommendResponse? _result;
  String? _errorMessage;

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
  final List<String> _irrigationTypes = [
    'drip',
    'sprinkler',
    'flood',
    'rainfed',
  ];

  Future<void> _recommend() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _result = null;
    });
    try {
      final service = ServiceFactory.getService();
      final response = await service.recommendCrop(
        RecommendRequest(
          district: _selectedDistrict,
          season: _selectedSeason,
          weekOfYear: 10,
          rainfallMm: _rainfall,
          tempMinC: _tempMin,
          tempMaxC: _tempMax,
          humidityPct: _humidity,
          soilPh: _soilPh,
          soilMoisturePct: _soilMoisture,
          nIndex: _nIndex,
          pIndex: _pIndex,
          kIndex: _kIndex,
          irrigationType: _selectedIrrigation,
        ),
      );
      setState(() => _result = response);
    } catch (e) {
      setState(() => _errorMessage = 'Recommendation failed: ${e.toString()}');
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
            _buildLocationCard(),
            const SizedBox(height: 16),
            _buildConditionsCard(),
            const SizedBox(height: 16),
            _buildSoilCard(),
            const SizedBox(height: 20),
            _buildRecommendButton(),
            const SizedBox(height: 20),
            if (_errorMessage != null) _buildErrorCard(),
            if (_result != null) _buildResultSection(),
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
          colors: [const Color(0xFF00695C), const Color(0xFF00897B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.recommend, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Crop Recommender',
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

  Widget _buildLocationCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
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
            const SizedBox(height: 12),
            _buildDropdown(
              'Irrigation Type',
              _selectedIrrigation,
              _irrigationTypes,
              Icons.water_drop,
              (v) => setState(() => _selectedIrrigation = v!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Weather Conditions',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildSlider(
              'Rainfall (mm)',
              _rainfall,
              0,
              300,
              Colors.blue,
              (v) => setState(() => _rainfall = v),
            ),
            _buildSlider(
              'Min Temp (°C)',
              _tempMin,
              5,
              35,
              Colors.lightBlue,
              (v) => setState(() => _tempMin = v),
            ),
            _buildSlider(
              'Max Temp (°C)',
              _tempMax,
              10,
              45,
              Colors.orange,
              (v) => setState(() => _tempMax = v),
            ),
            _buildSlider(
              'Humidity (%)',
              _humidity,
              20,
              100,
              Colors.teal,
              (v) => setState(() => _humidity = v),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Soil Conditions',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildSlider(
              'Soil pH',
              _soilPh,
              3.5,
              9.0,
              Colors.purple,
              (v) => setState(() => _soilPh = v),
            ),
            _buildSlider(
              'Soil Moisture (%)',
              _soilMoisture,
              10,
              100,
              Colors.cyan,
              (v) => setState(() => _soilMoisture = v),
            ),
            _buildSlider(
              'Nitrogen (N)',
              _nIndex,
              0,
              1,
              Colors.indigo,
              (v) => setState(() => _nIndex = v),
            ),
            _buildSlider(
              'Phosphorus (P)',
              _pIndex,
              0,
              1,
              Colors.deepOrange,
              (v) => setState(() => _pIndex = v),
            ),
            _buildSlider(
              'Potassium (K)',
              _kIndex,
              0,
              1,
              Colors.amber,
              (v) => setState(() => _kIndex = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _recommend,
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.agriculture),
        label: Text(
          _isLoading ? 'Analysing...' : 'Get Recommendations',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00695C),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildResultSection() {
    if (_result!.recommendations.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No valid crops found for this district and conditions.'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Recommendations',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            if (_result!.isMock)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: const Text(
                  'MOCK',
                  style: TextStyle(color: Colors.orange, fontSize: 10),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ...(_result!.recommendations
            .map((r) => _buildRecommendationCard(r))
            .toList()),
      ],
    );
  }

  Widget _buildRecommendationCard(CropRecommendation rec) {
    final rankColors = [
      const Color(0xFFFFD700),
      const Color(0xFFC0C0C0),
      const Color(0xFFCD7F32),
    ];
    final rankColor = rec.rank <= 3 ? rankColors[rec.rank - 1] : Colors.grey;
    final suitCount = rec.suitabilityFlags.values.where((v) => v).length;
    final totalFlags = rec.suitabilityFlags.length;

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: rankColor.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: rankColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${rec.rank}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rec.crop,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${(rec.confidenceScore * 100).toStringAsFixed(0)}% confidence',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${rec.expectedYieldKgPerHa.toInt()} kg/ha',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Rs. ${rec.expectedPriceLkrKg.toInt()}/kg',
                      style: const TextStyle(color: Colors.green, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: rec.confidenceScore,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(rankColor),
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.check_circle, size: 14, color: Colors.green[600]),
                const SizedBox(width: 4),
                Text(
                  '$suitCount/$totalFlags conditions met',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const Spacer(),
                ...rec.suitabilityFlags.entries.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      e.value ? Icons.check_circle : Icons.cancel,
                      size: 16,
                      color: e.value ? Colors.green : Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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

  Widget _buildSlider(
    String label,
    double value,
    double min,
    double max,
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
                  value.toStringAsFixed(max <= 1 ? 2 : 0),
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
