import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/freight_model.dart';
import '../../services/freight_service.dart';
import '../../widgets/common/status_tracker_widget.dart';
import '../shared/web_layout.dart';
import 'widgets/freight_widgets.dart';

class FreightDetailScreen extends StatefulWidget {
  final int freightId;

  const FreightDetailScreen({super.key, required this.freightId});

  @override
  State<FreightDetailScreen> createState() => _FreightDetailScreenState();
}

class _FreightDetailScreenState extends State<FreightDetailScreen> {
  final _service = FreightService();
  FreightModel? _freight;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final freight = await _service.getFreight(widget.freightId);
      if (!mounted) return;
      setState(() {
        _freight = freight;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancelar flete'),
        content: const Text('¿Estás seguro de que deseas cancelar este flete?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _service.updateStatus(
      widget.freightId,
      'cancelled',
      note: 'Cancelado por cliente',
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final freight = _freight;

    if (_loading) {
      return const WebPageScaffold(
        title: 'Detalle de flete',
        child: WebLoadingState(),
      );
    }

    if (freight == null) {
      return WebPageScaffold(
        title: 'Detalle de flete',
        child: WebPageBody(
          children: [
            WebEmptyState(
              icon: Icons.search_off_rounded,
              title: 'Flete no encontrado',
              description: 'No pudimos encontrar el detalle de este flete.',
              actionLabel: 'Reintentar',
              onAction: _load,
            ),
          ],
        ),
      );
    }

    final fmt = NumberFormat('#,##0', 'es_CL');
    final canCancel =
        freight.status == 'pending' || freight.status == 'accepted';

    return WebPageScaffold(
      title: 'Flete #${freight.id}',
      subtitle: 'Detalle operativo para cliente',
      child: WebPageBody(
        onRefresh: _load,
        children: [
          Center(
            child: FreightStatusBadge(
              status: freight.status,
              label: freight.statusLabel,
              color: freight.statusColor,
            ),
          ),
          const SizedBox(height: 24),
          StatusTrackerWidget(currentStatus: freight.status),
          const SizedBox(height: 16),
          FreightInfoCard(
            title: 'Ruta',
            icon: Icons.route_rounded,
            children: [
              FreightInfoRow(
                icon: Icons.my_location_rounded,
                color: AppTheme.success,
                label: 'Origen',
                value: freight.originAddress,
              ),
              const SizedBox(height: 10),
              FreightInfoRow(
                icon: Icons.location_on_rounded,
                color: AppTheme.error,
                label: 'Destino',
                value: freight.destinationAddress,
              ),
              if (freight.distanceKm != null) ...[
                const SizedBox(height: 10),
                FreightInfoRow(
                  icon: Icons.social_distance_rounded,
                  color: AppTheme.primary,
                  label: 'Distancia',
                  value: '${freight.distanceKm!.toStringAsFixed(1)} km',
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          FreightInfoCard(
            title: 'Carga',
            icon: Icons.inventory_2_outlined,
            children: [
              FreightInfoRow(
                icon: Icons.description_outlined,
                color: AppTheme.accent,
                label: 'Descripción',
                value: freight.cargoDescription,
              ),
              const SizedBox(height: 10),
              FreightInfoRow(
                icon: Icons.scale_outlined,
                color: AppTheme.accent,
                label: 'Peso',
                value: '${freight.cargoWeightKg.toStringAsFixed(0)} kg',
              ),
              if ((freight.requiresHelpers ?? 0) > 0) ...[
                const SizedBox(height: 10),
                FreightInfoRow(
                  icon: Icons.people_outline_rounded,
                  color: AppTheme.accent,
                  label: 'Ayudantes',
                  value: '${freight.requiresHelpers}',
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          FreightInfoCard(
            title: 'Precio',
            icon: Icons.payments_outlined,
            children: [
              if (freight.estimatedPrice != null)
                FreightInfoRow(
                  icon: Icons.request_quote_outlined,
                  color: AppTheme.primary,
                  label: 'Estimado',
                  value: '\$${fmt.format(freight.estimatedPrice)} CLP',
                ),
              if (freight.finalPrice != null) ...[
                const SizedBox(height: 10),
                FreightInfoRow(
                  icon: Icons.check_circle_outline_rounded,
                  color: AppTheme.success,
                  label: 'Final',
                  value: '\$${fmt.format(freight.finalPrice)} CLP',
                ),
              ],
              if (freight.estimatedPrice == null && freight.finalPrice == null)
                const Text(
                  'El precio se informará cuando el flete sea evaluado.',
                  style: TextStyle(
                    color: AppTheme.slate600,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
            ],
          ),
          if (canCancel) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error,
              ),
              onPressed: _cancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancelar flete'),
            ),
          ],
        ],
      ),
    );
  }
}
