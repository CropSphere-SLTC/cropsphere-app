import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app_lang.dart'; // AppLang, AppLangProvider — shared across app
import '../../widgets/app_theme.dart';

// Local persistence key for "remember last email" — Sign In tab only, never
// the Create New Account tab's email field.
const _lastSignInEmailPrefsKey = 'login_last_signin_email';

// ── Colour tokens ──────────────────────────────────────────────────────────────
const _bgOutside = Color(0xFFDFE6CE);
const _footerPrimary = Color(0xFF4A5E30);
const _logoName = Color(0xFF1B4D1B);
const _taglineMain = Color(0xFF2E4A1E);

// ── Strings model ──────────────────────────────────────────────────────────────
class _L {
  // Top
  final String taglineMain, taglineSub;
  // Tabs
  final String tabSignIn, tabRegister;
  // Sign-in card
  final String siTitle, siSub;
  // Register card
  final String suTitle, suSub;
  // Field labels / placeholders
  final String email, password, fullName, confirmPassword, passHint;
  // Actions
  final String forgotPassword,
      orDivider,
      orDividerReg,
      continueGoogle,
      signInBtn,
      createAccountBtn;
  // Footer
  final String projectTagline, developedBy;
  // Validation
  final String enterEmail,
      invalidEmail,
      enterPassword,
      minPassword,
      enterName,
      nameTooLong,
      passwordMismatch;
  // Password strength
  final String strWeak, strFair, strGood, strStrong, strVStrong;
  // Match
  final String pwMatch, pwNoMatch;
  // Errors
  final String errUserNotFound,
      errWrongPassword,
      errInvalidEmail,
      errUserDisabled,
      errTooMany,
      errSignInFail,
      errEmailInUse,
      errWeakPassword,
      errRegFail,
      errResetFail,
      errEnterEmailFirst,
      errPopupClosed,
      errPopupBlocked,
      errNetwork,
      errUnexpected;
  // Snackbars
  final String snackVerification, snackReset;

  const _L({
    required this.taglineMain,
    required this.taglineSub,
    required this.tabSignIn,
    required this.tabRegister,
    required this.siTitle,
    required this.siSub,
    required this.suTitle,
    required this.suSub,
    required this.email,
    required this.password,
    required this.fullName,
    required this.confirmPassword,
    required this.passHint,
    required this.forgotPassword,
    required this.orDivider,
    required this.orDividerReg,
    required this.continueGoogle,
    required this.signInBtn,
    required this.createAccountBtn,
    required this.projectTagline,
    required this.developedBy,
    required this.enterEmail,
    required this.invalidEmail,
    required this.enterPassword,
    required this.minPassword,
    required this.enterName,
    required this.nameTooLong,
    required this.passwordMismatch,
    required this.strWeak,
    required this.strFair,
    required this.strGood,
    required this.strStrong,
    required this.strVStrong,
    required this.pwMatch,
    required this.pwNoMatch,
    required this.errUserNotFound,
    required this.errWrongPassword,
    required this.errInvalidEmail,
    required this.errUserDisabled,
    required this.errTooMany,
    required this.errSignInFail,
    required this.errEmailInUse,
    required this.errWeakPassword,
    required this.errRegFail,
    required this.errResetFail,
    required this.errEnterEmailFirst,
    required this.errPopupClosed,
    required this.errPopupBlocked,
    required this.errNetwork,
    required this.errUnexpected,
    required this.snackVerification,
    required this.snackReset,
  });
}

// ── English ────────────────────────────────────────────────────────────────────
const _lEn = _L(
  taglineMain: 'Agricultural Intelligence for Sri Lankan Farmers',
  taglineSub: 'AI-powered yield, price, weather & crop recommendations.',
  tabSignIn: 'Sign In',
  tabRegister: 'Create New Account',
  siTitle: 'Welcome back',
  siSub: 'Sign in to access your farm dashboard',
  suTitle: 'Create New Account',
  suSub: 'Join CropSphere — your smart farming assistant',
  email: 'Email address',
  password: 'Password',
  fullName: 'Full name',
  confirmPassword: 'Confirm password',
  passHint: 'Password (min. 6 characters)',
  forgotPassword: 'Forgot password?',
  orDivider: 'or',
  orDividerReg: 'or sign up with',
  continueGoogle: 'Continue with Google',
  signInBtn: 'Sign In',
  createAccountBtn: 'Create Account',
  projectTagline:
      'Empowering Sri Lankan farmers through AI-ML driven harvest intelligence',
  developedBy:
      'Ongoing SLTC Final Year Project 2026 · Supun Seshan · Shifan Abdulla · Keshan Nilhara',
  enterEmail: 'Enter email',
  invalidEmail: 'Invalid email',
  enterPassword: 'Enter password',
  minPassword: 'At least 6 characters',
  enterName: 'Enter your name',
  nameTooLong: 'Name must be 100 characters or fewer',
  passwordMismatch: 'Passwords do not match',
  strWeak: 'Weak',
  strFair: 'Fair',
  strGood: 'Good',
  strStrong: 'Strong',
  strVStrong: 'Very strong',
  pwMatch: 'Passwords match ✓',
  pwNoMatch: 'Passwords do not match',
  errUserNotFound: 'No account found with this email.',
  errWrongPassword: 'Incorrect password. Please try again.',
  errInvalidEmail: 'Please enter a valid email address.',
  errUserDisabled: 'This account has been disabled.',
  errTooMany: 'Too many attempts. Please try again later.',
  errSignInFail: 'Sign in failed. Please try again.',
  errEmailInUse: 'An account already exists with this email.',
  errWeakPassword: 'Password too weak. Use at least 6 characters.',
  errRegFail: 'Registration failed. Please try again.',
  errResetFail: 'Could not send reset email. Check the address and try again.',
  errEnterEmailFirst: 'Enter your email above, then tap "Forgot password".',
  errPopupClosed: 'Sign in cancelled.',
  errPopupBlocked: 'Popup blocked — please allow popups for this site.',
  errNetwork: 'Network error. Check your internet connection.',
  errUnexpected: 'Unexpected error.',
  snackVerification: 'Verification email sent! Please check your inbox.',
  snackReset: 'Password reset email sent to ',
);

// ── Sinhala ────────────────────────────────────────────────────────────────────
const _lSi = _L(
  taglineMain: 'ශ්‍රී ලාංකික ගොවීන් සඳහා කෘෂි බුද්ධිමත්කරණය',
  taglineSub: 'AI මගින් අස්වැන්න, මිල, කාලගුණ සහ භෝග නිර්දේශ.',
  tabSignIn: 'පිවිසෙන්න',
  tabRegister: 'නව ගිණුම සාදන්න',
  siTitle: 'නැවත සාදරයෙන්',
  siSub: 'ඔබේ ගොවිතැන් ඩැෂ්බෝඩ් වෙත ප්‍රවේශ වන්න',
  suTitle: 'නව ගිණුම සාදන්න',
  suSub: 'CropSphere ඔබේ ස්මාර්ට් ගොවිතැන් සහකාරයා',
  email: 'විද්‍යුත් තැපෑල',
  password: 'මුරපදය',
  fullName: 'සම්පූර්ණ නම',
  confirmPassword: 'මුරපදය තහවුරු කරන්න',
  passHint: 'මුරපදය (අවම අකුරු 6)',
  forgotPassword: 'මුරපදය අමතකද?',
  orDivider: 'හෝ',
  orDividerReg: 'හෝ ලියාපදිංචි වන්න',
  continueGoogle: 'Google හරහා ඉදිරියට',
  signInBtn: 'පිවිසෙන්න',
  createAccountBtn: 'ගිණුම සාදන්න',
  projectTagline: 'AI-ML හරහා ශ්‍රී ලාංකික ගොවීන් සවිබල ගැන්වීම',
  developedBy: 'SLTC 2026 · සුපුන් සේෂාන් · ෂිෆාන් අබ්දුල්ලා · කේෂාන් නිල්හාර',
  enterEmail: 'විද්‍යුත් තැපෑල ඇතුළු කරන්න',
  invalidEmail: 'වලංගු නොවන ලිපිනය',
  enterPassword: 'මුරපදය ඇතුළු කරන්න',
  minPassword: 'අවම අකුරු 6ක්',
  enterName: 'නම ඇතුළු කරන්න',
  nameTooLong: 'නම අකුරු 100කට වඩා අඩු විය යුතුය',
  passwordMismatch: 'මුරපද නොගැලපේ',
  strWeak: 'දුර්වල',
  strFair: 'සාධාරණ',
  strGood: 'හොඳ',
  strStrong: 'ශක්තිමත්',
  strVStrong: 'ඉතා ශක්තිමත්',
  pwMatch: 'මුරපද ගැලපේ ✓',
  pwNoMatch: 'මුරපද නොගැලපේ',
  errUserNotFound: 'මෙම විද්‍යුත් තැපෑලෙන් ගිණුමක් හමු නොවීය.',
  errWrongPassword: 'වැරදි මුරපදය. නැවත උත්සාහ කරන්න.',
  errInvalidEmail: 'වලංගු විද්‍යුත් තැපෑලක් ඇතුළු කරන්න.',
  errUserDisabled: 'මෙම ගිණුම අක්‍රිය කර ඇත.',
  errTooMany: 'නැවත නැවත උත්සාහ. පසුව නැවත උත්සාහ කරන්න.',
  errSignInFail: 'පිවිසීම අසාර්ථකයි. නැවත උත්සාහ කරන්න.',
  errEmailInUse: 'මෙම විද්‍යුත් තැපෑලෙන් ගිණුමක් දැනටමත් ඇත.',
  errWeakPassword: 'මුරපදය දුර්වලයි. අවම අකුරු 6ක් භාවිතා කරන්න.',
  errRegFail: 'ලියාපදිංචිය අසාර්ථකයි. නැවත උත්සාහ කරන්න.',
  errResetFail: 'යළි සැකසීමේ විද්‍යුත් තැපෑල යැවීම අසාර්ථකයි.',
  errEnterEmailFirst:
      'ඉහත විද්‍යුත් තැපෑල ඇතුළු කර "මුරපදය අමතකද?" තට්ටු කරන්න.',
  errPopupClosed: 'පිවිසීම අවලංගු කරන ලදී.',
  errPopupBlocked: 'Popup අවහිර කර ඇත.',
  errNetwork: 'ජාල දෝෂය. සම්බන්ධතාව පරීක්ෂා කරන්න.',
  errUnexpected: 'අනපේක්ෂිත දෝෂය.',
  snackVerification: 'සත්‍යාපන විද්‍යුත් තැපෑල යවා ඇත! Inbox පරීක්ෂා කරන්න.',
  snackReset: 'මුරපද යළි සැකසීමේ විද්‍යුත් තැපෑල යවා ඇත: ',
);

// ── Tamil ──────────────────────────────────────────────────────────────────────
const _lTa = _L(
  taglineMain: 'இலங்கை விவசாயிகளுக்கான விவசாய நுண்ணறிவு',
  taglineSub: 'AI மூலம் விளைச்சல், விலை, வானிலை மற்றும் பயிர் பரிந்துரைகள்.',
  tabSignIn: 'உள்நுழைக',
  tabRegister: 'புதிய கணக்கு',
  siTitle: 'மீண்டும் வரவேற்கிறோம்',
  siSub: 'உங்கள் விவசாய டாஷ்போர்டை அணுகவும்',
  suTitle: 'புதிய கணக்கு உருவாக்கவும்',
  suSub: 'CropSphere — உங்கள் புத்திசாலி விவசாய உதவியாளர்',
  email: 'மின்னஞ்சல் முகவரி',
  password: 'கடவுச்சொல்',
  fullName: 'முழு பெயர்',
  confirmPassword: 'கடவுச்சொல்லை உறுதிப்படுத்தவும்',
  passHint: 'கடவுச்சொல் (குறைந்தது 6)',
  forgotPassword: 'கடவுச்சொல் மறந்துவிட்டதா?',
  orDivider: 'அல்லது',
  orDividerReg: 'அல்லது பதிவு செய்க',
  continueGoogle: 'Google மூலம் தொடரவும்',
  signInBtn: 'உள்நுழைக',
  createAccountBtn: 'கணக்கை உருவாக்கவும்',
  projectTagline: 'AI-ML மூலம் இலங்கை விவசாயிகளுக்கு அதிகாரம்',
  developedBy: 'SLTC 2026 · சுபுன் சேஷான் · ஷிஃபான் அப்துல்லா · கேஷான் நிலஹாரா',
  enterEmail: 'மின்னஞ்சலை உள்ளிடவும்',
  invalidEmail: 'தவறான மின்னஞ்சல்',
  enterPassword: 'கடவுச்சொல்லை உள்ளிடவும்',
  minPassword: 'குறைந்தது 6 எழுத்துக்கள்',
  enterName: 'உங்கள் பெயரை உள்ளிடவும்',
  nameTooLong: 'பெயர் 100 எழுத்துக்களுக்கு மிகாமல் இருக்க வேண்டும்',
  passwordMismatch: 'கடவுச்சொற்கள் பொருந்தவில்லை',
  strWeak: 'பலவீனம்',
  strFair: 'சராசரி',
  strGood: 'நல்லது',
  strStrong: 'வலிமை',
  strVStrong: 'மிகவும் வலிமை',
  pwMatch: 'கடவுச்சொற்கள் பொருந்துகின்றன ✓',
  pwNoMatch: 'கடவுச்சொற்கள் பொருந்தவில்லை',
  errUserNotFound: 'இந்த மின்னஞ்சலில் கணக்கு இல்லை.',
  errWrongPassword: 'தவறான கடவுச்சொல். மீண்டும் முயற்சிக்கவும்.',
  errInvalidEmail: 'சரியான மின்னஞ்சல் முகவரியை உள்ளிடவும்.',
  errUserDisabled: 'இந்த கணக்கு முடக்கப்பட்டுள்ளது.',
  errTooMany: 'மிகவும் அதிகமான முயற்சிகள். பிறகு முயற்சிக்கவும்.',
  errSignInFail: 'உள்நுழைவு தோல்வி. மீண்டும் முயற்சிக்கவும்.',
  errEmailInUse: 'இந்த மின்னஞ்சலில் கணக்கு ஏற்கனவே உள்ளது.',
  errWeakPassword: 'கடவுச்சொல் பலவீனமாக உள்ளது. குறைந்தது 6 எழுத்துக்கள்.',
  errRegFail: 'பதிவு தோல்வி. மீண்டும் முயற்சிக்கவும்.',
  errResetFail: 'மீட்டமைப்பு மின்னஞ்சல் அனுப்ப முடியவில்லை.',
  errEnterEmailFirst:
      'மேலே மின்னஞ்சலை உள்ளிட்டு "கடவுச்சொல் மறந்துவிட்டதா?" அழுத்தவும்.',
  errPopupClosed: 'உள்நுழைவு ரத்து செய்யப்பட்டது.',
  errPopupBlocked: 'Popup தடுக்கப்பட்டது.',
  errNetwork: 'நெட்வொர்க் பிழை. இணைப்பை சரிபார்க்கவும்.',
  errUnexpected: 'எதிர்பாராத பிழை.',
  snackVerification:
      'சரிபார்ப்பு மின்னஞ்சல் அனுப்பப்பட்டது! Inbox ஐ பார்க்கவும்.',
  snackReset: 'கடவுச்சொல் மீட்டமைப்பு மின்னஞ்சல் அனுப்பப்பட்டது: ',
);

_L _strings(AppLang lang) {
  switch (lang) {
    case AppLang.si:
      return _lSi;
    case AppLang.ta:
      return _lTa;
    default:
      return _lEn;
  }
}

// ── Password strength helper ───────────────────────────────────────────────────
class _StrengthResult {
  final double fraction;
  final Color color;
  final String label;
  const _StrengthResult(this.fraction, this.color, this.label);
}

_StrengthResult _scorePassword(String pw, _L s) {
  if (pw.isEmpty) return _StrengthResult(0, Colors.transparent, '');
  int score = 0;
  if (pw.length >= 6) score++;
  if (pw.length >= 10) score++;
  if (pw.contains(RegExp(r'[A-Z]'))) score++;
  if (pw.contains(RegExp(r'[0-9]'))) score++;
  if (pw.contains(RegExp(r'[^A-Za-z0-9]'))) score++;
  score = score.clamp(0, 4);
  const colors = [
    Color(0xFFE24B4A),
    Color(0xFFEF9F27),
    Color(0xFFFAC775),
    Color(0xFF97C459),
    Color(0xFF3B6D11),
  ];
  final labels = [s.strWeak, s.strFair, s.strGood, s.strStrong, s.strVStrong];
  return _StrengthResult((score + 1) / 5, colors[score], labels[score]);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  LoginScreen
// ═══════════════════════════════════════════════════════════════════════════════
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  // ── State ──────────────────────────────────────────────────────────────────
  bool _isLoading = false;
  String? _errorMessage;
  int _tabIndex = 0;
  int _prevTab = 0;
  AppLang _lang = AppLang.en;

  // Set at the top of build() from screenW ≥ 1024 — read by the card's own
  // builder methods below so the whole sign-in card (not just the header)
  // scales up a little on desktop/web, without threading an isDesktop
  // parameter through every one of them individually.
  bool _isDesktop = false;

  // Sign-in controllers
  final _siEmailCtrl = TextEditingController();
  final _siPassCtrl = TextEditingController();
  bool _siObscure = true;
  final _signInKey = GlobalKey<FormState>();

  // Register controllers
  final _suNameCtrl = TextEditingController();
  final _suEmailCtrl = TextEditingController();
  final _suPassCtrl = TextEditingController();
  final _suConfirmCtrl = TextEditingController();
  bool _suObscurePass = true;
  bool _suObscureConfirm = true;
  final _signUpKey = GlobalKey<FormState>();

  // Live password state
  _StrengthResult _strength = _StrengthResult(0, Colors.transparent, '');
  String? _matchMsg;
  Color _matchColor = Colors.transparent;

  // Animations
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryAnim;

  late final AnimationController _tabCtrl;
  late final Animation<double> _tabFadeOut, _tabFadeIn;
  late final Animation<double> _tabScaleOut, _tabScaleIn;
  late final Animation<Offset> _tabSlideOut, _tabSlideIn;

  late final AnimationController _langCtrl;
  late final Animation<double> _langFade;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _entryAnim = CurvedAnimation(
      parent: _entryCtrl,
      curve: Curves.easeOutCubic,
    );

    _tabCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _tabFadeOut = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _tabCtrl,
        curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
      ),
    );
    _tabFadeIn = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _tabCtrl,
        curve: const Interval(0.45, 1.0, curve: Curves.easeOut),
      ),
    );
    _tabScaleOut = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(
        parent: _tabCtrl,
        curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
      ),
    );
    _tabScaleIn = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(
        parent: _tabCtrl,
        curve: const Interval(0.45, 1.0, curve: Curves.easeOutBack),
      ),
    );
    _tabSlideOut =
        Tween<Offset>(begin: Offset.zero, end: const Offset(0, -0.025)).animate(
          CurvedAnimation(
            parent: _tabCtrl,
            curve: const Interval(0.0, 0.45, curve: Curves.easeIn),
          ),
        );
    _tabSlideIn = Tween<Offset>(begin: const Offset(0, 0.025), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _tabCtrl,
            curve: const Interval(0.45, 1.0, curve: Curves.easeOutCubic),
          ),
        );

    _langCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _langFade = CurvedAnimation(parent: _langCtrl, curve: Curves.easeInOut);

    _loadLastSignInEmail();
  }

  // ── Remember last email (Sign In tab only) ────────────────────────────────
  Future<void> _loadLastSignInEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_lastSignInEmailPrefsKey);
    if (!mounted || saved == null || saved.isEmpty) return;
    // Only pre-fill if the user hasn't already typed something — avoids
    // clobbering input if this resolves after the user started typing.
    if (_siEmailCtrl.text.isEmpty) {
      setState(() => _siEmailCtrl.text = saved);
    }
  }

  Future<void> _saveLastSignInEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSignInEmailPrefsKey, email);
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _tabCtrl.dispose();
    _langCtrl.dispose();
    _siEmailCtrl.dispose();
    _siPassCtrl.dispose();
    _suNameCtrl.dispose();
    _suEmailCtrl.dispose();
    _suPassCtrl.dispose();
    _suConfirmCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  _L get _s => _strings(_lang);

  void _setError(String? m) {
    if (mounted) setState(() => _errorMessage = m);
  }

  void _setLoading(bool v) {
    if (mounted) setState(() => _isLoading = v);
  }

  void _switchTab(int i) {
    if (i == _tabIndex) return;
    setState(() {
      _prevTab = _tabIndex;
      _tabIndex = i;
      _errorMessage = null;
    });
    _tabCtrl
      ..reset()
      ..forward();
  }

  Future<void> _switchLang(AppLang l) async {
    if (l == _lang) return;
    await _langCtrl.forward();
    if (!mounted) return;
    setState(() {
      _lang = l;
      _updateStrengthLabel();
      _updateMatchLabel();
    });
    // Write to global provider so every screen uses the same language
    AppLangProvider.of(context).setLang(l);
    _langCtrl.reverse();
  }

  void _updateStrengthLabel() {
    _strength = _scorePassword(_suPassCtrl.text, _s);
  }

  void _updateMatchLabel() {
    final p = _suPassCtrl.text;
    final c = _suConfirmCtrl.text;
    if (c.isEmpty) {
      _matchMsg = null;
      return;
    }
    if (p == c) {
      _matchMsg = _s.pwMatch;
      _matchColor = const Color(0xFF97C459);
    } else {
      _matchMsg = _s.pwNoMatch;
      _matchColor = const Color(0xFFE24B4A);
    }
  }

  void _onPasswordChanged(String val) {
    setState(() {
      _strength = _scorePassword(val, _s);
      _updateMatchLabel();
    });
  }

  void _onConfirmChanged(String _) {
    setState(() {
      _updateMatchLabel();
    });
  }

  // ── Auth ───────────────────────────────────────────────────────────────────
  // google_sign_in 7.x: GoogleSignIn is a singleton (.instance) that must be
  // initialize()'d exactly once before any other call — this guard makes
  // repeated sign-in attempts (e.g. cancel then retry) only pay that cost
  // the first time.
  bool _googleSignInInitialized = false;

  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    await GoogleSignIn.instance.initialize();
    _googleSignInInitialized = true;
  }

  Future<void> _signInWithGoogle() async {
    _setLoading(true);
    _setError(null);
    try {
      if (kIsWeb) {
        // Web: popup is fine
        final p = GoogleAuthProvider()
          ..addScope('email')
          ..addScope('profile')
          ..setCustomParameters({'prompt': 'select_account'});
        await FirebaseAuth.instance.signInWithPopup(p);
      } else {
        // Android / iOS: use google_sign_in package + credential.
        // v7 splits "authentication" (identity — the idToken) from
        // "authorization" (access to scopes — the accessToken), where
        // the old 6.x API returned both together off one .authentication
        // call.
        await _ensureGoogleSignInInitialized();
        final signIn = GoogleSignIn.instance;
        if (!signIn.supportsAuthenticate()) {
          _setError(_s.errSignInFail);
          return;
        }

        const scopes = ['email', 'profile'];
        GoogleSignInAccount googleUser;
        try {
          googleUser = await signIn.authenticate(scopeHint: scopes);
        } on GoogleSignInException catch (e) {
          if (e.code == GoogleSignInExceptionCode.canceled) {
            return; // user cancelled — same as the old null-return case
          }
          rethrow;
        }

        final idToken = googleUser.authentication.idToken;
        // 'email'/'profile' are non-sensitive scopes almost always already
        // granted by authenticate() above — authorizationForScopes() checks
        // that silently, so this only falls through to authorizeScopes()
        // (which can show its own prompt) if that comes back empty.
        final authorization =
            await googleUser.authorizationClient.authorizationForScopes(
              scopes,
            ) ??
            await googleUser.authorizationClient.authorizeScopes(scopes);
        final credential = GoogleAuthProvider.credential(
          accessToken: authorization.accessToken,
          idToken: idToken,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
    } on FirebaseAuthException catch (e) {
      debugPrint('GOOGLE SIGNIN ERROR: code=${e.code} message=${e.message}');
      _setError(switch (e.code) {
        'popup-closed-by-user' => _s.errPopupClosed,
        'popup-blocked' => _s.errPopupBlocked,
        'network-request-failed' => _s.errNetwork,
        _ => _s.errSignInFail,
      });
    } on GoogleSignInException catch (e) {
      debugPrint(
        'GOOGLE SIGNIN ERROR: code=${e.code} description=${e.description}',
      );
      _setError(_s.errSignInFail);
    } catch (e) {
      _setError('${_s.errUnexpected} ${e.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _signInWithEmail() async {
    if (!(_signInKey.currentState?.validate() ?? false)) return;
    _setLoading(true);
    _setError(null);
    try {
      final email = _siEmailCtrl.text.trim();
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _siPassCtrl.text,
      );
      await _saveLastSignInEmail(email);
    } on FirebaseAuthException catch (e) {
      _setError(switch (e.code) {
        'user-not-found' => _s.errUserNotFound,
        'wrong-password' => _s.errWrongPassword,
        'invalid-email' => _s.errInvalidEmail,
        'user-disabled' => _s.errUserDisabled,
        'too-many-requests' => _s.errTooMany,
        _ => _s.errSignInFail,
      });
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _registerWithEmail() async {
    if (!(_signUpKey.currentState?.validate() ?? false)) return;
    _setLoading(true);
    _setError(null);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _suEmailCtrl.text.trim(),
        password: _suPassCtrl.text,
      );
      if (_suNameCtrl.text.trim().isNotEmpty) {
        await cred.user?.updateDisplayName(_suNameCtrl.text.trim());
      }
      await cred.user?.sendEmailVerification();
      // Clear register form
      _suNameCtrl.clear();
      _suEmailCtrl.clear();
      _suPassCtrl.clear();
      _suConfirmCtrl.clear();
      if (mounted) {
        setState(() {
          _strength = _StrengthResult(0, Colors.transparent, '');
          _matchMsg = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_s.snackVerification),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      _setError(switch (e.code) {
        'email-already-in-use' => _s.errEmailInUse,
        'invalid-email' => _s.errInvalidEmail,
        'weak-password' => _s.errWeakPassword,
        _ => _s.errRegFail,
      });
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _siEmailCtrl.text.trim();
    if (email.isEmpty) {
      _setError(_s.errEnterEmailFirst);
      return;
    }
    _setLoading(true);
    _setError(null);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_s.snackReset}$email'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } on FirebaseAuthException catch (_) {
      _setError(_s.errResetFail);
    } finally {
      _setLoading(false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;

    // Dynamic max-width: interpolates smoothly between breakpoints.
    //   mobile  (<600)  → full width (no constraint)
    //   tablet  (600–1023) → 400–440 px, centred
    //   web     (≥1024) → 520 px, centred — bumped from 460 so the whole
    //     sign-in card reads a little bigger on desktop/web specifically.
    final double cardMaxW;
    if (screenW < 600) {
      cardMaxW = double.infinity;
    } else if (screenW < 1024) {
      // Linear interpolation: 400 at 600px → 440 at 1023px
      final t = ((screenW - 600) / (1024 - 600)).clamp(0.0, 1.0);
      cardMaxW = 400 + (40 * t);
    } else {
      cardMaxW = 520;
    }

    // Desktop/web (≥1024px) gets a slightly larger logo/wordmark/tagline,
    // and — via _isDesktop — a slightly larger card (inputs, buttons, tab
    // bar, card text) too. Same step as cardMaxW's own mobile/tablet/desktop
    // breakpoints above, rather than a continuous scale, since the design
    // calls out exactly these three discrete tiers.
    final isDesktop = screenW >= 1024;
    _isDesktop = isDesktop;
    final logoSize = isDesktop ? 46.0 : 40.0;
    final wordmarkSize = isDesktop ? 22.0 : 20.0;
    final taglineMainSize = isDesktop ? 18.0 : 16.0;
    final taglineSubSize = isDesktop ? 13.0 : 12.0;

    return Scaffold(
      backgroundColor: _bgOutside,
      body: SafeArea(
        child: FadeTransition(
          opacity: _entryAnim,
          child: AnimatedBuilder(
            animation: _langFade,
            builder: (_, child) => Opacity(
              opacity: (1 - _langFade.value).clamp(0.0, 1.0),
              child: child,
            ),
            child: Stack(
              children: [
                // ── Leaf watermarks ──────────────────────────────────────────
                // Dialed further down from 0.10/0.07 — with the card now
                // light instead of dark-dominant, the page reads airier
                // overall, and these decorative leaves read more
                // prominently against that lighter whole even though the
                // outer page background color itself hasn't changed.
                Positioned(
                  top: 24,
                  right: 12,
                  child: Opacity(
                    opacity: 0.06,
                    child: SvgPicture.string(_leafSvg, width: 100),
                  ),
                ),
                Positioned(
                  bottom: 60,
                  left: 8,
                  child: Opacity(
                    opacity: 0.045,
                    child: SvgPicture.string(_leafSvg, width: 80),
                  ),
                ),

                // ── Main layout ──────────────────────────────────────────────
                Builder(
                  builder: (context) {
                    final isMobile = screenW < 600;
                    final content = Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 20 : 24,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(height: isMobile ? 14 : 20),
                          _buildTagline(
                            mainSize: taglineMainSize,
                            subSize: taglineSubSize,
                          ),
                          const SizedBox(height: 14),
                          _buildLangSelector(),
                          const SizedBox(height: 14),
                          _buildCard(),
                          SizedBox(height: isMobile ? 16 : 20),
                        ],
                      ),
                    );

                    if (isMobile) {
                      // Mobile: footer flows immediately after the card as
                      // part of one [content, footer] unit, and that whole
                      // unit is vertically centred in the space below the
                      // top bar — same mechanism as tablet/desktop, except
                      // the footer is inside the centred block instead of
                      // pinned separately outside it. Pinning the footer
                      // separately (tablet/desktop's approach) put all the
                      // leftover slack above the tagline on a tall phone;
                      // top-anchoring the whole thing (an earlier attempt)
                      // put all of it below the footer instead. Centring the
                      // combined block splits whatever slack remains evenly
                      // between "above the tagline" and "below the footer"
                      // — roughly half the size in either spot compared to
                      // either single-sided version.
                      return Column(
                        children: [
                          _buildTopBar(
                            logoSize: logoSize,
                            wordmarkSize: wordmarkSize,
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: constraints.maxHeight,
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [content, _buildFooter()],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    }

                    // Tablet/desktop: unchanged — top bar and footer pinned,
                    // content vertically centred in the space between them.
                    return Column(
                      children: [
                        _buildTopBar(
                          logoSize: logoSize,
                          wordmarkSize: wordmarkSize,
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: Center(
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        maxWidth: cardMaxW,
                                      ),
                                      child: content,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        _buildFooter(),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar({
    required double logoSize,
    required double wordmarkSize,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          // Swapped the screen's hand-inlined static _cropSvg badge for the
          // real CropSphere brand mark PNG. Uses the _transparent variant
          // (RGBA, alpha=0 corners) rather than cropsphere_logo.png (flat
          // RGB, opaque near-white corners) — this screen's page background
          // isn't white, so the opaque file would show a visible whitish
          // square behind the circle badge.
          Image.asset(
            'assets/images/cropsphere_logo_transparent.png',
            width: logoSize,
            height: logoSize,
          ),
          const SizedBox(width: 10),
          Text(
            'CropSphere',
            style: TextStyle(
              color: _logoName,
              fontSize: wordmarkSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  // ── Tagline ────────────────────────────────────────────────────────────────
  Widget _buildTagline({required double mainSize, required double subSize}) {
    return Column(
      children: [
        Text(
          _s.taglineMain,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _taglineMain,
            fontSize: mainSize,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _s.taglineSub,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.login.outsideMutedText,
            fontSize: subSize,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  // ── Language selector ──────────────────────────────────────────────────────
  Widget _buildLangSelector() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _LangChip(
          label: 'En',
          selected: _lang == AppLang.en,
          onTap: () => _switchLang(AppLang.en),
        ),
        const SizedBox(width: 8),
        _LangChip(
          label: 'සිංහල',
          selected: _lang == AppLang.si,
          onTap: () => _switchLang(AppLang.si),
        ),
        const SizedBox(width: 8),
        _LangChip(
          label: 'தமிழ்',
          selected: _lang == AppLang.ta,
          onTap: () => _switchLang(AppLang.ta),
        ),
      ],
    );
  }

  // ── Auth card ──────────────────────────────────────────────────────────────
  Widget _buildCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.login.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.login.borderSubtle, width: 1),
        boxShadow: [
          BoxShadow(
            color: AppTheme.login.textPrimary.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Tab bar — underline style, grounded by a full-width baseline so
          // the active tab's indicator reads as "part of" a track rather
          // than floating.
          Container(
            padding: EdgeInsets.fromLTRB(
              _isDesktop ? 18 : 15,
              _isDesktop ? 15 : 13,
              _isDesktop ? 18 : 15,
              0,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppTheme.login.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                _TabBtn(
                  label: _s.tabSignIn,
                  selected: _tabIndex == 0,
                  onTap: () => _switchTab(0),
                  isDesktop: _isDesktop,
                ),
                const SizedBox(width: 8),
                _TabBtn(
                  label: _s.tabRegister,
                  selected: _tabIndex == 1,
                  onTap: () => _switchTab(1),
                  isDesktop: _isDesktop,
                ),
              ],
            ),
          ),
          // Animated form
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(20),
            ),
            child: AnimatedBuilder(
              animation: _tabCtrl,
              builder: (context, _) {
                if (!_tabCtrl.isAnimating) return _formContent(_tabIndex);
                return Stack(
                  fit: StackFit.passthrough,
                  children: [
                    FadeTransition(
                      opacity: _tabFadeOut,
                      child: ScaleTransition(
                        scale: _tabScaleOut,
                        child: SlideTransition(
                          position: _tabSlideOut,
                          child: _formContent(_prevTab),
                        ),
                      ),
                    ),
                    FadeTransition(
                      opacity: _tabFadeIn,
                      child: ScaleTransition(
                        scale: _tabScaleIn,
                        child: SlideTransition(
                          position: _tabSlideIn,
                          child: _formContent(_tabIndex),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Form dispatcher ────────────────────────────────────────────────────────
  Widget _formContent(int tab) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _isDesktop ? 22 : 18,
        _isDesktop ? 16 : 14,
        _isDesktop ? 22 : 18,
        _isDesktop ? 20 : 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Form title & subtitle
          Text(
            tab == 0 ? _s.siTitle : _s.suTitle,
            style: TextStyle(
              color: AppTheme.login.textPrimary,
              fontSize: _isDesktop ? 18 : 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            tab == 0 ? _s.siSub : _s.suSub,
            style: TextStyle(
              color: AppTheme.login.textSecondary,
              fontSize: _isDesktop ? 12 : 11,
            ),
          ),
          const SizedBox(height: 13),
          // Error banner
          if (_errorMessage != null && _tabIndex == tab) ...[
            _ErrorBanner(message: _errorMessage!),
            const SizedBox(height: 11),
          ],
          if (tab == 0) _buildSignInForm() else _buildRegisterForm(),
        ],
      ),
    );
  }

  // ── Sign-in form ───────────────────────────────────────────────────────────
  Widget _buildSignInForm() {
    return Form(
      key: _signInKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(
            controller: _siEmailCtrl,
            label: _s.email,
            icon: Icons.email_outlined,
            keyboard: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return _s.enterEmail;
              if (!v.contains('@')) return _s.invalidEmail;
              return null;
            },
          ),
          const SizedBox(height: 9),
          _field(
            controller: _siPassCtrl,
            label: _s.password,
            icon: Icons.lock_outline,
            obscure: _siObscure,
            suffix: _eyeBtn(
              _siObscure,
              () => setState(() => _siObscure = !_siObscure),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _isLoading ? null : _signInWithEmail(),
            validator: (v) =>
                (v == null || v.isEmpty) ? _s.enterPassword : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _ForgotPasswordLink(
              label: _s.forgotPassword,
              onTap: _isLoading ? null : _forgotPassword,
            ),
          ),
          const SizedBox(height: 10),
          _submitBtn(label: _s.signInBtn, onPressed: _signInWithEmail),
          const SizedBox(height: 12),
          _divider(_s.orDivider),
          const SizedBox(height: 12),
          _googleBtn(),
        ],
      ),
    );
  }

  // ── Register form ──────────────────────────────────────────────────────────
  Widget _buildRegisterForm() {
    return Form(
      key: _signUpKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _field(
            controller: _suNameCtrl,
            label: _s.fullName,
            icon: Icons.person_outline,
            maxLength: 100,
            textInputAction: TextInputAction.next,
            validator: (v) {
              final trimmed = v?.trim() ?? '';
              if (trimmed.isEmpty) return _s.enterName;
              if (trimmed.length > 100) return _s.nameTooLong;
              return null;
            },
          ),
          const SizedBox(height: 9),
          _field(
            controller: _suEmailCtrl,
            label: _s.email,
            icon: Icons.email_outlined,
            keyboard: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return _s.enterEmail;
              if (!v.contains('@')) return _s.invalidEmail;
              return null;
            },
          ),
          const SizedBox(height: 9),
          // Password with strength meter
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(
                controller: _suPassCtrl,
                label: _s.passHint,
                icon: Icons.lock_outline,
                obscure: _suObscurePass,
                suffix: _eyeBtn(
                  _suObscurePass,
                  () => setState(() => _suObscurePass = !_suObscurePass),
                ),
                textInputAction: TextInputAction.next,
                onChanged: _onPasswordChanged,
                validator: (v) {
                  if (v == null || v.isEmpty) return _s.enterPassword;
                  if (v.length < 6) return _s.minPassword;
                  return null;
                },
              ),
              if (_suPassCtrl.text.isNotEmpty) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _strength.fraction,
                    minHeight: 4,
                    backgroundColor: AppTheme.login.borderSubtle,
                    valueColor: AlwaysStoppedAnimation<Color>(_strength.color),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _strength.label,
                  style: TextStyle(fontSize: 10, color: _strength.color),
                ),
              ],
            ],
          ),
          const SizedBox(height: 9),
          // Confirm password with match indicator
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(
                controller: _suConfirmCtrl,
                label: _s.confirmPassword,
                icon: Icons.lock_outline,
                obscure: _suObscureConfirm,
                suffix: _eyeBtn(
                  _suObscureConfirm,
                  () => setState(() => _suObscureConfirm = !_suObscureConfirm),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _isLoading ? null : _registerWithEmail(),
                onChanged: _onConfirmChanged,
                validator: (v) =>
                    (v != _suPassCtrl.text) ? _s.passwordMismatch : null,
              ),
              if (_matchMsg != null) ...[
                const SizedBox(height: 4),
                Text(
                  _matchMsg!,
                  style: TextStyle(fontSize: 10, color: _matchColor),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _submitBtn(label: _s.createAccountBtn, onPressed: _registerWithEmail),
          const SizedBox(height: 12),
          _divider(_s.orDividerReg),
          const SizedBox(height: 12),
          _googleBtn(),
        ],
      ),
    );
  }

  // ── Shared widget builders ─────────────────────────────────────────────────
  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboard,
    bool obscure = false,
    Widget? suffix,
    void Function(String)? onChanged,
    String? Function(String?)? validator,
    int? maxLength,
    TextInputAction? textInputAction,
    void Function(String)? onSubmitted,
  }) {
    // Light Forui-style field: white/near-white fill, subtle border at
    // rest, focusRing-colored border on focus (200ms — Flutter's
    // InputDecorator default border transition; matches the ~150ms
    // convention closely enough that it doesn't feel out of step with the
    // rest of the app's hand-rolled animations).
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      onChanged: onChanged,
      maxLength: maxLength,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      style: TextStyle(
        color: AppTheme.login.textPrimary,
        fontSize: _isDesktop ? 14 : 13,
      ),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: AppTheme.login.textSecondary,
          fontSize: _isDesktop ? 13 : 12,
        ),
        prefixIcon: Icon(
          icon,
          color: AppTheme.login.textSecondary,
          size: _isDesktop ? 19 : 18,
        ),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(
          horizontal: _isDesktop ? 16 : 14,
          vertical: _isDesktop ? 14 : 12,
        ),
        counterText: '', // hide the maxLength counter — not part of this design
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.login.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.login.focusRing, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.login.errorMuted),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.login.errorMuted, width: 1.5),
        ),
        errorStyle: TextStyle(color: AppTheme.login.errorMuted, fontSize: 10),
      ),
    );
  }

  Widget _eyeBtn(bool obscure, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: obscure ? 'Show password' : 'Hide password',
      child: IconButton(
        icon: Icon(
          obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          color: AppTheme.login.textSecondary,
          size: _isDesktop ? 19 : 18,
        ),
        onPressed: onTap,
      ),
    );
  }

  Widget _submitBtn({required String label, required VoidCallback onPressed}) {
    // Filled primary action. Uses primaryDark (not primaryGreen) as the base
    // fill — primaryGreen-with-white-text only measures ~3.3:1 contrast,
    // short of WCAG AA's 4.5:1 floor for normal-weight text; primaryDark
    // clears it at ~6.1:1 (see Step 3 note). A darker shade on hover gives
    // the "hover-darken" affordance the design calls for without needing a
    // separate lighter primaryGreen fill to darken from.
    final hoverDark = Color.lerp(
      AppTheme.login.primaryDark,
      Colors.black,
      0.18,
    )!;
    return SizedBox(
      height: _isDesktop ? 50 : 44,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppTheme.login.primaryDark.withValues(alpha: 0.4);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)) {
              return hoverDark;
            }
            return AppTheme.login.primaryDark;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          elevation: const WidgetStatePropertyAll(0),
          textStyle: WidgetStatePropertyAll(
            TextStyle(
              fontSize: _isDesktop ? 15 : 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          animationDuration: const Duration(milliseconds: 150),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }

  Widget _googleBtn() {
    // Distinct secondary action — light/white fill with a subtle border, so
    // it reads clearly apart from the filled primary Sign In button (the
    // old version shared the card's own dark-green fill and blended in).
    return SizedBox(
      height: _isDesktop ? 50 : 44,
      child: OutlinedButton(
        onPressed: _isLoading ? null : _signInWithGoogle,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.login.textPrimary,
          side: BorderSide(color: AppTheme.login.borderSubtle),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.string(
              _googleSvg,
              width: _isDesktop ? 17 : 16,
              height: _isDesktop ? 17 : 16,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _s.continueGoogle,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: _isDesktop ? 14 : 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(String label) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppTheme.login.borderSubtle, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(
              color: AppTheme.login.dividerText,
              fontSize: _isDesktop ? 14 : 13,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppTheme.login.borderSubtle, height: 1)),
      ],
    );
  }

  // ── Footer ─────────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 4),
      child: Column(
        children: [
          Divider(
            color: AppTheme.login.outsideMutedText.withValues(alpha: 0.25),
            height: 1,
            indent: 24,
            endIndent: 24,
          ),
          const SizedBox(height: 10),
          Text(
            _s.projectTagline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _footerPrimary,
              fontSize: 11,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _s.developedBy,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.login.outsideMutedText,
              fontSize: 10,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Sub-widgets
// ═══════════════════════════════════════════════════════════════════════════════

class _LangChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LangChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Lighter Forui-style pill: unselected has no fill, just a subtle
    // outline; selected gets a soft primaryGreen tint (not the old solid
    // bright-green fill) plus primaryGreen text. These pills sit on the
    // page background (not the white card), so the unselected border uses
    // textSecondary at low alpha rather than borderSubtle — borderSubtle
    // reads too close in tone to the sage page background to stay visible.
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.login.primaryGreen.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected
                      ? AppTheme.login.primaryGreen.withValues(alpha: 0.5)
                      : AppTheme.login.primaryDark.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  // textSecondary (#6B7A6B) only measures ~3.5:1 against
                  // this pill's actual backdrop — the page's sage-tinted
                  // _bgOutside, not the white card — short of AA's 4.5:1
                  // floor for normal text. primaryDark clears ~5.4:1 here
                  // while still reading as visually muted next to the
                  // selected pill's brighter primaryGreen.
                  color: selected
                      ? AppTheme.login.primaryGreen
                      : AppTheme.login.primaryDark,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isDesktop;
  const _TabBtn({
    required this.label,
    required this.selected,
    required this.onTap,
    this.isDesktop = false,
  });

  @override
  Widget build(BuildContext context) {
    // Underline-style tab (Forui-inspired) — no filled pill, just a
    // muted/active text weight shift plus a thin bottom indicator on the
    // active tab. Lighter-weight than the old solid bright-green pill.
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            // 44/48px minimum touch target height per HCI requirements.
            constraints: BoxConstraints(minHeight: isDesktop ? 48 : 44),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected
                      ? AppTheme.login.primaryGreen
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              style: TextStyle(
                color: selected
                    ? AppTheme.login.textPrimary
                    : AppTheme.login.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: isDesktop ? 14 : 13,
              ),
              child: Text(label, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Forgot password?" link — primaryGreen text, no underline at rest, with
/// a subtle underline on pointer hover (web/desktop mouse only; touch
/// devices never fire hover events so this is inert on mobile).
class _ForgotPasswordLink extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  const _ForgotPasswordLink({required this.label, required this.onTap});

  @override
  State<_ForgotPasswordLink> createState() => _ForgotPasswordLinkState();
}

class _ForgotPasswordLinkState extends State<_ForgotPasswordLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: kIsWeb ? (_) => setState(() => _hovered = true) : null,
      onExit: kIsWeb ? (_) => setState(() => _hovered = false) : null,
      child: TextButton(
        onPressed: widget.onTap,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          minimumSize: const Size(0, 44), // 44px touch target, compact visual
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        child: Text(
          widget.label,
          style: TextStyle(
            color: AppTheme.login.primaryGreen,
            fontSize: 11,
            decoration: _hovered
                ? TextDecoration.underline
                : TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SVG Assets
// ═══════════════════════════════════════════════════════════════════════════════

const String _leafSvg = '''
<svg viewBox="0 0 110 110" xmlns="http://www.w3.org/2000/svg">
  <path d="M50 65 C35 58 22 42 28 28 C38 40 48 55 50 65Z" fill="#3A6B1A"/>
  <path d="M52 58 C67 50 80 36 74 22 C64 34 55 50 52 58Z" fill="#4CAF50"/>
  <path d="M50 50 C38 44 30 32 34 20 C42 30 48 42 50 50Z" fill="#66BB6A"/>
  <path d="M50 65 C50 50 50 35 50 20" stroke="#2E7D32" stroke-width="1.5" stroke-linecap="round" fill="none"/>
</svg>
''';

const String _googleSvg = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4"/>
  <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
  <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l3.66-2.84z" fill="#FBBC05"/>
  <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
</svg>
''';
