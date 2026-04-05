import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/freight_model.dart';
import '../../services/freight_service.dart';
import '../../core/theme/app_theme.dart';

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
      setState(() {
        _freights = data;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Fletes disponibles')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _freights.isEmpty
                ? const Center(
                    child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No hay fletes disponibles ahora',
                          style: TextStyle(color: AppTheme.textSecondary)),
                    ],
                  ))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _freights.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _AvailableCard(
                          freight: _freights[i],
                          onAccept: () => context
                              .push('/driver/freights/${_freights[i].id}')),
                    ),
                  ),
      );
}

class _AvailableCard extends StatelessWidget {
  final FreightModel freight;
  final VoidCallback onAccept;
  const _AvailableCard({required this.freight, required this.onAccept});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'es_CL');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
                color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.my_location, size: 15, color: AppTheme.success),
            const SizedBox(width: 6),
            Expanded(
                child: Text(freight.originAddress,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.location_on, size: 15, color: AppTheme.error),
            const SizedBox(width: 6),
            Expanded(
                child: Text(freight.destinationAddress,
                    style: const TextStyle(fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
          ]),
          const Divider(height: 16),
          Row(
            children: [
              Text('${freight.cargoWeightKg} kg',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
              if (freight.distanceKm != null) ...[
                const SizedBox(width: 12),
                Text('${freight.distanceKm!.toStringAsFixed(1)} km',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
              ],
              const Spacer(),
              if (freight.estimatedPrice != null)
                Text('\$${fmt.format(freight.estimatedPrice)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppTheme.primary)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onAccept,
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  minimumSize: const Size(double.infinity, 44)),
              child: const Text('Ver y aceptar'),
            ),
          ),
        ],
      ),
    );
  }
}
