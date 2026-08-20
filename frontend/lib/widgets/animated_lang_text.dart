// lib/widgets/animated_lang_text.dart
// Drop-in replacement for Text() that crossfades whenever its string value
// changes, instead of swapping instantly — used on the app's translated
// labels (headers, nav labels, section titles) so switching language
// (EN/SI/TA via AppLangProvider) reads as a transition, not a jump cut.
//
// Keyed on the string itself, not on AppLang, so it transitions correctly
// no matter why the text changed. No bounce/elastic curves, matching the
// app's established animation standard.

import 'package:flutter/material.dart';

class AnimatedLangText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final Duration duration;

  const AnimatedLangText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.duration = const Duration(milliseconds: 220),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: Text(
        text,
        key: ValueKey(text),
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}
