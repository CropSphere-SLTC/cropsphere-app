// lib/services/price_prefill.dart
// ─────────────────────────────────────────────────────────────────────────────
//  Demand forecast -> Price screen pre-fill channel.
//
//  WHY A NOTIFIER AND NOT A CONSTRUCTOR PARAMETER
//  Exactly the reason prediction_handoff.dart gives, and this file is
//  deliberately its twin rather than a second mechanism: main.dart builds its
//  seven screens ONCE into a `late final List<Widget>` and crossfades between
//  them inside a permanent Stack, so a tab switch never rebuilds a screen and
//  destroys its live state. Passing the crop/season down as constructor
//  arguments would mean rebuilding PriceScreen on every hand-off, which is
//  what that design exists to prevent — and would throw away whatever the
//  farmer had already entered there.
//
//  So the demand screen PUBLISHES here and the price screen SUBSCRIBES.
//  Neither constructor changes and the tab switch stays a pure crossfade.
//
//  WHY NOT REUSE predictionHandoff ITSELF
//  That channel means "open a NEW conversation grounded in this prediction",
//  and the chat screen consumes it by calling _startNewChat(). This one means
//  "put these two values in these two fields" — no result is cleared, nothing
//  is submitted, and the farmer still taps Predict themselves. Same shape,
//  different contract, so it gets its own single-slot notifier rather than an
//  overloaded flag on that one.
//
//  Single-slot and consume-once: the price screen sets the value back to null
//  after reading it, so re-entering the price tab later doesn't silently
//  re-apply a stale crop over something the farmer has since changed.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

/// Values to drop into the price screen's own inputs.
///
/// Both are English enum keys (`'Carrot'`, `'Maha'`), not display labels —
/// the price screen re-translates them through its own label functions, so a
/// hand-off made in Sinhala still lands correctly if the farmer switches
/// language on the way.
class PricePrefill {
  final String? crop;
  final String? season;

  const PricePrefill({this.crop, this.season});
}

/// The crop/season the farmer carried over from a demand forecast, waiting to
/// be picked up by the price screen. Null whenever there is nothing pending.
final ValueNotifier<PricePrefill?> pricePrefill = ValueNotifier<PricePrefill?>(
  null,
);
