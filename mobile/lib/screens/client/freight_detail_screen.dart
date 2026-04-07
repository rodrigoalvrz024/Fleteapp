import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/freight_model.dart';
import '../../services/freight_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common/status_tracker_widget.dart';

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
      final f = await _service.getFreight(widget.freightId);
      setState(() {
        _freight = f;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
      });
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
              child: const Text('No')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _service.updateStatus(widget.freightId, 'cancelled',
          note: 'Cancelado por cliente');
      if (mounted) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_freight == null) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('Flete no encontrado')));
    }
    final f = _freight!;
    final fmt = NumberFormat('#,##0', 'es_CL');

    return Scaffold(
      appBar: AppBar(title: Text('Flete #${f.id}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Estado
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                    color: f.statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(30)),
                child: Text(f.statusLabel,
                    style: TextStyle(
                        color: f.statusColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 24),

            StatusTrackerWidget(currentStatus: f.status),
            const SizedBox(height: 16),

            _InfoCard(title: 'Ruta', children: [
              _InfoRow(
                  icon: Icons.my_location,
                  color: AppTheme.success,
                  label: 'Origen',
                  value: f.originAddress),
              const SizedBox(height: 8),
              _InfoRow(
                  icon: Icons.location_on,
                  color: AppTheme.error,
                  label: 'Destino',
                  value: f.destinationAddress),
              if (f.distanceKm != null) ...[
                const SizedBox(height: 8),
                _InfoRow(
                    icon: Icons.route,
                    color: AppTheme.primary,
                    label: 'Distancia',
                    value: '${f.distanceKm!.toStringAsFixed(1)} km'),
              ],
            ]),
            const SizedBox(height: 14),

            _InfoCard(title: 'Carga', children: [
              _InfoRow(
                  icon: Icons.inventory_2_outlined,
                  color: AppTheme.accent,
                  label: 'Descripción',
                  value: f.cargoDescription),
              const SizedBox(height: 8),
              _InfoRow(
                  icon: Icons.scale_outlined,
                  color: AppTheme.accent,
                  label: 'Peso',
                  value: '${f.cargoWeightKg} kg'),
              if (f.requiresHelpers > 0) ...[
                const SizedBox(height: 8),
                _InfoRow(
                    icon: Icons.people_outline,
                    color: AppTheme.accent,
                    label: 'Ayudantes',
                    value: '${f.requiresHelpers}'),
              ],
            ]),
            const SizedBox(height: 14),

            _InfoCard(title: 'Precio', children: [
              if (f.estimatedPrice != null)
                _InfoRow(
                    icon: Icons.attach_money,
                    color: AppTheme.primary,
                    label: 'Estimado',
                    value: '\$${fmt.format(f.estimatedPrice)} CLP'),
              if (f.finalPrice != null) ...[
                const SizedBox(height: 8),
                _InfoRow(
                    icon: Icons.check_circle_outline,
                    color: AppTheme.success,
                    label: 'Final',
                    value: '\$${fmt.format(f.finalPrice)} CLP'),
              ],
            ]),
            const SizedBox(height: 24),

            if (f.status == 'pending' || f.status == 'accepted')
              ElevatedButton.icon(
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                onPressed: _cancel,
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancelar flete'),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _InfoCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppTheme.primary)),
            const Divider(height: 16),
            ...children,
          ],
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value;
  const _InfoRow(
      {required this.icon,
      required this.color,
      required this.label,
      required this.value});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text('$label: ',
              style:
                  const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13))),
        ],
      );
}
