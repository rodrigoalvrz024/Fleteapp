import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/freight_model.dart';
import '../../services/freight_service.dart';
import '../shared/web_layout.dart';
import 'widgets/freight_widgets.dart';

class FreightListScreen extends StatefulWidget {
  const FreightListScreen({super.key});

  @override
  State<FreightListScreen> createState() => _FreightListScreenState();
}

class _FreightListScreenState extends State<FreightListScreen> {
  final _service = FreightService();
  List<FreightModel> _freights = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _service.listFreights();
      if (!mounted) return;
      setState(() {
        _freights = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _createFreight() => context.push('/app/client/create-freight');

  @override
  Widget build(BuildContext context) {
    final activeCount = _freights
        .where((f) => f.status != 'completed' && f.status != 'cancelled')
        .length;
    final completedCount =
        _freights.where((f) => f.status == 'completed').length;
    final pendingCount = _freights.where((f) => f.status == 'pending').length;

    return WebPageScaffold(
      title: 'Mis fletes',
      subtitle: 'Revisa solicitudes, estados, rutas y precios',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createFreight,
        backgroundColor: AppTheme.primary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push('/app/client/freights/${freight.id}'),
        child: Container(
          decoration: isUrgent
              ? AppTheme.urgentDecoration().copyWith(
                  borderRadius: BorderRadius.circular(8),
                )
              : AppTheme.cardDecoration(radius: 8),
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
        decoration: AppTheme.cardDecoration(radius: 8),
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
