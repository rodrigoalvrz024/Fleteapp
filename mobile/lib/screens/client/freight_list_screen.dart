import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/freight_model.dart';
import '../../services/freight_service.dart';
import '../../core/theme/app_theme.dart';

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
      setState(() { _freights = data; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mis fletes')),
    body: _loading
        ? const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.primary,
            ))
        : _freights.isEmpty
            ? _EmptyState(
                onTap: () => context.push('/client/create-freight'))
            : RefreshIndicator(
                color: AppTheme.primary,
                onRefresh: _load,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: _freights.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => FreightCard(freight: _freights[i]),
                ),
              ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => context.push('/client/create-freight'),
      backgroundColor: AppTheme.primary,
      elevation: 0,
      icon: const Icon(Icons.add, color: Colors.white),
      label: const Text('Nuevo flete',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
    ),
  );
}

class FreightCard extends StatelessWidget {
  final FreightModel freight;
  const FreightCard({super.key, required this.freight});

  @override
  Widget build(BuildContext context) {
    final fmt    = NumberFormat('#,##0', 'es_CL');
    final status = freight.status;
    final isUrgent = freight.isUrgent ?? false;

    return GestureDetector(
      onTap: () => context.push('/client/freights/${freight.id}'),
      child: Container(
        decoration: isUrgent
            ? AppTheme.urgentDecoration()
            : AppTheme.cardDecoration(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Header: precio + badge ──────────────────
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
                            fontWeight: FontWeight.w500,
                            color: AppTheme.midnight,
                          ),
                        ),
                      Row(children: [
                        if (freight.distanceKm != null)
                          Text(
                            '${freight.distanceKm!.toStringAsFixed(1)} km',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.slate400,
                            ),
                          ),
                        if (isUrgent) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.urgent
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('urgente',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.urgent,
                                  fontWeight: FontWeight.w500,
                                )),
                          ),
                        ],
                      ]),
                    ],
                  ),
                ),
                _StatusBadge(status: status),
              ],
            ),
            const SizedBox(height: 14),

            // ── Ruta ───────────────────────────────────
            _RouteDisplay(
              origin: freight.originAddress,
              destination: freight.destinationAddress,
            ),
            const SizedBox(height: 12),

            // ── Footer: chips ───────────────────────────
            Row(children: [
              _Chip('${freight.cargoWeightKg.toStringAsFixed(0)} kg'),
              const SizedBox(width: 6),
              if ((freight.requiresHelpers ?? 0) > 0)
                _Chip('${freight.requiresHelpers} peoneta${freight.requiresHelpers! > 1 ? "s" : ""}'),
              const Spacer(),
              const Icon(Icons.chevron_right,
                  size: 16, color: AppTheme.slate400),
            ]),
          ],
        ),
      ),
    );
  }
}

class _RouteDisplay extends StatelessWidget {
  final String origin;
  final String destination;
  const _RouteDisplay({required this.origin, required this.destination});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Column(children: [
        Container(
          width: 8, height: 8,
          decoration: const BoxDecoration(
            color: AppTheme.success,
            shape: BoxShape.circle,
          ),
        ),
        Container(
          width: 1, height: 20,
          color: AppTheme.slate200,
        ),
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: AppTheme.error,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ]),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(origin,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.midnight,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            Text(destination,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.midnight,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    ],
  );
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: AppTheme.statusBg(status),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      AppTheme.statusLabel(status),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: AppTheme.statusColor(status),
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppTheme.slate100,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label,
        style: const TextStyle(
          fontSize: 11,
          color: AppTheme.slate600,
        )),
  );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyState({required this.onTap});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.local_shipping_outlined,
                size: 36, color: AppTheme.primary),
          ),
          const SizedBox(height: 20),
          const Text('Sin fletes aún',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppTheme.midnight,
              )),
          const SizedBox(height: 8),
          const Text(
            'Solicita tu primer flete y lo gestionamos por ti',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.slate400,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 200,
            child: ElevatedButton(
              onPressed: onTap,
              child: const Text('Solicitar flete'),
            ),
          ),
        ],
      ),
    ),
  );
}