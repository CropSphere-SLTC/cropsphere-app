// lib/widgets/searchable_dropdown.dart
// ─────────────────────────────────────────────────────────────────────────────
//  The ONE type-to-filter dropdown, shared by Yield, Price, Weather, Crop
//  Recommend, Demand and Chat.
//
//  WHY THIS EXISTS
//  This widget existed as five private `_searchableDropdown` methods, one per
//  screen. recommend_screen's own copy carried the note "this is now the
//  FOURTH copy ... it is the same drift app_top_bar.dart was created to end",
//  and demand_screen's said the same about the fifth. This file is that
//  extraction, finally done.
//
//  The four newer copies (price, weather, recommend, demand) were byte-for-byte
//  identical apart from which `AppTheme.accents.*` entry they named, so they
//  collapse into this one with `accent` as a parameter and no behaviour change
//  at all. yield_screen's was the outlier and genuinely changes — see the
//  MIGRATION NOTE at the bottom of this comment.
//
//  WHY RawAutocomplete AND NOT A PACKAGE
//  It needs no new dependency and no app-root theme wiring, and it carries the
//  same `InputDecoration` the plain (non-searchable) dropdowns use, so all the
//  fields in a form card stay visually flush.
//
//  WHY RawAutocomplete AND NOT Autocomplete
//  The caller must own the `TextEditingController`: rules like "clear the
//  district when the crop changes" reach into the field's text, which
//  `Autocomplete`'s private internal controller wouldn't permit. That is also
//  why [controller] and [focusNode] are required parameters here rather than
//  created internally — the owning State disposes them.
//
//  MIGRATION NOTE — yield_screen
//  Yield's copy predated the AppTheme.login/accents token pass and was the
//  only one without [itemLabel]. Moving it here changes it in four visible
//  ways, all of them bringing it in line with the other five screens:
//    • accent green #1B5E20 (AppTheme.primary) -> #306534 (accents.yield.ink)
//    • muted #8FA88F (textMuted) -> #6B7A6B (login.textSecondary)
//    • gains the 2px focus ring and explicit enabled border
//    • gains the hollow "not yet chosen" tick circle in the suffix
//  Its OPTION TEXT is deliberately left in English: yield passes the default
//  identity [itemLabel], exactly as before. Giving yield translated crop and
//  district options is a real fix but a separate, user-visible change.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Snap a searchable field's text to match its focus state.
///
/// ON FOCUS — force a real text transition so `RawAutocomplete` rebuilds its
/// option list and the field opens showing EVERY option.
///
/// This is the fix for "District doesn't work like Crop". `RawAutocomplete`
/// recomputes its options only when the field's TEXT changes — see
/// `_onChangedField` in the framework's autocomplete.dart:
///
///     if (value.text != _lastFieldText) { shouldUpdateOptions = true; }
///
/// It never calls optionsBuilder on focus. So tapping a field whose text
/// hasn't changed opens onto a stale list, or — before anything has ever been
/// typed — onto no list at all. District hit that hardest: choosing a crop
/// enables the field and swaps its options, but changes no text, so tapping it
/// showed nothing until you blind-typed a matching letter.
///
/// The nudge below drives a real text transition so the builder re-runs with
/// an empty query, which returns the full list. Both writes land in the same
/// synchronous turn, so no intermediate value is ever painted (Flutter only
/// rebuilds at a frame boundary), and `RawAutocomplete`'s own
/// `_onChangedCallId` discards the first, superseded result.
///
/// ON BLUR — snap the text back to the committed selection, so typing a
/// partial query and tapping away can't leave the field displaying something
/// that isn't actually selected.
///
/// Call it from a `FocusNode` listener registered in the owning State's
/// `initState`. [displayText] is what the field should read when unfocused —
/// pass the localised label when the screen uses [SearchableDropdown.itemLabel],
/// so blur restores the translated name and not the raw English key.
///
/// Pinned by test/searchable_dropdown_test.dart.
void syncSearchField(
  FocusNode node,
  TextEditingController ctrl,
  String? displayText,
) {
  if (node.hasFocus) {
    if (ctrl.text.isNotEmpty) {
      ctrl.clear(); // real change: "Badulla" -> "" -> full list
    } else {
      // Already empty, so clear() alone would notify nobody (a
      // ValueNotifier drops a write equal to its current value).
      ctrl.value = const TextEditingValue(text: ' ');
      ctrl.clear();
    }
    return;
  }
  final want = displayText ?? '';
  if (ctrl.text != want) ctrl.text = want;
}

/// The filled/empty tick shown in a form field's suffix — solid green check
/// once the field has a value, hollow circle while it doesn't.
///
/// Screens keep calling this for their non-searchable fields (season,
/// irrigation, forecast range) too, which is why it is public here rather
/// than private to [SearchableDropdown].
Widget fieldCheckIcon(bool done) => Padding(
  padding: const EdgeInsets.only(right: 2),
  child: Icon(
    done ? Icons.check_circle : Icons.radio_button_unchecked,
    size: 19,
    color: done ? AppTheme.success : AppTheme.login.borderSubtle,
  ),
);

/// A type-to-filter dropdown: a text field that opens a filtered option list
/// on focus and narrows it as the farmer types.
///
/// An empty query lists EVERY option. That alone is NOT enough to make a tap
/// behave like opening a dropdown — `RawAutocomplete` only re-runs
/// optionsBuilder on a text change — so the owning screen must also wire
/// [syncSearchField] to [focusNode]. See the long note there.
class SearchableDropdown extends StatelessWidget {
  /// Floating label for the field.
  final String label;

  /// The committed selection, as an entry of [items] (an English key when the
  /// screen is translating via [itemLabel]). Null = nothing chosen yet.
  final String? value;

  /// Option keys, in the order they should be offered.
  final List<String> items;

  /// Leading icon.
  final IconData icon;

  final ValueChanged<String?> onChanged;

  /// Owned and disposed by the calling State — see the file header.
  final TextEditingController controller;
  final FocusNode focusNode;

  /// The feature's identity colour, for the icons, the selected row and the
  /// check mark. `AppTheme.accents.yield`, `.price`, `.weather`, `.cropRec`,
  /// `.demand` or `.chat`.
  final FeatureAccent accent;

  /// Localised "Type to search" placeholder. Passed in rather than resolved
  /// here so each screen keeps using its own `_t` and this widget needs no
  /// language import.
  final String searchHint;

  /// Maps an option key to what the farmer reads. Defaults to identity, which
  /// is what yield_screen relies on to keep showing raw English keys.
  ///
  /// Filtering matches BOTH the key and the label, so typing "carrot" still
  /// finds the crop when the list is rendering "කැරට්".
  final String Function(String) itemLabel;

  /// Optional helper line under the field.
  final String? hint;

  final bool enabled;

  const SearchableDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.icon,
    required this.onChanged,
    required this.controller,
    required this.focusNode,
    required this.accent,
    required this.searchHint,
    this.itemLabel = _identity,
    this.hint,
    this.enabled = true,
  });

  static String _identity(String s) => s;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // Captures the field's own width so the options overlay lines up
    // edge-to-edge below it instead of sizing itself to its content.
    builder: (ctx, bc) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RawAutocomplete<String>(
          textEditingController: controller,
          focusNode: focusNode,
          displayStringForOption: itemLabel,
          optionsBuilder: (TextEditingValue v) {
            if (!enabled) return const Iterable<String>.empty();
            final q = v.text.trim().toLowerCase();
            // Empty, or still showing the committed selection (the farmer
            // reopened the field to change their mind) -> offer everything.
            //
            // itemLabel is only ever called with a REAL selection, never with
            // the '' stand-in for "nothing chosen": a caller's label function
            // is only obliged to map actual option keys, and one that throws
            // on '' would take the whole optionsBuilder down with it — leaving
            // RawAutocomplete showing its previous, unfiltered list.
            final sel = value;
            if (q.isEmpty ||
                q == (sel ?? '').toLowerCase() ||
                (sel != null && q == itemLabel(sel).toLowerCase())) {
              return items;
            }
            return items.where(
              (e) =>
                  e.toLowerCase().contains(q) ||
                  itemLabel(e).toLowerCase().contains(q),
            );
          },
          onSelected: (sel) {
            onChanged(sel);
            focusNode.unfocus();
          },
          fieldViewBuilder: (ctx, ctrl, fn, onFieldSubmitted) => TextFormField(
            controller: ctrl,
            focusNode: fn,
            enabled: enabled,
            onFieldSubmitted: (_) => onFieldSubmitted(),
            style: TextStyle(fontSize: 14, color: AppTheme.login.textPrimary),
            decoration: InputDecoration(
              labelText: label,
              hintText: enabled ? searchHint : null,
              hintStyle: TextStyle(
                color: AppTheme.login.textSecondary,
                fontSize: 13,
              ),
              labelStyle: TextStyle(color: AppTheme.login.textSecondary),
              prefixIcon: Icon(
                icon,
                color: enabled ? accent.ink : AppTheme.login.textSecondary,
                size: 20,
              ),
              // Tick + caret together. mainAxisSize.min keeps the Row from
              // trying to fill the field, and the loosened constraints stop
              // InputDecoration squeezing two icons into one icon's width.
              suffixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  fieldCheckIcon(value != null),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.arrow_drop_down,
                      color: enabled
                          ? accent.ink
                          : AppTheme.login.textSecondary,
                    ),
                  ),
                ],
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppTheme.login.borderSubtle),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppTheme.login.borderSubtle),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: AppTheme.login.focusRing,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              filled: !enabled,
              fillColor: enabled ? null : AppTheme.disabledSurface,
            ),
          ),
          optionsViewBuilder: (ctx, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              color: AppTheme.login.background,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: 240,
                  maxWidth: bc.maxWidth,
                ),
                child: SizedBox(
                  width: bc.maxWidth,
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (c, i) {
                      final opt = options.elementAt(i);
                      final isSelected = opt == value;
                      return InkWell(
                        onTap: () => onSelected(opt),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          color: isSelected
                              ? accent.fill.withValues(alpha: 0.14)
                              : null,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  itemLabel(opt),
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? accent.ink
                                        : AppTheme.login.textPrimary,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check, size: 16, color: accent.ink),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              hint!,
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.login.textSecondary,
              ),
            ),
          ),
      ],
    ),
  );
}
