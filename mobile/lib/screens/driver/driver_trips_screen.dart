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
import '../../widgets/muvv_mobile_ui.dart';

enum _TripFilter { all, active, completed, cancelled }

class DriverTripsScreen extends StatefulWidget {
  const DriverTripsScreen({super.key});

  @override
  State<DriverTripsScreen> createState() => _DriverTripsScreenState();
}

class _DriverTripsScreenState extends State<DriverTripsScreen> {
  final _service = FreightService();
  final _money = NumberFormat('#,##0', 'es_CL');
  final _date = DateFormat('d MMM yyyy, HH:mm', 'es_CL');
  List<FreightModel> _trips = [];
  bool _loading = true;
  String? _error;
  _TripFilter _filter = _TripFilter.all;

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
      final trips = await _service.listFreights();
      if (!mounted) return;
      setState(() {
        _trips = trips;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = apiErrorMessage(
          e,
          fallback: 'No pudimos cargar tus viajes. Intenta nuevamente.',
        );
      });
    }
  }

  bool _isActive(FreightModel trip) =>
      trip.status == 'accepted' || trip.status == 'in_progress';

  List<FreightModel> get _visibleTrips {
    return switch (_filter) {
      _TripFilter.active => _trips.where(_isActive).toList(),
      _TripFilter.completed =>
        _trips.where((trip) => trip.status == 'completed').toList(),
      _TripFilter.cancelled =>
        _trips.where((trip) => trip.status == 'cancelled').toList(),
      _TripFilter.all => _trips,
    };
  }

  @override
  Widget build(BuildContext context) {
    final active = _trips.where(_isActive).length;
    final completed = _trips.where((trip) => trip.status == 'completed').length;
    final cancelled = _trips.where((trip) => trip.status == 'cancelled').length;
    final visibleTrips = _visibleTrips;

    return WebPageScaffold(
      title: 'Mis viajes',
      subtitle: 'Historial y pagos',
      actions: const [DriverAppBarActions()],
      bottomNavigationBar: const MuvvBottomNavigation(
        selected: MuvvNavigationSection.activity,
        driver: true,
      ),
      child: _loading
          ? const WebLoadingState()
          : WebPageBody(
              onRefresh: _load,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 80),
              children: [
                _TripsSummary(
                  total: _trips.length,
                  active: active,
                  completed: completed,
                  cancelled: cancelled,
                ),
                const SizedBox(height: 16),
                _TripFilters(
                  selected: _filter,
                  total: _trips.length,
                  active: active,
                  completed: completed,
                  cancelled: cancelled,
                  onChanged: (value) => setState(() => _filter = value),
                ),
                const SizedBox(height: 14),
                if (_error != null)
                  WebEmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'No pudimos cargar tus viajes',
                    description: _error!,
                    actionLabel: 'Reintentar',
                    onAction: _load,
                  )
                else if (_trips.isEmpty)
                  WebEmptyState(
                    icon: Icons.route_outlined,
                    title: 'Aun no tienes viajes',
                    description:
                        'Cuando aceptes un flete aparecera aqui con su estado, pago y respaldo.',
                    actionLabel: 'Ver disponibles',
                    onAction: () => context.push('/app/driver/available'),
                  )
                else if (visibleTrips.isEmpty)
                  WebEmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    title: 'Sin viajes en esta vista',
                    description:
                        'Cambia el filtro para revisar otros estados de tus fletes.',
                    actionLabel: 'Ver todos',
                    onAction: () => setState(() => _filter = _TripFilter.all),
                  )
                else
                  for (final trip in visibleTrips) ...[
                    _DriverTripCard(
                      trip: trip,
                      money: _money,
                      date: _date,
                    ),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
    );
  }
}

class _TripsSummary extends StatelessWidget {
  final int total;
  final int active;
  final int completed;
  final int cancelled;

  const _TripsSummary({
    required this.total,
    required this.active,
    required this.completed,
    required this.cancelled,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Resumen de actividad',
          style: TextStyle(
            color: AppTheme.midnight,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Control rapido de tus fletes aceptados y cerrados.',
          style: TextStyle(
            color: AppTheme.slate600,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 14),
        _ResponsiveMetricGrid(
          children: [
            _MetricTile(
              label: 'Total',
              value: '$total',
              icon: Icons.stacked_line_chart_rounded,
              color: AppTheme.primary,
            ),
            _MetricTile(
              label: 'Activos',
              value: '$active',
              icon: Icons.near_me_outlined,
              color: AppTheme.warning,
            ),
            _MetricTile(
              label: 'Cerrados',
              value: '$completed',
              icon: Icons.check_circle_outline_rounded,
              color: AppTheme.success,
            ),
            _MetricTile(
              label: 'Cancelados',
              value: '$cancelled',
              icon: Icons.cancel_outlined,
              color: AppTheme.error,
            ),
          ],
        ),
      ],
    );
  }
}

class _ResponsiveMetricGrid extends StatelessWidget {
  final List<Widget> children;

  const _ResponsiveMetricGrid({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 560 ? 2 : children.length;
        const spacing = 8.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(
                width: itemWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class _TripFilters extends StatelessWidget {
  final _TripFilter selected;
  final int total;
  final int active;
  final int completed;
  final int cancelled;
  final ValueChanged<_TripFilter> onChanged;

  const _TripFilters({
    required this.selected,
    required this.total,
    required this.active,
    required this.completed,
    required this.cancelled,
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
          selected: selected == _TripFilter.all,
          onTap: () => onChanged(_TripFilter.all),
        ),
        _FilterChipButton(
          label: 'Activos',
          count: active,
          icon: Icons.near_me_outlined,
          selected: selected == _TripFilter.active,
          color: AppTheme.warning,
          onTap: () => onChanged(_TripFilter.active),
        ),
        _FilterChipButton(
          label: 'Cerrados',
          count: completed,
          icon: Icons.check_circle_outline_rounded,
          selected: selected == _TripFilter.completed,
          color: AppTheme.success,
          onTap: () => onChanged(_TripFilter.completed),
        ),
        _FilterChipButton(
          label: 'Cancelados',
          count: cancelled,
          icon: Icons.cancel_outlined,
          selected: selected == _TripFilter.cancelled,
          color: AppTheme.error,
          onTap: () => onChanged(_TripFilter.cancelled),
        ),
      ],
    );
  }
}

class _DriverTripCard extends StatelessWidget {
  final FreightModel trip;
  final NumberFormat money;
  final DateFormat date;

  const _DriverTripCard({
    required this.trip,
    required this.money,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final amount =
        trip.driverReceives ?? trip.finalPrice ?? trip.estimatedPrice;
    final isActive = trip.status == 'accepted' || trip.status == 'in_progress';
    final evidenceReady = trip.hasPickupPhoto && trip.hasDeliveryPhoto;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push('/app/driver/freights/${trip.id}'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(
            radius: 8,
            borderColor: isActive
                ? AppTheme.primary.withValues(alpha: 0.30)
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
                        Text(
                          'Flete #${trip.id}',
                          style: const TextStyle(
                            color: AppTheme.slate600,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          trip.cargoDescription,
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
                  FreightStatusBadge(status: trip.status),
                ],
              ),
              const SizedBox(height: 14),
              FreightRouteSummary(
                origin: trip.originAddress,
                destination: trip.destinationAddress,
                maxLines: 2,
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoPill(
                    icon: Icons.schedule_rounded,
                    label: date.format(trip.createdAt),
                  ),
                  if (trip.distanceKm != null)
                    _InfoPill(
                      icon: Icons.route_rounded,
                      label: '${trip.distanceKm!.toStringAsFixed(1)} km',
                    ),
                  _InfoPill(
                    icon: Icons.scale_outlined,
                    label: '${trip.cargoWeightKg.toStringAsFixed(0)} kg',
                  ),
                  if ((trip.requiresHelpers ?? 0) > 0)
                    _InfoPill(
                      icon: Icons.people_outline_rounded,
                      label:
                          '${trip.requiresHelpers} peoneta${trip.requiresHelpers! > 1 ? "s" : ""}',
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _ProgressNote(
                      evidenceReady: evidenceReady,
                      pinVerified: trip.deliveryPinVerified,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        amount == null
                            ? 'Por confirmar'
                            : '\$${money.format(amount)}',
                        style: const TextStyle(
                          color: AppTheme.success,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'a recibir',
                        style: TextStyle(
                          color: AppTheme.slate400,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.slate400,
                    size: 20,
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

class _ProgressNote extends StatelessWidget {
  final bool evidenceReady;
  final bool pinVerified;

  const _ProgressNote({
    required this.evidenceReady,
    required this.pinVerified,
  });

  @override
  Widget build(BuildContext context) {
    final color = pinVerified
        ? AppTheme.success
        : evidenceReady
            ? AppTheme.primary
            : AppTheme.slate600;
    final icon = pinVerified
        ? Icons.verified_rounded
        : evidenceReady
            ? Icons.photo_camera_back_outlined
            : Icons.pending_actions_outlined;
    final text = pinVerified
        ? 'Entrega confirmada'
        : evidenceReady
            ? 'Fotos registradas'
            : 'Evidencia pendiente';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 7),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
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
