// lib/screens/admin/admin_shell.dart
// Self-contained root for admin/superadmin. A role-aware sidebar (persistent on
// wide screens, a drawer on narrow) drives a content area that renders either
// an admin page or one of the user-app screens — so an admin lands here on
// login and can still use the whole user app from the sidebar's "App" section.
// The top bar carries the profile avatar (settings / change password / logout).

import 'package:flutter/material.dart';
import '../../models/profile_models.dart';
import '../../services/session_service.dart';
import '../../widgets/app_theme.dart';
import '../../widgets/profile_avatar_button.dart';
import 'shared/pages/audit_logs_page.dart';
import 'shared/pages/dashboard_page.dart';
import 'shared/pages/gap_report_page.dart';
import 'shared/pages/prediction_logs_page.dart';
import 'shared/pages/prompt_tuning_page.dart';
import 'shared/pages/security_page.dart';
import 'shared/pages/system_health_page.dart';
import 'shared/pages/user_management_page.dart';
import 'shared/widgets/admin_sidebar.dart';
import 'shared/widgets/notification_bell.dart';
import '../super_admin/pages/adjustment_detail_screen.dart';
import '../super_admin/pages/maintenance_page.dart';
import '../super_admin/pages/system_config_page.dart';
// User-app screens, reachable from the sidebar's "App" section.
import '../dashboard/dashboard_screen.dart';
import '../yield/yield_screen.dart';
import '../price/price_screen.dart';
import '../weather/weather_screen.dart';
import '../recommend/recommend_screen.dart';
import '../demand/demand_screen.dart';
import '../chat/chat_screen.dart';

class AdminShell extends StatefulWidget {
  final String role; // 'admin' | 'superadmin'
  final UserProfile? profile;
  final ValueChanged<UserProfile> onProfileUpdated;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenChangePassword;

  const AdminShell({
    super.key,
    required this.role,
    required this.profile,
    required this.onProfileUpdated,
    required this.onOpenSettings,
    required this.onOpenChangePassword,
  });

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  static const double _wideBreakpoint = 820;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  AdminPage _page = AdminPage.dashboard;

  bool get _isSuper => widget.role == 'superadmin';

  bool _isSuperOnly(AdminPage p) =>
      p == AdminPage.systemConfig ||
      p == AdminPage.maintenance ||
      p == AdminPage.promptTuning;

  void _select(AdminPage page) {
    // Guard: never render a superadmin-only page for an admin.
    if (!_isSuper && _isSuperOnly(page)) return;
    setState(() => _page = page);
  }

  // Deep-link from an adjustment notification. The detail view is
  // superadmin-gated (backend returns 403 for admins), so a plain admin only
  // gets the notification marked read — no dead-end navigation.
  void _openAdjustment(String adjustmentId) {
    if (!_isSuper) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdjustmentDetailScreen(adjustmentId: adjustmentId),
      ),
    );
  }

  // Maps a user screen's base-index navigation (0=Home … 6=Chat) onto the
  // corresponding sidebar page so in-app deep links still work here.
  void _navigateUser(int index) {
    if (index >= 0 && index < userAppPages.length) {
      _select(userAppPages[index]);
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed == true) await SessionService.logout();
  }

  Widget _buildPage() {
    switch (_page) {
      case AdminPage.dashboard:
        return DashboardPage(role: widget.role, onNavigate: _select);
      case AdminPage.systemHealth:
        return const SystemHealthPage();
      case AdminPage.users:
        return UserManagementPage(role: widget.role);
      case AdminPage.gapReport:
        return GapReportPage(role: widget.role, onNavigate: _select);
      case AdminPage.promptTuning:
        return const PromptTuningPage();
      case AdminPage.auditLogs:
        return AuditLogsPage(role: widget.role);
      case AdminPage.predictionLogs:
        return const PredictionLogsPage();
      case AdminPage.security:
        return SecurityPage(role: widget.role);
      case AdminPage.systemConfig:
        return const SystemConfigPage();
      case AdminPage.maintenance:
        return const MaintenancePage();
      // ── User-app views ──
      case AdminPage.appHome:
        return DashboardScreen(onNavigate: _navigateUser);
      case AdminPage.appYield:
        return YieldScreen(onNavigate: _navigateUser);
      case AdminPage.appPrice:
        return const PriceScreen();
      case AdminPage.appWeather:
        return const WeatherScreen();
      case AdminPage.appRecommend:
        return const RecommendScreen();
      case AdminPage.appDemand:
        return const DemandScreen();
      case AdminPage.appChat:
        return const ChatScreen();
    }
  }

  AdminSidebar _buildSidebar({required bool inDrawer}) {
    return AdminSidebar(
      role: widget.role,
      current: _page,
      onSelect: (page) {
        if (inDrawer) _scaffoldKey.currentState?.closeDrawer();
        _select(page);
      },
      onLogout: () {
        if (inDrawer) _scaffoldKey.currentState?.closeDrawer();
        _confirmLogout();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= _wideBreakpoint;
    final headerColor = _isSuper ? const Color(0xFF7B1616) : AppTheme.primary;

    // KeyedSubtree per page → each page's State is built fresh on navigation
    // (every page loads its own data on init).
    final content = Container(
      color: AppTheme.background,
      child: KeyedSubtree(key: ValueKey(_page), child: _buildPage()),
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.background,
      drawer: wide ? null : Drawer(child: _buildSidebar(inDrawer: true)),
      appBar: AppBar(
        backgroundColor: headerColor,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(adminPageTitle(_page)),
        actions: [
          NotificationBell(
            onOpenGapReport: () => _select(AdminPage.gapReport),
            onOpenAdjustment: _openAdjustment,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ProfileAvatarButton(
              profile: widget.profile,
              onProfileUpdated: widget.onProfileUpdated,
              onOpenSettings: widget.onOpenSettings,
              onOpenChangePassword: widget.onOpenChangePassword,
              onLogout: SessionService.logout,
            ),
          ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                _buildSidebar(inDrawer: false),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
    );
  }
}
