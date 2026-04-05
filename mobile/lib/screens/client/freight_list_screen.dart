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
        appBar: AppBar(title: const Text('Mis fletes')),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _freights.isEmpty
                ? const Center(
                    child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('No tienes fletes aún',
                          style: TextStyle(color: AppTheme.textSecondary)),
                    ],
                  ))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _freights.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) =>
                          _FreightCard(freight: _freights[i]),
                    ),
                  ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => context.push('/client/create-freight'),
          backgroundColor: AppTheme.primary,
          child: const Icon(Icons.add),
        ),
      );
}

class _FreightCard extends StatelessWidget {
  final FreightModel freight;
  const _FreightCard({required this.freight});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => context.push('/client/freights/${freight.id}'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: freight.statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(freight.statusLabel,
                      style: TextStyle(
                          color: freight.statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                Text('#${freight.id}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
              ]),
              const SizedBox(height: 12),
              _AddressRow(
                  icon: Icons.my_location,
                  color: AppTheme.success,
                  address: freight.originAddress),
              const SizedBox(height: 6),
              _AddressRow(
                  icon: Icons.location_on,
                  color: AppTheme.error,
                  address: freight.destinationAddress),
              const Divider(height: 20),
              Row(children: [
                const Icon(Icons.scale_outlined,
                    size: 14, color: AppTheme.textSecondary),
                const SizedBox(width: 4),
                Text('${freight.cargoWeightKg} kg',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(width: 14),
                if (freight.distanceKm != null) ...[
                  const Icon(Icons.route,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text('${freight.distanceKm!.toStringAsFixed(1)} km',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                ],
                const Spacer(),
                if (freight.estimatedPrice != null)
                  Text(
                      '\$${NumberFormat('#,##0', 'es_CL').format(freight.estimatedPrice)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                          fontSize: 15)),
              ]),
            ],
          ),
        ),
      );
}

class _AddressRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String address;
  const _AddressRow(
      {required this.icon, required this.color, required this.address});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
            child: Text(address,
                style: const TextStyle(fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis)),
      ]);
}
