// lib/screens/admin/shared/widgets/admin_sidebar.dart
// Role-aware sidebar navigation for the admin/superadmin shell. Superadmin-only
// items are hidden entirely when role == 'admin'. The user-facing app screens
// live under a single collapsible "User view" toggle (folded by default,
// auto-unfolds when the current page is a user screen).

import 'package:flutter/material.dart';
import '../../../../widgets/app_theme.dart';
import '../admin_ui.dart';

/// Every destination the shell can render — admin/superadmin pages plus the
/// user-facing app screens (so admins can use the app from within the panel).
enum AdminPage {
  // Admin panel
  dashboard,
  systemHealth,
  users,
  gapReport,
  auditLogs,
  predictionLogs,
  security,
  promptTuning,
  systemConfig,
  maintenance,
  // User app views
  appHome,
  appYield,
  appPrice,
  appWeather,
  appRecommend,
  appDemand,
  appChat,
}

class _NavItem {
  final AdminPage page;
  final IconData icon;
  final String label;
  final bool superOnly;
  const _NavItem(this.page, this.icon, this.label, {this.superOnly = false});
}

class _NavSection {
  final String title;
  final List<_NavItem> items;
  const _NavSection(this.title, this.items);
}

const List<_NavSection> _sections = [
  _NavSection('Monitoring', [
    _NavItem(AdminPage.dashboard, Icons.dashboard_outlined, 'Dashboard'),
    _NavItem(AdminPage.systemHealth, Icons.memory, 'System health'),
  ]),
  _NavSection('Management', [
    _NavItem(AdminPage.users, Icons.people_outline, 'Users'),
    _NavItem(AdminPage.gapReport, Icons.insights, 'Gap report'),
  ]),
  _NavSection('Logs', [
    _NavItem(AdminPage.auditLogs, Icons.history, 'Audit logs'),
    _NavItem(AdminPage.predictionLogs, Icons.model_training, 'Prediction logs'),
  ]),
  _NavSection('Security', [
    _NavItem(AdminPage.security, Icons.shield_outlined, 'Security'),
  ]),
  _NavSection('Superadmin', [
    _NavItem(
      AdminPage.promptTuning,
      Icons.tune,
      'Prompt tuning',
      superOnly: true,
    ),
    _NavItem(
      AdminPage.systemConfig,
      Icons.settings_outlined,
      'System config',
      superOnly: true,
    ),
    _NavItem(
      AdminPage.maintenance,
      Icons.storage_outlined,
      'Maintenance',
      superOnly: true,
    ),
  ]),
];

/// User-app screens shown under the collapsible "User view" toggle. Their order
/// matches the base-screen indices used by the user screens' onNavigate
/// callbacks (0=Home … 6=Chat).
const List<_NavItem> _userAppItems = [
  _NavItem(AdminPage.appHome, Icons.home_outlined, 'Home'),
  _NavItem(AdminPage.appYield, Icons.eco_outlined, 'Yield'),
  _NavItem(AdminPage.appPrice, Icons.payments_outlined, 'Price'),
  _NavItem(AdminPage.appWeather, Icons.cloud_outlined, 'Weather'),
  _NavItem(AdminPage.appRecommend, Icons.spa_outlined, 'Crop'),
  _NavItem(AdminPage.appDemand, Icons.shopping_basket_outlined, 'Demand'),
  _NavItem(AdminPage.appChat, Icons.chat_bubble_outline, 'Chat'),
];

const List<AdminPage> userAppPages = [
  AdminPage.appHome,
  AdminPage.appYield,
  AdminPage.appPrice,
  AdminPage.appWeather,
  AdminPage.appRecommend,
  AdminPage.appDemand,
  AdminPage.appChat,
];

bool isUserAppPage(AdminPage page) => userAppPages.contains(page);

/// Human-readable title for a page — used by the shell's app bar.
String adminPageTitle(AdminPage page) {
  for (final section in _sections) {
    for (final item in section.items) {
      if (item.page == page) return item.label;
    }
  }
  for (final item in _userAppItems) {
    if (item.page == page) return item.label;
  }
  return 'Admin';
}

class AdminSidebar extends StatefulWidget {
  final String role; // 'admin' | 'superadmin'
  final AdminPage current;
  final ValueChanged<AdminPage> onSelect;
  final VoidCallback onLogout;

  const AdminSidebar({
    super.key,
    required this.role,
    required this.current,
    required this.onSelect,
    required this.onLogout,
  });

  @override
  State<AdminSidebar> createState() => _AdminSidebarState();
}

class _AdminSidebarState extends State<AdminSidebar> {
  late bool _userExpanded;

  bool get _isSuper => widget.role == 'superadmin';

  @override
  void initState() {
    super.initState();
    // Folded by default; unfolded only if we open onto a user screen.
    _userExpanded = isUserAppPage(widget.current);
  }

  @override
  void didUpdateWidget(covariant AdminSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the active user screen visible if navigation lands on one (e.g. an
    // in-app deep link from the user dashboard).
    if (isUserAppPage(widget.current) && !_userExpanded) {
      _userExpanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      color: Colors.white,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final section in _sections) ..._buildSection(section),
                const Divider(height: 16, indent: 16, endIndent: 16),
                ..._buildUserViewGroup(),
              ],
            ),
          ),
          const Divider(height: 1),
          _bottomItem(
            Icons.logout,
            'Logout',
            widget.onLogout,
            color: AppTheme.error,
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      decoration: BoxDecoration(gradient: adminRoleGradient(widget.role)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.admin_panel_settings, color: Colors.white, size: 30),
          const SizedBox(height: 8),
          Text(
            _isSuper ? 'Superadmin Panel' : 'Admin Panel',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.role.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSection(_NavSection section) {
    // Hide the whole section if every item in it is gated to superadmin and
    // the current role is admin.
    final visibleItems = section.items
        .where((i) => _isSuper || !i.superOnly)
        .toList();
    if (visibleItems.isEmpty) return [];

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          section.title.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: AppTheme.textMuted,
          ),
        ),
      ),
      for (final item in visibleItems) _navTile(item),
    ];
  }

  // The collapsible "User view" group: a toggle header plus the user screens
  // when expanded.
  List<Widget> _buildUserViewGroup() {
    return [
      Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _userExpanded = !_userExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              children: [
                const Icon(
                  Icons.apps_outlined,
                  size: 20,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'User view',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  _userExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: AppTheme.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
      if (_userExpanded)
        for (final item in _userAppItems) _navTile(item, indented: true),
    ];
  }

  Widget _navTile(_NavItem item, {bool indented = false}) {
    final selected = item.page == widget.current;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onSelect(item.page),
        child: Container(
          padding: EdgeInsets.only(
            left: indented ? 34 : 16,
            right: 16,
            top: 11,
            bottom: 11,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.10)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: selected ? AppTheme.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                size: 20,
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
              ),
              const SizedBox(width: 12),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppTheme.primary : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomItem(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color color = AppTheme.textSecondary,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: color),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: onTap,
    );
  }
}
