// lib/services/prediction_handoff.dart
// ─────────────────────────────────────────────────────────────────────────────
//  Yield prediction -> AI Chat handoff channel.
//
//  WHY A NOTIFIER AND NOT A CONSTRUCTOR PARAMETER
//  main.dart builds its seven screens ONCE into a `late final List<Widget>`
//  and crossfades between them inside a permanent Stack — deliberately, so a
//  tab switch never rebuilds a screen and destroys its live state (see the
//  comment above _MainScaffoldState.pageFadeDuration; ChatScreen's whole
//  conversation lives in that state). Passing the prediction down as a
//  constructor argument would mean rebuilding ChatScreen on every handoff,
//  which is exactly what that design prevents.
//
//  So the yield screen PUBLISHES here and the chat screen SUBSCRIBES. Neither
//  constructor changes, `const ChatScreen()` keeps working in both main.dart
//  and admin_shell.dart, and the tab switch stays a pure crossfade.
//
//  Single-slot and consume-once: the chat screen sets the value back to null
//  after reading it, so re-entering the chat tab later doesn't replay a stale
//  prediction into a new conversation.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

import '../models/api_models.dart';

/// One pending handoff: the prediction, plus optionally the question the
/// farmer already chose on the yield page.
class PredictionHandoff {
  /// The numbers the conversation is about. Attached to every request in the
  /// resulting conversation, not just the first.
  final PredictionContext context;

  /// Set when the farmer tapped one of the quick-question chips on the yield
  /// result card rather than the plain "Ask AI about this" button. The chat
  /// screen sends it as the first message the moment it opens, so the answer
  /// is already arriving when the tab finishes switching — no intermediate
  /// screen asking them to pick again.
  ///
  /// Null for the plain button, which lands on the prediction empty state and
  /// waits for the farmer to type.
  final String? question;

  const PredictionHandoff(this.context, {this.question});
}

/// The prediction the farmer tapped "Ask AI about this" on, waiting to be
/// picked up by the chat screen. Null whenever there is nothing pending.
final ValueNotifier<PredictionHandoff?> predictionHandoff =
    ValueNotifier<PredictionHandoff?>(null);
