// lib/main.dart
// ─────────────────────────────────────────────────────────────────────────────
//  CropSphere — entry point
//  KEY CHANGES vs original:
//   1. Wraps entire app in AppLangProvider → language persists across every screen
//   2. Removed global AppBar (DashboardScreen owns its own header with CropSphere logo)
//   3. Custom bottom nav bar with SVG icons matching the 6 ML model cards
//   4. Language chosen on LoginScreen is automatically used everywhere
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'firebase_options.dart';
import 'app_lang.dart';
import 'widgets/app_theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/yield/yield_screen.dart';
import 'screens/price/price_screen.dart';
import 'screens/weather/weather_screen.dart';
import 'screens/demand/demand_screen.dart';
import 'screens/recommend/recommend_screen.dart';
import 'screens/chat/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const CropSphereApp());
}

// ─────────────────────────────────────────────────────────────────────────────
//  Root app widget — AppLangNotifier lives at top level so it survives routes
// ─────────────────────────────────────────────────────────────────────────────
class CropSphereApp extends StatefulWidget {
  const CropSphereApp({super.key});

  @override
  State<CropSphereApp> createState() => _CropSphereAppState();
}

class _CropSphereAppState extends State<CropSphereApp> {
  final _langNotifier = AppLangNotifier();

  @override
  void dispose() {
    _langNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppLangProvider(
      notifier: _langNotifier,
      child: MaterialApp(
        title: 'CropSphere',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(color: Color(0xFF4CAF50)),
                ),
              );
            }
            return snapshot.hasData ? const MainShell() : const LoginScreen();
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MainShell — IndexedStack of all screens + custom bottom nav
// ─────────────────────────────────────────────────────────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  late final List<Widget> _screens = [
    DashboardScreen(onNavigate: _navigateTo), // 0
    YieldScreen(onNavigate: _navigateTo), // 1
    const PriceScreen(), // 2
    const WeatherScreen(), // 3
    const RecommendScreen(), // 4
    const DemandScreen(), // 5
    const ChatScreen(), // 6
  ];

  void _navigateTo(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    // Rebuild nav labels when language changes
    final lang = AppLangProvider.lang(context);

    return Scaffold(
      backgroundColor: const Color(0xFFFAFFF5),
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: _CropBottomNav(
        selectedIndex: _selectedIndex,
        onTap: _navigateTo,
        lang: lang,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Custom bottom navigation bar
//  • 7 items (Home + 6 ML models)
//  • SVG icons unique per section — no FontAwesome, no generic Material icons
//  • Active item gets coloured background pill matching each card's colour family
//  • Labels translate when language changes
// ─────────────────────────────────────────────────────────────────────────────
class _CropBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final AppLang lang;

  const _CropBottomNav({
    required this.selectedIndex,
    required this.onTap,
    required this.lang,
  });

  static const _labelsEn = [
    'Home',
    'Yield',
    'Price',
    'Weather',
    'Crop',
    'Demand',
    'Chat',
  ];
  static const _labelsSi = [
    'මුල',
    'අස්වැන්න',
    'මිල',
    'කාලගුණ',
    'භෝග',
    'ඉල්ලුම',
    'AI',
  ];
  static const _labelsTa = [
    'முகப்பு',
    'விளைச்சல்',
    'விலை',
    'வானிலை',
    'பயிர்',
    'தேவை',
    'AI',
  ];

  static const _activeBg = [
    Color(0xFFE8F5E9), // Home
    Color(0xFFE8F5E9), // Yield
    Color(0xFFFFF8E1), // Price
    Color(0xFFE3F2FD), // Weather
    Color(0xFFF3E5F5), // Crop
    Color(0xFFE8EAF6), // Demand
    Color(0xFFE0F2F1), // Chat
  ];

  static const _activeColor = [
    Color(0xFF1B5E20),
    Color(0xFF2E7D32),
    Color(0xFFE65100),
    Color(0xFF1565C0),
    Color(0xFF6A1B9A),
    Color(0xFF283593),
    Color(0xFF004D40),
  ];

  List<String> get _labels => switch (lang) {
        AppLang.si => _labelsSi,
        AppLang.ta => _labelsTa,
        _ => _labelsEn,
      };

  @override
  Widget build(BuildContext context) {
    final labels = _labels;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE4EEE4))),
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(7, (i) {
              final active = selectedIndex == i;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  splashColor: _activeBg[i],
                  highlightColor: Colors.transparent,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        width: 34,
                        height: 30,
                        decoration: BoxDecoration(
                          color: active ? _activeBg[i] : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Center(
                          child: SvgPicture.string(
                            _navSvg(
                              i,
                              active
                                  ? _activeColor[i]
                                  : const Color(0xFFAEAEAE),
                            ),
                            width: 20,
                            height: 20,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        labels[i],
                        style: TextStyle(
                          fontSize: 7.5,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                          color: active
                              ? _activeColor[i]
                              : const Color(0xFFAEAEAE),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  String _navSvg(int i, Color color) {
    final c =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    return switch (i) {
      0 => // Home — house
        '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
            '<path d="M3 9.5L12 3L21 9.5V20C21 20.55 20.55 21 20 21H15V15H9V21H4C3.45 21 3 20.55 3 20V9.5Z" stroke="$c" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" fill="none"/>'
            '</svg>',
      1 => // Yield — rising bars + wheat stalk
        '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
            '<rect x="2" y="14" width="4" height="8" rx="1.5" fill="$c"/>'
            '<rect x="8" y="10" width="4" height="12" rx="1.5" fill="$c"/>'
            '<rect x="14" y="5" width="4" height="17" rx="1.5" fill="$c"/>'
            '<path d="M4 12L10 8L16 4" stroke="$c" stroke-width="1.6" stroke-linecap="round"/>'
            '<circle cx="16" cy="4" r="1.8" fill="$c"/>'
            '<path d="M17 2.5Q19 1 18.5 -0.5" stroke="$c" stroke-width="1" stroke-linecap="round" fill="none"/>'
            '</svg>',
      2 => // Price — coin stack with Rs + up arrow
        '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
            '<ellipse cx="11" cy="18" rx="6" ry="3.5" fill="$c" opacity="0.35"/>'
            '<ellipse cx="11" cy="15.5" rx="6" ry="3.5" fill="$c" opacity="0.6"/>'
            '<ellipse cx="11" cy="13" rx="6" ry="3.5" fill="$c"/>'
            '<path d="M19 8L21 5L23 8" stroke="$c" stroke-width="1.6" stroke-linecap="round" fill="none"/>'
            '<line x1="21" y1="5" x2="21" y2="11" stroke="$c" stroke-width="1.6" stroke-linecap="round"/>'
            '</svg>',
      3 => // Weather — sun + rain cloud
        '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
            '<circle cx="8" cy="8" r="3.5" fill="$c"/>'
            '<line x1="8" y1="2" x2="8" y2="4" stroke="$c" stroke-width="1.5" stroke-linecap="round"/>'
            '<line x1="8" y1="12" x2="8" y2="14" stroke="$c" stroke-width="1.5" stroke-linecap="round"/>'
            '<line x1="2" y1="8" x2="4" y2="8" stroke="$c" stroke-width="1.5" stroke-linecap="round"/>'
            '<line x1="12" y1="8" x2="14" y2="8" stroke="$c" stroke-width="1.5" stroke-linecap="round"/>'
            '<ellipse cx="17" cy="16" rx="6" ry="4" fill="$c" opacity="0.3"/>'
            '<ellipse cx="14.5" cy="17" rx="5" ry="3.5" fill="$c" opacity="0.55"/>'
            '<ellipse cx="17.5" cy="15.5" rx="5.5" ry="4" fill="$c"/>'
            '<line x1="13.5" y1="21" x2="13" y2="23" stroke="$c" stroke-width="1.4" stroke-linecap="round"/>'
            '<line x1="17" y1="21" x2="16.5" y2="23" stroke="$c" stroke-width="1.4" stroke-linecap="round"/>'
            '<line x1="20.5" y1="21" x2="20" y2="23" stroke="$c" stroke-width="1.4" stroke-linecap="round"/>'
            '</svg>',
      4 => // Crop recommendation — plant + checkmark badge
        '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
            '<path d="M12 22C12 16 12 11 12 6" stroke="$c" stroke-width="2" stroke-linecap="round"/>'
            '<path d="M12 15C8 13 4 9 6 4C10 8 11 12 12 15Z" fill="$c" opacity="0.65"/>'
            '<path d="M12 11C16 9 20 5 18 0C14 5 12 9 12 11Z" fill="$c"/>'
            '<circle cx="18" cy="5" r="4.5" fill="$c"/>'
            '<path d="M16 5L17.5 7L20 3.5" stroke="white" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>'
            '</svg>',
      5 => // Demand — market basket + arrow
        '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
            '<rect x="2" y="13" width="20" height="9" rx="2" fill="$c" opacity="0.35"/>'
            '<path d="M2 13Q12 7 22 13Z" fill="$c"/>'
            '<circle cx="7.5" cy="17" r="2" fill="$c" opacity="0.7"/>'
            '<circle cx="12" cy="16.5" r="2.3" fill="$c" opacity="0.55"/>'
            '<circle cx="16.5" cy="17.5" r="1.8" fill="$c" opacity="0.7"/>'
            '<path d="M10 7L12 3L14 7" stroke="$c" stroke-width="1.6" stroke-linecap="round" fill="none"/>'
            '<line x1="12" y1="3" x2="12" y2="9" stroke="$c" stroke-width="1.6" stroke-linecap="round"/>'
            '</svg>',
      _ => // AI Chat — speech bubble + star badge
        '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
            '<rect x="1" y="2" width="16" height="12" rx="4" fill="$c" opacity="0.85"/>'
            '<path d="M4 14L3 19L9 14Z" fill="$c" opacity="0.85"/>'
            '<circle cx="5.5" cy="8" r="1.4" fill="white"/>'
            '<circle cx="9" cy="8" r="1.4" fill="white"/>'
            '<circle cx="12.5" cy="8" r="1.4" fill="white"/>'
            '<circle cx="19" cy="5.5" r="4.5" fill="$c"/>'
            '<path d="M17 5.5L18.5 7L21 4" stroke="white" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>'
            '</svg>',
    };
  }
}
