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
    return WebPageScaffold(
      title: 'Mis fletes',
      subtitle: 'Revisa solicitudes, estados y precios',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createFreight,
        backgroundColor: AppTheme.primary,
        elevation: 0,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Nuevo flete',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
    final isUrgent = freight.isUrgent ?? false;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/app/client/freights/${freight.id}'),
        child: Container(
          decoration: isUrgent
              ? AppTheme.urgentDecoration()
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
                        if (freight.estimatedPrice != null)
                          Text(
                            '\$${fmt.format(freight.estimatedPrice)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.midnight,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (freight.distanceKm != null)
                              Text(
                                '${freight.distanceKm!.toStringAsFixed(1)} km',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.slate600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (isUrgent)
                              const FreightPill(
                                'urgente',
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
