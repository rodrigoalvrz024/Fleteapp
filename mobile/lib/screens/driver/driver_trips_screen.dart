import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/freight_model.dart';
import '../../services/freight_service.dart';
import '../../utils/api_error_message.dart';
import '../shared/web_layout.dart';
import 'widgets/driver_app_bar_actions.dart';

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

  @override
  Widget build(BuildContext context) {
    final active = _trips
        .where(
            (trip) => trip.status == 'accepted' || trip.status == 'in_progress')
        .length;
    final completed = _trips.where((trip) => trip.status == 'completed').length;

    return WebPageScaffold(
      title: 'Mis viajes',
      subtitle: 'Fletes aceptados, en curso y completados',
      actions: const [DriverAppBarActions()],
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
                    title: 'Sin viajes todavia',
                    description:
                        'Cuando aceptes un flete aparecera aqui para seguirlo hasta la entrega.',
                    actionLabel: 'Ver fletes disponibles',
                    onAction: () => context.push('/app/driver/available'),
                  )
                else
                  for (final trip in _trips) ...[
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

  const _TripsSummary({
    required this.total,
    required this.active,
    required this.completed,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _Metric(
            label: 'Total',
            value: '$total',
            color: AppTheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Metric(
            label: 'Activos',
            value: '$active',
            color: AppTheme.warning,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _Metric(
            label: 'Completados',
            value: '$completed',
            color: AppTheme.success,
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.all(12),
      decoration: AppTheme.cardDecoration(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
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
            ),
          ),
        ],
      ),
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
        trip.driverReceives ?? trip.estimatedPrice ?? trip.finalPrice;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.push('/app/driver/freights/${trip.id}'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(radius: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Flete #${trip.id}',
                      style: const TextStyle(
                        color: AppTheme.midnight,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: trip.statusColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      trip.statusLabel,
                      style: TextStyle(
                        color: trip.statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _RouteLine(
                icon: Icons.my_location_rounded,
                color: AppTheme.success,
                text: trip.originAddress,
              ),
              const SizedBox(height: 6),
              _RouteLine(
                icon: Icons.location_on_rounded,
                color: AppTheme.error,
                text: trip.destinationAddress,
              ),
              const Divider(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _Pill(Icons.schedule_rounded, date.format(trip.createdAt)),
                  if (trip.distanceKm != null)
                    _Pill(
                      Icons.route_rounded,
                      '${trip.distanceKm!.toStringAsFixed(1)} km',
                    ),
                  _Pill(
                    Icons.scale_outlined,
                    '${trip.cargoWeightKg.toStringAsFixed(0)} kg',
                  ),
                ],
              ),
              if (amount != null) ...[
                const SizedBox(height: 12),
                Text(
                  '\$${money.format(amount)} CLP',
                  style: const TextStyle(
                    color: AppTheme.success,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteLine extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _RouteLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.midnight,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Pill(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.slate400),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.slate600,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
