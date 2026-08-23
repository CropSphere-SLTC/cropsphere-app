// lib/widgets/floating_bottom_nav.dart
// ─────────────────────────────────────────────────────────────────────────────
//  Floating glassmorphic bottom nav (Samsung One UI-style capsule) —
//  replaces the old edge-to-edge _CropBottomNav.
//
//  • Mobile + tablet only (<1024px) — MainShell hides this entirely on
//    desktop, where the existing per-screen top nav is the sole navigation.
//  • 7 equal-width slots (Home/Yield/Price/Weather/Crop/Demand/Chat) so the
//    active pill's position is a simple index*slotWidth — no per-item width
//    changes, which is what makes the pill's slide between tabs a clean
//    AnimatedPositioned tween instead of a layout jump.
//  • Every item always shows icon + label (stacked) — not just the active
//    one — so users aren't left guessing what an unfamiliar icon means.
//    "Active" is still never color-alone: the sliding pill (a shape only
//    the active tab has) plus bold label weight carry that too.
//  • No separate icon asset pack (Lottie/Lordicon etc.) — instead each
//    icon animates itself in place on activation: a brief scale "pop"
//    (sine-shaped, so it eases up and back down with no bounce/overshoot
//    past its rest state) crossfaded with the muted→accent color change,
//    built entirely from the existing SVGs via TweenAnimationBuilder. Zero
//    extra assets/dependencies, and it reuses this app's own icon set
//    instead of a generic stock pack.
//  • Frosted glass via BackdropFilter/ImageFilter.blur, which is a Skia-level
//    effect present on Flutter's Android/iOS/web (CanvasKit) backends alike,
//    so it renders consistently across all three; no fallback needed.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../app_lang.dart';
import 'top_nav_items.dart' show kTopNavIndicatorCurve, kTopNavIndicatorDuration;
import 'animated_lang_text.dart';
import 'app_theme.dart';

class FloatingBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final AppLang lang;

  const FloatingBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    required this.lang,
  });

  static const int itemCount = 7;

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

  List<String> get _labels => switch (lang) {
    AppLang.si => _labelsSi,
    AppLang.ta => _labelsTa,
    _ => _labelsEn,
  };

  /// Inactive icon/label tone.
  static const mutedColor = Color(0xFFAEAEAE);

  @override
  Widget build(BuildContext context) {
    final labels = _labels;
    final primaryDark = AppTheme.login.primaryDark;

    return SafeArea(
      top: false,
      // Floating, not edge-to-edge — margin from the screen on all three
      // sides so it reads as a capsule sitting over the content behind it
      // (MainShell sets Scaffold.extendBody so that content actually
      // scrolls underneath, which is what makes the blur meaningful).
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              // Most host screens sit on a near-white/pale-green gradient,
              // so a pure-white fill at low opacity all but disappeared
              // into it — bumped up, plus a faint brand-tinted (not white)
              // border, so the capsule actually reads as floating over the
              // page instead of blending into it.
              color: Colors.white.withValues(alpha: 0.80),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: AppTheme.login.primaryDark.withValues(alpha: 0.14),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF000000).withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final itemW = constraints.maxWidth / itemCount;
                const pillInset = 4.0;
                return Stack(
                  children: [
                    // The active pill — a single widget that slides between
                    // slots, rather than each item animating its own
                    // background, so the transition reads as one shape
                    // moving instead of one fading out while another fades
                    // in.
                    AnimatedPositioned(
                      // Same timing/curve as the top nav's sliding
                      // indicator (kTopNavIndicatorDuration/Curve) so both
                      // navigations' indicators move identically. Every
                      // slot is equal width — all items show icon+label —
                      // so the pill slides without resizing; there is no
                      // width difference left to morph.
                      duration: kTopNavIndicatorDuration,
                      curve: kTopNavIndicatorCurve,
                      left: selectedIndex * itemW + pillInset,
                      top: 8,
                      width: itemW - pillInset * 2,
                      height: 48,
                      child: Container(
                        decoration: BoxDecoration(
                          color: primaryDark.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    Row(
                      children: List.generate(itemCount, (i) {
                        return SizedBox(
                          width: itemW,
                          height: 64,
                          child: _NavItem(
                            label: labels[i],
                            active: i == selectedIndex,
                            svg: _navSvg,
                            index: i,
                            activeColor: primaryDark,
                            onTap: () => onTap(i),
                          ),
                        );
                      }),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // Same 7 icon glyphs as the old bottom nav (Home/Yield/Price/Weather/
  // Crop/Demand/Chat) — admin's shield icon dropped since this component
  // never renders it (admins bypass MainShell into AdminShell entirely).
  String _navSvg(int i, Color color) {
    final c =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    return switch (i) {
      0 => // Home — filled house silhouette with a white door cutout,
        // matching the solid-fill weight of the other 6 icons (was
        // stroke-only, which read noticeably lighter now that every tab
        // shows its icon at once instead of only the active one). White
        // cutout matches how Crop's checkmark / Chat's face dots already
        // punch contrast detail into a solid fill elsewhere in this set.
        '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
            '<path d="M3 10L12 3L21 10V20C21 20.55 20.55 21 20 21H4C3.45 21 3 20.55 3 20V10Z" fill="$c"/>'
            '<rect x="9" y="14" width="6" height="7" rx="1" fill="white"/>'
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

/// One bottom-nav slot.
///
/// Stateful only so it can hold the pressed flag for the tap feedback: a
/// slight scale-down on pointer-down that springs back on release. Kept
/// short (90ms) and shallow (0.96) so it reads as tactile acknowledgement
/// rather than an animation the user has to wait through — and with a
/// plain easeOut, no elastic overshoot, matching the rest of the app.
class _NavItem extends StatefulWidget {
  final String label;
  final bool active;
  final int index;
  final Color activeColor;
  final VoidCallback onTap;
  final String Function(int, Color) svg;

  const _NavItem({
    required this.label,
    required this.active,
    required this.index,
    required this.activeColor,
    required this.onTap,
    required this.svg,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.active,
      label: widget.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.onTap,
          onTapDown: (_) => _setPressed(true),
          onTapUp: (_) => _setPressed(false),
          onTapCancel: () => _setPressed(false),
          child: AnimatedScale(
            scale: _pressed ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            child: Center(
              // Drives the icon's pop + the icon/label color crossfade off
              // one 0→1 value — TweenAnimationBuilder re-tweens smoothly
              // from wherever it currently sits whenever `active` flips, so
              // switching tabs mid-animation never jumps.
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: widget.active ? 1.0 : 0.0),
                duration: kTopNavIndicatorDuration,
                curve: kTopNavIndicatorCurve,
                builder: (context, t, _) {
                  final color = Color.lerp(
                    FloatingBottomNav.mutedColor,
                    widget.activeColor,
                    t,
                  )!;
                  // A single sine hump: 0 at rest, peaks mid-transition,
                  // back to 0 at rest — eases up and settles with no
                  // overshoot past 1.0.
                  final scale = 1.0 + math.sin(t * math.pi) * 0.14;
                  return Transform.scale(
                    scale: scale,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.string(
                          widget.svg(widget.index, color),
                          width: 18,
                          height: 18,
                        ),
                        const SizedBox(height: 3),
                        AnimatedLangText(
                          widget.label,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: t > 0.5
                                ? FontWeight.w800
                                : FontWeight.w500,
                            color: color,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
