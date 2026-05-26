import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/admin_service.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  final _service = AdminService();
  final _money = NumberFormat('#,##0', 'es_CL');
  bool _loading = true;
  bool _actionLoading = false;
  String? _error;
  AdminMetrics? _metrics;
  List<AdminUser> _users = [];
  List<AdminDriver> _drivers = [];
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (!ref.read(authProvider).isAuthenticated) {
      await ref.read(authProvider.notifier).checkAuth();
    }
    if (!mounted) return;
    if (ref.read(authProvider).user?.role != 'admin') {
      setState(() {
        _loading = false;
        _error = null;
      });
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        _service.getMetrics(),
        _service.listUsers(),
        _service.listDrivers(),
      ]);
      if (!mounted) return;
      setState(() {
        _metrics = results[0] as AdminMetrics;
        _users = results[1] as List<AdminUser>;
        _drivers = results[2] as List<AdminDriver>;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo cargar el panel admin.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(authProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  Future<void> _approve(AdminDriver driver) async {
    await _runDriverAction(
      success: '${driver.fullName} aprobado',
      action: () => _service.approveDriver(driver.id),
    );
  }

  Future<void> _reject(AdminDriver driver) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RejectDriverDialog(),
    );
    if (reason == null || reason.trim().isEmpty) return;
    await _runDriverAction(
      success: '${driver.fullName} rechazado',
      action: () => _service.rejectDriver(driver.id, reason.trim()),
    );
  }

  Future<void> _runDriverAction({
    required String success,
    required Future<void> Function() action,
  }) async {
    HapticFeedback.lightImpact();
    setState(() => _actionLoading = true);
    try {
      await action();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success), backgroundColor: AppTheme.success),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo completar la acción'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final width = MediaQuery.of(context).size.width;
    final compact = width < 720;
    final isAdmin = auth.user?.role == 'admin';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Administración'),
          actions: [
            IconButton(
              tooltip: 'Actualizar',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: !isAdmin && !_loading
                  ? _AccessDenied(onLogin: () => context.go('/login'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          compact ? 14 : 24,
                          18,
                          compact ? 14 : 24,
                          28,
                        ),
                        children: [
                          _Header(
                            name: auth.user?.fullName ?? 'Admin',
                            email: auth.user?.email ?? '',
                          ),
                          const SizedBox(height: 16),
                          if (_error != null) ...[
                            _ErrorBanner(message: _error!),
                            const SizedBox(height: 12),
                          ],
                          _MetricsGrid(
                            metrics: _metrics,
                            loading: _loading,
                            money: _money,
                          ),
                          if (!_loading && _metrics != null) ...[
                            const SizedBox(height: 12),
                            _MonitoringPanel(
                              metrics: _metrics!,
                              money: _money,
                            ),
                          ],
                          const SizedBox(height: 16),
                          _TabSelector(
                            index: _tabIndex,
                            userCount: _users.length,
                            driverCount: _drivers.length,
                            onChanged: (value) =>
                                setState(() => _tabIndex = value),
                          ),
                          const SizedBox(height: 12),
                          if (_loading)
                            const _LoadingPanel()
                          else if (_tabIndex == 0)
                            _UsersPanel(users: _users)
                          else
                            _DriversPanel(
                              drivers: _drivers,
                              actionLoading: _actionLoading,
                              onApprove: _approve,
                              onReject: _reject,
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String name;
  final String email;

  const _Header({required this.name, required this.email});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.midnight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Panel admin',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppTheme.midnight,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$name · $email',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.slate400,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _AccessDenied extends StatelessWidget {
  final VoidCallback onLogin;

  const _AccessDenied({required this.onLogin});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: _adminBox(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.midnight.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: AppTheme.midnight,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Acceso restringido',
                style: TextStyle(
                  color: AppTheme.midnight,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Inicia sesión con una cuenta admin para ver este panel.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.slate400, fontSize: 13),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: 220,
                child: ElevatedButton.icon(
                  onPressed: onLogin,
                  icon: const Icon(Icons.login_rounded, size: 18),
                  label: const Text('Iniciar sesión'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _MetricsGrid extends StatelessWidget {
  final AdminMetrics? metrics;
  final bool loading;
  final NumberFormat money;

  const _MetricsGrid({
    required this.metrics,
    required this.loading,
    required this.money,
  });

  @override
  Widget build(BuildContext context) {
    final data = [
      _MetricData(
        label: 'Usuarios activos',
        value: loading
            ? '...'
            : '${metrics?.activeUsers ?? 0}/${metrics?.totalUsers ?? 0}',
        icon: Icons.group_outlined,
        color: AppTheme.primary,
      ),
      _MetricData(
        label: 'Conductores',
        value: loading
            ? '...'
            : '${metrics?.approvedDrivers ?? 0}/${metrics?.totalDrivers ?? 0}',
        icon: Icons.badge_outlined,
        color: AppTheme.success,
      ),
      _MetricData(
        label: 'Fletes activos',
        value: loading ? '...' : '${metrics?.activeFreights ?? 0}',
        icon: Icons.local_shipping_outlined,
        color: AppTheme.urgent,
      ),
      _MetricData(
        label: 'Pagos autorizados',
        value: loading
            ? '...'
            : '\$${money.format(metrics?.authorizedPaymentsClp ?? 0)}',
        icon: Icons.payments_outlined,
        color: AppTheme.accent,
      ),
      _MetricData(
        label: 'Comisión plataforma',
        value: loading
            ? '...'
            : '\$${money.format(metrics?.platformCommissionClp ?? 0)}',
        icon: Icons.account_balance_wallet_outlined,
        color: AppTheme.success,
      ),
      _MetricData(
        label: 'Comisión pendiente',
        value: loading
            ? '...'
            : '\$${money.format(metrics?.pendingPlatformCommissionClp ?? 0)}',
        icon: Icons.hourglass_bottom_rounded,
        color: AppTheme.warning,
      ),
      _MetricData(
        label: 'Pago conductores',
        value: loading
            ? '...'
            : '\$${money.format(metrics?.driverPayoutClp ?? 0)}',
        icon: Icons.handshake_outlined,
        color: AppTheme.midnight,
      ),
      _MetricData(
        label: 'Por aprobar',
        value: loading ? '...' : '${metrics?.pendingDrivers ?? 0}',
        icon: Icons.fact_check_outlined,
        color: AppTheme.error,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 980
            ? 4
            : constraints.maxWidth > 520
                ? 2
                : 1;
        return GridView.builder(
          itemCount: data.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: columns == 1 ? 4.6 : 3.1,
          ),
          itemBuilder: (_, i) => _MetricTile(data: data[i]),
        );
      },
    );
  }
}

class _MetricData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

class _MetricTile extends StatelessWidget {
  final _MetricData data;

  const _MetricTile({required this.data});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: _adminBox(),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: data.color.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(data.icon, color: data.color, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    data.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.midnight,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.label,
                    style: const TextStyle(
                      color: AppTheme.slate400,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _MonitoringPanel extends StatelessWidget {
  final AdminMetrics metrics;
  final NumberFormat money;

  const _MonitoringPanel({required this.metrics, required this.money});

  @override
  Widget build(BuildContext context) {
    final panels = [
      _BreakdownPanel(
        title: 'Fletes por estado',
        icon: Icons.route_outlined,
        total: metrics.totalFreights,
        items: [
          _BreakdownItem(
            label: 'Pendientes',
            count: metrics.freightsByStatus['pending'] ?? 0,
            color: AppTheme.warning,
          ),
          _BreakdownItem(
            label: 'Aceptados',
            count: metrics.freightsByStatus['accepted'] ?? 0,
            color: AppTheme.primary,
          ),
          _BreakdownItem(
            label: 'En curso',
            count: metrics.freightsByStatus['in_progress'] ?? 0,
            color: AppTheme.accent,
          ),
          _BreakdownItem(
            label: 'Completados',
            count: metrics.completedFreights,
            color: AppTheme.success,
          ),
          _BreakdownItem(
            label: 'Cancelados',
            count: metrics.freightsByStatus['cancelled'] ?? 0,
            color: AppTheme.error,
          ),
        ],
      ),
      _BreakdownPanel(
        title: 'Conductores por estado',
        icon: Icons.badge_outlined,
        total: metrics.totalDrivers,
        items: [
          _BreakdownItem(
            label: 'Aprobados',
            count: metrics.approvedDrivers,
            color: AppTheme.success,
          ),
          _BreakdownItem(
            label: 'Pendientes',
            count: metrics.pendingDrivers,
            color: AppTheme.warning,
          ),
          _BreakdownItem(
            label: 'Suspendidos',
            count: metrics.suspendedDrivers,
            color: AppTheme.error,
          ),
        ],
      ),
      _FinancePanel(metrics: metrics, money: money),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 980) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < panels.length; i++) ...[
                Expanded(child: panels[i]),
                if (i != panels.length - 1) const SizedBox(width: 10),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < panels.length; i++) ...[
              panels[i],
              if (i != panels.length - 1) const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _BreakdownItem {
  final String label;
  final int count;
  final Color color;

  const _BreakdownItem({
    required this.label,
    required this.count,
    required this.color,
  });
}

class _BreakdownPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final int total;
  final List<_BreakdownItem> items;

  const _BreakdownPanel({
    required this.title,
    required this.icon,
    required this.total,
    required this.items,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: _adminBox(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelTitle(icon: icon, title: title),
            const SizedBox(height: 12),
            for (final item in items) ...[
              _BreakdownRow(item: item, total: total),
              if (item != items.last) const SizedBox(height: 10),
            ],
          ],
        ),
      );
}

class _BreakdownRow extends StatelessWidget {
  final _BreakdownItem item;
  final int total;

  const _BreakdownRow({required this.item, required this.total});

  @override
  Widget build(BuildContext context) {
    final progress = total <= 0 ? 0.0 : item.count / total;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.label,
                style: const TextStyle(
                  color: AppTheme.slate600,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${item.count}',
              style: const TextStyle(
                color: AppTheme.midnight,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: 6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              color: item.color,
              backgroundColor: AppTheme.slate100,
            ),
          ),
        ),
      ],
    );
  }
}

class _FinancePanel extends StatelessWidget {
  final AdminMetrics metrics;
  final NumberFormat money;

  const _FinancePanel({required this.metrics, required this.money});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: _adminBox(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelTitle(
              icon: Icons.insights_outlined,
              title: 'Salud financiera',
            ),
            const SizedBox(height: 12),
            _FinanceRow(
              label: 'Pagos autorizados',
              value: '\$${money.format(metrics.authorizedPaymentsClp)}',
            ),
            _FinanceRow(
              label: 'Tickets autorizados',
              value: '${metrics.authorizedPaymentsCount}',
            ),
            _FinanceRow(
              label: 'Ticket promedio',
              value: '\$${money.format(metrics.averageAuthorizedTicketClp)}',
            ),
            _FinanceRow(
              label: 'Bruto completado',
              value: '\$${money.format(metrics.grossCompletedClp)}',
            ),
            _FinanceRow(
              label: 'Finalización',
              value: '${metrics.completionRate}%',
            ),
          ],
        ),
      );
}

class _FinanceRow extends StatelessWidget {
  final String label;
  final String value;

  const _FinanceRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppTheme.slate400,
                  fontSize: 12,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: AppTheme.midnight,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}

class _PanelTitle extends StatelessWidget {
  final IconData icon;
  final String title;

  const _PanelTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, color: AppTheme.slate400, size: 16),
          const SizedBox(width: 7),
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.midnight,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
}

class _TabSelector extends StatelessWidget {
  final int index;
  final int userCount;
  final int driverCount;
  final ValueChanged<int> onChanged;

  const _TabSelector({
    required this.index,
    required this.userCount,
    required this.driverCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTheme.slate100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            _TabButton(
              selected: index == 0,
              icon: Icons.people_outline_rounded,
              label: 'Usuarios',
              count: userCount,
              onTap: () => onChanged(0),
            ),
            _TabButton(
              selected: index == 1,
              icon: Icons.local_shipping_outlined,
              label: 'Conductores',
              count: driverCount,
              onTap: () => onChanged(1),
            ),
          ],
        ),
      );
}

class _TabButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  const _TabButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 42,
            decoration: BoxDecoration(
              color: selected ? AppTheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              border: selected
                  ? Border.all(color: AppTheme.slate200, width: 0.5)
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: selected ? AppTheme.midnight : AppTheme.slate400,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? AppTheme.midnight : AppTheme.slate400,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 7),
                _CountBadge(count: count, selected: selected),
              ],
            ),
          ),
        ),
      );
}

class _CountBadge extends StatelessWidget {
  final int count;
  final bool selected;

  const _CountBadge({required this.count, required this.selected});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color:
              selected ? AppTheme.primary.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$count',
          style: TextStyle(
            color: selected ? AppTheme.primary : AppTheme.slate400,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _UsersPanel extends StatelessWidget {
  final List<AdminUser> users;

  const _UsersPanel({required this.users});

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.people_outline_rounded,
        text: 'Sin usuarios registrados',
      );
    }
    return _DataPanel(
      child: Column(
        children: [
          for (var i = 0; i < users.length; i++) ...[
            _UserRow(user: users[i]),
            if (i != users.length - 1) const Divider(),
          ],
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final AdminUser user;

  const _UserRow({required this.user});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _Avatar(label: user.fullName, active: user.isActive),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.midnight,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${user.email} · ${user.phone}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.slate400,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _RoleBadge(role: user.role),
            const SizedBox(width: 8),
            _StatusPill(
              label: user.isActive ? 'Activo' : 'Suspendido',
              color: user.isActive ? AppTheme.success : AppTheme.error,
            ),
          ],
        ),
      );
}

class _DriversPanel extends StatelessWidget {
  final List<AdminDriver> drivers;
  final bool actionLoading;
  final ValueChanged<AdminDriver> onApprove;
  final ValueChanged<AdminDriver> onReject;

  const _DriversPanel({
    required this.drivers,
    required this.actionLoading,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    if (drivers.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.local_shipping_outlined,
        text: 'Sin conductores registrados',
      );
    }
    return _DataPanel(
      child: Column(
        children: [
          for (var i = 0; i < drivers.length; i++) ...[
            _DriverRow(
              driver: drivers[i],
              actionLoading: actionLoading,
              onApprove: onApprove,
              onReject: onReject,
            ),
            if (i != drivers.length - 1) const Divider(),
          ],
        ],
      ),
    );
  }
}

class _DriverRow extends StatelessWidget {
  final AdminDriver driver;
  final bool actionLoading;
  final ValueChanged<AdminDriver> onApprove;
  final ValueChanged<AdminDriver> onReject;

  const _DriverRow({
    required this.driver,
    required this.actionLoading,
    required this.onApprove,
    required this.onReject,
  });

  bool get _pending => driver.status == 'pending';
  bool get _approved => driver.status == 'approved';

  @override
  Widget build(BuildContext context) {
    final vehicle = driver.vehicles.isNotEmpty ? driver.vehicles.first : null;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      driver.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.midnight,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _DriverStatus(status: driver.status),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${driver.email} · ${driver.phone}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.slate400,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              _VehicleLine(vehicle: vehicle),
              const SizedBox(height: 10),
              _DriverDocuments(driver: driver),
            ],
          );

          final actions = _DriverActions(
            pending: _pending,
            approved: _approved,
            loading: actionLoading,
            onApprove: () => onApprove(driver),
            onReject: () => onReject(driver),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: 12),
                actions,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 16),
              SizedBox(width: 240, child: actions),
            ],
          );
        },
      ),
    );
  }
}

class _DriverActions extends StatelessWidget {
  final bool pending;
  final bool approved;
  final bool loading;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _DriverActions({
    required this.pending,
    required this.approved,
    required this.loading,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    if (!pending) {
      return _StatusPill(
        label: approved ? 'Listo para operar' : 'Sin acción pendiente',
        color: approved ? AppTheme.success : AppTheme.slate400,
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: loading ? null : onReject,
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Rechazar'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.error,
              minimumSize: const Size(0, 42),
              side: BorderSide(color: AppTheme.error.withValues(alpha: 0.35)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: loading ? null : onApprove,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Aprobar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.success,
              minimumSize: const Size(0, 42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DriverDocuments extends StatelessWidget {
  final AdminDriver driver;

  const _DriverDocuments({required this.driver});

  @override
  Widget build(BuildContext context) {
    final docs = [
      _DocumentLink('Licencia', driver.licenseImageUrl),
      _DocumentLink(
        'Permiso',
        driver.circulationPermitUrl ?? driver.vehicleDocUrl,
      ),
      _DocumentLink('Revision', driver.technicalReviewUrl),
      _DocumentLink('SOAP', driver.soapUrl),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: docs
          .map(
            (doc) => _DocumentChip(
              label: doc.label,
              url: doc.url,
            ),
          )
          .toList(),
    );
  }
}

class _DocumentChip extends StatelessWidget {
  final String label;
  final String? url;

  const _DocumentChip({required this.label, required this.url});

  Future<void> _open() async {
    final value = url;
    if (value == null || value.isEmpty) return;
    final uri = Uri.tryParse(value);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final available = url != null && url!.isNotEmpty;
    return InkWell(
      onTap: available ? _open : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: available
              ? AppTheme.primary.withValues(alpha: 0.08)
              : AppTheme.slate100,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: available
                ? AppTheme.primary.withValues(alpha: 0.28)
                : AppTheme.slate200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              available ? Icons.visibility_outlined : Icons.error_outline,
              size: 14,
              color: available ? AppTheme.primary : AppTheme.warning,
            ),
            const SizedBox(width: 5),
            Text(
              available ? label : 'Falta $label',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: available ? AppTheme.primary : AppTheme.warning,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentLink {
  final String label;
  final String? url;

  const _DocumentLink(this.label, this.url);
}

class _VehicleLine extends StatelessWidget {
  final AdminVehicle? vehicle;

  const _VehicleLine({required this.vehicle});

  @override
  Widget build(BuildContext context) {
    if (vehicle == null) {
      return const Text(
        'Vehículo no registrado',
        style: TextStyle(color: AppTheme.warning, fontSize: 12),
      );
    }
    return Row(
      children: [
        const Icon(Icons.directions_car_outlined,
            color: AppTheme.slate400, size: 15),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${vehicle!.brand} ${vehicle!.model} ${vehicle!.year} · ${vehicle!.plate} · ${vehicle!.color}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.slate600, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _RejectDriverDialog extends StatefulWidget {
  const _RejectDriverDialog();

  @override
  State<_RejectDriverDialog> createState() => _RejectDriverDialogState();
}

class _RejectDriverDialogState extends State<_RejectDriverDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Rechazar conductor'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Motivo',
            hintText: 'Ej: licencia vencida',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _controller.text),
            child: const Text('Rechazar'),
          ),
        ],
      );
}

class _DataPanel extends StatelessWidget {
  final Widget child;

  const _DataPanel({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        decoration: _adminBox(),
        child: child,
      );
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) => Container(
        height: 180,
        alignment: Alignment.center,
        decoration: _adminBox(),
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
}

class _EmptyPanel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyPanel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        height: 180,
        alignment: Alignment.center,
        decoration: _adminBox(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppTheme.slate400, size: 36),
            const SizedBox(height: 10),
            Text(text, style: const TextStyle(color: AppTheme.slate400)),
          ],
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppTheme.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: AppTheme.error, fontSize: 13),
              ),
            ),
          ],
        ),
      );
}

class _Avatar extends StatelessWidget {
  final String label;
  final bool active;

  const _Avatar({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final initial = label.trim().isEmpty ? '?' : label.trim()[0].toUpperCase();
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: active
            ? AppTheme.primary.withValues(alpha: 0.1)
            : AppTheme.slate100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: active ? AppTheme.primary : AppTheme.slate400,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;

  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final color = switch (role) {
      'admin' => AppTheme.midnight,
      'driver' => AppTheme.success,
      _ => AppTheme.primary,
    };
    final label = switch (role) {
      'admin' => 'Admin',
      'driver' => 'Conductor',
      _ => 'Cliente',
    };
    return _StatusPill(label: label, color: color);
  }
}

class _DriverStatus extends StatelessWidget {
  final String status;

  const _DriverStatus({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'approved' => AppTheme.success,
      'pending' => AppTheme.warning,
      'suspended' => AppTheme.error,
      _ => AppTheme.slate400,
    };
    final label = switch (status) {
      'approved' => 'Aprobado',
      'pending' => 'Pendiente',
      'suspended' => 'Suspendido',
      _ => status,
    };
    return _StatusPill(label: label, color: color);
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

BoxDecoration _adminBox() => BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppTheme.slate200, width: 0.5),
    );
