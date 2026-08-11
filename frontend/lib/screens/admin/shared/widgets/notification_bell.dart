// lib/screens/admin/shared/widgets/notification_bell.dart
// The admin app-bar bell: an icon with an unread badge that polls every 60s,
// and the slide-in panel it opens. Self-contained so the shell only has to drop
// <NotificationBell/> into its app-bar actions and pass two navigation
// callbacks — no navigation restructuring.

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../models/admin_models.dart';
import '../../../../services/notification_service.dart';
import '../../../../widgets/app_theme.dart';
import '../admin_ui.dart';

/// How often the badge re-checks the unread count.
const _pollInterval = Duration(seconds: 60);

// Severity → (icon, colour). Shared by the panel cards. Blue for info comes
// from Material (AppTheme has no info colour); the rest map to the app palette.
({IconData icon, Color color}) _severityStyle(String severity) {
  switch (severity) {
    case 'success':
      return (icon: Icons.check_circle_outline, color: AppTheme.success);
    case 'warning':
      return (icon: Icons.warning_amber_outlined, color: AppTheme.warning);
    case 'error':
      return (icon: Icons.error_outline, color: AppTheme.error);
    default:
      return (icon: Icons.info_outline, color: Color(0xFF1976D2));
  }
}

class NotificationBell extends StatefulWidget {
  /// Deep-link handlers, invoked when a notification card is tapped. All are
  /// optional — a tap with no matching handler just marks the item read.
  final void Function(String adjustmentId)? onOpenAdjustment;
  final VoidCallback? onOpenGapReport;
  final VoidCallback? onOpenPatternManagement;
  final void Function(String patternId)? onOpenPattern;

  const NotificationBell({
    super.key,
    this.onOpenAdjustment,
    this.onOpenGapReport,
    this.onOpenPatternManagement,
    this.onOpenPattern,
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final _service = NotificationService();
  Timer? _timer;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refreshCount();
    _timer = Timer.periodic(_pollInterval, (_) => _refreshCount());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshCount() async {
    final count = await _service.getUnreadCount();
    if (mounted) setState(() => _unread = count);
  }

  Future<void> _openPanel() async {
    // The panel pops with the tapped notification when it carries an
    // action_url, so navigation happens here (after the panel closes) against
    // a live context rather than the panel's disposed one.
    final tapped = await showGeneralDialog<AdminNotification>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Notifications',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, _) {
        final width = MediaQuery.of(ctx).size.width;
        return Align(
          alignment: Alignment.centerRight,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: SizedBox(
              width: width < 480 ? width : 400,
              height: double.infinity,
              child: NotificationPanel(service: _service),
            ),
          ),
        );
      },
    );

    await _refreshCount();
    if (tapped != null) _handleAction(tapped);
  }

  // Route an action_url to the shell's navigation callbacks.
  void _handleAction(AdminNotification n) {
    final url = n.actionUrl ?? '';
    if (url.startsWith('/adjustment/')) {
      final id = url.substring('/adjustment/'.length);
      if (id.isNotEmpty) widget.onOpenAdjustment?.call(id);
    } else if (url.startsWith('/pattern-management/')) {
      final id = url.substring('/pattern-management/'.length);
      if (id.isNotEmpty) widget.onOpenPattern?.call(id);
    } else if (url == '/pattern-management') {
      widget.onOpenPatternManagement?.call();
    } else if (url == '/gap-report') {
      widget.onOpenGapReport?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_outlined),
          color: Colors.white,
          onPressed: _openPanel,
        ),
        if (_unread > 0)
          Positioned(
            right: 4,
            top: 4,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: BoxDecoration(
                  color: AppTheme.error,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  _unread > 9 ? '9+' : '$_unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The slide-in list. Owns its own load + mark-read state. Pops with an
/// [AdminNotification] when a card that has an action_url is tapped.
class NotificationPanel extends StatefulWidget {
  final NotificationService service;

  const NotificationPanel({super.key, required this.service});

  @override
  State<NotificationPanel> createState() => _NotificationPanelState();
}

class _NotificationPanelState extends State<NotificationPanel> {
  bool _loading = true;
  bool _error = false;
  List<AdminNotification> _items = [];
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final items = await widget.service.getNotifications(limit: 30);
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    // Optimistic — flip locally first, then persist.
    setState(() {
      _items = _items.map((n) => n.copyWith(read: true)).toList();
    });
    try {
      await widget.service.markAllRead();
    } catch (_) {
      // A failed persist is non-fatal; the next poll re-syncs the badge.
    }
  }

  Future<void> _onTap(AdminNotification n) async {
    if (!n.read) {
      setState(() {
        _items = _items
            .map((x) => x.id == n.id ? x.copyWith(read: true) : x)
            .toList();
      });
      try {
        await widget.service.markRead(n.id);
      } catch (_) {
        // Non-fatal — the badge re-syncs on the next poll.
      }
    }
    if (!mounted) return;
    if (n.actionUrl != null && n.actionUrl!.isNotEmpty) {
      // Hand navigation back to the bell against a live context.
      Navigator.of(context).pop(n);
    } else {
      // No deep link — toggle the message expansion in place.
      setState(() {
        _expanded.contains(n.id) ? _expanded.remove(n.id) : _expanded.add(n.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      elevation: 8,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final hasUnread = _items.any((n) => !n.read);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Notifications',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          if (hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read'),
            ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close, color: AppTheme.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (_error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: AdminErrorCard(
            message: 'Could not load notifications.',
            onRetry: _load,
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_none,
                size: 44,
                color: AppTheme.textMuted,
              ),
              SizedBox(height: 10),
              Text(
                'No notifications yet.\nSystem alerts will appear here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _items.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (_, i) => _card(_items[i]),
      ),
    );
  }

  Widget _card(AdminNotification n) {
    final style = _severityStyle(n.severity);
    final expanded = _expanded.contains(n.id);
    return InkWell(
      onTap: () => _onTap(n),
      child: Container(
        // Unread cards get a faint tint so they stand out from read ones.
        color: n.read ? null : style.color.withValues(alpha: 0.05),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(style.icon, color: style.color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: n.read
                                ? FontWeight.w600
                                : FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      if (!n.read) ...[
                        const SizedBox(width: 6),
                        Container(
                          margin: const EdgeInsets.only(top: 5),
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: style.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    n.message,
                    maxLines: expanded ? null : 2,
                    overflow: expanded ? null : TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        adminTimeAgo(n.createdAt),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                      if (n.actionUrl != null && n.actionUrl!.isNotEmpty) ...[
                        const Spacer(),
                        Icon(
                          Icons.chevron_right,
                          size: 16,
                          color: AppTheme.textMuted,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
