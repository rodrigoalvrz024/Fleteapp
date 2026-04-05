import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/freight_model.dart';
import '../../services/freight_service.dart';
import '../../core/theme/app_theme.dart';

class DriverFreightDetailScreen extends StatefulWidget {
  final int freightId;
  const DriverFreightDetailScreen({super.key, required this.freightId});
  @override
  State<DriverFreightDetailScreen> createState() =>
      _DriverFreightDetailScreenState();
}

class _DriverFreightDetailScreenState extends State<DriverFreightDetailScreen> {
  final _service = FreightService();
  FreightModel? _freight;
  bool _loading = true;
  bool _actionLoading = false;

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

  Future<void> _accept() async {
    setState(() {
      _actionLoading = true;
    });
    try {
      await _service.acceptFreight(widget.freightId);
      await _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Flete aceptado'),
            backgroundColor: AppTheme.success));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Error al aceptar'),
            backgroundColor: AppTheme.error));
    } finally {
      setState(() {
        _actionLoading = false;
      });
    }
  }

  Future<void> _updateStatus(String status) async {
    setState(() {
      _actionLoading = true;
    });
    try {
      await _service.updateStatus(widget.freightId, status);
      await _load();
    } finally {
      setState(() {
        _actionLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_freight == null)
      return Scaffold(
          appBar: AppBar(), body: const Center(child: Text('No encontrado')));

    final f = _freight!;
    final fmt = NumberFormat('#,##0', 'es_CL');

    return Scaffold(
      appBar: AppBar(title: Text('Flete #${f.id}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                    color: f.statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(30)),
                child: Text(f.statusLabel,
                    style: TextStyle(
                        color: f.statusColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
            _Card(children: [
              _Row(
                  icon: Icons.my_location,
                  color: AppTheme.success,
                  label: 'Origen',
                  value: f.originAddress),
              const SizedBox(height: 8),
              _Row(
                  icon: Icons.location_on,
                  color: AppTheme.error,
                  label: 'Destino',
                  value: f.destinationAddress),
              if (f.distanceKm != null) ...[
                const SizedBox(height: 8),
                _Row(
                    icon: Icons.route,
                    color: AppTheme.primary,
                    label: 'Distancia',
                    value: '${f.distanceKm!.toStringAsFixed(1)} km'),
              ],
            ]),
            const SizedBox(height: 12),
            _Card(children: [
              _Row(
                  icon: Icons.inventory_2_outlined,
                  color: AppTheme.accent,
                  label: 'Carga',
                  value: f.cargoDescription),
              const SizedBox(height: 8),
              _Row(
                  icon: Icons.scale_outlined,
                  color: AppTheme.accent,
                  label: 'Peso',
                  value: '${f.cargoWeightKg} kg'),
            ]),
            const SizedBox(height: 12),
            if (f.estimatedPrice != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(14)),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.attach_money,
                      color: AppTheme.success, size: 28),
                  Text('\$${fmt.format(f.estimatedPrice)} CLP',
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.success)),
                ]),
              ),
            const SizedBox(height: 24),
            if (_actionLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              if (f.status == 'pending')
                ElevatedButton.icon(
                  onPressed: _accept,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Aceptar flete'),
                ),
              if (f.status == 'accepted')
                ElevatedButton.icon(
                  onPressed: () => _updateStatus('in_progress'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondary),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar viaje'),
                ),
              if (f.status == 'in_progress')
                ElevatedButton.icon(
                  onPressed: () => _updateStatus('completed'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success),
                  icon: const Icon(Icons.flag),
                  label: const Text('Marcar como completado'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)]),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value;
  const _Row(
      {required this.icon,
      required this.color,
      required this.label,
      required this.value});
  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
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
