// lib/widgets/followup_chip.dart
// ─────────────────────────────────────────────────────────────────────────────
//  The pill-shaped suggestion chip used under a chat reply.
//
//  Lifted verbatim out of chat_screen's _buildSuggestions so the yield
//  screen's "Ask AI about this" quick questions are literally this component
//  rather than a second chip that merely resembles it. Styling is unchanged:
//  primary @10% fill, primary @30% border, radius 20, 12px primaryDark text,
//  single line with ellipsis.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'app_theme.dart';

class FollowupChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const FollowupChip({super.key, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 12, color: AppTheme.primaryDark),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// The four quick questions offered on a yield prediction result.
///
/// English-only, deliberately: they are sent verbatim as the farmer's chat
/// message, and the chat experience (starter prompts, replies, the RAG
/// corpus) is English throughout. Translating the labels would mean the
/// message shown in the transcript no longer matched the chip that was
/// tapped.
const List<String> kPredictionStarters = [
  'Explain this prediction',
  'How can I improve this yield?',
  'What price will I get for this?',
  'Is this a good yield for my area?',
];

/// The four quick questions offered on a price prediction result.
///
/// English-only for the same reason as [kPredictionStarters]: they are sent
/// verbatim as the farmer's chat message, so translating the label would mean
/// the transcript no longer matched the chip that was tapped.
const List<String> kPriceStarters = [
  'Explain this price',
  'When should I sell?',
  'How does this compare to other districts?',
  'How can I get a better price?',
];
