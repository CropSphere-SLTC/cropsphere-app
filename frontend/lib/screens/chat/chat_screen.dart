// lib/screens/chat/chat_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart'
    show
        Clipboard,
        ClipboardData,
        HardwareKeyboard,
        KeyDownEvent,
        LogicalKeyboardKey;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../config/app_config.dart';
import '../../services/prediction_handoff.dart';
import '../../services/service_factory.dart';
import '../../services/chat_history_service.dart';
import '../../services/profile_service.dart';
import '../../models/api_models.dart';
import '../../models/chat_history_models.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/language_control.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../widgets/followup_chip.dart';
import '../../widgets/growth_logo.dart';
import '../../widgets/skeleton_loading.dart';
import '../../widgets/theme_toggle_button.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const double _wideBreakpoint = 900;
  static const _logoAsset = 'assets/images/cropsphere_logo.png';
  static const _onboardingFollowups = [
    'Carrot yield in Badulla',
    'Best season for maize in Anuradhapura',
    'What crops do you cover?',
  ];
  static const _starterIcons = [
    Icons.grass,
    Icons.calendar_month,
    Icons.list_alt,
  ];

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _controller = TextEditingController();
  // Not final: swapped for a fresh instance on every conversation switch —
  // see _swapScrollController for why.
  ScrollController _scrollController = ScrollController();
  final _historyService = ChatHistoryService();
  final List<ChatMessage> _history = [];
  final List<Map<String, dynamic>> _displayMessages = [];
  bool _isLoading = false;
  bool _isStreaming = false;
  // True once the user has scrolled away from the bottom far enough that a
  // "scroll to bottom" affordance should appear instead of auto-scrolling
  // them back down against their will.
  bool _showScrollToBottom = false;
  // Wide-layout permanent sidebar collapse toggle. In-memory only — the app
  // has no local UI-state persistence pattern yet (dashboard_screen.dart has
  // the same "swap for SharedPreferences later" note for its saved tips),
  // so this resets on reload rather than introducing a new dependency for
  // a single flag.
  bool _sidebarCollapsed = false;

  /// User-friendly messages for streaming failures, keyed by the error
  /// codes shared with the backend SSE contract. No technical detail.
  static const _streamErrorMessages = <String, String>{
    'network':
        "Couldn't reach the server. Check your connection and try again.",
    'rate_limit':
        'The AI service is busy right now. Please wait a moment and try again.',
    'server_error':
        'The AI service is temporarily unavailable. Try again shortly.',
    'stream_interrupted': 'Response was interrupted.',
    'empty_response': 'No response received. Try rephrasing your question.',
    'auth_error': 'Your session may have expired. Please sign in again.',
  };

  // ── Conversation history state ──────────────────────────────────────────
  String? _conversationId; // null = new chat
  List<ConversationSummary> _conversations = [];
  bool _conversationsLoading = false;
  // True while _openConversation's getConversation() call is in flight —
  // drives the message-list skeleton so switching conversations shows
  // something immediately instead of a blank pane until messages arrive.
  bool _openingConversation = false;
  // Conversation ids mid-delete — kept in the list one more frame so the
  // fade+collapse animation has something to animate before it's gone.
  final Set<String> _deletingIds = {};
  // Conversation ids that just appeared from a silent refresh — their tile
  // plays a one-time fade + slide-down entrance, then the id is dropped.
  final Set<String> _justAddedIds = {};
  // Buffered-typewriter reveal timers, one per actively-streaming bubble
  // (see _startRevealTimer) — tracked here purely so dispose() can cancel
  // any still running if the screen closes mid-stream.
  final Set<Timer> _revealTimers = {};
  // Bumped on every conversation switch (open or "New Chat") so the message
  // list's AnimatedSwitcher key changes even between two blank "new chat"
  // states, which share the same (null) _conversationId.
  int _chatSwitchGen = 0;
  List<String> _suggestedFollowups = [];
  String? _selectedDistrict;
  String? _selectedCrop;
  String _selectedModel = 'accurate';

  /// The yield prediction this conversation is about, published by the yield
  /// screen through [predictionHandoff] when the farmer taps "Ask AI about
  /// this".
  ///
  /// HOW IT PERSISTS FOR FOLLOW-UPS: it lives here, in the screen's state, for
  /// the whole lifetime of the conversation — every ChatRequest built while it
  /// is non-null carries it, not just the first. So a farmer who taps
  /// "Explain this prediction" and then types "and what about fertiliser?"
  /// still has the AI grounded in the same numbers. It is cleared only when
  /// the conversation ends: "New Chat" (_startNewChat) or opening a different
  /// conversation from the sidebar (_openConversation).
  PredictionContext? _predictionCtx;

  // Saved profile context — used only to personalize the empty state (starter
  // cards + welcome subtitle). The backend applies saved context to answers.
  String? _savedDistrict;
  String? _savedCrop;

  final List<String> _districts = [
    'Nuwara Eliya',
    'Badulla',
    'Anuradhapura',
    'Monaragala',
    'Ampara',
    'Hambantota',
    'Batticaloa',
    'Jaffna',
  ];
  final List<String> _crops = [
    'Carrot',
    'Maize',
    'Green gram',
    'Cowpea',
    'Finger millet',
    'Groundnut',
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    predictionHandoff.addListener(_onPredictionHandoff);
    // A prediction can already be waiting when this screen first mounts (the
    // yield screen published one before the chat tab had ever been built).
    // Adopted by direct assignment, NOT through _onPredictionHandoff: there
    // is no conversation to reset yet, and setState() must not run inside
    // initState.
    final pending = predictionHandoff.value;
    if (pending != null) {
      predictionHandoff.value = null;
      _predictionCtx = pending.context;
      _sendHandoffQuestion(pending.question);
    }
    if (!AppConfig.useMockServices) {
      _loadConversations();
      _loadSavedPreferences();
    }
  }

  /// Picks up a prediction published by the yield screen: opens a FRESH
  /// conversation for it, then holds the context for that conversation's
  /// lifetime.
  ///
  /// Consume-once — the channel is reset to null immediately, so returning to
  /// the chat tab later doesn't replay a stale prediction into a new
  /// conversation. _startNewChat() clears `_predictionCtx`, so the assignment
  /// has to come after it.
  void _onPredictionHandoff() {
    final handoff = predictionHandoff.value;
    if (handoff == null) return;
    // Cleared BEFORE any work. Assigning here re-enters this listener
    // synchronously, and that re-entrant call must find null and return
    // immediately rather than handling the same prediction twice.
    predictionHandoff.value = null;
    if (!mounted) return;
    _startNewChat();
    setState(() => _predictionCtx = handoff.context);
    _sendHandoffQuestion(handoff.question);
  }

  /// Sends the question the farmer already picked on the yield result card.
  ///
  /// Deferred to after the frame: this runs from initState on a cold open,
  /// and from inside a setState-bearing handler otherwise, so _sendMessage's
  /// own setState must not land mid-build. By the time it fires,
  /// `_predictionCtx` is set, so the very first request already carries the
  /// prediction.
  void _sendHandoffQuestion(String? question) {
    if (question == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sendMessage(question);
    });
  }

  /// Gives the message list a brand-new ScrollController on every
  /// conversation switch.
  ///
  /// BUG FIX: the message list's AnimatedSwitcher crossfade (from earlier
  /// work) keeps the outgoing conversation's ListView mounted for ~150ms
  /// while the incoming one fades in. Both used to share one
  /// `_scrollController`, so for that window the controller had two
  /// attached ScrollPositions at once; the outgoing list's leftover scroll
  /// offset (in pixels) then got inherited as the incoming list's starting
  /// position, landing partway down a longer conversation instead of at
  /// its bottom — reading as "opens to the middle". A fresh controller per
  /// switch means the two lists never share state; the old one is disposed
  /// only after the crossfade has had time to fully unmount it.
  void _swapScrollController() {
    final old = _scrollController;
    old.removeListener(_handleScroll);
    _scrollController = ScrollController()..addListener(_handleScroll);
    Future.delayed(const Duration(milliseconds: 200), old.dispose);
  }

  /// Tracks how far the user has scrolled from the bottom of the message
  /// list, toggling the floating "scroll to bottom" button. Also driven
  /// (via `_scrollToBottom`) whenever new content changes the scroll extent
  /// without the user themselves scrolling.
  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final show = position.maxScrollExtent - position.pixels > 120;
    if (show != _showScrollToBottom) {
      setState(() => _showScrollToBottom = show);
    }
  }

  // Load the farmer's saved area/crop to personalize the empty state. Silent
  // best-effort — a failure just means generic starter cards.
  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = await ProfileService().getPreferences();
      if (!mounted) return;
      setState(() {
        _savedDistrict = prefs.preferredDistrict;
        _savedCrop = prefs.preferredCrop;
      });
    } catch (_) {
      /* personalization is optional */
    }
  }

  /// [silent] skips the loading flag — used for every refresh after the
  /// initial fetch (new conversation, rename, delete) so the sidebar never
  /// flashes back to the skeleton placeholder just to redraw one changed
  /// row. Only the very first load, with nothing on screen yet, shows it.
  Future<void> _loadConversations({bool silent = false}) async {
    if (!silent) setState(() => _conversationsLoading = true);
    try {
      final conversations = await _historyService.listConversations();
      if (mounted) setState(() => _conversations = conversations);
    } catch (e) {
      debugPrint('Failed to load conversations: $e');
    } finally {
      if (!silent && mounted) setState(() => _conversationsLoading = false);
    }
  }

  /// Refreshes the sidebar after a brand-new conversation is created,
  /// without the full-list flash a plain `_loadConversations()` would
  /// cause: fetches silently, then marks the new id so its tile plays a
  /// one-time fade + slide-down entrance instead of just appearing.
  Future<void> _refreshAfterNewConversation(String newConversationId) async {
    await _loadConversations(silent: true);
    if (!mounted) return;
    setState(() => _justAddedIds.add(newConversationId));
    // Must outlast the entrance animation's own 220ms — dropping the id
    // early would flip `isNew` to false mid-flight, aborting the
    // TweenAnimationBuilder and popping straight to its end state.
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) setState(() => _justAddedIds.remove(newConversationId));
    });
  }

  Future<void> _openConversation(ConversationSummary summary) async {
    // Close the drawer on mobile before loading.
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    setState(() => _openingConversation = true);
    try {
      final detail = await _historyService.getConversation(summary.id);
      if (!mounted) return;
      setState(() {
        _conversationId = detail.id;
        _displayMessages
          ..clear()
          ..addAll(
            detail.messages.map(
              (m) => {
                'role': m.role,
                'content': m.content,
                // BUG FIX: this was omitted entirely, so history-loaded
                // messages had no 'time' at all — msgTime == null disables
                // both tap AND hover in _buildMessageBubble, regardless of
                // any hover-wiring fix, since there's nothing to reveal.
                if (m.timestamp != null) 'time': m.timestamp,
              },
            ),
          );
        _history
          ..clear()
          ..addAll(
            detail.messages.map(
              (m) => ChatMessage(role: m.role, content: m.content),
            ),
          );
        _suggestedFollowups = [];
        // Stored conversations carry no prediction context — dropping it
        // stops an unrelated older chat inheriting the last prediction.
        _predictionCtx = null;
        _chatSwitchGen++;
        _swapScrollController();
      });
      // Opening a conversation should show its end immediately — no
      // animated scroll, just land on the true bottom (see
      // _swapScrollController for why a fresh controller is required here).
      _scrollToBottom(force: true, animate: false);
      // Restore this user's thumbs votes so feedback survives a reload.
      _restoreFeedback(detail.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load conversation')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingConversation = false);
    }
  }

  // Best-effort: pull the saved votes for this conversation and paint them
  // onto the matching bubbles. Failure is silent — the chat still works.
  Future<void> _restoreFeedback(String conversationId) async {
    if (AppConfig.useMockServices) return;
    try {
      final votes = await ServiceFactory.getService().getConversationFeedback(
        conversationId,
      );
      if (!mounted || votes.isEmpty) return;
      setState(() {
        for (var i = 0; i < _displayMessages.length; i++) {
          final vote = votes[i];
          if (vote != null) _displayMessages[i]['feedback'] = vote;
        }
      });
    } catch (_) {
      /* best-effort — reloaded chat still works without restored votes */
    }
  }

  void _startNewChat() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    setState(() {
      _conversationId = null;
      _displayMessages.clear();
      _history.clear();
      _suggestedFollowups = [];
      // A new conversation is not about the old prediction. The handoff path
      // re-sets this straight after calling us — see _onPredictionHandoff.
      _predictionCtx = null;
      _chatSwitchGen++;
      _swapScrollController();
    });
  }

  Future<void> _renameConversation(ConversationSummary summary) async {
    final controller = TextEditingController(text: summary.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename conversation'),
        content: TextField(
          controller: controller,
          maxLength: 100,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty || newTitle == summary.title) {
      return;
    }
    try {
      await _historyService.renameConversation(summary.id, newTitle);
      _loadConversations(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to rename conversation')),
        );
      }
    }
  }

  Future<void> _deleteConversation(ConversationSummary summary) async {
    // showGeneralDialog (rather than plain showDialog) so a transitionBuilder
    // can be supplied — Navigator drives the same AnimationController in
    // reverse on dismiss, so this one curve covers both the fade+scale-in on
    // appearance and the fade+scale-out on Cancel/Delete/tap-outside.
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, animation, secondaryAnimation) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text('"${summary.title}" will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
    if (confirmed != true) return;
    // Play the fade+collapse first, then actually delete — the tile stays
    // in _conversations (still fetchable) until the animation finishes, so
    // its removal never looks like an abrupt jump-cut.
    setState(() => _deletingIds.add(summary.id));
    await Future.delayed(const Duration(milliseconds: 200));
    try {
      await _historyService.deleteConversation(summary.id);
      if (summary.id == _conversationId) _startNewChat();
      // Silent — the fade+collapse above already resolved this tile's
      // removal; a loading flash here would undo that smoothness.
      await _loadConversations(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete conversation')),
        );
      }
    } finally {
      if (mounted) setState(() => _deletingIds.remove(summary.id));
    }
  }

  Future<void> _sendMessage(String message) async {
    if (_isLoading || _isStreaming) return; // never two concurrent requests
    if (message.trim().isEmpty) return;
    if (message.length > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message too long. Maximum 500 characters.'),
        ),
      );
      return;
    }
    if (AppConfig.useStreamingChat) {
      await _sendMessageStreaming(message);
    } else {
      await _sendMessageNonStreaming(message);
    }
  }

  /// Non-streaming fallback — the original POST /api/chat flow, kept
  /// intact and selected via AppConfig.useStreamingChat = false.
  ///
  /// [isRetry] skips re-adding the user bubble/history entry — used by
  /// "regenerate response" to re-run the last question without duplicating
  /// it in the transcript.
  Future<void> _sendMessageNonStreaming(
    String message, {
    bool isRetry = false,
  }) async {
    _controller.clear();
    setState(() {
      if (!isRetry) {
        _displayMessages.add({
          'role': 'user',
          'content': message,
          'time': DateTime.now(),
        });
        _history.add(ChatMessage(role: 'user', content: message));
      }
      _isLoading = true;
      _suggestedFollowups = [];
    });
    _scrollToBottom(force: true);

    try {
      final service = ServiceFactory.getService();
      final userId = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
      final response = await service.sendChat(
        ChatRequest(
          message: message,
          conversationHistory: _buildValidHistory(),
          userId: userId,
          district: _selectedDistrict,
          crop: _selectedCrop,
          model: _selectedModel,
          language: 'auto',
          conversationId: _conversationId,
          // Non-null for every turn of a prediction conversation, not just
          // the first — see _predictionCtx.
          predictionContext: _predictionCtx,
        ),
      );

      // A new chat gets its conversation id from the first reply — refresh
      // the sidebar so the new conversation appears immediately.
      final isNewConversation =
          _conversationId == null && response.conversationId.isNotEmpty;
      if (response.conversationId.isNotEmpty) {
        _conversationId = response.conversationId;
      }
      if (isNewConversation && !AppConfig.useMockServices) {
        _refreshAfterNewConversation(response.conversationId);
      }

      setState(() {
        _displayMessages.add({
          'role': 'assistant',
          'content': response.reply,
          'isMock': response.isMock,
          'confidence': response.confidence,
          'sources': response.sourcesUsed,
          'time': DateTime.now(),
        });
        _history.add(ChatMessage(role: 'assistant', content: response.reply));
        _suggestedFollowups = response.suggestedFollowups;
        // Keep last 10 turns
        if (_history.length > 20) {
          _history.removeRange(0, 2);
          _displayMessages.removeRange(0, 2);
        }
      });
    } catch (e) {
      setState(() {
        _displayMessages.add({
          'role': 'error',
          'content': 'Error: ${e.toString()}',
        });
      });
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
  }

  /// Streaming send path: adds an empty assistant bubble immediately, then
  /// appends SSE text deltas as they arrive. Metadata (confidence, sources,
  /// followups, conversation id) lands at the end of the stream. On failure
  /// the bubble keeps any partial text and gains an inline error + retry.
  ///
  /// [isRetry] skips re-adding the user bubble/history entry — the original
  /// send already added them, and _buildValidHistory() excludes the trailing
  /// user message, so the retried message is never duplicated in context.
  ///
  /// [reuseBubble] — used by regenerate/retry — resets an EXISTING bubble's
  /// fields in place instead of creating and inserting a new one.
  ///
  /// BUG FIX: this used to remove the old bubble and append a fresh one,
  /// which (a) briefly shrank the list before growing back, a content-
  /// height dip right as the scroll-to-bottom animation kicked in, and
  /// (b) gave the new bubble a different object identity, so its list
  /// item's Element (and everything under it — avatar, bubble container)
  /// unmounted and remounted. Reusing the same object/Element/key means
  /// there is no unmount at all — the "thinking" state can never render as
  /// anything other than the exact same bot-bubble structure a normal new
  /// message uses, because it *is* the same bubble, just with its fields
  /// reset.
  Future<void> _sendMessageStreaming(
    String message, {
    bool isRetry = false,
    Map<String, dynamic>? reuseBubble,
  }) async {
    if (_isStreaming) return; // guard: never two concurrent streams
    _controller.clear();
    final bubble = reuseBubble ?? <String, dynamic>{'role': 'assistant'};
    // _isStreaming is set synchronously, before any await, so the input
    // field is disabled for the whole stream — initial send and retry alike.
    setState(() {
      _isStreaming = true;
      if (!isRetry) {
        _displayMessages.add({
          'role': 'user',
          'content': message,
          'time': DateTime.now(),
        });
        _history.add(ChatMessage(role: 'user', content: message));
      }
      if (reuseBubble != null) {
        // Cancel any reveal timer left over from this bubble's previous
        // life before resetting it — see _startRevealTimer.
        (bubble['_revealTimer'] as Timer?)?.cancel();
      } else {
        _displayMessages.add(bubble);
      }
      bubble
        ..['content'] = ''
        ..['streaming'] = true
        ..['retryFor'] = message
        ..['time'] = DateTime.now()
        ..['_fadingOut'] = false
        // Marks this bubble as belonging to a real, active stream — the
        // one and only thing that lets it enter the reveal/typing state
        // (see the isLiveStream check in _buildMessageBubble). A history-
        // loaded message never gets this set.
        ..['_isLiveStream'] = true
        ..remove('confidence')
        ..remove('sources')
        ..remove('errorCode')
        ..remove('isMock')
        ..remove('_revealedLen')
        ..remove('_revealTimer');
      _suggestedFollowups = [];
    });
    _scrollToBottom(force: true);
    _startRevealTimer(bubble);

    final userId = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
    final request = ChatRequest(
      message: message,
      conversationHistory: _buildValidHistory(),
      userId: userId,
      district: _selectedDistrict,
      crop: _selectedCrop,
      model: _selectedModel,
      language: 'auto',
      conversationId: _conversationId,
      // Non-null for every turn of a prediction conversation, not just the
      // first — see _predictionCtx.
      predictionContext: _predictionCtx,
    );

    var completed = false;
    try {
      await for (final event in ServiceFactory.getService().sendChatStream(
        request,
      )) {
        switch (event['type']) {
          case 'text':
            setState(() {
              bubble['content'] =
                  (bubble['content'] as String) +
                  (event['content'] as String? ?? '');
            });
          // No scroll call here — network chunks arrive in bursty,
          // irregular batches, and animating to bottom on each one used to
          // restart an in-flight 400ms scroll animation before it settled,
          // reading as a stutter. The buffered reveal timer below now
          // owns auto-scroll: it advances on a steady 16ms tick that
          // matches what's actually growing on screen, and jumps rather
          // than animates while live so the view tracks the caret exactly
          // instead of chasing it in restarted bursts.
          case 'metadata':
            final convId = event['conversation_id'] as String? ?? '';
            final isNewConversation =
                _conversationId == null && convId.isNotEmpty;
            if (convId.isNotEmpty) _conversationId = convId;
            if (isNewConversation && !AppConfig.useMockServices) {
              _refreshAfterNewConversation(convId);
            }
            setState(() {
              bubble['confidence'] = event['confidence'] as String? ?? '';
              bubble['sources'] = List<String>.from(event['sources'] ?? []);
              // The model appends its follow-up suggestions as "FOLLOWUP:"
              // lines at the very end of the answer, so they stream into the
              // bubble as ordinary text before the server can strip them.
              // Metadata arrives once the stream is complete — replace the
              // bubble with the clean text here. The server already strips
              // them from what it persists, so this only fixes the live view.
              bubble['content'] = _stripFollowupMarkers(
                bubble['content'] as String? ?? '',
              );
              _suggestedFollowups = List<String>.from(
                event['suggested_followups'] ?? [],
              );
            });
          case 'error':
            setState(() {
              bubble['errorCode'] = event['code'] as String? ?? 'server_error';
              // A failed stream never reaches metadata, so clean the partial
              // text here too — the farmer must never be left looking at a
              // raw "FOLLOWUP:" line.
              bubble['content'] = _stripFollowupMarkers(
                bubble['content'] as String? ?? '',
              );
            });
          case 'done':
            completed = true;
        }
      }
    } catch (_) {
      setState(() {
        bubble['errorCode'] ??= 'stream_interrupted';
      });
    } finally {
      setState(() {
        bubble['streaming'] = false;
        if (!completed && bubble['errorCode'] == null) {
          // Stream ended without [DONE] or an explicit error event.
          bubble['errorCode'] = 'stream_interrupted';
        }
        if (completed && bubble['errorCode'] == null) {
          _history.add(
            ChatMessage(
              role: 'assistant',
              content: bubble['content'] as String,
            ),
          );
          // Keep last 10 turns
          if (_history.length > 20) {
            _history.removeRange(0, 2);
            _displayMessages.removeRange(0, 2);
          }
        }
        _isStreaming = false;
      });
      _scrollToBottom();
    }
  }

  /// Removes a failed streamed bubble and resends its user message.
  /// _sendMessageStreaming sets _isStreaming synchronously, so the input
  /// stays disabled and a second concurrent stream is impossible.
  Future<void> _retryStream(Map<String, dynamic> bubble) async {
    if (_isStreaming || _isLoading) return;
    final retryFor = bubble['retryFor'] as String?;
    if (retryFor == null) return;
    // Fade the failed bubble out, then reuse this exact object for the
    // fresh stream (see _sendMessageStreaming's [reuseBubble] doc) — its
    // AnimatedOpacity fades back to 1 once the reset lands, showing the
    // same bubble's thinking dots rather than a new/different one.
    setState(() => bubble['_fadingOut'] = true);
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await _sendMessageStreaming(retryFor, isRetry: true, reuseBubble: bubble);
  }

  /// "Regenerate response" — re-asks the question behind the given (last,
  /// completed) bot answer and replaces it with a fresh one, without
  /// duplicating the question bubble or its history entry.
  Future<void> _regenerateResponse(int index) async {
    if (_isStreaming || _isLoading) return;
    final question = _questionForAnswer(index);
    if (question.isEmpty) return;
    final msg = _displayMessages[index];
    // See _retryStream — same fade-out, then swap the new "thinking"
    // placeholder into this exact slot (no separate remove+append dip).
    setState(() => msg['_fadingOut'] = true);
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    if (_history.isNotEmpty && _history.last.role == 'assistant') {
      setState(() => _history.removeLast());
    }
    if (AppConfig.useStreamingChat) {
      await _sendMessageStreaming(question, isRetry: true, reuseBubble: msg);
    } else {
      // Non-streaming has no "thinking placeholder" bubble concept — the
      // full reply only appears once it arrives — so there's nothing to
      // swap in place; fall back to removing the old answer first.
      setState(() => _displayMessages.remove(msg));
      await _sendMessageNonStreaming(question, isRetry: true);
    }
  }

  /// Copies a bot answer's plain text to the clipboard (reasoning line
  /// excluded, matching what's visible as the "main" answer). Flips the
  /// message's own '_copied' flag on for 1.5s so its copy icon can swap to
  /// a checkmark, then reverts.
  ///
  /// BUG FIX: a second tap while the checkmark from a first tap was still
  /// showing used to get cut short — the first tap's revert timer fired
  /// regardless and flipped '_copied' back to false mid-way through the
  /// second tap's own 1.5s window. Each tap now stamps a token; a timer
  /// only reverts the flag if it's still the most recent tap's timer.
  ///
  /// BUG FIX: this used to ALSO show a SnackBar alongside the in-button
  /// checkmark swap — two confirmations firing for one action, competing
  /// for attention. The checkmark alone is the confirmation now.
  void _copyMessage(Map<String, dynamic> msg) {
    final content = msg['content'] as String? ?? '';
    final parsed = _parseReply(content);
    final text = parsed.answer.isNotEmpty ? parsed.answer : content;
    Clipboard.setData(ClipboardData(text: text));
    final token = (msg['_copyToken'] as int? ?? 0) + 1;
    msg['_copyToken'] = token;
    setState(() => msg['_copied'] = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted && msg['_copyToken'] == token) {
        setState(() => msg['_copied'] = false);
      }
    });
  }

  /// Removes the model's "FOLLOWUP:" suggestion lines from streamed text.
  ///
  /// The suggestions are an internal protocol between the prompt and the
  /// backend parser (see chatbot_service._parse_followups_from_response) — they
  /// arrive at the tail of the stream and become the chips in the metadata
  /// event. They must never remain visible as answer text. The backend already
  /// strips them from the persisted copy; this cleans the live bubble.
  String _stripFollowupMarkers(String text) {
    if (!text.contains('FOLLOWUP:')) return text;
    return text
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('FOLLOWUP:'))
        .join('\n')
        .trimRight();
  }

  /// Buffered, fixed-pace "typewriter" reveal for a streaming bubble.
  ///
  /// The network/SSE layer is completely untouched — `bubble['content']`
  /// still fills in as fast as chunks arrive. This timer separately tracks
  /// how much of that content has actually been REVEALED on screen
  /// (`bubble['_revealedLen']`), advancing it by a small, fixed amount on a
  /// steady tick regardless of how bursty the network delivery is. If the
  /// reveal catches up to content that's already arrived, it simply idles
  /// (no error, no state change) until either more text lands or the
  /// stream finishes; once both the network is done AND the reveal has
  /// caught up to the final text, the timer stops itself. Restarted (via
  /// [reuseBubble] regenerate/retry) resets from an empty buffer.
  void _startRevealTimer(Map<String, dynamic> bubble) {
    const tickInterval = Duration(milliseconds: 16);
    const charsPerTick = 5; // ≈310 chars/sec — brisk, readable "typing"
    late final Timer timer;
    timer = Timer.periodic(tickInterval, (_) {
      if (!mounted) {
        timer.cancel();
        _revealTimers.remove(timer);
        return;
      }
      final content = bubble['content'] as String? ?? '';
      final revealedLen = bubble['_revealedLen'] as int? ?? 0;
      final networkDone = bubble['streaming'] != true;
      if (revealedLen < content.length) {
        setState(() {
          bubble['_revealedLen'] = (revealedLen + charsPerTick).clamp(
            0,
            content.length,
          );
        });
        // Auto-scroll paced to the same 16ms tick that grows the bubble, so
        // the view tracks the caret smoothly instead of chasing it in
        // restarted animateTo bursts (see the removed per-chunk call above).
        // A plain jump, not an animation — at this cadence an eased
        // animateTo would just be restarting itself every frame.
        _scrollToBottom(animate: false);
      } else if (networkDone) {
        // Caught up AND the network is finished — nothing left to type.
        timer.cancel();
        _revealTimers.remove(timer);
        bubble.remove('_revealTimer');
      }
      // else: caught up but the network is still sending — idle this tick,
      // a natural pause rather than any kind of error/stuck state.
    });
    bubble['_revealTimer'] = timer;
    _revealTimers.add(timer);
  }

  /// [force] jumps to the bottom unconditionally — used right after the
  /// user's own send, and when opening a conversation, so they always see
  /// what they just did. Without it, this only scrolls if the user is
  /// already near the bottom (streaming deltas, the final response landing,
  /// etc.) — never yanking them back down if they've scrolled up to read
  /// something earlier; `_handleScroll` still runs so the floating
  /// "scroll to bottom" button appears instead.
  ///
  /// [animate] set to false makes it an instant jump rather than an
  /// animated scroll — used when opening a conversation, which should show
  /// its end right away, not visibly scroll there.
  void _scrollToBottom({bool force = false, bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      final nearBottom = position.maxScrollExtent - position.pixels < 120;
      // userScrollDirection reflects an active user drag specifically — it
      // never gets set by our own animateTo/jumpTo below (those go through
      // a programmatic scroll activity, not a drag one) — so this only
      // ever defers to a real in-progress user gesture, not our own
      // previous auto-scroll.
      final userScrolling =
          position.userScrollDirection != ScrollDirection.idle;
      if (!force && (!nearBottom || userScrolling)) {
        _handleScroll();
        return;
      }
      if (animate) {
        _scrollController.animateTo(
          position.maxScrollExtent,
          // Long enough for the motion to actually read as a scroll, not
          // an abrupt jump — same easeOutCubic, just slower.
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    for (final timer in _revealTimers) {
      timer.cancel();
    }
    _scrollController.removeListener(_handleScroll);
    predictionHandoff.removeListener(_onPredictionHandoff);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= _wideBreakpoint;
    final chatArea = Column(
      children: [
        _buildHeader(isWide),
        _buildContextBar(),
        Expanded(
          child: Stack(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeOut,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                // Keyed by switch generation (not conversation id) so two
                // separate "New Chat" taps — which share the same null id —
                // still trigger a fresh transition instead of no-op-ing.
                child: KeyedSubtree(
                  key: ValueKey(_chatSwitchGen),
                  child: _buildMessageList(),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 16,
                child: _buildScrollToBottomButton(),
              ),
            ],
          ),
        ),
        if (_suggestedFollowups.isNotEmpty) _buildSuggestions(),
        _buildInputBar(),
      ],
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.background,
      drawer: isWide ? null : Drawer(child: SafeArea(child: _buildSidebar())),
      body: isWide
          ? Row(
              children: [
                // ClipRect + OverflowBox: the sidebar's own content stays
                // pinned at its natural 280px width throughout — only the
                // AnimatedContainer's width (and the clip) actually
                // animates — so collapsing reads as a clean slide, not a
                // squeeze/reflow of the conversation list.
                ClipRect(
                  child: AnimatedContainer(
                    // A larger layout change than the small UI animations
                    // elsewhere, so it gets a slower duration; easeInOutCubic
                    // (steeper ease in and out than the default easeInOut
                    // curve) reads as a more deliberate, natural slide
                    // rather than a mechanical linear-ish width change.
                    duration: const Duration(milliseconds: 340),
                    curve: Curves.easeInOutCubic,
                    width: _sidebarCollapsed ? 0 : 280,
                    child: OverflowBox(
                      minWidth: 0,
                      maxWidth: 280,
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 280,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border(
                              right: BorderSide(color: Colors.grey[300]!),
                            ),
                          ),
                          // Content fades noticeably faster (150ms) than the
                          // 340ms width animation: collapsing, it's already
                          // gone before the clip narrows enough to visibly
                          // cut through any text; expanding, it's already
                          // legible well before the panel finishes opening
                          // rather than looking "squished" while still
                          // catching up mid-width.
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 150),
                            curve: Curves.easeOut,
                            opacity: _sidebarCollapsed ? 0 : 1,
                            child: _buildSidebar(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(child: chatArea),
              ],
            )
          : chatArea,
    );
  }

  // ── Sidebar ───────────────────────────────────────────────────────────────

  Widget _buildSidebar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            onPressed: _startNewChat,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Chat'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _conversationsLoading
              ? _buildSidebarSkeleton()
              : _conversations.isEmpty
              ? _buildSidebarEmptyState()
              : _buildGroupedConversationList(),
        ),
      ],
    );
  }

  /// Buckets conversations into "Today"/"Yesterday"/"This week"/"Older" by
  /// local calendar day. The input is already newest-first from the API, so
  /// each bucket comes out newest-first too — no re-sort needed. Iteration
  /// order over this map is insertion order, and entries are always
  /// inserted Today → Yesterday → This week → Older, so callers can rely on
  /// that group ordering directly.
  Map<String, List<ConversationSummary>> _groupConversationsByDate() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final groups = <String, List<ConversationSummary>>{
      'Today': [],
      'Yesterday': [],
      'This week': [],
      'Older': [],
    };
    for (final c in _conversations) {
      final updated = c.updatedAt?.toLocal();
      if (updated == null) {
        groups['Older']!.add(c);
        continue;
      }
      final day = DateTime(updated.year, updated.month, updated.day);
      if (day == today) {
        groups['Today']!.add(c);
      } else if (day == yesterday) {
        groups['Yesterday']!.add(c);
      } else if (day.isAfter(weekAgo)) {
        groups['This week']!.add(c);
      } else {
        groups['Older']!.add(c);
      }
    }
    groups.removeWhere((_, items) => items.isEmpty);
    return groups;
  }

  Widget _buildGroupedConversationList() {
    final groups = _groupConversationsByDate();
    final flatItems = <Object>[]; // section-header String or a summary
    for (final entry in groups.entries) {
      flatItems.add(entry.key);
      flatItems.addAll(entry.value);
    }
    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      itemCount: flatItems.length,
      itemBuilder: (ctx, i) {
        final item = flatItems[i];
        // Keyed by id (not index) so a tile's in-flight delete/insert
        // animation state stays attached to the right conversation across
        // list mutations, the same reasoning as the message list's
        // ObjectKey below.
        if (item is String) {
          return KeyedSubtree(
            key: ValueKey('header-$item'),
            child: _sectionHeader(item),
          );
        }
        final summary = item as ConversationSummary;
        return KeyedSubtree(
          key: ValueKey(summary.id),
          child: _animatedConversationTile(summary),
        );
      },
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.textMuted,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  /// Fades + collapses a conversation tile out when it's mid-delete, instead
  /// of letting it disappear instantly on the next list refresh. A tile
  /// that just arrived from `_refreshAfterNewConversation` instead plays a
  /// one-time fade + slide-down entrance (opposite direction of the delete
  /// collapse) — `_justAddedIds` drops the id once that's played once, so
  /// later rebuilds (e.g. from streaming elsewhere) render it plainly.
  Widget _animatedConversationTile(ConversationSummary summary) {
    final isDeleting = _deletingIds.contains(summary.id);
    final isNew = _justAddedIds.contains(summary.id);
    final tile = AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        opacity: isDeleting ? 0 : 1,
        child: isDeleting
            ? const SizedBox(width: double.infinity)
            : _buildConversationTile(summary),
      ),
    );
    if (!isNew) return tile;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      // easeOutCubic decelerates more naturally than the plain linear-ish
      // easeOut — fast start, gentle settle, reads as one continuous motion
      // rather than the fade and slide feeling like two separate things
      // (they're still driven off the one `t`, so they're always in sync;
      // the curve is what was making that sync feel abrupt).
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * -8),
          child: child,
        ),
      ),
      child: tile,
    );
  }

  /// Skeleton placeholder rows shown during the initial conversation fetch —
  /// replaces the old bare spinner so the sidebar shape is visible right
  /// away. Staggered pattern: rows fade/slide in one after another instead
  /// of all appearing at once, which reads better for list content than a
  /// flat block-level pulse.
  Widget _buildSidebarSkeleton() {
    return StaggeredSkeletonList(
      itemCount: 5,
      itemBuilder: (context, i) => _skeletonRow(),
    );
  }

  Widget _skeletonRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: AppTheme.textMuted.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppTheme.textMuted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 8,
                  width: 60,
                  decoration: BoxDecoration(
                    color: AppTheme.textMuted.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 40,
              color: AppTheme.textMuted.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 12),
            Text(
              AppConfig.useMockServices
                  ? 'History unavailable in mock mode'
                  : 'Your conversations will appear here',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationTile(ConversationSummary summary) {
    final isActive = summary.id == _conversationId;
    return ListTile(
      dense: true,
      selected: isActive,
      selectedTileColor: AppTheme.primary.withValues(alpha: 0.08),
      leading: Icon(
        Icons.chat_bubble_outline,
        size: 18,
        color: isActive ? AppTheme.primary : Colors.grey[500],
      ),
      title: Text(
        summary.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          color: isActive ? AppTheme.primaryDark : Colors.black87,
        ),
      ),
      subtitle: Text(
        _relativeTime(summary.updatedAt),
        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
      ),
      // Hover menu on web/desktop, long-press menu on mobile.
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_vert, size: 16, color: Colors.grey[500]),
        onSelected: (action) => action == 'rename'
            ? _renameConversation(summary)
            : _deleteConversation(summary),
        itemBuilder: (ctx) => const [
          PopupMenuItem(
            value: 'rename',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.edit_outlined, size: 18),
              title: Text('Rename'),
            ),
          ),
          PopupMenuItem(
            value: 'delete',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.delete_outline, size: 18),
              title: Text('Delete'),
            ),
          ),
        ],
      ),
      onTap: () => _openConversation(summary),
      onLongPress: () => _showConversationActions(summary),
    );
  }

  void _showConversationActions(ConversationSummary summary) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                _renameConversation(summary);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppTheme.error),
              title: const Text(
                'Delete',
                style: TextStyle(color: AppTheme.error),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _deleteConversation(summary);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime? time) {
    if (time == null) return '';
    final diff = DateTime.now().difference(time.toLocal());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${time.toLocal().day}/${time.toLocal().month}/${time.toLocal().year}';
  }

  /// "HH:MM" clock time for the tap-to-reveal timestamp under a bubble
  /// (relative time reads better in the sidebar list; a specific message
  /// benefits from the exact time it was sent/received).
  String _formatClockTime(DateTime time) {
    final local = time.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _buildHeader(bool isWide) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primary, AppTheme.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          if (!isWide)
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              tooltip: 'Conversations',
              padding: EdgeInsets.zero,
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            )
          else
            IconButton(
              icon: Icon(
                _sidebarCollapsed ? Icons.menu : Icons.menu_open,
                color: Colors.white,
              ),
              tooltip: _sidebarCollapsed
                  ? 'Show conversations'
                  : 'Hide conversations',
              padding: EdgeInsets.zero,
              onPressed: () =>
                  setState(() => _sidebarCollapsed = !_sidebarCollapsed),
            ),
          _logo(28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CropSphere AI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                AppConfig.useMockServices
                    ? 'Mock Mode · LLaMA 3 + RAG'
                    : 'Live · LLaMA 3 + RAG',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (_displayMessages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white70),
              tooltip: 'Clear chat',
              onPressed: _startNewChat,
            ),
          const SizedBox(width: 4),
          // Chat's top bar is the one screen that never had a language
          // switcher — added here too for a consistent cluster across all
          // 7 screens. White icon to read against this bar's dark gradient.
          const LanguageControl(),
          const SizedBox(width: 8),
          const ThemeToggleButton(color: Colors.white),
          const SizedBox(width: 8),
          const ProfileAvatarButton(diameter: 32),
        ],
      ),
    );
  }

  Widget _buildContextBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.background,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text(
              'Context:',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(width: 8),
            _buildContextChip(
              'District',
              _selectedDistrict,
              _districts,
              (v) => setState(() => _selectedDistrict = v),
            ),
            const SizedBox(width: 8),
            _buildContextChip(
              'Crop',
              _selectedCrop,
              _crops,
              (v) => setState(() => _selectedCrop = v),
            ),
            const SizedBox(width: 8),
            _buildModelToggle(),
          ],
        ),
      ),
    );
  }

  Widget _buildContextChip(
    String label,
    String? selected,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return GestureDetector(
      onTap: () async {
        final result = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text('Select $label'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, null),
                child: Text('Any $label'),
              ),
              ...options.map(
                (o) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, o),
                  child: Text(o),
                ),
              ),
            ],
          ),
        );
        onChanged(result);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected != null
              ? AppTheme.primary.withValues(alpha: 0.1)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected != null ? AppTheme.primary : AppTheme.textMuted,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected ?? label,
              style: TextStyle(
                fontSize: 12,
                color: selected != null
                    ? AppTheme.primary
                    : AppTheme.textSecondary,
                fontWeight: selected != null
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: selected != null ? AppTheme.primary : AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.textMuted),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModelOption('fast', '⚡ Fast'),
          _buildModelOption('accurate', '🎯 Accurate'),
        ],
      ),
    );
  }

  Widget _buildModelOption(String value, String label) {
    final isSelected = _selectedModel == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedModel = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: isSelected ? Border.all(color: AppTheme.primary) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    if (_openingConversation) {
      return _buildMessageListSkeleton();
    }
    if (_displayMessages.isEmpty) {
      final ctx = _predictionCtx;
      return ctx != null
          ? _buildPredictionEmptyState(ctx)
          : _buildEmptyState();
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      // No overscroll bounce/glow — clamps at the edges. This is a
      // web-first app; bounce is an iOS-specific affectation that reads as
      // slightly "off" on desktop/web, and clamping is the more neutral,
      // professional convention there (and on Android).
      physics: const ClampingScrollPhysics(),
      itemCount: _displayMessages.length + (_isLoading ? 1 : 0),
      // A few screens' worth of extra cache above/below the viewport so
      // scrolling through a long conversation doesn't constantly tear down
      // and rebuild (re-parsing each bubble's markdown) items right at the
      // viewport edge. Bubbles are variable-height (markdown, XAI footer,
      // sources), so a fixed itemExtent isn't an option here.
      cacheExtent: 800,
      itemBuilder: (ctx, i) {
        if (i == _displayMessages.length) return _buildTypingIndicator();
        final msg = _displayMessages[i];
        // ObjectKey(msg) — msg's own identity — keeps each bubble's Element
        // (and its in-flight _fadingOut/_copied/_showTime/_hovering state)
        // correctly associated with the right message across list
        // mutations like regenerate/retry (remove one, append another),
        // rather than Flutter reusing the Element at that index for
        // whatever message now happens to sit there. RepaintBoundary keeps
        // one bubble's repaints (e.g. the streaming caret) from forcing its
        // neighbors to repaint too.
        return RepaintBoundary(
          key: ObjectKey(msg),
          child: _entranceAnimate(msg, _buildMessageBubble(msg, i)),
        );
      },
    );
  }

  /// Shown while `_openConversation` is fetching the selected conversation's
  /// messages — alternating user/assistant bubble shapes so the pane's
  /// eventual layout is recognisable immediately, instead of staying blank
  /// until the request resolves. Staggered pattern: each row fades/slides in
  /// with a short delay after the last, then breathes in place.
  Widget _buildMessageListSkeleton() {
    return StaggeredSkeletonList(
      itemCount: 6,
      physics: const ClampingScrollPhysics(),
      itemBuilder: (context, i) {
        final isUser = i.isOdd;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Align(
            alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: isUser ? 220 : 320),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.textMuted.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 10, width: isUser ? 160 : 280),
                    const SizedBox(height: 8),
                    SkeletonBox(height: 10, width: isUser ? 100 : 220),
                    if (!isUser) ...[
                      const SizedBox(height: 8),
                      const SkeletonBox(height: 10, width: 140),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Minimal, one-time fade + slight rise for a newly-appended bubble —
  /// signals "a new turn happened" without drawing attention to itself.
  /// Marks the message as already-animated on its own data so scrolling
  /// back up through history never replays it.
  Widget _entranceAnimate(Map<String, dynamic> msg, Widget child) {
    if (msg['_entered'] == true) return child;
    msg['_entered'] = true;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      builder: (context, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: c),
      ),
      child: child,
    );
  }

  /// Small floating "scroll to bottom" affordance — only ever an offer, per
  /// [_scrollToBottom]'s non-force path never yanking the user down on its
  /// own. Fades in/out rather than popping so it doesn't grab attention.
  Widget _buildScrollToBottomButton() {
    return IgnorePointer(
      ignoring: !_showScrollToBottom,
      child: AnimatedOpacity(
        opacity: _showScrollToBottom ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Material(
          color: AppTheme.primary,
          shape: const CircleBorder(),
          elevation: 3,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _scrollToBottom(force: true),
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.arrow_downward, size: 18, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  /// CropSphere logo, used at every size across the screen (header, bot
  /// avatar, empty-state badge). ClipOval trims the source PNG's thin
  /// square margin around the circle so no white corner/edge shows once
  /// it's placed on a non-white background (e.g. the header gradient).
  Widget _logo(double size) {
    return ClipOval(
      child: Image.asset(
        _logoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }

  /// Modern centered empty state shown when a conversation has no messages
  /// yet (fresh launch or "New Chat") — replaces the old placeholder text
  /// and welcome bubble. Tapping a starter card sends it exactly like a
  /// followup chip tap; the bottom chip row stays hidden the whole time
  /// since _suggestedFollowups is empty until a real response arrives.
  // Starter prompts, personalized to the saved area/crop when we have them.
  List<String> get _starterPrompts {
    final d = _savedDistrict;
    if (d == null || d.isEmpty) return _onboardingFollowups;
    final c = _savedCrop ?? 'Carrot';
    return [
      '$c yield in $d',
      'Best season for $c in $d',
      'What crops do you cover?',
    ];
  }

  /// Shown when the farmer arrived from a yield prediction via the free-form
  /// "Ask something else about this" button, i.e. without having picked a
  /// question yet.
  ///
  /// It carries NO starter chips: the four quick questions live on the yield
  /// result card now, and tapping one there is auto-sent on arrival — so this
  /// state is only ever reached when the farmer wants to type their own.
  Widget _buildPredictionEmptyState(PredictionContext ctx) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const GrowthLogo(progress: 1.0, size: 72),
              const SizedBox(height: 16),
              Text(
                'About your yield prediction',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
              if (ctx.summary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    ctx.summary,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'Ask anything about it — I have your crop, district, '
                'season, area and weather.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppTheme.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Fully-bloomed GrowthLogo (progress: 1.0) instead of the
              // static PNG — visual consistency with the launch animation,
              // same 72px size as the old _logo(72) call. _logo() itself
              // (used elsewhere for small avatar-style logos in bubbles/
              // header) is untouched.
              const GrowthLogo(progress: 1.0, size: 72),
              const SizedBox(height: 16),
              Text(
                'CropSphere',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Ask about crops, yields, and prices for Sri Lankan '
                  'agriculture',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              if (_savedDistrict != null && _savedDistrict!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Welcome back! Your area: ${_savedDistrict!}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              for (var i = 0; i < _starterPrompts.length; i++) ...[
                _buildStarterCard(_starterIcons[i], _starterPrompts[i]),
                if (i < _starterPrompts.length - 1) const SizedBox(height: 9),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStarterCard(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => _sendMessage(text),
        child: Container(
          width: double.infinity,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.background),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Blocks automatic image fetches triggered by markdown `![alt](url)`
  /// syntax in bot-authored text (answers, reasoning/sources/advisory).
  /// That text originates from the backend/LLM, so an embedded image URL
  /// (e.g. via prompt injection or a compromised RAG source) would
  /// otherwise be fetched automatically as a NetworkImage — a
  /// tracking-pixel / data-exfiltration vector. Rendered as a small inline
  /// placeholder instead; no request is ever made for `uri`.
  static Widget _blockedImageBuilder(Uri uri, String? title, String? alt) {
    return Tooltip(
      message: alt?.isNotEmpty == true ? alt! : 'Image blocked',
      child: const Icon(
        Icons.broken_image_outlined,
        size: 16,
        color: Colors.grey,
      ),
    );
  }

  static final _answerStyleSheet = MarkdownStyleSheet(
    p: TextStyle(color: Colors.black87, fontSize: 14),
    strong: TextStyle(
      color: Colors.black87,
      fontSize: 14,
      fontWeight: FontWeight.w700,
    ),
    listBullet: TextStyle(color: Colors.black87, fontSize: 14),
  );

  /// Renders a bot answer's body. Once revealing is done (or for a loaded
  /// history bubble), it's just the plain markdown text. While the
  /// buffered typewriter reveal (`_startRevealTimer`) is still catching
  /// up, only the revealed prefix of the text is shown — network delivery
  /// speed plays no part here, `_revealedLen` is the only thing this reads.
  Widget _buildAnswerBody(
    Map<String, dynamic> msg,
    _ParsedReply parsed,
    bool isRevealing,
  ) {
    if (!isRevealing) {
      return MarkdownBody(
        data: parsed.answer,
        softLineBreak: true,
        styleSheet: _answerStyleSheet,
        imageBuilder: _blockedImageBuilder,
      );
    }
    final revealedLen = (msg['_revealedLen'] as int? ?? 0).clamp(
      0,
      parsed.answer.length,
    );
    final visible = parsed.answer.substring(0, revealedLen);
    // The caret now sits inline right after the last typed character (a
    // WidgetSpan in the same text flow) instead of on its own line below
    // the text — it moves WITH the typing position, wrapping onto whatever
    // line the text itself is currently on. Trade-off: while actively
    // revealing, markdown (**bold**, lists) shows as literal characters —
    // Text.rich can't easily track "end of the last MarkdownBody line" the
    // way a plain text flow can. It settles into fully-parsed markdown the
    // instant revealing finishes (the `!isRevealing` branch above).
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: visible,
            style: const TextStyle(color: Colors.black87, fontSize: 14),
          ),
          const WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.only(left: 2),
              child: _BlinkingCursor(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, int index) {
    final isUser = msg['role'] == 'user';
    final isError = msg['role'] == 'error';
    final isMock = msg['isMock'] as bool? ?? false;

    // XAI data — bot replies only; user and error bubbles are unchanged.
    // Messages loaded from saved history have no 'confidence'/'sources' keys
    // and gracefully render without badge/footer.
    final isBot = !isUser && !isError;
    final isStreamingMsg = isBot && (msg['streaming'] as bool? ?? false);
    // CRITICAL BUG FIX: a message loaded from history has no '_revealedLen'
    // (defaults to 0) but DOES have its full content already — so
    // `revealedLen < contentLen` (0 < however-long-the-answer-is) was
    // ALWAYS true, and with no reveal timer ever running for it (one is
    // only ever started by _sendMessageStreaming), `_revealedLen` could
    // never advance. isRevealing was permanently stuck true, so
    // _buildAnswerBody kept rendering an empty substring — just the
    // blinking cursor, forever, even after a refresh.
    //
    // '_isLiveStream' is the explicit fix: only _sendMessageStreaming ever
    // sets it, on bubbles it actually creates/reuses for a real live
    // stream. History-loaded messages never have it, so they can never
    // enter the reveal state at all, regardless of any length math —
    // they render their full text instantly, unconditionally.
    final isLiveStream = msg['_isLiveStream'] == true;
    // True while the network is still sending OR the buffered typewriter
    // reveal (_startRevealTimer) hasn't yet caught up to everything that's
    // arrived — the bubble stays in its "still coming in" visual state
    // (dots/cursor, no badge/footer/actions yet) until the LAST character
    // has actually been typed out, not just received. Never true for a
    // history-loaded message (see isLiveStream above).
    final revealedLen = msg['_revealedLen'] as int? ?? 0;
    final contentLen = isBot ? (msg['content'] as String? ?? '').length : 0;
    final isRevealing =
        isBot && isLiveStream && (isStreamingMsg || revealedLen < contentLen);
    // Streamed bubbles get a fade-in on badge/footer when metadata lands;
    // regular history bubbles render statically (no re-fade on scroll).
    final wasStreamed = isBot && msg.containsKey('streaming');
    final errorCode = isBot ? msg['errorCode'] as String? : null;
    final confidence = isBot ? (msg['confidence'] as String? ?? '') : '';
    final sources = isBot
        ? ((msg['sources'] as List?)?.cast<String>() ?? const <String>[])
        : const <String>[];
    // While still revealing, show the text raw — the reasoning line is
    // split into the footer only once the full answer is visible, not just
    // once the network is done (metadata can arrive slightly before the
    // typewriter has caught up).
    final parsed = isBot && !isRevealing
        ? _parseReply(msg['content'] as String)
        : _ParsedReply('', msg['content'] as String);
    // Backend's Low-confidence label carries an advisory after the em dash
    // ("please verify with an agricultural officer") — badge shows the short
    // label, the advisory moves to the muted footer.
    final advisory = confidence.contains('—')
        ? confidence.split('—').last.trim()
        : '';
    final hasFooter =
        parsed.reasoning.isNotEmpty ||
        sources.isNotEmpty ||
        advisory.isNotEmpty;
    // Tap a bubble to reveal the hover row (timestamp + actions) — kept
    // off by default so the transcript stays uncluttered. Stored on the
    // message itself so it survives rebuilds without extra top-level
    // state. MouseRegion (wired above, unconditionally) does the same for
    // an actual mouse pointer — touch input never triggers it — so this
    // adds hover-to-reveal on web/desktop for free without a platform
    // check, while tap keeps working unchanged on mobile. Full reveal
    // logic (including the timestamp text itself) lives in _buildHoverRow.
    final showTime = msg['_showTime'] as bool? ?? false;
    // Only the most recent completed bot answer offers "regenerate" — older
    // turns would be confusing to silently rewrite.
    final canRegenerate =
        isBot &&
        !isRevealing &&
        errorCode == null &&
        index == _displayMessages.length - 1;
    // Set by _retryStream/_regenerateResponse right before they remove this
    // bubble and kick off a fresh one — gives the old content a brief fade
    // out instead of vanishing on the spot when regeneration starts.
    final fadingOut = msg['_fadingOut'] as bool? ?? false;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      opacity: fadingOut ? 0 : 1,
      child: MouseRegion(
        // BUG FIX: this used to be gated on `msgTime != null`, so hover
        // (and tap) did nothing at all for any bubble without a
        // timestamp — which, before the earlier fix that started
        // populating 'time' on history-loaded messages, was EVERY
        // history message. Now that the hover row also carries actions
        // (copy/regenerate/edit/feedback) that are useful with or without
        // a timestamp, this is wired unconditionally — identical for
        // freshly-streamed and history-loaded messages alike, since both
        // go through this exact same widget with no separate code path.
        onEnter: (_) => setState(() => msg['_hovering'] = true),
        onExit: (_) => setState(() => msg['_hovering'] = false),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => setState(() => msg['_showTime'] = !showTime),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            // The hover row is a separate element below the bubble, not part
            // of it — this Column (default crossAxisAlignment.start) is what
            // makes that row always left-align to the message's own left
            // edge, regardless of which way the Row below it pushes the
            // bubble itself.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: isUser
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isUser) ...[_logo(32), const SizedBox(width: 8)],
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isUser
                              ? AppTheme.primaryDark
                              : isError
                              ? AppTheme.error.withValues(alpha: 0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isUser ? 16 : 4),
                            bottomRight: Radius.circular(isUser ? 4 : 16),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // TOP — XAI confidence badge (bot messages only); held
                            // back until the answer has fully finished revealing
                            // (metadata can otherwise land slightly before the
                            // buffered typewriter catches up), then fades in.
                            if (confidence.isNotEmpty && !isRevealing) ...[
                              wasStreamed
                                  ? _fadeIn(_confidenceBadge(confidence))
                                  : _confidenceBadge(confidence),
                              const SizedBox(height: 6),
                            ],
                            // MIDDLE — answer text (reasoning split out for bot replies).
                            // Before the first token arrives, a sequential dot-pulse
                            // stands in for the empty bubble; once text is being
                            // revealed, a blinking caret marks the growing edge.
                            // Bot replies render as markdown (the model uses **bold**,
                            // numbered/dash lists in math and multi-item answers) —
                            // softLineBreak keeps single '\n's as real line breaks,
                            // matching how our system prompt actually formats text
                            // (single newlines between steps/list items, not blank
                            // lines). User/error bubbles stay plain text.
                            isBot
                                ? (isRevealing && parsed.answer.isEmpty
                                      ? const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 2,
                                          ),
                                          child: _ThinkingDots(),
                                        )
                                      : _buildAnswerBody(
                                          msg,
                                          parsed,
                                          isRevealing,
                                        ))
                                : Text(
                                    parsed.answer,
                                    style: TextStyle(
                                      color: isUser
                                          ? Colors.white
                                          : AppTheme.error,
                                      fontSize: 14,
                                    ),
                                  ),
                            // BOTTOM — muted XAI footer; hidden when empty
                            // (out-of-scope) or while still revealing (sources/
                            // advisory can arrive via metadata before the
                            // typewriter has finished typing the answer out).
                            if (hasFooter && !isRevealing)
                              wasStreamed
                                  ? _fadeIn(
                                      _xaiFooter(parsed, sources, advisory),
                                    )
                                  : _xaiFooter(parsed, sources, advisory),
                            // Inline stream-error state: keeps any partial text above,
                            // adds a muted warning + optional retry inside the bubble.
                            if (errorCode != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.warning_amber_outlined,
                                    size: 14,
                                    color: Colors.orange[800],
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _streamErrorMessages[errorCode] ??
                                          _streamErrorMessages['server_error']!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.orange[800],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              // Auth errors need a fresh sign-in, not a retry.
                              if (errorCode != 'auth_error')
                                TextButton.icon(
                                  onPressed: () => _retryStream(msg),
                                  icon: const Icon(Icons.refresh, size: 14),
                                  label: const Text('Tap to retry'),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 28),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    foregroundColor: AppTheme.primaryDark,
                                    textStyle: const TextStyle(fontSize: 12),
                                  ),
                                ),
                            ],
                            if (isMock)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Mock response',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange[700],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (isUser) ...[
                      const SizedBox(width: 8),
                      CircleAvatar(
                        backgroundColor: AppTheme.primary,
                        radius: 16,
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ],
                  ],
                ),
                // The hover row itself — separate from the bubble, below it.
                // Bot: left-aligned, indented past the avatar to sit under
                // the bubble's own text. User: right-aligned, matching the
                // bubble's own alignment above it. The actual alignment is
                // decided inside _buildHoverRow (its fixed-height SizedBox
                // spans the full row width, so aligning here would do
                // nothing — it's the Align *inside* that positions the
                // compact content within that width).
                Padding(
                  padding: EdgeInsets.only(top: 4, left: isUser ? 0 : 40),
                  child: _buildHoverRow(
                    msg,
                    index,
                    isUser: isUser,
                    canShowActions:
                        isUser || (isBot && !isRevealing && errorCode == null),
                    canRegenerate: canRegenerate,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The shared hover row: timestamp (if any) on the left, actions on the
  /// right — off by default, fades in on hover/tap.
  ///
  /// BUG FIX: this used to be an AnimatedCrossFade, which animates SIZE —
  /// collapsing to zero height when hidden and growing when revealed. That
  /// growth pushed every message below it down the list on every hover,
  /// which reads as the whole conversation jumping around. The row's
  /// height is now reserved permanently (whether hovering or not) and only
  /// its opacity animates, so hovering never moves anything else on screen.
  Widget _buildHoverRow(
    Map<String, dynamic> msg,
    int index, {
    required bool isUser,
    required bool canShowActions,
    required bool canRegenerate,
  }) {
    final msgTime = msg['time'] as DateTime?;
    final showTime = msg['_showTime'] as bool? ?? false;
    final hovering = msg['_hovering'] as bool? ?? false;
    final revealed = showTime || hovering;
    if (msgTime == null && !canShowActions) return const SizedBox.shrink();
    // This row used to live INSIDE the dark user-message bubble, where
    // white/white70 was correct. It now sits below the bubble on the
    // ordinary light page background for both roles, so it always uses
    // the muted/dark palette.
    const iconColor = AppTheme.textMuted;
    return SizedBox(
      // Fixed height, always reserved — tall enough for the 30px action
      // buttons plus the row's own top padding — so revealing/hiding it
      // never changes this message's total height.
      height: 34,
      // BUG FIX: this was hardcoded to centerLeft, silently overriding any
      // alignment applied by the caller around _buildHoverRow — this
      // SizedBox already fills the full row width (see below), so it's
      // this Align, not anything wrapping the call site, that actually
      // decides where the compact content sits.
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          opacity: revealed ? 1 : 0,
          // Hidden icons/text shouldn't intercept taps or show tooltips.
          child: IgnorePointer(
            ignoring: !revealed,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (msgTime != null) ...[
                    Text(
                      _formatClockTime(msgTime),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    if (canShowActions) const SizedBox(width: 10),
                  ],
                  if (canShowActions)
                    isUser
                        ? _buildUserActionsRow(msg, iconColor)
                        : _buildBubbleActionsRow(msg, index, canRegenerate),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Bot-bubble actions: copy, regenerate (last answer only), and the
  /// existing thumbs-up/down feedback control.
  ///
  /// BUG FIX: feedback used to require `sources.isNotEmpty` — but the
  /// conversation-history endpoint never returns sources at all (only
  /// role/content/timestamp), so on ANY reopened conversation, every
  /// answer without an already-cast vote silently lost its feedback
  /// control. This row is already only reached for a real, completed,
  /// non-error bot answer (see canShowActions in _buildMessageBubble), so
  /// feedback is simply always offered here now.
  Widget _buildBubbleActionsRow(
    Map<String, dynamic> msg,
    int index,
    bool canRegenerate,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _copyButton(msg),
        if (canRegenerate)
          _bubbleActionButton(
            icon: Icons.refresh,
            tooltip: 'Regenerate response',
            onTap: () => _regenerateResponse(index),
          ),
        _buildFeedbackRow(msg, index),
      ],
    );
  }

  /// User-bubble actions: copy (the user's own message text — same
  /// `_copyMessage` used for bot answers, which already falls back to the
  /// whole `content` string when there's no "Reasoning:" prefix to strip)
  /// and a UI-only "edit" placeholder. No message-editing/conversation-
  /// branching logic exists yet — that's a future session.
  Widget _buildUserActionsRow(Map<String, dynamic> msg, Color iconColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _copyButton(msg, color: iconColor, checkedColor: Colors.greenAccent),
        _bubbleActionButton(
          icon: Icons.edit_outlined,
          tooltip: 'Edit (coming soon)',
          color: iconColor,
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Editing messages isn't available yet."),
              duration: Duration(seconds: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bubbleActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color color = AppTheme.textMuted,
  }) {
    return IconButton(
      icon: Icon(icon, size: 15, color: color),
      onPressed: onTap,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    );
  }

  /// Copy button that briefly swaps to a checkmark on tap (`_copyMessage`
  /// flips `msg['_copied']` for 1.5s) — confirms the copy without a second,
  /// competing snackbar-only signal. [color]/[checkedColor] let the user-
  /// bubble variant use light colors that read against the dark bubble
  /// background, while the bot-bubble default stays unchanged.
  Widget _copyButton(
    Map<String, dynamic> msg, {
    Color color = AppTheme.textMuted,
    Color checkedColor = AppTheme.success,
  }) {
    final copied = msg['_copied'] as bool? ?? false;
    return IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        // Scale + fade together (not the plain fade AnimatedSwitcher uses
        // by default) so the copy→check swap actually reads as a change,
        // not a faint crossfade at this icon's small size.
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          copied ? Icons.check : Icons.copy_outlined,
          key: ValueKey(copied),
          size: 15,
          color: copied ? checkedColor : color,
        ),
      ),
      onPressed: () => _copyMessage(msg),
      tooltip: copied ? 'Copied' : 'Copy',
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    );
  }

  // Thumbs up/down on a bot answer. Once a vote is cast, the other button
  // disappears and the selected one is disabled (one feedback per message).
  Widget _buildFeedbackRow(Map<String, dynamic> msg, int index) {
    final feedback = msg['feedback'] as String?;
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (feedback == null || feedback == 'up')
            _feedbackButton(
              filled: feedback == 'up',
              onIcon: Icons.thumb_up,
              offIcon: Icons.thumb_up_outlined,
              color: AppTheme.success,
              tooltip: 'Helpful',
              onTap: feedback == null
                  ? () => _sendFeedback(msg, index, 'up')
                  : null,
            ),
          if (feedback == null || feedback == 'down')
            _feedbackButton(
              filled: feedback == 'down',
              onIcon: Icons.thumb_down,
              offIcon: Icons.thumb_down_outlined,
              color: AppTheme.accent, // orange
              tooltip: 'Not helpful',
              onTap: feedback == null
                  ? () => _sendFeedback(msg, index, 'down')
                  : null,
            ),
        ],
      ),
    );
  }

  Widget _feedbackButton({
    required bool filled,
    required IconData onIcon,
    required IconData offIcon,
    required Color color,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return IconButton(
      icon: Icon(
        filled ? onIcon : offIcon,
        size: 16,
        color: filled ? color : Colors.grey[400],
      ),
      onPressed: onTap, // null once any vote is cast → disabled
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    );
  }

  // Optimistic: fill the icon immediately, then fire the call in the
  // background. If it fails, keep the UI as-is — the vote is lost silently
  // (feedback must never block or slow the chat experience).
  void _sendFeedback(Map<String, dynamic> msg, int index, String feedback) {
    setState(() => msg['feedback'] = feedback);
    unawaited(
      ServiceFactory.getService()
          .sendFeedback(
            conversationId: _conversationId ?? '',
            messageIndex: index,
            feedback: feedback,
            messageText: _questionForAnswer(index),
          )
          .catchError((_) {
            /* best-effort — keep the UI as-is */
          }),
    );
  }

  // The user question this answer responds to → most_downvoted_questions.
  String _questionForAnswer(int answerIndex) {
    for (var i = answerIndex - 1; i >= 0; i--) {
      if (_displayMessages[i]['role'] == 'user') {
        return _displayMessages[i]['content'] as String? ?? '';
      }
    }
    return '';
  }

  /// Splits a bot reply into (reasoning, answer). The backend instructs the
  /// model to lead with one "Reasoning: ..." sentence, then the answer on a
  /// new line. Splits on the first blank line, falling back to the first
  /// newline (the model often emits a single \n). No "Reasoning:" prefix →
  /// the whole reply is the answer.
  _ParsedReply _parseReply(String reply) {
    final trimmed = reply.trimLeft();
    if (!trimmed.startsWith('Reasoning:')) return _ParsedReply('', reply);
    var cut = trimmed.indexOf('\n\n');
    if (cut == -1) cut = trimmed.indexOf('\n');
    if (cut == -1) return _ParsedReply('', reply); // one-liner: don't hide it
    return _ParsedReply(
      trimmed.substring('Reasoning:'.length, cut).trim(),
      trimmed.substring(cut).trim(),
    );
  }

  /// Small colored chip showing the XAI confidence label. Long backend labels
  /// ("Low confidence — please verify...") are truncated at the em dash; the
  /// advisory tail is rendered in the bubble footer instead. Reuses the same
  /// CsConfidenceBadge/AppTheme.confidenceColor mapping as the rest of the
  /// app (yield/price screens) so "High"/"Medium"/"Low" mean the same shade
  /// everywhere.
  Widget _confidenceBadge(String confidence) {
    final label = confidence.split('—').first.trim();
    final level = switch (label) {
      'High confidence' => 'high',
      'Moderate confidence' => 'medium',
      _ => 'low', // Low confidence, "Out of scope", and unknown labels
    };
    return CsConfidenceBadge(confidence: level);
  }

  /// The bubble's muted XAI footer: divider + reasoning/sources/advisory.
  Widget _xaiFooter(
    _ParsedReply parsed,
    List<String> sources,
    String advisory,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Container(height: 1, color: Colors.grey[200]),
        const SizedBox(height: 6),
        if (parsed.reasoning.isNotEmpty)
          _xaiFooterLine(Icons.lightbulb_outline, parsed.reasoning),
        if (sources.isNotEmpty)
          _xaiFooterLine(Icons.description_outlined, sources.join(', ')),
        if (advisory.isNotEmpty) _xaiFooterLine(Icons.info_outline, advisory),
      ],
    );
  }

  /// Fades a widget in on first build — used so the confidence badge and
  /// XAI footer appear smoothly when stream metadata arrives, not jarringly.
  Widget _fadeIn(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      builder: (context, opacity, c) => Opacity(opacity: opacity, child: c),
      child: child,
    );
  }

  /// One muted line in the XAI footer (reasoning / sources / advisory).
  /// Renders as markdown defensively — the reasoning line is normally a
  /// plain sentence, but if the model ever puts **bold** or a dash list in
  /// there (e.g. a mis-split reformulation reply), it still renders
  /// properly instead of showing raw asterisks/dashes.
  Widget _xaiFooterLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 12, color: Colors.grey[500]),
          const SizedBox(width: 4),
          Expanded(
            child: MarkdownBody(
              data: text,
              softLineBreak: true,
              imageBuilder: _blockedImageBuilder,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  height: 1.3,
                ),
                strong: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  height: 1.3,
                  fontWeight: FontWeight.w700,
                ),
                listBullet: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  height: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Row(
      children: [
        _logo(32),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 4,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [_buildDot(0), _buildDot(150), _buildDot(300)],
          ),
        ),
      ],
    );
  }

  Widget _buildDot(int delay) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.4, end: 1.0),
      duration: Duration(milliseconds: 600 + delay),
      builder: (ctx, val, _) => Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: val),
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _buildSuggestions() {
    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _suggestedFollowups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) => FollowupChip(
          text: _suggestedFollowups[i],
          onTap: () => _sendMessage(_suggestedFollowups[i]),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                // Caps growth at ~5 lines; TextField scrolls internally once
                // content exceeds that (built into EditableText — no extra
                // ScrollController needed).
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: Focus(
                    // Physical/hardware Enter — web & desktop. Soft
                    // keyboards on mobile don't dispatch this, so touch
                    // input keeps using the IME's own return-key behavior
                    // (still wired below via onSubmitted) untouched.
                    onKeyEvent: (node, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.enter) {
                        if (HardwareKeyboard.instance.isShiftPressed) {
                          // Shift+Enter: let it through as a newline.
                          return KeyEventResult.ignored;
                        }
                        _sendMessage(_controller.text);
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _controller,
                      maxLength: 500,
                      minLines: 1,
                      maxLines: null,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      decoration: InputDecoration(
                        hintText: 'Ask about crops, prices, weather...',
                        counterText: '',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        // Same shape as enabledBorder, just the accent
                        // color — a subtle, theme-consistent focus cue
                        // (Flutter animates the border color transition
                        // between states itself).
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: AppTheme.primary,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      // Fallback for platforms/IMEs that do fire a "submit"
                      // action for the return key (e.g. some mobile IMEs
                      // configured for "send") — harmless no-op elsewhere
                      // since Enter is already handled above on desktop/web.
                      onSubmitted: _sendMessage,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: (_isLoading || _isStreaming)
                    ? null
                    : () => _sendMessage(_controller.text),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOut,
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (_isLoading || _isStreaming)
                        ? Colors.grey
                        : AppTheme.primaryDark,
                    shape: BoxShape.circle,
                  ),
                  child: (_isLoading || _isStreaming)
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
          // Recognition-over-recall: only surface the char budget once it
          // actually matters, instead of a silent hard cutoff at 500.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              final len = value.text.length;
              if (len <= 400) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$len/500',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: len >= 500 ? FontWeight.w600 : null,
                      color: len >= 500 ? AppTheme.error : AppTheme.textMuted,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  List<ChatMessage> _buildValidHistory() {
    final history = List<ChatMessage>.from(
      _history.sublist(0, _history.length - 1),
    );
    // Keep only alternating user/assistant pairs
    final valid = <ChatMessage>[];
    for (final msg in history) {
      if (valid.isEmpty && msg.role == 'user') {
        valid.add(msg);
      } else if (valid.isNotEmpty && msg.role != valid.last.role) {
        valid.add(msg);
      }
    }
    // Limit to last 10 turns and truncate long messages
    final limited = valid.length > 10
        ? valid.sublist(valid.length - 10)
        : valid;
    return limited
        .map(
          (m) => ChatMessage(
            role: m.role,
            content: m.content.length > 400
                ? '${m.content.substring(0, 400)}...'
                : m.content,
          ),
        )
        .toList();
  }
}

/// Bot reply split into its XAI reasoning sentence and the main answer.
class _ParsedReply {
  final String reasoning;
  final String answer;
  _ParsedReply(this.reasoning, this.answer);
}

/// Three small dots that pulse in sequence — stands in for the empty bot
/// bubble between sending a message and the first streamed token. A single
/// looping AnimationController drives all three; each dot reads the shared
/// value with a phase offset so they visibly chase one another, never in
/// lockstep. Not a spinner: nothing rotates or travels.
class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Extra height above the dots' own 6px so the upward bob has room to
    // play without clipping; dots sit bottom-aligned at rest.
    return SizedBox(
      height: 12,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _dot(0),
          const SizedBox(width: 4),
          _dot(1 / 3),
          const SizedBox(width: 4),
          _dot(2 / 3),
        ],
      ),
    );
  }

  Widget _dot(double phase) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = (_controller.value + phase) % 1.0;
        // One up-down lobe per cycle, eased — smooth rise and fall, no snap.
        // Drives both opacity and a small upward bob off the same phase, so
        // each dot brightens and lifts together, then dims and settles.
        final lobe = Curves.easeInOut.transform(t < 0.5 ? t * 2 : (1 - t) * 2);
        return Transform.translate(
          offset: Offset(0, -lobe * 3.5),
          child: Opacity(
            opacity: 0.3 + lobe * 0.7,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppTheme.textMuted,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Thin vertical caret that blinks at the end of the streaming answer text,
/// like a text-editor cursor. Toggles every 500ms; removed the instant a
/// bubble's 'streaming' flag flips false (stream complete).
class _BlinkingCursor extends StatefulWidget {
  const _BlinkingCursor();

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        margin: const EdgeInsets.only(top: 2),
        width: 2,
        height: 14,
        color: AppTheme.textPrimary,
      ),
    );
  }
}
