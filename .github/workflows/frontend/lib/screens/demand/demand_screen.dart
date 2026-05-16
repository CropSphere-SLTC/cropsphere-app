// lib/screens/demand/demand_screen.dart

import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../services/service_factory.dart';
import '../../models/api_models.dart';
import '../../widgets/app_theme.dart';

class DemandScreen extends StatefulWidget {
  const DemandScreen({super.key});
  @override
  State<DemandScreen> createState() => _DemandScreenState();
}

class _DemandScreenState extends State<DemandScreen> {
  String _selectedCrop = 'Carrot';
  String _selectedSeason = 'Maha';
  double _demandLag1 = 78.0;
  double _demandLag2 = 75.0;
  double _demandLag4 = 72.0;
  double _retailPrice = 89.0;
  double _inflationIndex = 1.2;
  int _holidayFlag = 0;
  int _festivalFlag = 0;
  bool _isLoading = false;
  DemandResponse? _result;
  String? _errorMessage;

  final List<String> _crops = [
    'Carrot',
    'Maize',
    'Green gram',
    'Cowpea',
    'Finger millet',
    'Groundnut',
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
      final response = await service.predictDemand(
        DemandRequest(
          crop: _selectedCrop,
          season: _selectedSeason,
          weekOfYear: 10,
          demandLag1: _demandLag1,
          demandLag2: _demandLag2,
          demandLag4: _demandLag4,
          retailPriceLkrKg: _retailPrice,
          inflationIndex: _inflationIndex,
          holidayFlag: _holidayFlag,
          festivalFlag: _festivalFlag,
          consumerPrefIndex: 65.0,
          searchTrendIndex: 55.0,
        ),
      );
      setState(() => _result = response);
    } catch (e) {
      setState(() => _errorMessage = 'Prediction failed: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Color _trendColor(String trend) {
    switch (trend) {
      case 'rising':
        return Colors.green;
      case 'falling':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  IconData _trendIcon(String trend) {
    switch (trend) {
      case 'rising':
        return Icons.trending_up;
      case 'falling':
        return Icons.trending_down;
      default:
        return Icons.trending_flat;
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
            _buildInputCard(),
            const SizedBox(height: 16),
            _buildHistoryCard(),
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
          colors: [const Color(0xFF6A1B9A), const Color(0xFF8E24AA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.bar_chart, color: Colors.white, size: 32),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Demand Forecast',
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

  Widget _buildInputCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedCrop,
              decoration: InputDecoration(
                labelText: 'Crop',
                prefixIcon: Icon(Icons.eco, color: AppTheme.primary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: _crops
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedCrop = v!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedSeason,
              decoration: InputDecoration(
                labelText: 'Season',
                prefixIcon: const Icon(Icons.calendar_month),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: _seasons
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedSeason = v!),
            ),
            const SizedBox(height: 12),
            _buildSlider(
              'Retail Price (LKR/kg)',
              _retailPrice,
              20,
              500,
              Colors.green,
              (v) => setState(() => _retailPrice = v),
            ),
            _buildSlider(
              'Inflation Index',
              _inflationIndex,
              0.5,
              3.0,
              Colors.red,
              (v) => setState(() => _inflationIndex = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recent Demand History',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Demand index values from previous weeks',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _buildSlider(
              'Last Week (lag 1)',
              _demandLag1,
              0,
              200,
              Colors.purple,
              (v) => setState(() => _demandLag1 = v),
            ),
            _buildSlider(
              '2 Weeks Ago (lag 2)',
              _demandLag2,
              0,
              200,
              Colors.deepPurple,
              (v) => setState(() => _demandLag2 = v),
            ),
            _buildSlider(
              '4 Weeks Ago (lag 4)',
              _demandLag4,
              0,
              200,
              Colors.indigo,
              (v) => setState(() => _demandLag4 = v),
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
              'Demand Boosters',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            SwitchListTile(
              title: const Text('Holiday Week'),
              value: _holidayFlag == 1,
              onChanged: (v) => setState(() => _holidayFlag = v ? 1 : 0),
              activeThumbColor: AppTheme.primary,
            ),
            SwitchListTile(
              title: const Text('Festival Week'),
              subtitle: const Text('Avurudu, Vesak, Deepavali, Christmas'),
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
            : const Icon(Icons.analytics),
        label: Text(
          _isLoading ? 'Forecasting...' : 'Forecast Demand',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6A1B9A),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final trend = _result!.trend;
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: const Color(0xFF6A1B9A),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Demand Forecast',
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
            const SizedBox(height: 12),
            Text(
              _result!.predictedDemandIndex.toStringAsFixed(1),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'Demand Index',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _trendColor(trend).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _trendColor(trend)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_trendIcon(trend), color: _trendColor(trend), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    trend.toUpperCase(),
                    style: TextStyle(
                      color: _trendColor(trend),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
