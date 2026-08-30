import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/freight_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/freight_service.dart';
import '../../utils/api_error_message.dart';
import '../shared/web_layout.dart';
import 'widgets/freight_widgets.dart';
import '../../widgets/muvv_mobile_ui.dart';

class FreightListScreen extends ConsumerStatefulWidget {
  const FreightListScreen({super.key});

  @override
  ConsumerState<FreightListScreen> createState() => _FreightListScreenState();
}

class _FreightListScreenState extends ConsumerState<FreightListScreen> {
  final _service = FreightService();
  List<FreightModel> _freights = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!ref.read(authProvider).isAuthenticated) {
        await ref.read(authProvider.notifier).checkAuth();
      }
      final user = ref.read(authProvider).user;
      if (user == null || user.role != 'client') {
        if (!mounted) return;
        setState(() {
          _freights = [];
          _loading = false;
          _error = null;
        });
        return;
      }

      final data = await _service.listFreights();
      if (!mounted) return;
      setState(() {
        _freights = data;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(
          e,
          fallback: 'No pudimos cargar tus fletes. Intenta nuevamente.',
        );
      });
    }
  }

  void _createFreight() => context.push('/app/client/create-freight');

  String _homePathForRole(String? role) {
    if (role == 'driver') return '/app/driver';
    if (role == 'admin') return '/admin';
    return '/app/client';
  }

  String _roleLabel(String? role) {
    if (role == 'driver') return 'conductor';
    if (role == 'admin') return 'administrador';
    return 'usuario';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final homePath = _homePathForRole(user?.role);
    final activeCount = _freights
        .where((f) => f.status != 'completed' && f.status != 'cancelled')
        .length;
    final completedCount =
        _freights.where((f) => f.status == 'completed').length;
    final pendingCount = _freights.where((f) => f.status == 'pending').length;

    return WebPageScaffold(
      title: 'Mis fletes',
      subtitle: user == null
          ? 'Revisa solicitudes, estados, rutas y precios'
          : '${user.email} · revisa solicitudes, estados, rutas y precios',
      actions: [WebAppBarActions(homePath: homePath)],
      bottomNavigationBar: const MuvvBottomNavigation(
        selected: MuvvNavigationSection.activity,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: user?.role == 'client' ? _createFreight : null,
        backgroundColor: AppTheme.primary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Nuevo flete',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
      child: _loading
          ? const WebLoadingState()
          : user != null && user.role != 'client'
              ? WebPageBody(
                  children: [
                    WebEmptyState(
                      icon: Icons.lock_outline_rounded,
                      title: 'Estas en una cuenta de ${_roleLabel(user.role)}',
                      description:
                          'Para crear y ver tus fletes de cliente, inicia sesion con una cuenta de cliente. Esta cuenta no tiene permisos para solicitar fletes.',
                      actionLabel: 'Ir a mi inicio',
                      onAction: () => context.go(homePath),
                    ),
                  ],
                )
              : _error != null
                  ? WebPageBody(
                      onRefresh: _load,
                      children: [
                        WebEmptyState(
                          icon: Icons.cloud_off_outlined,
                          title: 'No pudimos cargar tus fletes',
                          description: _error!,
                          actionLabel: 'Reintentar',
                          onAction: _load,
                        ),
                      ],
                    )
                  : _freights.isEmpty
                      ? WebPageBody(
                          children: [
                            WebEmptyState(
                              icon: Icons.local_shipping_outlined,
                              title: 'Sin fletes aun',
                              description:
                                  'Solicita tu primer flete y lo gestionamos por ti.',
                              actionLabel: 'Solicitar flete',
                              onAction: _createFreight,
                            ),
                          ],
                        )
                      : WebPageBody(
                          onRefresh: _load,
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                          children: [
                            _FreightListSummary(
                              total: _freights.length,
                              active: activeCount,
                              pending: pendingCount,
                              completed: completedCount,
                              onCreate: _createFreight,
                            ),
                            const SizedBox(height: 14),
                            for (final freight in _freights) ...[
                              FreightCard(freight: freight),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ),
    );
  }
}

class FreightCard extends StatelessWidget {
  final FreightModel freight;

  const FreightCard({super.key, required this.freight});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'es_CL');
    final dateFmt = DateFormat('d MMM, HH:mm', 'es_CL');
    final isUrgent = freight.isUrgent ?? false;
    final amount =
        freight.finalPrice ?? freight.estimatedPrice ?? freight.clientPays;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/app/client/freights/${freight.id}'),
        child: Container(
          decoration: isUrgent
              ? AppTheme.urgentDecoration().copyWith(
                  borderRadius: BorderRadius.circular(18),
                )
              : AppTheme.cardDecoration(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Flete #${freight.id}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.slate600,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (amount != null)
                          Text(
                            '\$${fmt.format(amount)} CLP',
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              color: AppTheme.midnight,
                              letterSpacing: 0,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            FreightPill(dateFmt.format(freight.createdAt)),
                            if (freight.distanceKm != null)
                              FreightPill(
                                '${freight.distanceKm!.toStringAsFixed(1)} km',
                              ),
                            if (isUrgent)
                              const FreightPill(
                                'Urgente',
                                color: AppTheme.urgent,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  FreightStatusBadge(status: freight.status),
                ],
              ),
              const SizedBox(height: 14),
              FreightRouteSummary(
                origin: freight.originAddress,
                destination: freight.destinationAddress,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FreightPill('${freight.cargoWeightKg.toStringAsFixed(0)} kg'),
                  const SizedBox(width: 6),
                  if ((freight.requiresHelpers ?? 0) > 0)
                    FreightPill(
                      '${freight.requiresHelpers} peoneta'
                      '${freight.requiresHelpers! > 1 ? "s" : ""}',
                    ),
                  const Spacer(),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppTheme.slate400,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FreightListSummary extends StatelessWidget {
  final int total;
  final int active;
  final int pending;
  final int completed;
  final VoidCallback onCreate;

  const _FreightListSummary({
    required this.total,
    required this.active,
    required this.pending,
    required this.completed,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resumen operativo',
                        style: TextStyle(
                          color: AppTheme.midnight,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Estado actual de tus solicitudes',
                        style: TextStyle(
                          color: AppTheme.slate600,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: 'Nuevo flete',
                  child: IconButton(
                    onPressed: onCreate,
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _SummaryMetric(
                    label: 'Total',
                    value: '$total',
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryMetric(
                    label: 'Activos',
                    value: '$active',
                    color: AppTheme.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryMetric(
                    label: 'Pendientes',
                    value: '$pending',
                    color: AppTheme.warning,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryMetric(
                    label: 'Completados',
                    value: '$completed',
                    color: AppTheme.success,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 70),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.16)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.slate600,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      );
}
