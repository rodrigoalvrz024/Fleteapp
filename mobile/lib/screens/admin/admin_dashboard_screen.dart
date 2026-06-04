import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_theme.dart';
import '../../models/payout_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/admin_service.dart';
import '../../utils/file_download.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  final _service = AdminService();
  final _money = NumberFormat('#,##0', 'es_CL');
  final _auditEntityIdController = TextEditingController();
  final _auditActorIdController = TextEditingController();
  bool _loading = true;
  bool _auditLoading = false;
  bool _actionLoading = false;
  String? _error;
  AdminMetrics? _metrics;
  List<AdminUser> _users = [];
  List<AdminDriver> _drivers = [];
  List<AdminPrivacyRequest> _privacyRequests = [];
  List<AdminAuditEvent> _auditEvents = [];
  List<AdminOperationalAlert> _alerts = [];
  List<AdminLegalConsent> _legalConsents = [];
  List<PayoutModel> _payouts = [];
  String _auditEntityType = '';
  String _auditEventType = '';
  String _auditActorRole = '';
  DateTime? _auditFromDate;
  DateTime? _auditToDate;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _auditEntityIdController.dispose();
    _auditActorIdController.dispose();
    super.dispose();
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

  String? _auditDateParam(DateTime? value) {
    if (value == null) return null;
    return DateFormat('yyyy-MM-dd').format(value);
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
        _service.listPrivacyRequests(),
        _service.listOperationalAlerts(),
        _service.listPayouts(),
        _service.listLegalConsents(),
        _service.listAuditEvents(
          limit: 100,
          entityType: _auditEntityType,
          entityId: _auditEntityIdController.text.trim(),
          eventType: _auditEventType,
          actorUserId: _auditActorIdController.text.trim(),
          actorRole: _auditActorRole,
          occurredFrom: _auditDateParam(_auditFromDate),
          occurredTo: _auditDateParam(_auditToDate),
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _metrics = results[0] as AdminMetrics;
        _users = results[1] as List<AdminUser>;
        _drivers = results[2] as List<AdminDriver>;
        _privacyRequests = results[3] as List<AdminPrivacyRequest>;
        _alerts = results[4] as List<AdminOperationalAlert>;
        _payouts = results[5] as List<PayoutModel>;
        _legalConsents = results[6] as List<AdminLegalConsent>;
        _auditEvents = results[7] as List<AdminAuditEvent>;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo cargar el panel admin.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAuditEvents() async {
    setState(() {
      _auditLoading = true;
      _error = null;
    });

    try {
      final events = await _service.listAuditEvents(
        limit: 100,
        entityType: _auditEntityType,
        entityId: _auditEntityIdController.text.trim(),
        eventType: _auditEventType,
        actorUserId: _auditActorIdController.text.trim(),
        actorRole: _auditActorRole,
        occurredFrom: _auditDateParam(_auditFromDate),
        occurredTo: _auditDateParam(_auditToDate),
      );
      if (!mounted) return;
      setState(() => _auditEvents = events);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo cargar el historial.');
      }
    } finally {
      if (mounted) setState(() => _auditLoading = false);
    }
  }

  Future<void> _clearAuditFilters() async {
    _auditEntityIdController.clear();
    _auditActorIdController.clear();
    setState(() {
      _auditEntityType = '';
      _auditEventType = '';
      _auditActorRole = '';
      _auditFromDate = null;
      _auditToDate = null;
    });
    await _loadAuditEvents();
  }

  Future<void> _pickAuditDate({required bool from}) async {
    final now = DateTime.now();
    final current = from ? _auditFromDate : _auditToDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2025),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      if (from) {
        _auditFromDate = picked;
        if (_auditToDate != null && _auditToDate!.isBefore(picked)) {
          _auditToDate = picked;
        }
      } else {
        _auditToDate = picked;
        if (_auditFromDate != null && _auditFromDate!.isAfter(picked)) {
          _auditFromDate = picked;
        }
      }
    });
  }

  Future<void> _exportAuditEvents() async {
    setState(() => _auditLoading = true);
    try {
      final csv = await _service.exportAuditEventsCsv(
        limit: 5000,
        entityType: _auditEntityType,
        entityId: _auditEntityIdController.text.trim(),
        eventType: _auditEventType,
        actorUserId: _auditActorIdController.text.trim(),
        actorRole: _auditActorRole,
        occurredFrom: _auditDateParam(_auditFromDate),
        occurredTo: _auditDateParam(_auditToDate),
      );
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      await downloadTextFile(
        filename: 'fleteapp_historial_$stamp.csv',
        content: csv,
        mimeType: 'text/csv;charset=utf-8',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Historial exportado en CSV'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo exportar el historial'),
          backgroundColor: AppTheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _auditLoading = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(authProvider.notifier).logout();
    if (mounted) context.go('/auth/login');
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

  Future<void> _deleteDocuments(AdminDriver driver) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteDocumentsDialog(),
    );
    if (reason == null) return;
    await _runDriverAction(
      success: 'Documentos de ${driver.fullName} eliminados',
      action: () => _service.deleteDriverDocuments(
        driver.id,
        reason: reason.trim(),
      ),
    );
  }

  Future<void> _updatePrivacyRequest(
    AdminPrivacyRequest request,
    String status,
  ) async {
    final needsResponse = status == 'resolved' || status == 'rejected';
    final response = needsResponse
        ? await showDialog<String>(
            context: context,
            builder: (_) => _PrivacyRequestDialog(status: status),
          )
        : '';
    if (response == null) return;

    await _runDriverAction(
      success: 'Solicitud ${request.id} actualizada',
      action: () => _service.updatePrivacyRequest(
        requestId: request.id,
        status: status,
        response: response.trim(),
      ),
    );
  }

  Future<void> _updatePayout(PayoutModel payout) async {
    final update = await showDialog<_PayoutUpdateData>(
      context: context,
      builder: (_) => _PayoutUpdateDialog(payout: payout),
    );
    if (update == null) return;

    await _runDriverAction(
      success: 'Liquidacion #${payout.id} actualizada',
      action: () => _service.updatePayout(
        payoutId: payout.id,
        status: update.status,
        scheduledFor: update.scheduledFor,
        transferReference: update.transferReference,
        note: update.note,
      ),
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
                  ? _AccessDenied(onLogin: () => context.go('/auth/login'))
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
                          if (!_loading) ...[
                            const SizedBox(height: 12),
                            _OperationalAlertsPanel(alerts: _alerts),
                          ],
                          const SizedBox(height: 16),
                          _TabSelector(
                            index: _tabIndex,
                            userCount: _users.length,
                            driverCount: _drivers.length,
                            privacyCount: _privacyRequests.length,
                            payoutCount: _payouts.length,
                            auditCount: _auditEvents.length,
                            legalCount: _legalConsents.length,
                            onChanged: (value) =>
                                setState(() => _tabIndex = value),
                          ),
                          const SizedBox(height: 12),
                          if (_loading)
                            const _LoadingPanel()
                          else if (_tabIndex == 0)
                            _UsersPanel(users: _users)
                          else if (_tabIndex == 1)
                            _DriversPanel(
                              drivers: _drivers,
                              actionLoading: _actionLoading,
                              onApprove: _approve,
                              onReject: _reject,
                              onDeleteDocuments: _deleteDocuments,
                            )
                          else if (_tabIndex == 2)
                            _PayoutsPanel(
                              payouts: _payouts,
                              money: _money,
                              actionLoading: _actionLoading,
                              onUpdate: _updatePayout,
                            )
                          else if (_tabIndex == 3)
                            _PrivacyRequestsPanel(
                              requests: _privacyRequests,
                              actionLoading: _actionLoading,
                              onUpdate: _updatePrivacyRequest,
                            )
                          else if (_tabIndex == 4)
                            _AuditEventsPanel(
                              events: _auditEvents,
                              loading: _auditLoading,
                              selectedEntityType: _auditEntityType,
                              selectedEventType: _auditEventType,
                              selectedActorRole: _auditActorRole,
                              fromDate: _auditFromDate,
                              toDate: _auditToDate,
                              entityIdController: _auditEntityIdController,
                              actorIdController: _auditActorIdController,
                              onEntityTypeChanged: (value) => setState(
                                () => _auditEntityType = value ?? '',
                              ),
                              onEventTypeChanged: (value) => setState(
                                () => _auditEventType = value ?? '',
                              ),
                              onActorRoleChanged: (value) => setState(
                                () => _auditActorRole = value ?? '',
                              ),
                              onPickFromDate: () => _pickAuditDate(from: true),
                              onPickToDate: () => _pickAuditDate(from: false),
                              onApplyFilters: _loadAuditEvents,
                              onClearFilters: _clearAuditFilters,
                              onExportCsv: _exportAuditEvents,
                            )
                          else
                            _LegalConsentsPanel(consents: _legalConsents),
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
        label: 'Por pagar conductores',
        value: loading
            ? '...'
            : '\$${money.format(metrics?.pendingDriverPayoutClp ?? 0)}',
        icon: Icons.pending_actions_outlined,
        color: AppTheme.warning,
      ),
      _MetricData(
        label: 'Pagado conductores',
        value: loading
            ? '...'
            : '\$${money.format(metrics?.paidDriverPayoutClp ?? 0)}',
        icon: Icons.handshake_outlined,
        color: AppTheme.success,
      ),
      _MetricData(
        label: 'Por aprobar',
        value: loading ? '...' : '${metrics?.pendingDrivers ?? 0}',
        icon: Icons.fact_check_outlined,
        color: AppTheme.error,
      ),
      _MetricData(
        label: 'Solicitudes datos',
        value: loading ? '...' : '${metrics?.pendingPrivacyRequests ?? 0}',
        icon: Icons.privacy_tip_outlined,
        color: AppTheme.midnight,
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

class _OperationalAlertsPanel extends StatelessWidget {
  final List<AdminOperationalAlert> alerts;

  const _OperationalAlertsPanel({required this.alerts});

  Color _color(String severity) => switch (severity) {
        'critical' => AppTheme.error,
        'warning' => AppTheme.warning,
        'success' => AppTheme.success,
        _ => AppTheme.primary,
      };

  IconData _icon(String severity) => switch (severity) {
        'critical' => Icons.error_outline_rounded,
        'warning' => Icons.warning_amber_rounded,
        'success' => Icons.check_circle_outline_rounded,
        _ => Icons.info_outline_rounded,
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: _adminBox(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PanelTitle(
              icon: Icons.monitor_heart_outlined,
              title: 'Alertas operacionales',
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < alerts.length; i++) ...[
              _OperationalAlertRow(
                alert: alerts[i],
                color: _color(alerts[i].severity),
                icon: _icon(alerts[i].severity),
              ),
              if (i != alerts.length - 1) const Divider(height: 18),
            ],
          ],
        ),
      );
}

class _OperationalAlertRow extends StatelessWidget {
  final AdminOperationalAlert alert;
  final Color color;
  final IconData icon;

  const _OperationalAlertRow({
    required this.alert,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        alert.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.midnight,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _StatusPill(label: '${alert.count}', color: color),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  alert.message,
                  style: const TextStyle(
                    color: AppTheme.slate600,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                if (alert.action.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    alert.action,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
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
              label: 'Liquidaciones por pagar',
              value: '\$${money.format(metrics.pendingDriverPayoutClp)}',
            ),
            _FinanceRow(
              label: 'Liquidaciones pagadas',
              value: '\$${money.format(metrics.paidDriverPayoutClp)}',
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
  final int privacyCount;
  final int payoutCount;
  final int auditCount;
  final int legalCount;
  final ValueChanged<int> onChanged;

  const _TabSelector({
    required this.index,
    required this.userCount,
    required this.driverCount,
    required this.privacyCount,
    required this.payoutCount,
    required this.auditCount,
    required this.legalCount,
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
              label: 'Revision',
              count: driverCount,
              onTap: () => onChanged(1),
            ),
            _TabButton(
              selected: index == 2,
              icon: Icons.account_balance_wallet_outlined,
              label: 'Liquidaciones',
              count: payoutCount,
              onTap: () => onChanged(2),
            ),
            _TabButton(
              selected: index == 3,
              icon: Icons.privacy_tip_outlined,
              label: 'Datos',
              count: privacyCount,
              onTap: () => onChanged(3),
            ),
            _TabButton(
              selected: index == 4,
              icon: Icons.history_rounded,
              label: 'Historial',
              count: auditCount,
              onTap: () => onChanged(4),
            ),
            _TabButton(
              selected: index == 5,
              icon: Icons.verified_user_outlined,
              label: 'Legal',
              count: legalCount,
              onTap: () => onChanged(5),
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
        child: Tooltip(
          message: label,
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showLabel = constraints.maxWidth >= 92;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 17,
                        color: selected ? AppTheme.midnight : AppTheme.slate400,
                      ),
                      if (showLabel) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected
                                  ? AppTheme.midnight
                                  : AppTheme.slate400,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 7),
                      _CountBadge(count: count, selected: selected),
                    ],
                  );
                },
              ),
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

class _PayoutsPanel extends StatelessWidget {
  final List<PayoutModel> payouts;
  final NumberFormat money;
  final bool actionLoading;
  final ValueChanged<PayoutModel> onUpdate;

  const _PayoutsPanel({
    required this.payouts,
    required this.money,
    required this.actionLoading,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    if (payouts.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.account_balance_wallet_outlined,
        text: 'Sin liquidaciones registradas',
      );
    }
    return _DataPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: _PanelTitle(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Liquidaciones de conductores',
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < payouts.length; i++) ...[
            _PayoutRow(
              payout: payouts[i],
              money: money,
              actionLoading: actionLoading,
              onUpdate: onUpdate,
            ),
            if (i != payouts.length - 1) const Divider(),
          ],
        ],
      ),
    );
  }
}

class _PayoutRow extends StatelessWidget {
  final PayoutModel payout;
  final NumberFormat money;
  final bool actionLoading;
  final ValueChanged<PayoutModel> onUpdate;

  const _PayoutRow({
    required this.payout,
    required this.money,
    required this.actionLoading,
    required this.onUpdate,
  });

  Color get _statusColor => switch (payout.status) {
        'scheduled' => AppTheme.primary,
        'paid' => AppTheme.success,
        'failed' => AppTheme.error,
        _ => AppTheme.warning,
      };

  String _formatDate(DateTime? value) {
    if (value == null) return '';
    return DateFormat('dd/MM/yyyy HH:mm').format(value.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final milestone = switch (payout.status) {
      'scheduled' => 'Programada ${_formatDate(payout.scheduledFor)}',
      'paid' => 'Pagada ${_formatDate(payout.paidAt)}',
      'failed' => 'Requiere correccion',
      _ => 'Pendiente de programacion',
    };
    return Padding(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '\$${money.format(payout.amount)} CLP',
                      style: const TextStyle(
                        color: AppTheme.midnight,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _StatusPill(label: payout.statusLabel, color: _statusColor),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${payout.driverName} · Flete #${payout.freightId} · Pago #${payout.paymentId}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.slate600,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                milestone,
                style: const TextStyle(color: AppTheme.slate400, fontSize: 12),
              ),
              if ((payout.transferReference ?? '').isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  'Referencia: ${payout.transferReference}',
                  style:
                      const TextStyle(color: AppTheme.slate400, fontSize: 12),
                ),
              ],
              if ((payout.note ?? '').isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  payout.note!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: AppTheme.slate600, fontSize: 12),
                ),
              ],
            ],
          );
          final action = OutlinedButton.icon(
            onPressed: actionLoading ? null : () => onUpdate(payout),
            icon: const Icon(Icons.edit_calendar_outlined, size: 17),
            label: const Text('Gestionar'),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                if (payout.status != 'paid') ...[
                  const SizedBox(height: 12),
                  action,
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: details),
              if (payout.status != 'paid') ...[
                const SizedBox(width: 16),
                action,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PrivacyRequestsPanel extends StatelessWidget {
  final List<AdminPrivacyRequest> requests;
  final bool actionLoading;
  final void Function(AdminPrivacyRequest request, String status) onUpdate;

  const _PrivacyRequestsPanel({
    required this.requests,
    required this.actionLoading,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.privacy_tip_outlined,
        text: 'Sin solicitudes de privacidad',
      );
    }
    return _DataPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: _PanelTitle(
              icon: Icons.privacy_tip_outlined,
              title: 'Solicitudes de datos personales',
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < requests.length; i++) ...[
            _PrivacyRequestRow(
              request: requests[i],
              actionLoading: actionLoading,
              onUpdate: onUpdate,
            ),
            if (i != requests.length - 1) const Divider(),
          ],
        ],
      ),
    );
  }
}

class _PrivacyRequestRow extends StatelessWidget {
  final AdminPrivacyRequest request;
  final bool actionLoading;
  final void Function(AdminPrivacyRequest request, String status) onUpdate;

  const _PrivacyRequestRow({
    required this.request,
    required this.actionLoading,
    required this.onUpdate,
  });

  Color get _statusColor => switch (request.status) {
        'pending' => AppTheme.warning,
        'in_review' => AppTheme.primary,
        'resolved' => AppTheme.success,
        'rejected' => AppTheme.error,
        _ => AppTheme.slate400,
      };

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '';
    try {
      return DateFormat('dd/MM HH:mm').format(DateTime.parse(value).toLocal());
    } catch (_) {
      return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final created = _formatDate(request.createdAt);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      request.typeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.midnight,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _StatusPill(label: request.statusLabel, color: _statusColor),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${request.fullName} · ${request.email}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.slate400,
                  fontSize: 12,
                ),
              ),
              if (created.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  'Creada $created',
                  style: const TextStyle(
                    color: AppTheme.slate400,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if ((request.message ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  request.message!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.slate600,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
              if ((request.adminResponse ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  request.adminResponse!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.slate600,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          );

          final actions = _PrivacyRequestActions(
            request: request,
            loading: actionLoading,
            onUpdate: onUpdate,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: details),
              const SizedBox(width: 16),
              SizedBox(width: 260, child: actions),
            ],
          );
        },
      ),
    );
  }
}

class _PrivacyRequestActions extends StatelessWidget {
  final AdminPrivacyRequest request;
  final bool loading;
  final void Function(AdminPrivacyRequest request, String status) onUpdate;

  const _PrivacyRequestActions({
    required this.request,
    required this.loading,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    if (!request.isOpen) {
      return _StatusPill(
        label: request.statusLabel,
        color: request.status == 'resolved' ? AppTheme.success : AppTheme.error,
      );
    }

    final canTake = request.status == 'pending';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        if (canTake)
          OutlinedButton.icon(
            onPressed: loading ? null : () => onUpdate(request, 'in_review'),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('Tomar'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: loading ? null : () => onUpdate(request, 'rejected'),
          icon: const Icon(Icons.close_rounded, size: 18),
          label: const Text('Rechazar'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.error,
            minimumSize: const Size(0, 40),
            side: BorderSide(color: AppTheme.error.withValues(alpha: 0.35)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        ElevatedButton.icon(
          onPressed: loading ? null : () => onUpdate(request, 'resolved'),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('Resolver'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.success,
            minimumSize: const Size(0, 40),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}

class _AuditEventsPanel extends StatelessWidget {
  final List<AdminAuditEvent> events;
  final bool loading;
  final String selectedEntityType;
  final String selectedEventType;
  final String selectedActorRole;
  final DateTime? fromDate;
  final DateTime? toDate;
  final TextEditingController entityIdController;
  final TextEditingController actorIdController;
  final ValueChanged<String?> onEntityTypeChanged;
  final ValueChanged<String?> onEventTypeChanged;
  final ValueChanged<String?> onActorRoleChanged;
  final VoidCallback onPickFromDate;
  final VoidCallback onPickToDate;
  final VoidCallback onApplyFilters;
  final VoidCallback onClearFilters;
  final VoidCallback onExportCsv;

  const _AuditEventsPanel({
    required this.events,
    required this.loading,
    required this.selectedEntityType,
    required this.selectedEventType,
    required this.selectedActorRole,
    required this.fromDate,
    required this.toDate,
    required this.entityIdController,
    required this.actorIdController,
    required this.onEntityTypeChanged,
    required this.onEventTypeChanged,
    required this.onActorRoleChanged,
    required this.onPickFromDate,
    required this.onPickToDate,
    required this.onApplyFilters,
    required this.onClearFilters,
    required this.onExportCsv,
  });

  @override
  Widget build(BuildContext context) => _DataPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: _PanelTitle(
                      icon: Icons.history_rounded,
                      title: 'Historial operacional',
                    ),
                  ),
                  if (loading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    _StatusPill(
                      label: '${events.length} eventos',
                      color: AppTheme.slate400,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: _AuditFiltersBar(
                selectedEntityType: selectedEntityType,
                selectedEventType: selectedEventType,
                selectedActorRole: selectedActorRole,
                fromDate: fromDate,
                toDate: toDate,
                entityIdController: entityIdController,
                actorIdController: actorIdController,
                onEntityTypeChanged: onEntityTypeChanged,
                onEventTypeChanged: onEventTypeChanged,
                onActorRoleChanged: onActorRoleChanged,
                onPickFromDate: onPickFromDate,
                onPickToDate: onPickToDate,
                onApplyFilters: onApplyFilters,
                onClearFilters: onClearFilters,
                onExportCsv: onExportCsv,
              ),
            ),
            if (loading) const LinearProgressIndicator(minHeight: 2),
            if (events.isEmpty)
              const _InlineEmptyState(
                icon: Icons.history_rounded,
                text: 'Sin eventos para estos filtros',
              )
            else
              for (var i = 0; i < events.length; i++) ...[
                _AuditEventRow(
                  event: events[i],
                  onOpen: () => showDialog<void>(
                    context: context,
                    builder: (_) => _AuditEventDialog(event: events[i]),
                  ),
                ),
                if (i != events.length - 1) const Divider(),
              ],
          ],
        ),
      );
}

class _AuditFiltersBar extends StatelessWidget {
  static const _entityOptions = <String, String>{
    '': 'Todas',
    'user': 'Usuarios',
    'driver': 'Conductores',
    'vehicle': 'Vehiculos',
    'freight': 'Fletes',
    'payment': 'Pagos',
    'driver_payout': 'Liquidaciones',
    'data_privacy_request': 'Privacidad',
    'user_consent': 'Legal',
    'system': 'Sistema',
  };

  static const _eventOptions = <String, String>{
    '': 'Todas',
    'user.registered': 'Usuario registrado',
    'user.updated': 'Perfil actualizado',
    'user.suspended': 'Usuario suspendido',
    'user.activated': 'Usuario activado',
    'driver.registered': 'Conductor registrado',
    'driver.updated': 'Conductor actualizado',
    'driver.approved': 'Conductor aprobado',
    'driver.rejected': 'Conductor rechazado',
    'driver.document_uploaded': 'Documento subido',
    'driver.submitted_for_review': 'Enviado a revision',
    'driver.documents_deleted': 'Documentos eliminados',
    'vehicle.created': 'Vehiculo creado',
    'freight.created': 'Flete creado',
    'freight.accepted': 'Flete aceptado',
    'freight.status_changed': 'Estado de flete',
    'payment.initiated': 'Pago iniciado',
    'payment.authorized': 'Pago autorizado',
    'driver_payout.created': 'Liquidacion creada',
    'driver_payout.pending': 'Liquidacion pendiente',
    'driver_payout.scheduled': 'Liquidacion programada',
    'driver_payout.paid': 'Liquidacion pagada',
    'driver_payout.failed': 'Liquidacion fallida',
    'privacy_request.created': 'Solicitud creada',
    'privacy_request.status_changed': 'Solicitud actualizada',
    'legal.terms_accepted': 'Terminos aceptados',
    'legal.privacy_accepted': 'Privacidad aceptada',
    'legal.driver_document_verification_accepted': 'Docs conductor aceptados',
    'system.backend_error': 'Error backend',
  };

  static const _actorOptions = <String, String>{
    '': 'Todos',
    'admin': 'Admin',
    'client': 'Cliente',
    'driver': 'Conductor',
  };

  final String selectedEntityType;
  final String selectedEventType;
  final String selectedActorRole;
  final DateTime? fromDate;
  final DateTime? toDate;
  final TextEditingController entityIdController;
  final TextEditingController actorIdController;
  final ValueChanged<String?> onEntityTypeChanged;
  final ValueChanged<String?> onEventTypeChanged;
  final ValueChanged<String?> onActorRoleChanged;
  final VoidCallback onPickFromDate;
  final VoidCallback onPickToDate;
  final VoidCallback onApplyFilters;
  final VoidCallback onClearFilters;
  final VoidCallback onExportCsv;

  const _AuditFiltersBar({
    required this.selectedEntityType,
    required this.selectedEventType,
    required this.selectedActorRole,
    required this.fromDate,
    required this.toDate,
    required this.entityIdController,
    required this.actorIdController,
    required this.onEntityTypeChanged,
    required this.onEventTypeChanged,
    required this.onActorRoleChanged,
    required this.onPickFromDate,
    required this.onPickToDate,
    required this.onApplyFilters,
    required this.onClearFilters,
    required this.onExportCsv,
  });

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 170,
            child: _AuditDropdown(
              label: 'Entidad',
              value: _entityOptions.containsKey(selectedEntityType)
                  ? selectedEntityType
                  : '',
              options: _entityOptions,
              onChanged: onEntityTypeChanged,
            ),
          ),
          SizedBox(
            width: 250,
            child: _AuditDropdown(
              label: 'Accion',
              value: _eventOptions.containsKey(selectedEventType)
                  ? selectedEventType
                  : '',
              options: _eventOptions,
              onChanged: onEventTypeChanged,
            ),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: entityIdController,
              textInputAction: TextInputAction.search,
              keyboardType: TextInputType.text,
              onSubmitted: (_) => onApplyFilters(),
              decoration: _auditInputDecoration(
                label: 'ID entidad',
                icon: Icons.tag_rounded,
              ),
            ),
          ),
          SizedBox(
            width: 160,
            child: _AuditDropdown(
              label: 'Actor',
              value: _actorOptions.containsKey(selectedActorRole)
                  ? selectedActorRole
                  : '',
              options: _actorOptions,
              onChanged: onActorRoleChanged,
            ),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: actorIdController,
              textInputAction: TextInputAction.search,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => onApplyFilters(),
              decoration: _auditInputDecoration(
                label: 'ID actor',
                icon: Icons.badge_outlined,
              ),
            ),
          ),
          _AuditDateButton(
            label: 'Desde',
            date: fromDate,
            onPressed: onPickFromDate,
          ),
          _AuditDateButton(
            label: 'Hasta',
            date: toDate,
            onPressed: onPickToDate,
          ),
          ElevatedButton.icon(
            onPressed: onApplyFilters,
            icon: const Icon(Icons.filter_alt_outlined, size: 18),
            label: const Text('Filtrar'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          OutlinedButton.icon(
            onPressed: onExportCsv,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('CSV'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          IconButton.outlined(
            tooltip: 'Limpiar filtros',
            onPressed: onClearFilters,
            icon: const Icon(Icons.filter_alt_off_outlined),
            style: IconButton.styleFrom(
              minimumSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      );
}

class _AuditDateButton extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onPressed;

  const _AuditDateButton({
    required this.label,
    required this.date,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final text = date == null ? label : DateFormat('dd/MM/yyyy').format(date!);
    return SizedBox(
      width: 132,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.calendar_today_outlined, size: 17),
        label: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: date == null ? AppTheme.slate400 : AppTheme.midnight,
          side: const BorderSide(color: AppTheme.slate200),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}

class _AuditDropdown extends StatelessWidget {
  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;

  const _AuditDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        key: ValueKey('$label-$value'),
        initialValue: value,
        isExpanded: true,
        decoration: _auditInputDecoration(
          label: label,
          icon: Icons.tune_rounded,
        ),
        items: options.entries
            .map(
              (option) => DropdownMenuItem(
                value: option.key,
                child: Text(
                  option.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      );
}

InputDecoration _auditInputDecoration({
  required String label,
  required IconData icon,
}) =>
    InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 18),
      isDense: true,
      filled: true,
      fillColor: AppTheme.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.slate200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.slate200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppTheme.primary),
      ),
    );

class _InlineEmptyState extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InlineEmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 150,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppTheme.slate400, size: 34),
            const SizedBox(height: 10),
            Text(text, style: const TextStyle(color: AppTheme.slate400)),
          ],
        ),
      );
}

class _AuditEventRow extends StatelessWidget {
  final AdminAuditEvent event;
  final VoidCallback onOpen;

  const _AuditEventRow({
    required this.event,
    required this.onOpen,
  });

  Color get _eventColor {
    if (event.eventType.startsWith('driver.')) return AppTheme.success;
    if (event.eventType.startsWith('freight.')) return AppTheme.primary;
    if (event.eventType.startsWith('payment.')) return AppTheme.midnight;
    if (event.eventType.startsWith('driver_payout.')) return AppTheme.success;
    if (event.eventType.startsWith('privacy_request.')) return AppTheme.error;
    if (event.eventType.startsWith('legal.')) return AppTheme.success;
    if (event.eventType.startsWith('system.')) return AppTheme.error;
    if (event.eventType.startsWith('user.')) return AppTheme.warning;
    return AppTheme.slate400;
  }

  IconData get _eventIcon {
    if (event.eventType.startsWith('driver.')) {
      return Icons.local_shipping_outlined;
    }
    if (event.eventType.startsWith('freight.')) return Icons.route_outlined;
    if (event.eventType.startsWith('payment.')) return Icons.payments_outlined;
    if (event.eventType.startsWith('driver_payout.')) {
      return Icons.account_balance_wallet_outlined;
    }
    if (event.eventType.startsWith('privacy_request.')) {
      return Icons.privacy_tip_outlined;
    }
    if (event.eventType.startsWith('legal.')) {
      return Icons.verified_user_outlined;
    }
    if (event.eventType.startsWith('system.')) {
      return Icons.error_outline_rounded;
    }
    if (event.eventType.startsWith('user.')) return Icons.person_outline;
    return Icons.history_rounded;
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '';
    try {
      return DateFormat('dd/MM HH:mm').format(DateTime.parse(value).toLocal());
    } catch (_) {
      return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final occurredAt = _formatDate(event.occurredAt);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _eventColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_eventIcon, color: _eventColor, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.targetLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.midnight,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: compact ? 140 : 220,
                          ),
                          child: _StatusPill(
                            label: event.eventLabel,
                            color: _eventColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      occurredAt.isEmpty
                          ? event.actorLabel
                          : '${event.actorLabel} - $occurredAt',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.slate400,
                        fontSize: 12,
                      ),
                    ),
                    if (event.detailSummary.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        event.detailSummary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.slate600,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (event.requestId != null &&
                            event.requestId!.isNotEmpty)
                          _AuditMetaChip(label: 'Req ${event.requestId}'),
                        if (event.beforeData.isNotEmpty)
                          _AuditMetaChip(
                            label: 'Antes ${event.beforeData.length}',
                          ),
                        if (event.afterData.isNotEmpty)
                          _AuditMetaChip(
                            label: 'Despues ${event.afterData.length}',
                          ),
                        OutlinedButton.icon(
                          onPressed: onOpen,
                          icon: const Icon(Icons.visibility_outlined, size: 16),
                          label: const Text('Ver'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 32),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 0,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AuditMetaChip extends StatelessWidget {
  final String label;

  const _AuditMetaChip({required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.slate100,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppTheme.slate400,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _AuditEventDialog extends StatelessWidget {
  final AdminAuditEvent event;

  const _AuditEventDialog({required this.event});

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '';
    try {
      return DateFormat('dd/MM/yyyy HH:mm:ss').format(
        DateTime.parse(value).toLocal(),
      );
    } catch (_) {
      return value;
    }
  }

  String _prettyJson(Map<String, dynamic> data) {
    if (data.isEmpty) return '{}';
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  @override
  Widget build(BuildContext context) {
    final occurredAt = _formatDate(event.occurredAt);
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: _PanelTitle(
                      icon: Icons.manage_search_rounded,
                      title: 'Detalle de evento #${event.id}',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatusPill(
                        label: event.targetLabel,
                        color: AppTheme.primary,
                      ),
                      _StatusPill(
                        label: event.eventLabel,
                        color: AppTheme.midnight,
                      ),
                      _AuditMetaChip(label: event.actorLabel),
                      if (occurredAt.isNotEmpty)
                        _AuditMetaChip(label: occurredAt),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _AuditInfoGrid(event: event),
                  if ((event.reason ?? '').isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _AuditDetailSection(
                      title: 'Motivo',
                      child: SelectableText(
                        event.reason!,
                        style: const TextStyle(
                          color: AppTheme.slate600,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 720;
                      final before = _AuditJsonSection(
                        title: 'Antes',
                        value: _prettyJson(event.beforeData),
                      );
                      final after = _AuditJsonSection(
                        title: 'Despues',
                        value: _prettyJson(event.afterData),
                      );
                      if (compact) {
                        return Column(
                          children: [
                            before,
                            const SizedBox(height: 12),
                            after,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: before),
                          const SizedBox(width: 12),
                          Expanded(child: after),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  _AuditJsonSection(
                    title: 'Metadata',
                    value: _prettyJson(event.metadata),
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

class _AuditInfoGrid extends StatelessWidget {
  final AdminAuditEvent event;

  const _AuditInfoGrid({required this.event});

  @override
  Widget build(BuildContext context) {
    final items = [
      _AuditInfoItem('Entidad', event.entityType),
      _AuditInfoItem('ID entidad', event.entityId ?? ''),
      _AuditInfoItem('Accion', event.eventType),
      _AuditInfoItem('Actor', event.actorLabel),
      _AuditInfoItem('IP', event.ipAddress ?? ''),
      _AuditInfoItem('Request', event.requestId ?? ''),
      _AuditInfoItem('User agent', event.userAgent ?? ''),
    ].where((item) => item.value.trim().isNotEmpty).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 700 ? 2 : 1;
        return GridView.builder(
          itemCount: items.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: columns == 1 ? 6.4 : 4.3,
          ),
          itemBuilder: (_, index) => _AuditInfoTile(item: items[index]),
        );
      },
    );
  }
}

class _AuditInfoItem {
  final String label;
  final String value;

  const _AuditInfoItem(this.label, this.value);
}

class _AuditInfoTile extends StatelessWidget {
  final _AuditInfoItem item;

  const _AuditInfoTile({required this.item});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.slate200, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.slate400,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            SelectableText(
              item.value,
              maxLines: 2,
              style: const TextStyle(
                color: AppTheme.midnight,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _AuditDetailSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _AuditDetailSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.slate200, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.midnight,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );
}

class _AuditJsonSection extends StatelessWidget {
  final String title;
  final String value;

  const _AuditJsonSection({
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) => _AuditDetailSection(
        title: title,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 260),
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.midnight,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.35,
              ),
            ),
          ),
        ),
      );
}

class _LegalConsentsPanel extends StatelessWidget {
  final List<AdminLegalConsent> consents;

  const _LegalConsentsPanel({required this.consents});

  @override
  Widget build(BuildContext context) {
    if (consents.isEmpty) {
      return const _EmptyPanel(
        icon: Icons.verified_user_outlined,
        text: 'Sin consentimientos registrados',
      );
    }
    return _DataPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: _PanelTitle(
              icon: Icons.verified_user_outlined,
              title: 'Aceptaciones legales',
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < consents.length; i++) ...[
            _LegalConsentRow(consent: consents[i]),
            if (i != consents.length - 1) const Divider(),
          ],
        ],
      ),
    );
  }
}

class _LegalConsentRow extends StatelessWidget {
  final AdminLegalConsent consent;

  const _LegalConsentRow({required this.consent});

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '';
    try {
      return DateFormat('dd/MM/yyyy HH:mm').format(
        DateTime.parse(value).toLocal(),
      );
    } catch (_) {
      return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final acceptedAt = _formatDate(consent.acceptedAt);
    final subtitle = [
      consent.email,
      if (acceptedAt.isNotEmpty) acceptedAt,
      if ((consent.ipAddress ?? '').isNotEmpty) 'IP ${consent.ipAddress}',
    ].join(' - ');

    return Padding(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      consent.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.midnight,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _RoleBadge(role: consent.role),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.slate400,
                  fontSize: 12,
                ),
              ),
              if ((consent.userAgent ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  consent.userAgent!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.slate400,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          );

          final legalTags = Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: compact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              _StatusPill(label: consent.typeLabel, color: AppTheme.success),
              _AuditMetaChip(label: 'v${consent.version}'),
              _AuditMetaChip(label: 'Usuario #${consent.userId}'),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: 10),
                legalTags,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: details),
              const SizedBox(width: 16),
              SizedBox(width: 320, child: legalTags),
            ],
          );
        },
      ),
    );
  }
}

class _DriversPanel extends StatelessWidget {
  final List<AdminDriver> drivers;
  final bool actionLoading;
  final ValueChanged<AdminDriver> onApprove;
  final ValueChanged<AdminDriver> onReject;
  final ValueChanged<AdminDriver> onDeleteDocuments;

  const _DriversPanel({
    required this.drivers,
    required this.actionLoading,
    required this.onApprove,
    required this.onReject,
    required this.onDeleteDocuments,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: _PanelTitle(
              icon: Icons.fact_check_outlined,
              title: 'Revision de documentos y solicitudes',
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < drivers.length; i++) ...[
            _DriverRow(
              driver: drivers[i],
              actionLoading: actionLoading,
              onApprove: onApprove,
              onReject: onReject,
              onDeleteDocuments: onDeleteDocuments,
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
  final ValueChanged<AdminDriver> onDeleteDocuments;

  const _DriverRow({
    required this.driver,
    required this.actionLoading,
    required this.onApprove,
    required this.onReject,
    required this.onDeleteDocuments,
  });

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
              if (driver.documentsRetentionUntil != null ||
                  driver.documentsDeletedAt != null) ...[
                const SizedBox(height: 10),
                _DriverDocumentRetention(driver: driver),
              ],
              if (driver.reviewHistory.isNotEmpty) ...[
                const SizedBox(height: 10),
                _DriverReviewHistory(reviews: driver.reviewHistory),
              ],
            ],
          );

          final actions = _DriverActions(
            pending: driver.isPending,
            approved: driver.isApproved,
            suspended: driver.isSuspended,
            hasDocuments: driver.hasAnyDocument,
            loading: actionLoading,
            onApprove: () => onApprove(driver),
            onReject: () => onReject(driver),
            onDeleteDocuments: () => onDeleteDocuments(driver),
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
  final bool suspended;
  final bool hasDocuments;
  final bool loading;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDeleteDocuments;

  const _DriverActions({
    required this.pending,
    required this.approved,
    required this.suspended,
    required this.hasDocuments,
    required this.loading,
    required this.onApprove,
    required this.onReject,
    required this.onDeleteDocuments,
  });

  @override
  Widget build(BuildContext context) {
    if (!pending) {
      if (suspended && hasDocuments) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: _StatusPill(
                label: 'Retener documentos',
                color: AppTheme.error,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: loading ? null : onDeleteDocuments,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Borrar docs'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                minimumSize: const Size(0, 42),
                side: BorderSide(color: AppTheme.error.withValues(alpha: 0.35)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        );
      }
      return _StatusPill(
        label: approved
            ? 'Listo para operar'
            : suspended
                ? 'Sin docs privados'
                : 'Sin acción pendiente',
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
      _DocumentLink(
        label: 'Licencia',
        type: 'license_image',
        available: driver.documents['license_image'] == true,
      ),
      _DocumentLink(
        label: 'Permiso',
        type: driver.documents['circulation_permit'] == true
            ? 'circulation_permit'
            : 'vehicle_doc',
        available: driver.documents['circulation_permit'] == true ||
            driver.documents['vehicle_doc'] == true,
      ),
      _DocumentLink(
        label: 'Revision',
        type: 'technical_review',
        available: driver.documents['technical_review'] == true,
      ),
      _DocumentLink(
        label: 'SOAP',
        type: 'soap',
        available: driver.documents['soap'] == true,
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: docs
          .map(
            (doc) => _DocumentChip(
              driverId: driver.id,
              label: doc.label,
              type: doc.type,
              available: doc.available,
            ),
          )
          .toList(),
    );
  }
}

class _DocumentChip extends StatelessWidget {
  final int driverId;
  final String label;
  final String type;
  final bool available;

  const _DocumentChip({
    required this.driverId,
    required this.label,
    required this.type,
    required this.available,
  });

  Future<void> _open() async {
    if (!available) return;
    final value = await AdminService().getDriverDocumentViewUrl(
      driverId: driverId,
      documentType: type,
    );
    final uri = Uri.tryParse(value);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
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
  final String type;
  final bool available;

  const _DocumentLink({
    required this.label,
    required this.type,
    required this.available,
  });
}

class _DriverDocumentRetention extends StatelessWidget {
  final AdminDriver driver;

  const _DriverDocumentRetention({required this.driver});

  String _formatDate(String value) {
    try {
      return DateFormat('dd/MM/yyyy HH:mm')
          .format(DateTime.parse(value).toLocal());
    } catch (_) {
      return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final deletedAt = driver.documentsDeletedAt;
    final retentionUntil = driver.documentsRetentionUntil;
    final deleted = deletedAt != null;
    final color = deleted ? AppTheme.slate400 : AppTheme.warning;
    final icon =
        deleted ? Icons.delete_outline_rounded : Icons.lock_clock_outlined;
    final text = deleted
        ? 'Documentos eliminados ${_formatDate(deletedAt)}'
        : 'Retencion hasta ${_formatDate(retentionUntil!)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverReviewHistory extends StatelessWidget {
  final List<AdminDriverReview> reviews;

  const _DriverReviewHistory({required this.reviews});

  @override
  Widget build(BuildContext context) {
    final latest = reviews.first;
    final approved = latest.action == 'approved';
    final deleted = latest.action == 'documents_deleted';
    final color = approved
        ? AppTheme.success
        : deleted
            ? AppTheme.slate400
            : AppTheme.error;
    final created = latest.createdAt != null
        ? DateFormat('dd/MM HH:mm').format(DateTime.parse(latest.createdAt!))
        : '';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                approved
                    ? Icons.verified_outlined
                    : deleted
                        ? Icons.delete_outline_rounded
                        : Icons.report_outlined,
                size: 15,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${latest.actionLabel} por ${latest.adminName ?? 'admin'}'
                  '${created.isNotEmpty ? ' - $created' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if ((latest.reason ?? '').isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              latest.reason!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.slate600,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 7),
          _ReviewDocumentSummary(snapshot: latest.documentsSnapshot),
        ],
      ),
    );
  }
}

class _ReviewDocumentSummary extends StatelessWidget {
  final Map<String, bool> snapshot;

  const _ReviewDocumentSummary({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final total = [
      snapshot['license_image'],
      snapshot['circulation_permit'] == true || snapshot['vehicle_doc'] == true,
      snapshot['technical_review'],
      snapshot['soap'],
    ].where((value) => value == true).length;
    return Text(
      'Documentos presentes al revisar: $total/4',
      style: const TextStyle(
        color: AppTheme.slate400,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );
  }
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

class _PayoutUpdateData {
  final String status;
  final DateTime? scheduledFor;
  final String? transferReference;
  final String? note;

  const _PayoutUpdateData({
    required this.status,
    this.scheduledFor,
    this.transferReference,
    this.note,
  });
}

class _PayoutUpdateDialog extends StatefulWidget {
  final PayoutModel payout;

  const _PayoutUpdateDialog({required this.payout});

  @override
  State<_PayoutUpdateDialog> createState() => _PayoutUpdateDialogState();
}

class _PayoutUpdateDialogState extends State<_PayoutUpdateDialog> {
  late String _status;
  late DateTime _scheduledFor;
  late final TextEditingController _referenceController;
  late final TextEditingController _noteController;

  List<String> get _options => switch (widget.payout.status) {
        'scheduled' => const ['paid', 'pending', 'failed'],
        'failed' => const ['scheduled', 'pending', 'paid'],
        _ => const ['scheduled', 'paid', 'failed'],
      };

  String _label(String status) => switch (status) {
        'pending' => 'Dejar pendiente',
        'scheduled' => 'Programar transferencia',
        'paid' => 'Marcar pagada',
        'failed' => 'Registrar fallo',
        _ => status,
      };

  @override
  void initState() {
    super.initState();
    _status = _options.first;
    _scheduledFor = widget.payout.scheduledFor?.toLocal() ??
        DateTime.now().add(const Duration(days: 1));
    _referenceController = TextEditingController(
      text: widget.payout.transferReference ?? '',
    );
    _noteController = TextEditingController(text: widget.payout.note ?? '');
  }

  @override
  void dispose() {
    _referenceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _scheduledFor,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(
      () => _scheduledFor = DateTime(picked.year, picked.month, picked.day, 12),
    );
  }

  bool get _canSubmit {
    if (_status == 'paid') return _referenceController.text.trim().isNotEmpty;
    if (_status == 'failed') return _noteController.text.trim().isNotEmpty;
    return true;
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.pop(
      context,
      _PayoutUpdateData(
        status: _status,
        scheduledFor: _status == 'scheduled' ? _scheduledFor : null,
        transferReference:
            _status == 'paid' ? _referenceController.text.trim() : null,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Gestionar liquidacion #${widget.payout.id}'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.payout.driverName} · Flete #${widget.payout.freightId}',
                style: const TextStyle(color: AppTheme.slate600, fontSize: 13),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Nuevo estado'),
                items: [
                  for (final status in _options)
                    DropdownMenuItem(
                      value: status,
                      child: Text(_label(status)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
              if (_status == 'scheduled') ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: Text(
                    'Fecha: ${DateFormat('dd/MM/yyyy').format(_scheduledFor)}',
                  ),
                ),
              ],
              if (_status == 'paid') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _referenceController,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Referencia de transferencia',
                    hintText: 'Ej: transferencia bancaria 10452',
                  ),
                ),
              ],
              if (_status == 'failed' || _status == 'scheduled') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _noteController,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: _status == 'failed'
                        ? 'Motivo del fallo'
                        : 'Nota opcional',
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: _canSubmit ? _submit : null,
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Guardar'),
          ),
        ],
      );
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

class _DeleteDocumentsDialog extends StatefulWidget {
  const _DeleteDocumentsDialog();

  @override
  State<_DeleteDocumentsDialog> createState() => _DeleteDocumentsDialogState();
}

class _DeleteDocumentsDialogState extends State<_DeleteDocumentsDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Borrar documentos privados'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Esta accion elimina los archivos privados del almacenamiento y deja registro en auditoria.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Motivo opcional',
                hintText: 'Ej: solicitud rechazada y plazo cerrado',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, _controller.text),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Borrar'),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
          ),
        ],
      );
}

class _PrivacyRequestDialog extends StatefulWidget {
  final String status;

  const _PrivacyRequestDialog({required this.status});

  @override
  State<_PrivacyRequestDialog> createState() => _PrivacyRequestDialogState();
}

class _PrivacyRequestDialogState extends State<_PrivacyRequestDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolving = widget.status == 'resolved';
    return AlertDialog(
      title: Text(resolving ? 'Resolver solicitud' : 'Rechazar solicitud'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        minLines: 2,
        maxLines: 4,
        decoration: InputDecoration(
          labelText: 'Respuesta',
          hintText: resolving
              ? 'Ej: solicitud gestionada por soporte'
              : 'Ej: falta validar identidad',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          style: FilledButton.styleFrom(
            backgroundColor: resolving ? AppTheme.success : AppTheme.error,
          ),
          child: Text(resolving ? 'Resolver' : 'Rechazar'),
        ),
      ],
    );
  }
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
