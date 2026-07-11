// lib/screens/chat/chat_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../config/app_config.dart';
import '../../services/service_factory.dart';
import '../../services/chat_history_service.dart';
import '../../models/api_models.dart';
import '../../models/chat_history_models.dart';
import '../../widgets/app_theme.dart';

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
  final ScrollController _scrollController = ScrollController();
  final _historyService = ChatHistoryService();
  final List<ChatMessage> _history = [];
  final List<Map<String, dynamic>> _displayMessages = [];
  bool _isLoading = false;
  bool _isStreaming = false;

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
  List<String> _suggestedFollowups = [];
  String? _selectedDistrict;
  String? _selectedCrop;
  String _selectedModel = 'accurate';

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
    if (!AppConfig.useMockServices) _loadConversations();
  }

  Future<void> _loadConversations() async {
    setState(() => _conversationsLoading = true);
    try {
      final conversations = await _historyService.listConversations();
      if (mounted) setState(() => _conversations = conversations);
    } catch (e) {
      debugPrint('Failed to load conversations: $e');
    } finally {
      if (mounted) setState(() => _conversationsLoading = false);
    }
  }

  Future<void> _openConversation(ConversationSummary summary) async {
    // Close the drawer on mobile before loading.
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
    try {
      final detail = await _historyService.getConversation(summary.id);
      if (!mounted) return;
      setState(() {
        _conversationId = detail.id;
        _displayMessages
          ..clear()
          ..addAll(
            detail.messages.map((m) => {'role': m.role, 'content': m.content}),
          );
        _history
          ..clear()
          ..addAll(
            detail.messages.map(
              (m) => ChatMessage(role: m.role, content: m.content),
            ),
          );
        _suggestedFollowups = [];
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load conversation')),
        );
      }
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
      _loadConversations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to rename conversation')),
        );
      }
    }
  }

  Future<void> _deleteConversation(ConversationSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
    );
    if (confirmed != true) return;
    try {
      await _historyService.deleteConversation(summary.id);
      if (summary.id == _conversationId) _startNewChat();
      _loadConversations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete conversation')),
        );
      }
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
  Future<void> _sendMessageNonStreaming(String message) async {
    _controller.clear();
    setState(() {
      _displayMessages.add({'role': 'user', 'content': message});
      _history.add(ChatMessage(role: 'user', content: message));
      _isLoading = true;
      _suggestedFollowups = [];
    });
    _scrollToBottom();

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
        _loadConversations();
      }

      setState(() {
        _displayMessages.add({
          'role': 'assistant',
          'content': response.reply,
          'isMock': response.isMock,
          'confidence': response.confidence,
          'sources': response.sourcesUsed,
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
  Future<void> _sendMessageStreaming(
    String message, {
    bool isRetry = false,
  }) async {
    if (_isStreaming) return; // guard: never two concurrent streams
    _controller.clear();
    final bubble = <String, dynamic>{
      'role': 'assistant',
      'content': '',
      'streaming': true,
      'retryFor': message,
    };
    // _isStreaming is set synchronously, before any await, so the input
    // field is disabled for the whole stream — initial send and retry alike.
    setState(() {
      _isStreaming = true;
      if (!isRetry) {
        _displayMessages.add({'role': 'user', 'content': message});
        _history.add(ChatMessage(role: 'user', content: message));
      }
      _displayMessages.add(bubble);
      _suggestedFollowups = [];
    });
    _scrollToBottom();

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
            _scrollToBottom();
          case 'metadata':
            final convId = event['conversation_id'] as String? ?? '';
            final isNewConversation =
                _conversationId == null && convId.isNotEmpty;
            if (convId.isNotEmpty) _conversationId = convId;
            if (isNewConversation && !AppConfig.useMockServices) {
              _loadConversations();
            }
            setState(() {
              bubble['confidence'] = event['confidence'] as String? ?? '';
              bubble['sources'] = List<String>.from(event['sources'] ?? []);
              _suggestedFollowups = List<String>.from(
                event['suggested_followups'] ?? [],
              );
            });
          case 'error':
            setState(() {
              bubble['errorCode'] = event['code'] as String? ?? 'server_error';
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
    setState(() => _displayMessages.remove(bubble));
    await _sendMessageStreaming(retryFor, isRetry: true);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
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
        Expanded(child: _buildMessageList()),
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
                SizedBox(
                  width: 280,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        right: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    child: _buildSidebar(),
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
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : _conversations.isEmpty
              ? Center(
                  child: Text(
                    AppConfig.useMockServices
                        ? 'History unavailable in mock mode'
                        : 'No conversations yet',
                    style: TextStyle(color: Colors.grey[500], fontSize: 13),
                  ),
                )
              : ListView.builder(
                  itemCount: _conversations.length,
                  itemBuilder: (ctx, i) =>
                      _buildConversationTile(_conversations[i]),
                ),
        ),
      ],
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

  Widget _buildHeader(bool isWide) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF37474F), const Color(0xFF546E7A)],
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
        ],
      ),
    );
  }

  Widget _buildContextBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey[100],
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text(
              'Context:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
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
            color: selected != null ? AppTheme.primary : Colors.grey[300]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected ?? label,
              style: TextStyle(
                fontSize: 12,
                color: selected != null ? AppTheme.primary : Colors.grey[600],
                fontWeight: selected != null
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 16,
              color: selected != null ? AppTheme.primary : Colors.grey,
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
        border: Border.all(color: Colors.grey[300]!),
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
            color: isSelected ? AppTheme.primary : Colors.grey[600],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    if (_displayMessages.isEmpty) {
      return _buildEmptyState();
    }
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _displayMessages.length + (_isLoading ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == _displayMessages.length) return _buildTypingIndicator();
        final msg = _displayMessages[i];
        return _buildMessageBubble(msg);
      },
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
  Widget _buildEmptyState() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _logo(72),
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
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              ),
              const SizedBox(height: 24),
              for (var i = 0; i < _onboardingFollowups.length; i++) ...[
                _buildStarterCard(_starterIcons[i], _onboardingFollowups[i]),
                if (i < _onboardingFollowups.length - 1)
                  const SizedBox(height: 9),
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
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
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

  Widget _buildMessageBubble(Map<String, dynamic> msg) {
    final isUser = msg['role'] == 'user';
    final isError = msg['role'] == 'error';
    final isMock = msg['isMock'] as bool? ?? false;

    // XAI data — bot replies only; user and error bubbles are unchanged.
    // Messages loaded from saved history have no 'confidence'/'sources' keys
    // and gracefully render without badge/footer.
    final isBot = !isUser && !isError;
    final isStreamingMsg = isBot && (msg['streaming'] as bool? ?? false);
    // Streamed bubbles get a fade-in on badge/footer when metadata lands;
    // regular history bubbles render statically (no re-fade on scroll).
    final wasStreamed = isBot && msg.containsKey('streaming');
    final errorCode = isBot ? msg['errorCode'] as String? : null;
    final confidence = isBot ? (msg['confidence'] as String? ?? '') : '';
    final sources = isBot
        ? ((msg['sources'] as List?)?.cast<String>() ?? const <String>[])
        : const <String>[];
    // While text is still streaming, show it raw — the reasoning line is
    // split into the footer only once the stream completes ([DONE]).
    final parsed = isBot && !isStreamingMsg
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
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
                    ? Colors.red[50]
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
                  // TOP — XAI confidence badge (bot messages only); fades in
                  // when metadata arrives at the end of a stream
                  if (confidence.isNotEmpty) ...[
                    wasStreamed
                        ? _fadeIn(_confidenceBadge(confidence))
                        : _confidenceBadge(confidence),
                    const SizedBox(height: 6),
                  ],
                  // MIDDLE — answer text (reasoning split out for bot replies);
                  // "..." placeholder while the stream is starting (Phase 1)
                  Text(
                    isStreamingMsg && parsed.answer.isEmpty
                        ? '...'
                        : parsed.answer,
                    style: TextStyle(
                      color: isUser
                          ? Colors.white
                          : isError
                          ? Colors.red
                          : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                  // BOTTOM — muted XAI footer; hidden when empty (out-of-scope)
                  if (hasFooter)
                    wasStreamed
                        ? _fadeIn(_xaiFooter(parsed, sources, advisory))
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
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
              child: const Icon(Icons.person, color: Colors.white, size: 16),
            ),
          ],
        ],
      ),
    );
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
  /// advisory tail is rendered in the bubble footer instead.
  Widget _confidenceBadge(String confidence) {
    final label = confidence.split('—').first.trim();
    final (bg, fg) = switch (label) {
      'High confidence' => (Colors.green[600]!, Colors.white),
      'Moderate confidence' => (Colors.amber[400]!, Colors.black87),
      'Low confidence' => (Colors.orange[700]!, Colors.white),
      _ => (Colors.grey[600]!, Colors.white), // Out of scope + unknown
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
      ),
    );
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
      duration: const Duration(milliseconds: 300),
      builder: (context, opacity, c) => Opacity(opacity: opacity, child: c),
      child: child,
    );
  }

  /// One muted line in the XAI footer (reasoning / sources / advisory).
  Widget _xaiFooterLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 12, color: Colors.grey[500]),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
                height: 1.3,
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
        itemBuilder: (ctx, i) => GestureDetector(
          onTap: () => _sendMessage(_suggestedFollowups[i]),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              _suggestedFollowups[i],
              style: TextStyle(fontSize: 12, color: AppTheme.primaryDark),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              maxLength: 500,
              maxLines: null,
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                filled: true,
                fillColor: Colors.grey[50],
              ),
              onSubmitted: _sendMessage,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: (_isLoading || _isStreaming)
                ? null
                : () => _sendMessage(_controller.text),
            child: Container(
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
