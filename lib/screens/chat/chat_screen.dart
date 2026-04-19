// lib/screens/chat/chat_screen.dart

import 'package:flutter/material.dart';
import '../../widgets/app_theme.dart';
import '../../models/api_models.dart';
import '../../services/service_factory.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _service = ServiceFactory();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _history = [];
  final List<_ChatBubble> _bubbles = [];
  List<String> _suggestedFollowups = [
    'What should I plant this Maha season?',
    'Expected yield for Carrot in Nuwara Eliya?',
    'Which crop has best profit margin?',
  ];
  bool _isLoading = false;
  String? _selectedDistrict;
  String? _selectedCrop;

  Future<void> _send(String message) async {
    if (message.trim().isEmpty || _isLoading) return;

    // Validate max 500 chars (security: matches Pydantic schema)
    if (message.length > 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message too long (max 500 characters)')),
      );
      return;
    }

    _controller.clear();
    setState(() {
      _bubbles.add(_ChatBubble(text: message, isUser: true));
      _history.add(ChatMessage(role: 'user', content: message));
      _isLoading = true;
      _suggestedFollowups = [];
    });
    _scrollToBottom();

    try {
      final response = await _service.sendChat(
        ChatRequest(
          message: message,
          conversationHistory: _history.length > 1
              ? _history.sublist(0, _history.length - 1).take(10).toList()
              : [],
          userId: 'supun_dev',
          district: _selectedDistrict,
          crop: _selectedCrop,
        ),
      );

      setState(() {
        _bubbles.add(
          _ChatBubble(
            text: response.reply,
            isUser: false,
            isMock: response.isMock,
            sources: response.sourcesUsed,
          ),
        );
        _history.add(ChatMessage(role: 'assistant', content: response.reply));
        _suggestedFollowups = response.suggestedFollowups;
      });
    } catch (e) {
      setState(() {
        _bubbles.add(
          _ChatBubble(
            text: 'Sorry, I encountered an error. Please try again.',
            isUser: false,
            isError: true,
          ),
        );
      });
    } finally {
      setState(() => _isLoading = false);
      _scrollToBottom();
    }
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.smart_toy, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('Agricultural Advisor'),
          ],
        ),
        actions: [
          const CsMockBadge(),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onSelected: (_) {},
            itemBuilder: (_) => [
              PopupMenuItem(
                child: CsDropdown(
                  label: 'District context',
                  value: _selectedDistrict,
                  items: ['None', ...CropSphereConstants.districts],
                  onChanged: (v) => setState(
                    () => _selectedDistrict = v == 'None' ? null : v,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Model info bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF00695C).withOpacity(0.08),
            child: const Text(
              'Model 6 · LLaMA 3 + RAG · 100% retrieval accuracy · Groq API',
              style: TextStyle(fontSize: 11, color: Color(0xFF00695C)),
            ),
          ),
          // Chat messages
          Expanded(
            child: _bubbles.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _bubbles.length + (_isLoading ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == _bubbles.length) return _buildTypingIndicator();
                      return _buildBubble(_bubbles[i]);
                    },
                  ),
          ),
          // Suggested followups
          if (_suggestedFollowups.isNotEmpty && !_isLoading)
            Container(
              height: 44,
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 6),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _suggestedFollowups.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) => GestureDetector(
                  onTap: () => _send(_suggestedFollowups[i]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppTheme.primary.withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      _suggestedFollowups[i],
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          // Input bar
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            decoration: BoxDecoration(
              color: AppTheme.surfaceCard,
              border: Border(
                top: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    maxLength: 500,
                    maxLines: null,
                    decoration: const InputDecoration(
                      hintText: 'Ask about crops, weather, prices...',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: _send,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isLoading ? null : () => _send(_controller.text),
                  icon: const Icon(Icons.send),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.agriculture, color: AppTheme.primary, size: 64),
          const SizedBox(height: 16),
          const Text(
            'Agricultural Advisor',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ask me anything about Sri Lankan crops, weather, market prices, or farming advice.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 24),
          const Text(
            'Try asking:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          ..._suggestedFollowups.map(
            (q) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => _send(q),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.primary.withOpacity(0.2),
                    ),
                  ),
                  child: Text(
                    q,
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(_ChatBubble bubble) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: bubble.isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!bubble.isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.smart_toy, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bubble.isUser
                    ? AppTheme.primary
                    : bubble.isError
                    ? AppTheme.error.withOpacity(0.1)
                    : AppTheme.surfaceCard,
                borderRadius: BorderRadius.circular(12),
                border: bubble.isUser
                    ? null
                    : Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bubble.text,
                    style: TextStyle(
                      color: bubble.isUser
                          ? Colors.white
                          : AppTheme.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                  if (bubble.isMock && !bubble.isUser) ...[
                    const SizedBox(height: 6),
                    const CsMockBadge(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(width: 40),
          Text(
            'Thinking...',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _ChatBubble {
  final String text;
  final bool isUser;
  final bool isMock;
  final bool isError;
  final List<String> sources;

  _ChatBubble({
    required this.text,
    required this.isUser,
    this.isMock = false,
    this.isError = false,
    this.sources = const [],
  });
}
