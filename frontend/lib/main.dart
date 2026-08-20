// lib/main.dart
// ─────────────────────────────────────────────────────────────────────────────
//  CropSphere — entry point
//  KEY CHANGES vs original:
//   1. Wraps entire app in AppLangProvider → language persists across every screen
//   2. Removed global AppBar (DashboardScreen owns its own header with CropSphere logo)
//   3. Custom bottom nav bar with SVG icons matching the 6 ML model cards
//   4. Language chosen on LoginScreen is automatically used everywhere
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'firebase_options.dart';
import 'app_lang.dart';
import 'widgets/animated_lang_text.dart';
import 'widgets/app_theme.dart';
import 'widgets/growth_logo.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/yield/yield_screen.dart';
import 'screens/price/price_screen.dart';
import 'screens/weather/weather_screen.dart';
import 'screens/demand/demand_screen.dart';
import 'screens/recommend/recommend_screen.dart';
import 'screens/chat/chat_screen.dart';
import 'screens/admin/admin_shell.dart';
import 'services/admin_service.dart';
import 'services/profile_service.dart';
import 'services/session_service.dart';
import 'models/profile_models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase init, web persistence setup, and the first auth-state read all
  // now happen inside the launch splash (_LaunchScreen), racing the logo/name
  // animation instead of blocking runApp() — see _LaunchScreen for why.
  runApp(const CropSphereApp());
}

/// Scales a size linearly with the viewport's shortest side, clamped to
/// [min, max] — used for the launch/welcome screens' logo and text sizing
/// so they don't stay pinned at mobile-friendly constants on a desktop-web
/// window. Shortest side (not raw width) so a narrow-but-tall window scales
/// the same as a short-but-wide one, rather than one axis dominating.
/// [400, 1000] is the reference range: at or below a small phone's
/// shortest side it's exactly [min]; at or above a modest desktop window
/// it's exactly [max]; linear in between.
double _responsiveSize(
  BuildContext context, {
  required double min,
  required double max,
}) {
  const lower = 400.0, upper = 1000.0;
  final shortestSide = MediaQuery.sizeOf(context).shortestSide;
  final t = ((shortestSide - lower) / (upper - lower)).clamp(0.0, 1.0);
  return min + (max - min) * t;
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

  // True only until the launch splash hands off — see _onLaunchReady. Once
  // false, _user is the source of truth and is kept current by _authSub.
  bool _launching = true;
  User? _user;
  StreamSubscription<User?>? _authSub;

  // True only when the current _user just signed in during THIS running
  // app instance (a real null → user transition, e.g. submitting the
  // login form) — false when _user was already signed in before this
  // instance started and is merely being restored (a page refresh, or the
  // app relaunching with a persisted session). _PostLoginRouter uses this
  // to gate the welcome screen: a restore isn't "a login" and should go
  // straight to the destination once the splash resolves it, not replay
  // the welcome flow.
  bool _isFreshSignIn = false;

  @override
  void dispose() {
    _authSub?.cancel();
    _langNotifier.dispose();
    super.dispose();
  }

  // Called exactly once, when _LaunchScreen's animation and bootstrap have
  // both finished. From here on, an explicit subscription (not a rebuilt
  // StreamBuilder) tracks auth changes, so _buildAuthenticatedFlow only ever
  // reruns on a real sign-in/sign-out/inactivity-logout — same guarantee the
  // old StreamBuilder gave, just without re-showing a "waiting" state for an
  // auth read the splash already resolved.
  void _onLaunchReady(User? initialUser) {
    setState(() {
      _user = initialUser;
      _launching = false;
      // Whatever the splash's bootstrap found (signed in or not) is a
      // restored session, never a fresh sign-in.
      _isFreshSignIn = false;
    });
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (!mounted) return;
      setState(() {
        // A new subscription to authStateChanges() immediately re-emits
        // the current state as its first event — by the time that lands,
        // _user above already equals it, so this correctly reads false
        // for that redundant first event and only flags a genuine
        // null → user transition (an actual sign-in) as fresh.
        _isFreshSignIn = _user == null && user != null;
        _user = user;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppLangProvider(
      notifier: _langNotifier,
      child: MaterialApp(
        title: 'CropSphere',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: _launching
            ? _LaunchScreen(onReady: _onLaunchReady)
            : _buildAuthenticatedFlow(),
      ),
    );
  }

  Widget _buildAuthenticatedFlow() {
    final user = _user;
    if (user == null) {
      // Signed out (including the timer's own inactivity logout) —
      // nothing left to auto-expire until the next sign-in.
      SessionService.stopTimer();
      return const LoginScreen();
    }
    // (Re)start the 15-minute inactivity timer for this session.
    SessionService.startTimer();
    // Keyed on uid: _buildAuthenticatedFlow only reruns on a real auth
    // change (see _onLaunchReady/_authSub above), and a sign-out always
    // interposes LoginScreen before any new sign-in, so this key is a
    // defensive belt-and-braces rather than something that fires in
    // practice — it guarantees a fresh _PostLoginRouter (and so a fresh
    // first-login check + welcome flow) if that ever stops being true.
    return _InactivityWatcher(
      child: _PostLoginRouter(
        key: ValueKey(user.uid),
        user: user,
        freshSignIn: _isFreshSignIn,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _PostLoginRouter — Steps 3-6: decides, once per sign-in, whether this is
//  a first-time or returning user using Firebase Auth's own account-creation
//  metadata (no custom Firestore flag), and routes accordingly.
// ─────────────────────────────────────────────────────────────────────────────
class _PostLoginRouter extends StatefulWidget {
  final User user;
  // False for a restored session (page refresh, app relaunch while still
  // signed in) — the welcome screen only ever shows for an actual sign-in
  // that happened during this running app instance. See _isFreshSignIn in
  // _CropSphereAppState.
  final bool freshSignIn;
  const _PostLoginRouter({
    super.key,
    required this.user,
    required this.freshSignIn,
  });

  @override
  State<_PostLoginRouter> createState() => _PostLoginRouterState();
}

class _PostLoginRouterState extends State<_PostLoginRouter> {
  late final bool _isFirstLogin = _computeIsFirstLogin(widget.user);

  // Only meaningful when !_isFirstLogin — true until the welcome screen's
  // display timer elapses (Step 5: auto-advance, no button).
  bool _showWelcome = true;

  // Populated once _WelcomeScreen's own profile fetch resolves (or stays
  // null if it never does before the display timer elapses) — handed to
  // MainShell below so it can skip re-fetching the same profile on mount.
  UserProfile? _fetchedProfile;

  // Step 3. Both fields are DateTime? built from the same
  // millisecond-precision server timestamp
  // (firebase_auth_platform_interface's UserMetadata constructs both via
  // DateTime.fromMillisecondsSinceEpoch off int fields from one JWT/claims
  // payload), so a direct DateTime== compare is exact — there's no
  // separate-source clock skew to normalize away here.
  //
  // Step 6: either field can be null (e.g. a provider that doesn't report
  // one). That's ambiguous, not "first login" — default to the
  // returning-user path, since an unnecessary brief welcome costs less
  // than wrongly skipping it for a genuine first login.
  static bool _computeIsFirstLogin(User user) {
    final created = user.metadata.creationTime;
    final lastSignIn = user.metadata.lastSignInTime;
    if (created == null || lastSignIn == null) return false;
    return created == lastSignIn;
  }

  void _advanceToDashboard(UserProfile? profile) {
    if (!mounted) return;
    setState(() {
      _fetchedProfile = profile;
      _showWelcome = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // The welcome screen (Step 5) is gated on this being both a returning
    // user AND an actual sign-in performed just now — a restored session
    // (refresh/relaunch) skips straight to the destination, same as a
    // first-time login skips it entirely.
    final showWelcomeFlow = widget.freshSignIn && !_isFirstLogin;

    if (!showWelcomeFlow) {
      // Step 4 (first-time login) lands on the existing Chat screen
      // (index 6), whose existing empty state (unmodified) already covers
      // a brand-new user with no conversations yet. A restored returning-
      // user session lands on Home (index 0) directly, with no welcome.
      return MainShell(initialIndex: _isFirstLogin ? 6 : 0);
    }
    // Step 5 — brief personalized welcome, auto-advances, then crossfades
    // into the dashboard (AnimatedSwitcher's default transition) rather
    // than cutting to it abruptly.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _showWelcome
          ? _WelcomeScreen(
              key: const ValueKey('welcome'),
              user: widget.user,
              onDone: _advanceToDashboard,
            )
          : MainShell(
              key: const ValueKey('dashboard'),
              initialProfile: _fetchedProfile,
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _WelcomeScreen — Step 5. display_name isn't available synchronously here
//  (GET /api/user/profile is a real network call — see profile_service.dart
//  / ProfileService.getProfile()), so this WAITS on the fetch (bounded by
//  _maxProfileWait) rather than racing it against an independent display
//  timer — the earlier version fired its timer on a fixed clock regardless
//  of the fetch, so a fetch slower than that timer silently lost the name
//  every time. Once the fetch settles (or times out — Step 6, e.g. a
//  first-ever login's profile-creation race, or just a slow connection),
//  THEN the screen holds for a short fixed beat (_postResolveDisplay) so
//  the greeting is still readable before auto-advancing.
// ─────────────────────────────────────────────────────────────────────────────
class _WelcomeScreen extends StatefulWidget {
  final User user;
  // Passes the fetched profile along once resolved (null if the fetch
  // failed or timed out) so MainShell can reuse it instead of re-fetching
  // the same profile again right after mounting.
  final ValueChanged<UserProfile?> onDone;
  const _WelcomeScreen({super.key, required this.user, required this.onDone});

  @override
  State<_WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<_WelcomeScreen> {
  // Upper bound on how long to wait for the profile fetch before showing
  // the greeting anyway — caps total wait so a slow/failed fetch can't
  // hang the welcome screen indefinitely.
  static const _maxProfileWait = Duration(milliseconds: 2000);
  // Fixed beat the greeting stays on screen for once resolved (or timed
  // out), before auto-advancing — shorter than before since it no longer
  // has to also cover the fetch itself.
  static const _postResolveDisplay = Duration(milliseconds: 800);

  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      _profile = await ProfileService().getProfile().timeout(_maxProfileWait);
    } catch (e) {
      // Best-effort — Step 6 fallback: greeting below just omits the name.
      // Covers both a genuine fetch failure and the timeout (a
      // TimeoutException is thrown by Future.timeout on expiry).
      debugPrint('WELCOME: profile fetch failed or timed out — $e');
    }
    if (!mounted) return;
    setState(() {}); // show whatever _profile ended up as
    await Future.delayed(_postResolveDisplay);
    if (!mounted) return;
    widget.onDone(_profile);
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile?.name;
    final greeting = (name == null || name.isEmpty)
        ? 'Welcome back!'
        : 'Welcome back, $name!';
    // Scales from the original mobile-friendly constants (64/22) up to a
    // desktop-web-appropriate size (140/36) — see _responsiveSize.
    final logoSize = _responsiveSize(context, min: 64, max: 140);
    final fontSize = _responsiveSize(context, min: 22, max: 36);
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fully-bloomed GrowthLogo (progress: 1.0) instead of the
            // static PNG — visual consistency with the launch animation.
            GrowthLogo(progress: 1.0, size: logoSize),
            const SizedBox(height: 20),
            Text(
              greeting,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _LaunchScreen — branded splash shown while Firebase initializes and the
//  current auth session is resolved. The logo is a staged growth animation
//  (GrowthLogo — seed → stem → leaves → shadow → flower bloom, see
//  widgets/growth_logo.dart) rather than a scaled static image; it always
//  plays in full (no bounce/elastic curves anywhere in it), and the handoff
//  to onReady only fires once BOTH that animation AND the async bootstrap
//  are done, whichever finishes last — a fast bootstrap still waits out the
//  animation, and a slow bootstrap (or a cold Firebase init) never cuts the
//  animation short or holds on a frozen/blank logo waiting on a fixed timer.
// ─────────────────────────────────────────────────────────────────────────────
class _LaunchScreen extends StatefulWidget {
  final ValueChanged<User?> onReady;
  const _LaunchScreen({required this.onReady});

  @override
  State<_LaunchScreen> createState() => _LaunchScreenState();
}

class _LaunchScreenState extends State<_LaunchScreen>
    with SingleTickerProviderStateMixin {
  static const _animDuration = Duration(milliseconds: 1000);
  // Text starts fading in this far into the animation — staggered after the
  // logo, not simultaneous with it.
  static const _textDelay = Duration(milliseconds: 180);

  late final AnimationController _controller;
  late final Animation<double> _textOpacity;

  bool _animDone = false;
  bool _bootDone = false;
  User? _bootUser;
  bool _proceeded = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(vsync: this, duration: _animDuration);
    final textStart = _textDelay.inMilliseconds / _animDuration.inMilliseconds;
    _textOpacity = CurvedAnimation(
      parent: _controller,
      curve: Interval(textStart, 1.0, curve: Curves.easeOut),
    );

    _controller.forward().whenComplete(() {
      _animDone = true;
      _maybeProceed();
    });

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Web auth state defaults to IndexedDB, which is what throws "Database
      // is closing" when the browser restricts or tears down that store —
      // incognito, storage pressure, or a partitioned third-party context.
      // Persistence.LOCAL maps to browserLocalPersistence (localStorage),
      // avoiding IndexedDB entirely while still surviving a closed tab.
      //
      // Guarded: this targets environments where browser storage is
      // unreliable, so it is precisely where it might throw. Sign-in still
      // works without it; only persistence across reloads is lost.
      if (kIsWeb) {
        try {
          await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
        } catch (e) {
          debugPrint('AUTH PERSISTENCE: could not set LOCAL — $e');
        }
      }

      _bootUser = await FirebaseAuth.instance.authStateChanges().first;
    } catch (e) {
      // Bootstrap failing shouldn't strand the user on the splash forever —
      // fall through with no resolved user so they land on the login screen
      // and can retry from there.
      debugPrint('LAUNCH BOOTSTRAP: $e');
    }
    if (!mounted) return;
    _bootDone = true;
    _maybeProceed();
  }

  void _maybeProceed() {
    if (_proceeded || !_animDone || !_bootDone) return;
    _proceeded = true;
    widget.onReady(_bootUser);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Scales from the original mobile-friendly constants (96/28) up to a
    // desktop-web-appropriate size (160/40) — see _responsiveSize.
    final logoSize = _responsiveSize(context, min: 96, max: 160);
    final fontSize = _responsiveSize(context, min: 28, max: 40);
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GrowthLogo(progress: _controller.value, size: logoSize),
                const SizedBox(height: 16),
                Opacity(
                  opacity: _textOpacity.value,
                  child: Text(
                    'CropSphere',
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  _InactivityWatcher — resets SessionService's 15-minute timer on any user
//  interaction anywhere in the authenticated app. Only wraps the post-login
//  subtree; LoginScreen has nothing to time out. Listener is used (not
//  GestureDetector) so this observes taps/scrolls/pointer moves without
//  consuming them — every existing gesture handler underneath still works.
// ─────────────────────────────────────────────────────────────────────────────
class _InactivityWatcher extends StatelessWidget {
  final Widget child;
  const _InactivityWatcher({required this.child});

  void _bump([_]) => SessionService.resetTimer();

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _bump,
      onPointerMove: _bump,
      onPointerSignal: _bump,
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  MainShell — IndexedStack of all screens + custom bottom nav
// ─────────────────────────────────────────────────────────────────────────────
class MainShell extends StatefulWidget {
  // Which bottom-nav tab to land on — e.g. Chat (6) for a first-time user
  // routed straight past the welcome flow (see _PostLoginRouter). Ignored
  // for admins/superadmins, who bypass this nav entirely into AdminShell.
  final int initialIndex;
  // Already-fetched profile (from _WelcomeScreen's own fetch) — when
  // supplied, _MainShellState skips its own initial _loadProfile() call and
  // starts from this instead. Null for the first-time-user path (no welcome
  // screen ran) and for any other direct navigation to MainShell.
  final UserProfile? initialProfile;
  const MainShell({super.key, this.initialIndex = 0, this.initialProfile});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  // Bounds the initial render's wait on checkAdminAccess() — long enough
  // that the common (fast, non-rate-limited) case never shows a flash of
  // the wrong shell, short enough that a slow/rate-limited check (see
  // AdminService._getWithRetryOn429's up-to-3s retry-after delay) can't
  // hang the whole UI. If the check is still unresolved after this, render
  // proceeds with the safe default (non-admin); _checkAdminAccess's own
  // setState still fires whenever it actually resolves and will swap to
  // AdminShell then if it turns out this account is admin — a rare,
  // bounded correction instead of an unbounded block.
  static const _adminCheckMaxWait = Duration(milliseconds: 600);

  late int _selectedIndex = widget.initialIndex;
  bool _isAdmin = false;
  // True once the first checkAdminAccess() resolves OR _adminCheckMaxWait
  // elapses, whichever is first — see _adminCheckMaxWait above.
  bool _adminCheckSettled = false;
  late UserProfile? _profile = widget.initialProfile;

  // The user-facing bottom-nav screens. Admins don't use this layout — they get
  // AdminShell (which hosts these same screens in its "App" sidebar section).
  late final List<Widget> _screens = [
    DashboardScreen(onNavigate: _navigateTo), // 0
    YieldScreen(onNavigate: _navigateTo), // 1
    PriceScreen(onNavigate: _navigateTo), // 2
    WeatherScreen(onNavigate: _navigateTo), // 3
    RecommendScreen(onNavigate: _navigateTo), // 4
    DemandScreen(onNavigate: _navigateTo), // 5
    const ChatScreen(), // 6
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAdminAccess();
    // Falls back to "settled, non-admin" if checkAdminAccess() is still
    // in flight after the bounded wait — see _adminCheckMaxWait.
    Future.delayed(_adminCheckMaxWait, () {
      if (mounted && !_adminCheckSettled) {
        setState(() => _adminCheckSettled = true);
      }
    });
    // Only fetch if the caller didn't already hand us a fresh profile —
    // the resume/Home-tap refreshes below still always re-fetch, unaffected.
    if (widget.initialProfile == null) _loadProfile();
    // Deferred slightly rather than fired in the same tick as the calls
    // above — this landing right on top of _WelcomeScreen's own profile
    // fetch (and, for a first-time login, this screen's own _loadProfile)
    // is what was bursting the admin-access rate limit right at the
    // login handoff, triggering AdminService._getWithRetryOn429's 3s
    // retry-after delay. Preferences aren't needed for the first frame,
    // so they can afford to wait.
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _loadLanguagePreference();
    });
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await ProfileService().getProfile();
      if (mounted) setState(() => _profile = profile);
    } catch (e) {
      debugPrint('Failed to load profile: $e');
    }
  }

  // The saved language preference otherwise only takes effect once the user
  // re-visits Account Settings and saves again in that session — apply it
  // to the shared AppLangNotifier as soon as the app boots.
  Future<void> _loadLanguagePreference() async {
    try {
      final prefs = await ProfileService().getPreferences();
      if (!mounted) return;
      final lang = AppLang.values.firstWhere(
        (l) => l.name == prefs.language,
        orElse: () => AppLang.en,
      );
      AppLangProvider.of(context).setLang(lang);
    } catch (e) {
      debugPrint('Failed to load language preference: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // A role change made by a superadmin elsewhere (e.g. promoting this same
  // account to admin, or admin to superadmin) never reaches an already-open
  // session on its own — checkAdminAccess()/loadProfile() only ran once, in
  // initState(). Re-run both whenever the app comes back to the foreground,
  // and whenever the user taps Home, so a freshly granted (or revoked, or
  // changed-tier) role is picked up without requiring a full app restart.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAdminAccess();
      _loadProfile();
    }
  }

  Future<void> _checkAdminAccess() async {
    final isAdmin = await AdminService().checkAdminAccess();
    if (mounted) {
      setState(() {
        _isAdmin = isAdmin;
        _adminCheckSettled = true;
      });
    }
  }

  void _navigateTo(int index) {
    setState(() => _selectedIndex = index);
    if (index == 0) {
      _checkAdminAccess();
      _loadProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hold the shell only briefly (_adminCheckMaxWait) for checkAdminAccess()
    // to resolve, so an admin usually never sees the user home before being
    // routed to the panel — but this is a bounded wait, not an indefinite
    // block; see _adminCheckMaxWait for what happens if it's still pending.
    if (!_adminCheckSettled) {
      return const Scaffold(
        backgroundColor: Color(0xFFFAFFF5),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF4CAF50)),
        ),
      );
    }

    // Admins/superadmins land directly in the admin panel; the user app lives
    // in the panel's "App" sidebar section.
    if (_isAdmin) {
      return AdminShell(
        // checkAdminAccess() only confirms admin-or-above; the loaded profile
        // decides the tier. Default to 'admin' until the profile arrives.
        role: _profile?.role == 'superadmin' ? 'superadmin' : 'admin',
      );
    }

    // Rebuild nav labels when language changes
    final lang = AppLangProvider.lang(context);
    final safeIndex = _selectedIndex < _screens.length ? _selectedIndex : 0;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFFF5),
      body: IndexedStack(index: safeIndex, children: _screens),
      bottomNavigationBar: _CropBottomNav(
        selectedIndex: safeIndex,
        onTap: _navigateTo,
        lang: lang,
        showAdmin: false,
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
  final bool showAdmin;

  const _CropBottomNav({
    required this.selectedIndex,
    required this.onTap,
    required this.lang,
    this.showAdmin = false,
  });

  static const _labelsEn = [
    'Home',
    'Yield',
    'Price',
    'Weather',
    'Crop',
    'Demand',
    'Chat',
    'Admin',
  ];
  static const _labelsSi = [
    'මුල',
    'අස්වැන්න',
    'මිල',
    'කාලගුණ',
    'භෝග',
    'ඉල්ලුම',
    'AI',
    'පරිපාලක',
  ];
  static const _labelsTa = [
    'முகப்பு',
    'விளைச்சல்',
    'விலை',
    'வானிலை',
    'பயிர்',
    'தேவை',
    'AI',
    'நிர்வாகி',
  ];

  static const _activeBg = [
    Color(0xFFE8F5E9), // Home
    Color(0xFFE8F5E9), // Yield
    Color(0xFFFFF8E1), // Price
    Color(0xFFE3F2FD), // Weather
    Color(0xFFF3E5F5), // Crop
    Color(0xFFE8EAF6), // Demand
    Color(0xFFE0F2F1), // Chat
    Color(0xFFFFEBEE), // Admin
  ];

  static const _activeColor = [
    Color(0xFF1B5E20),
    Color(0xFF2E7D32),
    Color(0xFFE65100),
    Color(0xFF1565C0),
    Color(0xFF6A1B9A),
    Color(0xFF283593),
    Color(0xFF004D40),
    Color(0xFFC62828), // Admin
  ];

  List<String> get _labels => switch (lang) {
    AppLang.si => _labelsSi,
    AppLang.ta => _labelsTa,
    _ => _labelsEn,
  };

  @override
  Widget build(BuildContext context) {
    final labels = _labels;
    final itemCount = showAdmin ? 8 : 7;
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
            children: List.generate(itemCount, (i) {
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
                      AnimatedLangText(
                        labels[i],
                        style: TextStyle(
                          fontSize: 7.5,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.w500,
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
      7 => // Admin — shield with checkmark
        '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
            '<path d="M12 2L20 5V11C20 16 16.5 20.5 12 22C7.5 20.5 4 16 4 11V5L12 2Z" fill="$c" opacity="0.85"/>'
            '<path d="M8.5 12L11 14.5L16 9" stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>'
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
