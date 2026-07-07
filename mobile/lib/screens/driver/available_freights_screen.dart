import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/freight_model.dart';
import '../../services/freight_service.dart';
import '../../utils/api_error_message.dart';
import '../client/widgets/freight_widgets.dart';
import '../shared/web_layout.dart';
import 'widgets/driver_app_bar_actions.dart';

enum _AvailableFilter { all, urgent, scheduled }

class AvailableFreightsScreen extends StatefulWidget {
  const AvailableFreightsScreen({super.key});

  @override
  State<AvailableFreightsScreen> createState() =>
      _AvailableFreightsScreenState();
}

class _AvailableFreightsScreenState extends State<AvailableFreightsScreen> {
  final _service = FreightService();
  List<FreightModel> _freights = [];
  bool _loading = true;
  String? _error;
  _AvailableFilter _filter = _AvailableFilter.all;

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
      final data = await _service.listFreights(status: 'available');
      if (!mounted) return;
      setState(() {
        _freights = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(
          e,
          fallback: 'No pudimos cargar los fletes disponibles.',
        );
      });
    }
  }

  List<FreightModel> get _visibleFreights {
    return switch (_filter) {
      _AvailableFilter.urgent =>
        _freights.where((freight) => freight.isUrgent == true).toList(),
      _AvailableFilter.scheduled =>
        _freights.where((freight) => freight.scheduledAt != null).toList(),
      _AvailableFilter.all => _freights,
    };
  }

  @override
  Widget build(BuildContext context) {
    final urgent = _freights.where((f) => f.isUrgent == true).length;
    final scheduled = _freights.where((f) => f.scheduledAt != null).length;
    final visibleFreights = _visibleFreights;

    return WebPageScaffold(
      title: 'Fletes disponibles',
      subtitle: 'Oportunidades para aceptar',
      actions: const [DriverAppBarActions()],
      child: _loading
          ? const WebLoadingState()
          : WebPageBody(
              onRefresh: _load,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
              children: [
                _OpportunityHeader(
                  total: _freights.length,
                  urgent: urgent,
                  scheduled: scheduled,
                  onRefresh: _load,
                ),
                const SizedBox(height: 16),
                _AvailableFilters(
                  selected: _filter,
                  total: _freights.length,
                  urgent: urgent,
                  scheduled: scheduled,
                  onChanged: (value) => setState(() => _filter = value),
                ),
                const SizedBox(height: 14),
                if (_error != null)
                  WebEmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'No pudimos cargar fletes',
                    description: _error!,
                    actionLabel: 'Reintentar',
                    onAction: _load,
                  )
                else if (_freights.isEmpty)
                  WebEmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'No hay fletes disponibles',
                    description:
                        'Cuando aparezcan solicitudes aprobadas para conductores las veras aqui.',
                    actionLabel: 'Actualizar',
                    onAction: _load,
                  )
                else if (visibleFreights.isEmpty)
                  WebEmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    title: 'Sin resultados',
                    description:
                        'No hay fletes que coincidan con este filtro por ahora.',
                    actionLabel: 'Ver todos',
                    onAction: () =>
                        setState(() => _filter = _AvailableFilter.all),
                  )
                else
                  for (final freight in visibleFreights) ...[
                    _AvailableFreightCard(
                      freight: freight,
                      onTap: () => context.push(
                        '/app/driver/freights/${freight.id}',
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
    );
  }
}

class _OpportunityHeader extends StatelessWidget {
  final int total;
  final int urgent;
  final int scheduled;
  final Future<void> Function() onRefresh;

  const _OpportunityHeader({
    required this.total,
    required this.urgent,
    required this.scheduled,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Panel de oportunidades',
                    style: TextStyle(
                      color: AppTheme.midnight,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Datos en vivo para decidir rapido.',
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
              message: 'Actualizar',
              child: IconButton(
                onPressed: onRefresh,
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.surface,
                  foregroundColor: AppTheme.midnight,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: AppTheme.slate200),
                  ),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'Disponibles',
                value: '$total',
                icon: Icons.local_shipping_outlined,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricTile(
                label: 'Urgentes',
                value: '$urgent',
                icon: Icons.bolt_rounded,
                color: AppTheme.urgent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricTile(
                label: 'Programados',
                value: '$scheduled',
                icon: Icons.event_available_outlined,
                color: AppTheme.success,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AvailableFilters extends StatelessWidget {
  final _AvailableFilter selected;
  final int total;
  final int urgent;
  final int scheduled;
  final ValueChanged<_AvailableFilter> onChanged;

  const _AvailableFilters({
    required this.selected,
    required this.total,
    required this.urgent,
    required this.scheduled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FilterChipButton(
          label: 'Todos',
          count: total,
          icon: Icons.grid_view_rounded,
          selected: selected == _AvailableFilter.all,
          onTap: () => onChanged(_AvailableFilter.all),
        ),
        _FilterChipButton(
          label: 'Urgentes',
          count: urgent,
          icon: Icons.bolt_rounded,
          selected: selected == _AvailableFilter.urgent,
          color: AppTheme.urgent,
          onTap: () => onChanged(_AvailableFilter.urgent),
        ),
        _FilterChipButton(
          label: 'Programados',
          count: scheduled,
          icon: Icons.schedule_rounded,
          selected: selected == _AvailableFilter.scheduled,
          color: AppTheme.success,
          onTap: () => onChanged(_AvailableFilter.scheduled),
        ),
      ],
    );
  }
}

class _AvailableFreightCard extends StatelessWidget {
  final FreightModel freight;
  final VoidCallback onTap;

  const _AvailableFreightCard({
    required this.freight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0', 'es_CL');
    final date = DateFormat('d MMM, HH:mm', 'es_CL');
    final driverAmount =
        freight.driverReceives ?? freight.estimatedPrice ?? freight.finalPrice;
    final isUrgent = freight.isUrgent == true;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(
            radius: 8,
            borderColor: isUrgent
                ? AppTheme.urgent.withValues(alpha: 0.34)
                : AppTheme.slate200,
          ),
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
                        Row(
                          children: [
                            Text(
                              'Flete #${freight.id}',
                              style: const TextStyle(
                                color: AppTheme.slate600,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                            if (isUrgent) ...[
                              const SizedBox(width: 8),
                              const FreightPill(
                                'Urgente',
                                color: AppTheme.urgent,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          freight.cargoDescription,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.midnight,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        driverAmount == null
                            ? 'Por confirmar'
                            : '\$${money.format(driverAmount)}',
                        style: const TextStyle(
                          color: AppTheme.midnight,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'pago estimado',
                        style: TextStyle(
                          color: AppTheme.slate400,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FreightRouteSummary(
                origin: freight.originAddress,
                destination: freight.destinationAddress,
                maxLines: 2,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (freight.distanceKm != null)
                    _InfoPill(
                      icon: Icons.route_rounded,
                      label: '${freight.distanceKm!.toStringAsFixed(1)} km',
                    ),
                  _InfoPill(
                    icon: Icons.scale_outlined,
                    label: '${freight.cargoWeightKg.toStringAsFixed(0)} kg',
                  ),
                  if ((freight.requiresHelpers ?? 0) > 0)
                    _InfoPill(
                      icon: Icons.people_outline_rounded,
                      label:
                          '${freight.requiresHelpers} peoneta${freight.requiresHelpers! > 1 ? "s" : ""}',
                    ),
                  if (freight.scheduledAt != null)
                    _InfoPill(
                      icon: Icons.schedule_rounded,
                      label: date.format(freight.scheduledAt!),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Revisa distancia, carga y condiciones antes de aceptar.',
                      style: TextStyle(
                        color: AppTheme.slate600,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: onTap,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text('Ver detalle'),
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

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
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
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _FilterChipButton({
    required this.label,
    required this.count,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.color = AppTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? color : AppTheme.slate600;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.10) : AppTheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.30) : AppTheme.slate200,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                color: foreground.withValues(alpha: 0.75),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoPill({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.slate100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.slate600),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.slate600,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}
