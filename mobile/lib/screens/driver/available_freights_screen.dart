import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/freight_model.dart';
import '../../services/freight_service.dart';
import '../shared/web_layout.dart';
import 'widgets/driver_app_bar_actions.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _service.listFreights(status: 'available');
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

  @override
  Widget build(BuildContext context) {
    return WebPageScaffold(
      title: 'Fletes disponibles',
      subtitle: 'Solicitudes que puedes revisar y aceptar',
      actions: const [DriverAppBarActions()],
      child: _loading
          ? const WebLoadingState()
          : _freights.isEmpty
              ? const WebPageBody(
                  children: [
                    WebEmptyState(
                      icon: Icons.inbox_outlined,
                      title: 'No hay fletes disponibles',
                      description:
                          'Cuando haya nuevas solicitudes aprobadas para conductores apareceran aqui.',
                    ),
                  ],
                )
              : WebPageBody(
                  onRefresh: _load,
                  children: [
                    for (final freight in _freights) ...[
                      _AvailableCard(
                        freight: freight,
                        onAccept: () => context.push(
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

class _AvailableCard extends StatelessWidget {
  final FreightModel freight;
  final VoidCallback onAccept;

  const _AvailableCard({
    required this.freight,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'es_CL');
    return WebPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RouteLine(
            icon: Icons.my_location_rounded,
            color: AppTheme.success,
            text: freight.originAddress,
          ),
          const SizedBox(height: 8),
          _RouteLine(
            icon: Icons.location_on_rounded,
            color: AppTheme.error,
            text: freight.destinationAddress,
          ),
          const Divider(height: 22),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Meta(
                  icon: Icons.scale_outlined,
                  label: '${freight.cargoWeightKg} kg'),
              if (freight.distanceKm != null)
                _Meta(
                  icon: Icons.route_rounded,
                  label: '${freight.distanceKm!.toStringAsFixed(1)} km',
                ),
              if ((freight.requiresHelpers ?? 0) > 0)
                _Meta(
                  icon: Icons.people_outline_rounded,
                  label: '${freight.requiresHelpers} peoneta',
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  freight.estimatedPrice == null
                      ? 'Precio por confirmar'
                      : '\$${fmt.format(freight.estimatedPrice)} CLP',
                  style: const TextStyle(
                    color: AppTheme.midnight,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: onAccept,
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('Ver y aceptar'),
              ),
            ],
          ),
        ],
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

class _Meta extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Meta({required this.icon, required this.label});

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
