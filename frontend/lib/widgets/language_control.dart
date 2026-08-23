// lib/widgets/language_control.dart
// The one language switcher shared by every top bar in the app. Replaces
// the 6 near-identical private `_LangPill` classes that used to be
// copy-pasted into dashboard/price/weather/yield/demand/recommend screens.
//
// Self-contained like ProfileAvatarButton — reads AppLangProvider itself,
// so it drops into any top bar as `const LanguageControl()` with no props
// threaded through the screen that hosts it. Picks its own presentation
// off the current screen width: the familiar 3-pill row at ≥1024px (no
// space constraint on desktop), a compact dropdown below that — same
// EN/සිංහල/தமிழ் options and the same AppLangProvider.setLang() call
// either way, so this is a pure UI change over the switching logic that
// already existed.

import 'package:flutter/material.dart';

import '../app_lang.dart';
import 'top_nav_metrics.dart';

class LanguageControl extends StatelessWidget {
  /// Label size and control height, supplied by the top bar so the control
  /// lines up with the nav labels. Null keeps the compact defaults used by
  /// the mobile app bars, which have no nav row to align to.
  final double? labelSize;
  final double? height;

  const LanguageControl({super.key, this.labelSize, this.height});

  @override
  Widget build(BuildContext context) {
    // Pills need ~185px at the larger label size — more than three nav
    // items — so they appear only where the bar can afford them. Below
    // that the same control renders as its compact dropdown, which costs
    // about a third as much.
    final roomForPills =
        MediaQuery.of(context).size.width >= TopNavMetrics.comfortableFrom;
    return roomForPills
        ? _LanguagePills(labelSize: labelSize, height: height)
        : _LanguageDropdown(labelSize: labelSize, height: height);
  }
}

// ── Desktop: 3-pill row (unchanged presentation from the old _LangPill) ────
class _LanguagePills extends StatelessWidget {
  final double? labelSize;
  final double? height;
  const _LanguagePills({this.labelSize, this.height});

  @override
  Widget build(BuildContext context) {
    final notifier = AppLangProvider.of(context);
    final current = notifier.lang;
    final fs = labelSize ?? 9.5;
    return Container(
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F0),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: AppLang.values.map((l) {
          final active = l == current;
          return Semantics(
            button: true,
            selected: active,
            label: l.fullName,
            child: GestureDetector(
              onTap: () => notifier.setLang(l),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFF1B5E20)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  l.label,
                  style: TextStyle(
                    fontSize: fs,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                    color: active ? Colors.white : const Color(0xFF888888),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Mobile/tablet: single dropdown showing the current language ───────────
class _LanguageDropdown extends StatelessWidget {
  final double? labelSize;
  final double? height;
  const _LanguageDropdown({this.labelSize, this.height});

  @override
  Widget build(BuildContext context) {
    final notifier = AppLangProvider.of(context);
    final current = notifier.lang;
    return Semantics(
      button: true,
      label: 'Language: ${current.fullName}',
      child: PopupMenuButton<AppLang>(
        tooltip: 'Change language',
        initialValue: current,
        onSelected: notifier.setLang,
        offset: const Offset(0, 36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        itemBuilder: (context) => AppLang.values.map((l) {
          final active = l == current;
          return PopupMenuItem(
            value: l,
            child: Row(
              children: [
                Text(
                  l.fullName,
                  style: TextStyle(
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active
                        ? const Color(0xFF1B5E20)
                        : const Color(0xFF333333),
                  ),
                ),
                if (active) ...[
                  const Spacer(),
                  const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: Color(0xFF1B5E20),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
        child: Container(
          height: height,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF0F4F0),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                current.label,
                style: TextStyle(
                  fontSize: labelSize ?? 11.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1B5E20),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: Color(0xFF1B5E20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
