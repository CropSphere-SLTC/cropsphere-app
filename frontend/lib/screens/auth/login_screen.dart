import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../app_lang.dart'; // AppLang, AppLangProvider — shared across app
import '../../widgets/app_theme.dart';

// ── Colour tokens ──────────────────────────────────────────────────────────────
const _bgOutside = Color(0xFFDFE6CE);
const _bgCard = Color(0xFF2D6A2F);
const _bgField = Color(0xFF3D7A40);
const _borderCard = Color(0xFF4CAF50);
const _accentLight = Color(0xFF90EE90);
const _textOnGreen = Color(0xFF1A3A1A);
const _textMuted = Color(0xFFB8D4A0);
const _textHint = Color(0xFFD4EAC0);
const _footerPrimary = Color(0xFF4A5E30);
const _footerSecondary = Color(0xFF6B7A52);
const _logoName = Color(0xFF1B4D1B);
const _taglineMain = Color(0xFF2E4A1E);
const _taglineSub = Color(0xFF6B7A52);

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
    _tabSlideIn =
        Tween<Offset>(begin: const Offset(0, 0.025), end: Offset.zero).animate(
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
  Future<void> _signInWithGoogle() async {
    _setLoading(true);
    _setError(null);
    try {
      final p = GoogleAuthProvider()
        ..addScope('email')
        ..addScope('profile')
        ..setCustomParameters({'prompt': 'select_account'});
      await FirebaseAuth.instance.signInWithPopup(p);
    } on FirebaseAuthException catch (e) {
      _setError(switch (e.code) {
        'popup-closed-by-user' => _s.errPopupClosed,
        'popup-blocked' => _s.errPopupBlocked,
        'network-request-failed' => _s.errNetwork,
        _ => _s.errSignInFail,
      });
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
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _siEmailCtrl.text.trim(),
        password: _siPassCtrl.text,
      );
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
    //   web     (≥1024) → 460 px, centred
    final double cardMaxW;
    if (screenW < 600) {
      cardMaxW = double.infinity;
    } else if (screenW < 1024) {
      // Linear interpolation: 400 at 600px → 440 at 1023px
      final t = ((screenW - 600) / (1024 - 600)).clamp(0.0, 1.0);
      cardMaxW = 400 + (40 * t);
    } else {
      cardMaxW = 460;
    }

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
                Positioned(
                  top: 24,
                  right: 12,
                  child: Opacity(
                    opacity: 0.10,
                    child: SvgPicture.string(_leafSvg, width: 100),
                  ),
                ),
                Positioned(
                  bottom: 60,
                  left: 8,
                  child: Opacity(
                    opacity: 0.07,
                    child: SvgPicture.string(_leafSvg, width: 80),
                  ),
                ),

                // ── Main layout ──────────────────────────────────────────────
                Column(
                  children: [
                    // Top bar — logo pinned top-left
                    _buildTopBar(),

                    // Scrollable centre content — vertically centred on tablet/web
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            child: ConstrainedBox(
                              // minHeight fills the available space so the inner
                              // Column can centre itself vertically on larger screens.
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight,
                              ),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: cardMaxW == double.infinity
                                        ? double.infinity
                                        : cardMaxW,
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: screenW < 600 ? 20 : 24,
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          height: screenW < 600 ? 14 : 20,
                                        ),
                                        _buildTagline(),
                                        const SizedBox(height: 14),
                                        _buildLangSelector(),
                                        const SizedBox(height: 14),
                                        _buildCard(),
                                        SizedBox(
                                          height: screenW < 600 ? 16 : 20,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    // Footer pinned bottom-center
                    _buildFooter(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                ),
              ),
              SvgPicture.string(_cropSvg, width: 34, height: 34),
            ],
          ),
          const SizedBox(width: 10),
          const Text(
            'CropSphere',
            style: TextStyle(
              color: _logoName,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  // ── Tagline ────────────────────────────────────────────────────────────────
  Widget _buildTagline() {
    return Column(
      children: [
        Text(
          _s.taglineMain,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _taglineMain,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _s.taglineSub,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _taglineSub, fontSize: 12, height: 1.5),
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
        color: _bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _borderCard.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Tab bar
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 0),
            child: Row(
              children: [
                _TabBtn(
                  label: _s.tabSignIn,
                  selected: _tabIndex == 0,
                  onTap: () => _switchTab(0),
                ),
                const SizedBox(width: 8),
                _TabBtn(
                  label: _s.tabRegister,
                  selected: _tabIndex == 1,
                  onTap: () => _switchTab(1),
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
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Form title & subtitle
          Text(
            tab == 0 ? _s.siTitle : _s.suTitle,
            style: const TextStyle(
              color: Color(0xFFF1FAF1),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            tab == 0 ? _s.siSub : _s.suSub,
            style: TextStyle(
              color: _textMuted.withValues(alpha: 0.7),
              fontSize: 11,
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
            validator: (v) =>
                (v == null || v.isEmpty) ? _s.enterPassword : null,
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading ? null : _forgotPassword,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                _s.forgotPassword,
                style: const TextStyle(color: _accentLight, fontSize: 11),
              ),
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
            validator: (v) => (v?.trim().isEmpty ?? true) ? _s.enterName : null,
          ),
          const SizedBox(height: 9),
          _field(
            controller: _suEmailCtrl,
            label: _s.email,
            icon: Icons.email_outlined,
            keyboard: TextInputType.emailAddress,
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
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
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
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: _textHint.withValues(alpha: 0.6),
          fontSize: 12,
        ),
        prefixIcon: Icon(
          icon,
          color: _accentLight.withValues(alpha: 0.6),
          size: 18,
        ),
        suffixIcon: suffix,
        filled: true,
        fillColor: _bgField,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _accentLight.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _accentLight, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 10),
      ),
    );
  }

  Widget _eyeBtn(bool obscure, VoidCallback onTap) {
    return IconButton(
      icon: Icon(
        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: _accentLight.withValues(alpha: 0.55),
        size: 18,
      ),
      onPressed: onTap,
    );
  }

  Widget _submitBtn({required String label, required VoidCallback onPressed}) {
    return SizedBox(
      height: 44,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _accentLight,
          foregroundColor: _textOnGreen,
          disabledBackgroundColor: _accentLight.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _textOnGreen,
                ),
              )
            : Text(label),
      ),
    );
  }

  Widget _googleBtn() {
    return SizedBox(
      height: 42,
      child: OutlinedButton(
        onPressed: _isLoading ? null : _signInWithGoogle,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFC8E6C9),
          side: BorderSide(color: _accentLight.withValues(alpha: 0.28)),
          backgroundColor: _bgField,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.string(_googleSvg, width: 16, height: 16),
            const SizedBox(width: 10),
            Text(
              _s.continueGoogle,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(String label) {
    return Row(
      children: [
        Expanded(
          child: Divider(color: _accentLight.withValues(alpha: 0.2), height: 1),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(
              color: _textMuted.withValues(alpha: 0.45),
              fontSize: 10,
            ),
          ),
        ),
        Expanded(
          child: Divider(color: _accentLight.withValues(alpha: 0.2), height: 1),
        ),
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
            color: _taglineSub.withValues(alpha: 0.25),
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
            style: const TextStyle(
              color: _footerSecondary,
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF4CAF50).withValues(alpha: 0.18)
              : const Color(0xFF2D6A2F).withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF4CAF50).withValues(alpha: 0.65)
                : const Color(0xFF90EE90).withValues(alpha: 0.18),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? const Color(0xFF2E7D32) : const Color(0xFF6B7A52),
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
  const _TabBtn({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? _accentLight.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? _accentLight : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected
                  ? _accentLight
                  : Colors.white.withValues(alpha: 0.32),
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13,
            ),
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

const String _cropSvg = '''
<svg viewBox="0 0 110 110" xmlns="http://www.w3.org/2000/svg">
  <ellipse cx="55" cy="96" rx="36" ry="7" fill="#1B4D1B" opacity="0.7"/>
  <path d="M55 95 C55 80 52 65 50 50" stroke="#4CAF50" stroke-width="2.5" stroke-linecap="round" fill="none"/>
  <path d="M50 65 C35 58 22 42 28 28 C38 40 48 55 50 65Z" fill="#388E3C" opacity="0.9"/>
  <path d="M50 65 C42 58 35 44 28 28" stroke="#2E7D32" stroke-width="1" fill="none" opacity="0.6"/>
  <path d="M52 58 C67 50 80 36 74 22 C64 34 55 50 52 58Z" fill="#4CAF50" opacity="0.9"/>
  <path d="M52 58 C62 50 70 36 74 22" stroke="#388E3C" stroke-width="1" fill="none" opacity="0.6"/>
  <path d="M50 50 C38 44 30 32 34 20 C42 30 48 42 50 50Z" fill="#66BB6A" opacity="0.8"/>
  <circle cx="50" cy="28" r="3.5" fill="#FFC107" opacity="0.9"/>
  <circle cx="44" cy="22" r="3"   fill="#FFB300" opacity="0.85"/>
  <circle cx="56" cy="20" r="3"   fill="#FFC107" opacity="0.9"/>
  <circle cx="50" cy="14" r="3.5" fill="#FFD54F" opacity="0.95"/>
  <circle cx="43" cy="13" r="2.5" fill="#FFB300" opacity="0.8"/>
  <circle cx="57" cy="12" r="2.5" fill="#FFC107" opacity="0.85"/>
  <circle cx="50" cy="8"  r="2"   fill="#FFD54F" opacity="0.9"/>
  <path d="M50 50 C50 42 50 35 50 28" stroke="#558B2F" stroke-width="2" stroke-linecap="round" fill="none"/>
  <ellipse cx="40" cy="46" rx="2" ry="3" fill="#B3E5FC" opacity="0.6" transform="rotate(-20 40 46)"/>
  <ellipse cx="63" cy="40" rx="1.5" ry="2.5" fill="#B3E5FC" opacity="0.5" transform="rotate(15 63 40)"/>
</svg>
''';

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
