// lib/widgets/localized_names.dart
// ─────────────────────────────────────────────────────────────────────────────
//  The ONE set of trilingual crop / district display names, shared by every
//  screen that shows a crop or district to a farmer.
//
//  WHY THIS EXISTS
//  These maps were const-duplicated across screens: `_districtNames` lived in
//  price_screen, weather_screen AND recommend_screen (three byte-identical
//  copies), and `_cropNames` in price_screen with demand_screen carrying the
//  same six translations again inside its own `_crops` catalogue. Each copy
//  is a place a seventh district or a corrected Tamil spelling can be added
//  to one file and silently missed in the others — the same drift
//  app_top_bar.dart and searchable_dropdown.dart were created to end.
//
//  INTERNAL KEYS STAY ENGLISH. The English name is what goes to the backend
//  (predictions, chat context, validCropDistricts lookups); only the label
//  rendered on screen is translated. So every map here is keyed by the exact
//  string in CropSphereConstants.crops / .districts.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/widgets.dart';

import '../app_lang.dart';

/// A trilingual string: `{'en': ..., 'si': ..., 'ta': ...}`.
///
/// Screens each had a private `typedef _L` for this; they can now import it
/// instead. Named `L` (not `_L`) purely so it is exportable.
typedef L = Map<String, String>;

/// The active language as the `'en'`/`'si'`/`'ta'` key these maps use.
///
/// Every screen had an identical private `_langKey` getter doing this switch.
String langKeyOf(BuildContext context) =>
    switch (AppLangProvider.lang(context)) {
      AppLang.si => 'si',
      AppLang.ta => 'ta',
      AppLang.en => 'en',
    };

/// Resolve a trilingual map for [context]'s language, falling back to English.
String tr(BuildContext context, L m) => m[langKeyOf(context)] ?? m['en']!;

// ─────────────────────────────────────────────────────────────────────────────
//  Crops
// ─────────────────────────────────────────────────────────────────────────────

/// Trilingual crop display names, keyed by CropSphereConstants.crops.
///
/// The two former copies (price_screen's `_cropNames` and demand_screen's
/// `_crops[...].name`) had already drifted apart in TWO cells. price_screen's
/// values win both, because price/yield/recommend all rendered from that copy
/// while demand's was read by one screen:
///
///   • Maize  si — 'බඩඉරිඟු' (price) over 'ඉරිඟු' (demand). The former is the
///     standard DOA term for the grain crop; the bare form is a colloquial
///     short version of the same word.
///   • Cowpea ta — 'காராமணி' (price) over 'அவரை' (demand). These are NOT the
///     same plant: காராமணி is cowpea (Vigna unguiculata), அவரை is hyacinth
///     bean (Lablab purpureus). demand_screen was naming the wrong crop to
///     Tamil-reading farmers.
///
/// So migrating demand onto this map is a visible text change on that screen
/// for Sinhala and Tamil, and a correctness fix for the Tamil one.
const Map<String, L> kCropNames = {
  'Carrot': {'en': 'Carrot', 'si': 'කැරට්', 'ta': 'கேரட்'},
  'Maize': {'en': 'Maize', 'si': 'බඩඉරිඟු', 'ta': 'மக்காச்சோளம்'},
  'Green gram': {'en': 'Green gram', 'si': 'මුං ඇට', 'ta': 'பச்சைப்பயறு'},
  'Cowpea': {'en': 'Cowpea', 'si': 'කව්පි', 'ta': 'காராமணி'},
  'Finger millet': {'en': 'Finger millet', 'si': 'කුරක්කන්', 'ta': 'கேழ்வரகு'},
  'Groundnut': {'en': 'Groundnut', 'si': 'රටකජු', 'ta': 'வேர்க்கடலை'},
};

// ─────────────────────────────────────────────────────────────────────────────
//  Districts
// ─────────────────────────────────────────────────────────────────────────────

/// Trilingual district display names, keyed by CropSphereConstants.districts.
///
/// Official Sinhala/Tamil district names, not word-for-word translations —
/// carried over verbatim from the three identical copies this replaces.
const Map<String, L> kDistrictNames = {
  'Nuwara Eliya': {'en': 'Nuwara Eliya', 'si': 'නුවරඑළිය', 'ta': 'நுவரெலியா'},
  'Badulla': {'en': 'Badulla', 'si': 'බදුල්ල', 'ta': 'பதுளை'},
  'Anuradhapura': {
    'en': 'Anuradhapura',
    'si': 'අනුරාධපුරය',
    'ta': 'அனுராதபுரம்',
  },
  'Monaragala': {'en': 'Monaragala', 'si': 'මොනරාගල', 'ta': 'மொணராகலை'},
  'Ampara': {'en': 'Ampara', 'si': 'අම්පාර', 'ta': 'அம்பாறை'},
  'Hambantota': {'en': 'Hambantota', 'si': 'හම්බන්තොට', 'ta': 'அம்பாந்தோட்டை'},
  'Batticaloa': {'en': 'Batticaloa', 'si': 'මඩකලපුව', 'ta': 'மட்டக்களப்பு'},
  'Jaffna': {'en': 'Jaffna', 'si': 'යාපනය', 'ta': 'யாழ்ப்பாணம்'},
};

// ─────────────────────────────────────────────────────────────────────────────
//  Lookups
// ─────────────────────────────────────────────────────────────────────────────

/// Display name for [crop] in [langKey], falling back to the raw English key
/// when a crop isn't mapped yet (keeps the UI from breaking on a new crop
/// added to the dataset before its translations land).
///
/// Returns `''` for null, matching the former per-screen `_cropLabel`.
String cropLabel(String langKey, String? crop) {
  if (crop == null) return '';
  final m = kCropNames[crop];
  if (m == null) return crop;
  return m[langKey] ?? m['en'] ?? crop;
}

/// District counterpart of [cropLabel]. Same null and fallback behaviour.
String districtLabel(String langKey, String? district) {
  if (district == null) return '';
  final m = kDistrictNames[district];
  if (m == null) return district;
  return m[langKey] ?? m['en'] ?? district;
}
