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
  // ── Crop & Location — null = not yet selected ──────────────────────────────
  String? _selectedCrop;
  String? _selectedDistrict;
  String? _selectedSeason;
  String? _selectedIrrigation;
  String? _selectedSeedVariety;
  String _selectedPrevCrop = 'Green gram';

  // ── Farm setup ─────────────────────────────────────────────────────────────
  double _cultivatedAreaHa = 1.0;

  // ── Weather ────────────────────────────────────────────────────────────────
  double _rainfall    = 45.0;
  double _tempMin     = 12.0;
  double _tempMax     = 22.0;
  double _humidity    = 78.0;
  double _windSpeed   = 12.0;
  double _solarRad    = 16.0;

  // ── State ──────────────────────────────────────────────────────────────────
  bool _isLoading = false;
  Map<String, dynamic>? _result;
  String? _errorMessage;

  // ── Crop → valid districts ─────────────────────────────────────────────────
  static const Map<String, List<String>> _cropDistricts = {
    'Carrot':        ['Nuwara Eliya', 'Badulla', 'Jaffna'],
    'Maize':         ['Anuradhapura', 'Monaragala', 'Ampara'],
    'Green gram':    ['Hambantota', 'Monaragala', 'Jaffna'],
    'Cowpea':        ['Anuradhapura', 'Monaragala', 'Ampara'],
    'Finger millet': ['Anuradhapura', 'Monaragala', 'Ampara'],
    'Groundnut':     ['Monaragala', 'Ampara', 'Batticaloa', 'Jaffna'],
  };

  // ── DOA recommended seed varieties per crop ────────────────────────────────
  static const Map<String, List<String>> _seedVarieties = {
    'Carrot':        ['HORDI Carrot 1', 'Kuroda', 'Nantes'],
    'Maize':         ['HORDI Maize 1', 'Ruwan', 'Sampath', 'Pioneer 30Y87'],
    'Green gram':    ['MI 5', 'MI 6', 'Ari', 'Kandy 1', 'Arka Vilas'],
    'Cowpea':        ['Bushitao', 'IT 82D-889', 'Polon 1', 'Waruni'],
    'Finger millet': ['Ravi', 'Rawana', 'Oshadha', 'HORDI Kurakkan 1'],
    'Groundnut':     ['Walawa', 'Tissa', 'Indi', 'Ukulama'],
  };

  static const List<String> _prevCrops = [
    'Green gram', 'Cowpea', 'Maize', 'Carrot',
    'Finger millet', 'Groundnut', 'Fallow', 'Paddy',
  ];

  // ── Seasons with Sri Lanka month descriptions ──────────────────────────────
  static const List<Map<String, String>> _seasons = [
    {
      'name': 'Maha',
      'months': 'October – March',
      'desc': 'The major cultivation season driven by the north-east monsoon. '
          'Rainfall is reliable across most districts, making it the most '
          'productive season for Carrot, Finger millet and Green gram. '
          'Planting begins around October when rains arrive and harvest '
          'completes by March.',
    },
    {
      'name': 'Yala',
      'months': 'April – September',
      'desc': 'The secondary cultivation season supported by the south-west '
          'monsoon. Rainfall is lower and less reliable than Maha so '
          'irrigation is often necessary. Best suited for drought-tolerant '
          'crops such as Groundnut, Cowpea and Maize in dry-zone districts '
          'like Monaragala and Ampara.',
    },
    {
      'name': 'Inter',
      'months': 'March – April & Sep – October',
      'desc': 'Short inter-monsoon periods between the two main seasons. '
          'Characterised by unpredictable showers and high humidity. '
          'Fast-maturing crops like Green gram and Cowpea can complete a '
          'cycle during this window in suitable districts.',
    },
  ];

  // ── Irrigation types — flood removed ──────────────────────────────────────
  static const List<Map<String, String>> _irrigationTypes = [
    {
      'value': 'drip',
      'label': 'Drip Irrigation',
      'desc': 'Water delivered directly to roots — highest water efficiency. '
          'Ideal for Carrot and Groundnut in water-scarce areas.',
    },
    {
      'value': 'sprinkler',
      'label': 'Sprinkler Irrigation',
      'desc': 'Water sprayed evenly over the crop. Good for upland vegetables '
          'and crops needing uniform moisture distribution.',
    },
    {
      'value': 'rainfed',
      'label': 'Rainfed (No Irrigation)',
      'desc': 'Relies entirely on natural rainfall. Suitable for Maha season '
          'in districts with reliable north-east monsoon precipitation.',
    },
  ];

  // ── Soil & management recommendations per crop (DOA guidelines) ────────────
  static const Map<String, Map<String, dynamic>> _soilRecs = {
    'Carrot': {
      'soilPh': 6.2, 'soilMoisture': 60.0,
      'fertilizerIndex': 0.80, 'pesticideIndex': 0.60,
      'nIndex': 0.55, 'pIndex': 0.70, 'kIndex': 0.65,
      'summary': 'Carrot is sensitive to soil conditions. Loose, well-drained '
          'sandy loam with good phosphorus and moderate nitrogen gives the '
          'best straight roots and high yield.',
      'phNote': 'Slightly acidic soil (pH 5.8–6.5) is ideal for good root development.',
      'moistureNote': 'Keep at 55–65% — too wet causes root rot, too dry causes cracking.',
      'fertNote': 'Moderate fertiliser. Excess nitrogen causes forked, hairy roots.',
      'npkNote': 'Higher phosphorus (P) is critical for root elongation. Avoid excess nitrogen (N).',
    },
    'Maize': {
      'soilPh': 6.5, 'soilMoisture': 65.0,
      'fertilizerIndex': 0.85, 'pesticideIndex': 0.55,
      'nIndex': 0.80, 'pIndex': 0.60, 'kIndex': 0.70,
      'summary': 'Maize is a high-input crop that responds strongly to '
          'nitrogen fertiliser. Well-drained fertile loam with high N and '
          'good potassium gives the best grain yields.',
      'phNote': 'Near-neutral soil (pH 6.0–7.0) maximises nutrient uptake.',
      'moistureNote': 'Consistent moisture is critical during tasselling and grain fill.',
      'fertNote': 'Heavy nitrogen feeder — split application at planting and 30 days after.',
      'npkNote': 'Nitrogen (N) is most critical. Potassium (K) supports stalk strength.',
    },
    'Green gram': {
      'soilPh': 6.8, 'soilMoisture': 50.0,
      'fertilizerIndex': 0.40, 'pesticideIndex': 0.45,
      'nIndex': 0.25, 'pIndex': 0.55, 'kIndex': 0.50,
      'summary': 'Green gram is a low-input legume that improves soil health '
          'through nitrogen fixation. Minimal fertiliser, well-drained soil '
          'and moderate moisture give reliable yields.',
      'phNote': 'Near-neutral pH (6.0–7.5) maximises nitrogen fixation by root bacteria.',
      'moistureNote': 'Drought tolerant — excess moisture causes waterlogging and pod shedding.',
      'fertNote': 'Low fertiliser needed. Green gram fixes its own nitrogen — starter dose only.',
      'npkNote': 'Very low N needed — root bacteria fix atmospheric nitrogen. Focus P for pod set.',
    },
    'Cowpea': {
      'soilPh': 6.5, 'soilMoisture': 50.0,
      'fertilizerIndex': 0.35, 'pesticideIndex': 0.40,
      'nIndex': 0.20, 'pIndex': 0.50, 'kIndex': 0.45,
      'summary': 'Cowpea is one of the most drought-tolerant crops in Sri Lanka. '
          'It needs very little fertiliser and thrives in sandy or loamy soils '
          'with good drainage.',
      'phNote': 'Tolerates pH 5.5–7.0. Performs well across a range of soil types.',
      'moistureNote': 'Very drought tolerant once established — avoid waterlogging at all stages.',
      'fertNote': 'Minimal fertiliser required. Cowpea fixes its own nitrogen like green gram.',
      'npkNote': 'Low nitrogen — relies on biological N fixation. P supports root nodule development.',
    },
    'Finger millet': {
      'soilPh': 6.0, 'soilMoisture': 55.0,
      'fertilizerIndex': 0.60, 'pesticideIndex': 0.40,
      'nIndex': 0.60, 'pIndex': 0.45, 'kIndex': 0.55,
      'summary': 'Finger millet (Kurakkan) is a hardy crop well-adapted to dry '
          'zones. Moderate fertiliser on well-drained red loam or sandy soil '
          'gives good yields with minimal inputs.',
      'phNote': 'Tolerates slightly acidic soils (pH 5.0–7.0) — grows well in red laterite.',
      'moistureNote': 'Moderate moisture needed. Drought tolerant but sensitive to waterlogging.',
      'fertNote': 'Moderate nitrogen promotes good tillering and grain fill.',
      'npkNote': 'Balanced NPK needed. Nitrogen drives tiller count; potassium improves grain quality.',
    },
    'Groundnut': {
      'soilPh': 6.2, 'soilMoisture': 55.0,
      'fertilizerIndex': 0.45, 'pesticideIndex': 0.50,
      'nIndex': 0.25, 'pIndex': 0.65, 'kIndex': 0.60,
      'summary': 'Groundnut needs loose, well-drained sandy loam so pods can '
          'penetrate the soil easily. Low nitrogen, good phosphorus and '
          'calcium-rich soil give the best yield and oil quality.',
      'phNote': 'Prefers pH 5.9–7.0. Calcium availability at this pH prevents pod disorders.',
      'moistureNote': 'Good moisture during pod development is critical. Sandy loam allows peg penetration.',
      'fertNote': 'Low fertiliser — fixes own nitrogen. Calcium and phosphorus are more important.',
      'npkNote': 'Very low N needed. High P supports pod fill; K improves oil content.',
    },
  };

  // ── Average yields per crop for result comparison (kg/ha) ─────────────────
  static const Map<String, double> _avgYields = {
    'Carrot': 20000, 'Maize': 3500, 'Green gram': 900,
    'Cowpea': 1200,  'Finger millet': 1800, 'Groundnut': 2000,
  };

  // ── Derived getters ────────────────────────────────────────────────────────
  List<String> get _availableDistricts =>
      _selectedCrop != null ? (_cropDistricts[_selectedCrop!] ?? []) : [];

  List<String> get _availableSeedVarieties =>
      _selectedCrop != null ? (_seedVarieties[_selectedCrop!] ?? []) : [];

  Map<String, dynamic>? get _activeSoilRec =>
      _selectedCrop != null ? _soilRecs[_selectedCrop!] : null;

  bool get _canPredict =>
      _selectedCrop != null &&
      _selectedDistrict != null &&
      _selectedSeason != null &&
      _selectedIrrigation != null;

  static int _weekOfYear() {
    final now = DateTime.now();
    final soy = DateTime(now.year, 1, 1);
    return (((now.difference(soy).inDays + soy.weekday - 1) / 7).ceil())
        .clamp(1, 52);
  }

  String _interpretation(double yieldVal) {
    final avg = _avgYields[_selectedCrop!] ?? 2000;
    final pct = ((yieldVal - avg) / avg * 100).round();
    if (pct >= 15)  return '🟢 ${pct}% above average for $_selectedCrop — excellent conditions';
    if (pct >= 0)   return '🟡 ${pct}% above average — good conditions';
    if (pct >= -15) return '🟠 ${pct.abs()}% below average — consider improving inputs';
    return '🔴 ${pct.abs()}% below average — review soil and weather inputs';
  }

  Color _confColor(String c) {
    switch (c.toLowerCase()) {
      case 'high':   return AppTheme.success;
      case 'medium': return AppTheme.warning;
      default:       return AppTheme.error;
    }
  }

  // ── Predict ────────────────────────────────────────────────────────────────
  Future<void> _predict() async {
    if (!_canPredict) return;
    final rec = _activeSoilRec!;
    setState(() { _isLoading = true; _errorMessage = null; _result = null; });
    try {
      final resp = await ServiceFactory.getService().predictYield(
        YieldRequest(
          crop: _selectedCrop!,
          district: _selectedDistrict!,
          season: _selectedSeason!,
          weekOfYear: _weekOfYear(),
          rainfallMm: _rainfall,
          tempMinC: _tempMin,
          tempMaxC: _tempMax,
          humidityPct: _humidity,
          windSpeedKmh: _windSpeed,
          solarRadiationMj: _solarRad,
          soilPh: (rec['soilPh'] as num).toDouble(),
          soilMoisturePct: (rec['soilMoisture'] as num).toDouble(),
          cultivatedAreaHa: _cultivatedAreaHa,
          seedVariety: _selectedSeedVariety ?? _availableSeedVarieties.first,
          fertilizerIndex: (rec['fertilizerIndex'] as num).toDouble(),
          pesticideIndex: (rec['pesticideIndex'] as num).toDouble(),
          irrigationType: _selectedIrrigation!,
          nIndex: (rec['nIndex'] as num).toDouble(),
          pIndex: (rec['pIndex'] as num).toDouble(),
          kIndex: (rec['kIndex'] as num).toDouble(),
          prevCrop: _selectedPrevCrop,
          demandIndex: 85.0,
          inflationIndex: 1.2,
          holidayFlag: 0,
          festivalFlag: 0,
        ),
      );
      setState(() => _result = {
        'yield': resp.predictedYieldKgPerHa,
        'confidence': resp.confidence,
        'model': resp.modelUsed,
        'isMock': resp.isMock,
      });
    } catch (e) {
      setState(() => _errorMessage = 'Prediction failed: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const SizedBox(height: 20),
            _sectionTitle('Crop & Location', Icons.eco),
            const SizedBox(height: 10),
            _cropLocationCard(),
            const SizedBox(height: 20),
            _sectionTitle('Farm Setup', Icons.agriculture),
            const SizedBox(height: 10),
            _farmSetupCard(),
            const SizedBox(height: 20),
            _sectionTitle('Weather Conditions', Icons.cloud),
            const SizedBox(height: 10),
            _weatherCard(),
            const SizedBox(height: 20),
            _sectionTitle('Soil & Management', Icons.science),
            const SizedBox(height: 10),
            _soilSection(),
            const SizedBox(height: 16),
            _weekBanner(),
            const SizedBox(height: 16),
            _predictButton(),
            const SizedBox(height: 20),
            if (_errorMessage != null) _errorCard(),
            if (_result != null) _resultCard(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ── Widgets ────────────────────────────────────────────────────────────────

  Widget _header() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppTheme.primaryDark, AppTheme.primary],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(12),
      boxShadow: [BoxShadow(
        color: AppTheme.primaryDark.withValues(alpha: 0.3),
        blurRadius: 8, offset: const Offset(0, 3),
      )],
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.grass, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Yield Predictor',
                style: TextStyle(color: Colors.white, fontSize: 20,
                    fontWeight: FontWeight.bold)),
            Text(
              AppConfig.useMockServices ? 'Mock Mode' : 'Random Forest · R²=0.975',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75), fontSize: 12),
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text('Week ${_weekOfYear()}',
              style: const TextStyle(color: Colors.white, fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );

  Widget _sectionTitle(String title, IconData icon) => Row(
    children: [
      Icon(icon, size: 16, color: AppTheme.primaryDark),
      const SizedBox(width: 6),
      Text(title, style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w700,
          color: AppTheme.primaryDark)),
    ],
  );

  // ── Crop & Location ────────────────────────────────────────────────────────
  Widget _cropLocationCard() => _card(
    child: Column(children: [
      // Crop
      _nullDropdown(
        label: 'Select Crop', value: _selectedCrop,
        items: CropSphereConstants.crops, icon: Icons.eco,
        onChanged: (val) => setState(() {
          _selectedCrop = val;
          _selectedDistrict = null;
          _selectedSeedVariety = null;
          _result = null;
        }),
      ),
      const SizedBox(height: 12),

      // District
      _nullDropdown(
        label: 'Select District', value: _selectedDistrict,
        items: _availableDistricts, icon: Icons.location_on,
        hint: _selectedCrop != null
            ? 'Valid districts for $_selectedCrop'
            : 'Select a crop first',
        enabled: _selectedCrop != null,
        onChanged: (val) => setState(() => _selectedDistrict = val),
      ),
      const SizedBox(height: 12),

      // Season with description
      _seasonDropdown(),
      const SizedBox(height: 12),

      // Seed variety
      _nullDropdown(
        label: 'Seed Variety', value: _selectedSeedVariety,
        items: _availableSeedVarieties, icon: Icons.grain,
        hint: _selectedCrop != null
            ? 'DOA recommended varieties for $_selectedCrop'
            : 'Select a crop first',
        enabled: _selectedCrop != null,
        onChanged: (val) => setState(() => _selectedSeedVariety = val),
      ),
      const SizedBox(height: 12),

      // Previous crop
      _simpleDropdown(
        label: 'Previous Crop (last season)', value: _selectedPrevCrop,
        items: _prevCrops, icon: Icons.history,
        hint: 'Crop rotation affects soil nutrients',
        onChanged: (val) => setState(() => _selectedPrevCrop = val!),
      ),
      const SizedBox(height: 12),

      // Irrigation with description
      _irrigationDropdown(),
    ]),
  );

  Widget _seasonDropdown() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<String>(
        value: _selectedSeason,
        hint: const Text('Select Season',
            style: TextStyle(color: AppTheme.textMuted)),
        decoration: InputDecoration(
          labelText: 'Season',
          prefixIcon: const Icon(Icons.calendar_month,
              color: AppTheme.primary, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        items: _seasons.map((s) => DropdownMenuItem<String>(
          value: s['name'],
          child: Text('${s['name']!}  ·  ${s['months']!}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        )).toList(),
        selectedItemBuilder: (ctx) => _seasons.map((s) =>
            Text('${s['name']!}  ·  ${s['months']!}',
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w500))).toList(),
        onChanged: (val) => setState(() => _selectedSeason = val),
      ),
      if (_selectedSeason != null) ...[
        const SizedBox(height: 8),
        _infoBox(
          _seasons.firstWhere((s) => s['name'] == _selectedSeason)['desc']!,
          color: AppTheme.primary,
          icon: Icons.info_outline,
        ),
      ],
    ]);
  }

  Widget _irrigationDropdown() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<String>(
        value: _selectedIrrigation,
        hint: const Text('Select Irrigation Type',
            style: TextStyle(color: AppTheme.textMuted)),
        decoration: InputDecoration(
          labelText: 'Irrigation Type',
          prefixIcon: const Icon(Icons.water_drop,
              color: AppTheme.primary, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        items: _irrigationTypes.map((t) => DropdownMenuItem<String>(
          value: t['value'],
          child: Text(t['label']!,
              style: const TextStyle(fontSize: 14)),
        )).toList(),
        selectedItemBuilder: (ctx) => _irrigationTypes.map((t) =>
            Text(t['label']!,
                style: const TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w500))).toList(),
        onChanged: (val) => setState(() => _selectedIrrigation = val),
      ),
      if (_selectedIrrigation != null) ...[
        const SizedBox(height: 8),
        _infoBox(
          _irrigationTypes
              .firstWhere((t) => t['value'] == _selectedIrrigation)['desc']!,
          color: Colors.blue,
          icon: Icons.water_drop_outlined,
        ),
      ],
    ]);
  }

  // ── Farm setup ─────────────────────────────────────────────────────────────
  Widget _farmSetupCard() => _card(
    child: _slider(
      label: 'Cultivated Area', value: _cultivatedAreaHa,
      min: 0.1, max: 10.0, unit: 'ha',
      icon: Icons.crop_square, color: AppTheme.primary,
      hint: 'Size of land being cultivated',
      onChanged: (v) => setState(() => _cultivatedAreaHa = v),
    ),
  );

  // ── Weather ────────────────────────────────────────────────────────────────
  Widget _weatherCard() => _card(
    child: Column(children: [
      _slider(label: 'Rainfall', value: _rainfall, min: 0, max: 300,
          unit: 'mm', icon: Icons.water, color: Colors.blue,
          onChanged: (v) => setState(() => _rainfall = v)),
      _slider(label: 'Min Temperature', value: _tempMin, min: 5, max: 35,
          unit: '°C', icon: Icons.thermostat, color: Colors.lightBlue,
          onChanged: (v) => setState(() => _tempMin = v)),
      _slider(label: 'Max Temperature', value: _tempMax, min: 10, max: 45,
          unit: '°C', icon: Icons.thermostat, color: Colors.orange,
          onChanged: (v) => setState(() => _tempMax = v)),
      _slider(label: 'Humidity', value: _humidity, min: 20, max: 100,
          unit: '%', icon: Icons.opacity, color: Colors.teal,
          onChanged: (v) => setState(() => _humidity = v)),
      _slider(label: 'Wind Speed', value: _windSpeed, min: 0, max: 60,
          unit: 'km/h', icon: Icons.air, color: Colors.blueGrey,
          hint: 'Average weekly wind speed',
          onChanged: (v) => setState(() => _windSpeed = v)),
      _slider(label: 'Solar Radiation', value: _solarRad, min: 5, max: 30,
          unit: 'MJ', icon: Icons.wb_sunny, color: Colors.amber,
          hint: 'Weekly solar radiation (MJ/m²)',
          onChanged: (v) => setState(() => _solarRad = v)),
    ]),
  );

  // ── Soil & Management — read-only recommendation panel ────────────────────
  Widget _soilSection() {
    if (_selectedCrop == null) {
      return _card(
        child: Row(children: [
          Icon(Icons.eco_outlined, size: 32,
              color: AppTheme.textMuted.withValues(alpha: 0.4)),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Select a crop first to see soil & management recommendations.',
              style: TextStyle(fontSize: 13, color: AppTheme.textMuted, height: 1.4),
            ),
          ),
        ]),
      );
    }

    final rec = _activeSoilRec!;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0EBE0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header band
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.07),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: const Border(bottom: BorderSide(color: Color(0xFFE0EBE0))),
          ),
          child: Row(children: [
            const Icon(Icons.auto_awesome, size: 16, color: AppTheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Recommended soil conditions for $_selectedCrop',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    color: AppTheme.primary),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('DOA Guidelines',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: AppTheme.success)),
            ),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Summary
            Text(rec['summary'] as String,
                style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary,
                    height: 1.55)),
            const SizedBox(height: 16),

            // Tile row 1 — pH and Moisture
            Row(children: [
              Expanded(child: _soilTile(
                label: 'Soil pH',
                value: (rec['soilPh'] as double).toStringAsFixed(1),
                unit: 'pH', icon: Icons.science, color: Colors.purple,
                note: rec['phNote'] as String,
              )),
              const SizedBox(width: 10),
              Expanded(child: _soilTile(
                label: 'Soil Moisture',
                value: (rec['soilMoisture'] as double).toStringAsFixed(0),
                unit: '%', icon: Icons.water_drop_outlined, color: Colors.cyan,
                note: rec['moistureNote'] as String,
              )),
            ]),
            const SizedBox(height: 10),

            // Tile row 2 — Fertilizer and Pesticide
            Row(children: [
              Expanded(child: _soilTile(
                label: 'Fertilizer',
                value: ((rec['fertilizerIndex'] as double) * 100).toStringAsFixed(0),
                unit: '%', icon: Icons.grass, color: Colors.green,
                note: rec['fertNote'] as String,
              )),
              const SizedBox(width: 10),
              Expanded(child: _soilTile(
                label: 'Pesticide',
                value: ((rec['pesticideIndex'] as double) * 100).toStringAsFixed(0),
                unit: '%', icon: Icons.bug_report, color: Colors.brown,
                note: 'Recommended dose percentage for effective pest management.',
              )),
            ]),
            const SizedBox(height: 16),

            // NPK panel
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F9F4),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCCE3CC)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.biotech, size: 14, color: AppTheme.textSecondary),
                  SizedBox(width: 6),
                  Text('NPK Nutrient Recommendation',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                          color: AppTheme.textSecondary)),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _npkTile('N', rec['nIndex'] as double,
                      Colors.indigo, 'Nitrogen')),
                  const SizedBox(width: 8),
                  Expanded(child: _npkTile('P', rec['pIndex'] as double,
                      Colors.deepOrange, 'Phosphorus')),
                  const SizedBox(width: 8),
                  Expanded(child: _npkTile('K', rec['kIndex'] as double,
                      Colors.amber, 'Potassium')),
                ]),
                const SizedBox(height: 10),
                Text(rec['npkNote'] as String,
                    style: const TextStyle(fontSize: 12,
                        color: AppTheme.textSecondary, height: 1.5)),
              ]),
            ),
            const SizedBox(height: 12),

            // Auto-use notice
            _infoBox(
              'These values are automatically used in the prediction based on '
              'DOA agronomic guidelines for optimal yield from this crop.',
              color: AppTheme.info,
              icon: Icons.check_circle_outline,
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _soilTile({
    required String label, required String value, required String unit,
    required IconData icon, required Color color, required String note,
  }) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: color)),
      ]),
      const SizedBox(height: 6),
      Text('$value $unit', style: TextStyle(fontSize: 20,
          fontWeight: FontWeight.bold, color: color)),
      const SizedBox(height: 6),
      Text(note, style: const TextStyle(fontSize: 10,
          color: AppTheme.textSecondary, height: 1.4)),
    ]),
  );

  Widget _npkTile(String sym, double idx, Color color, String name) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Column(children: [
      Text(sym, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
          color: color)),
      const SizedBox(height: 4),
      Text('${(idx * 100).toStringAsFixed(0)}%',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
      Text(name, style: const TextStyle(fontSize: 9, color: AppTheme.textMuted)),
    ]),
  );

  // ── Week banner ────────────────────────────────────────────────────────────
  Widget _weekBanner() {
    final now = DateTime.now();
    return _infoBox(
      'Week of year auto-detected as Week ${_weekOfYear()} '
      '(${now.day}/${now.month}/${now.year}). '
      'The model uses this for seasonal adjustments.',
      color: AppTheme.info, icon: Icons.info_outline,
    );
  }

  // ── Predict button ─────────────────────────────────────────────────────────
  Widget _predictButton() {
    final ready = _canPredict;
    return SizedBox(
      width: double.infinity, height: 52,
      child: ElevatedButton.icon(
        onPressed: (_isLoading || !ready) ? null : _predict,
        icon: _isLoading
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.analytics),
        label: Text(
          _isLoading
              ? 'Predicting...'
              : ready
                  ? 'Predict Yield'
                  : 'Select Crop, District, Season & Irrigation first',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: ready ? AppTheme.primaryDark : Colors.grey.shade400,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  // ── Result card ────────────────────────────────────────────────────────────
  Widget _resultCard() {
    final yieldVal   = _result!['yield'] as double;
    final confidence = _result!['confidence'] as String;
    final model      = _result!['model'] as String? ?? 'Random Forest';
    final isMock     = _result!['isMock'] as bool? ?? false;
    final avg        = _avgYields[_selectedCrop!] ?? 2000;
    final ratio      = (yieldVal / avg).clamp(0.0, 2.0);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppTheme.primaryDark, AppTheme.primary],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(
            color: AppTheme.primaryDark.withValues(alpha: 0.35),
            blurRadius: 12, offset: const Offset(0, 4),
          )],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Predicted Yield',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            Row(children: [
              if (isMock) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Text('MOCK DATA',
                      style: TextStyle(color: Colors.orange, fontSize: 10)),
                ),
                const SizedBox(width: 8),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(model,
                    style: const TextStyle(color: Colors.white60, fontSize: 10)),
              ),
            ]),
          ]),
          const SizedBox(height: 12),
          Text('${yieldVal.toStringAsFixed(0)} kg/ha',
              style: const TextStyle(color: Colors.white, fontSize: 42,
                  fontWeight: FontWeight.bold, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.circle, size: 9, color: _confColor(confidence)),
            const SizedBox(width: 6),
            Text('${confidence.toUpperCase()} CONFIDENCE',
                style: TextStyle(color: _confColor(confidence),
                    fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ]),
          const SizedBox(height: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('vs. average yield',
                  style: TextStyle(color: Colors.white60, fontSize: 11)),
              Text('Avg: ${avg.toStringAsFixed(0)} kg/ha',
                  style: const TextStyle(color: Colors.white60, fontSize: 11)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio / 2, minHeight: 8,
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(
                  ratio >= 1.0 ? AppTheme.primaryLight : Colors.orangeAccent),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _rStat('Crop', _selectedCrop!),
              _vDiv(),
              _rStat('District', _selectedDistrict!),
              _vDiv(),
              _rStat('Season', _selectedSeason!),
              _vDiv(),
              _rStat('Area', '${_cultivatedAreaHa.toStringAsFixed(1)} ha'),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE0EBE0)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.lightbulb_outline, size: 15, color: AppTheme.accent),
            SizedBox(width: 6),
            Text('What this means',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
          ]),
          const SizedBox(height: 8),
          Text(_interpretation(yieldVal),
              style: const TextStyle(fontSize: 13,
                  color: AppTheme.textPrimary, height: 1.5)),
          const SizedBox(height: 8),
          Text(
            'Total expected harvest: '
            '${(yieldVal * _cultivatedAreaHa).toStringAsFixed(0)} kg '
            'from ${_cultivatedAreaHa.toStringAsFixed(1)} ha',
            style: const TextStyle(fontSize: 13,
                color: AppTheme.textSecondary, height: 1.4),
          ),
        ]),
      ),
    ]);
  }

  Widget _rStat(String l, String v) => Column(children: [
    Text(l, style: const TextStyle(color: Colors.white54, fontSize: 10)),
    const SizedBox(height: 3),
    Text(v, style: const TextStyle(color: Colors.white, fontSize: 12,
        fontWeight: FontWeight.w700)),
  ]);

  Widget _vDiv() => Container(width: 1, height: 28, color: Colors.white24);

  // ── Error ──────────────────────────────────────────────────────────────────
  Widget _errorCard() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.red.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline, color: Colors.red, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(_errorMessage!,
          style: const TextStyle(color: Colors.red, fontSize: 13))),
    ]),
  );

  // ── Reusable primitives ────────────────────────────────────────────────────

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppTheme.surfaceCard,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE0EBE0)),
    ),
    child: child,
  );

  Widget _infoBox(String text, {required Color color, required IconData icon}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text,
              style: TextStyle(fontSize: 12, color: color, height: 1.5))),
        ]),
      );

  Widget _slider({
    required String label, required double value,
    required double min, required double max, required String unit,
    required IconData icon, required Color color,
    required ValueChanged<double> onChanged, String? hint,
  }) {
    final dec = unit == 'pH' || unit == '' || unit == 'ha';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 13,
                  fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
              if (hint != null)
                Text(hint, style: const TextStyle(
                    fontSize: 10, color: AppTheme.textMuted)),
            ],
          )),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('${value.toStringAsFixed(dec ? 2 : 0)}$unit',
                style: TextStyle(fontSize: 12,
                    fontWeight: FontWeight.bold, color: color)),
          ),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color, thumbColor: color,
            overlayColor: color.withValues(alpha: 0.15),
            inactiveTrackColor: color.withValues(alpha: 0.15),
            trackHeight: 3,
          ),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ]),
    );
  }

  Widget _nullDropdown({
    required String label, required String? value,
    required List<String> items, required IconData icon,
    required ValueChanged<String?> onChanged,
    String? hint, bool enabled = true,
  }) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    DropdownButtonFormField<String>(
      value: value,
      hint: Text(label, style: const TextStyle(color: AppTheme.textMuted)),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon,
            color: enabled ? AppTheme.primary : AppTheme.textMuted, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        fillColor: enabled ? null : Colors.grey.withValues(alpha: 0.04),
      ),
      items: enabled
          ? items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList()
          : [],
      onChanged: enabled ? onChanged : null,
    ),
    if (hint != null)
      Padding(
        padding: const EdgeInsets.only(top: 4, left: 4),
        child: Text(hint,
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
      ),
  ]);

  Widget _simpleDropdown({
    required String label, required String value,
    required List<String> items, required IconData icon,
    required ValueChanged<String?> onChanged, String? hint,
  }) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppTheme.primary, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    ),
    if (hint != null)
      Padding(
        padding: const EdgeInsets.only(top: 4, left: 4),
        child: Text(hint,
            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
      ),
  ]);
}