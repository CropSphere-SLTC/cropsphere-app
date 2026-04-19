// lib/screens/weather/weather_screen.dart

import 'package:flutter/material.dart';
import '../../widgets/app_theme.dart';
import '../../models/api_models.dart';
import '../../services/service_factory.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});
  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  final _service = ServiceFactory();
  String? _district = 'Nuwara Eliya';
  int _weeksAhead = 4;
  bool _isLoading = false;
  WeatherResponse? _result;
  String? _error;

  String get _todayDate {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _forecast() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _result = null;
    });
    try {
      final response = await _service.forecastWeather(
        WeatherRequest(
          district: _district!,
          startDate: _todayDate,
          weeksAhead: _weeksAhead,
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
        title: const Text('Weather Forecast'),
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
                color: AppTheme.info.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.info.withOpacity(0.3)),
              ),
              child: const Text(
                'Model 2 · LSTM (7 districts) + RF (Nuwara Eliya) · temp R²=0.974',
                style: TextStyle(fontSize: 12, color: AppTheme.info),
              ),
            ),
            const SizedBox(height: 16),
            CsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'District',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CsDropdown(
                    label: 'Select district',
                    value: _district,
                    items: CropSphereConstants.districts,
                    onChanged: (v) => setState(() => _district = v),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Weeks ahead',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  Row(
                    children: [1, 2, 3, 4]
                        .map(
                          (w) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('$w wk'),
                              selected: _weeksAhead == w,
                              selectedColor: AppTheme.primary.withOpacity(0.2),
                              onSelected: (_) =>
                                  setState(() => _weeksAhead = w),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _forecast,
              icon: const Icon(Icons.cloud_download),
              label: const Text('Get Forecast'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: AppTheme.error)),
            if (_result != null) ..._buildForecastCards(_result!),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildForecastCards(WeatherResponse result) {
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${result.district} · ${result.forecasts.length}-week forecast',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          if (result.isMock) const CsMockBadge(),
        ],
      ),
      const SizedBox(height: 12),
      ...result.forecasts.map(
        (week) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: CsCard(
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.info.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      'W${week.weekNumber}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.info,
                        fontSize: 13,
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
                        week.date,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _weatherChip(
                            Icons.water_drop,
                            '${week.rainfallMm}mm',
                            Colors.blue,
                          ),
                          const SizedBox(width: 8),
                          _weatherChip(
                            Icons.thermostat,
                            '${week.tempMinC.round()}-${week.tempMaxC.round()}°C',
                            Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          _weatherChip(
                            Icons.air,
                            '${week.humidityPct.round()}%',
                            Colors.teal,
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
    ];
  }

  Widget _weatherChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
