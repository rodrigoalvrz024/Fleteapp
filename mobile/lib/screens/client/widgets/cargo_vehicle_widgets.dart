import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/cargo_guidance.dart';
import '../../../widgets/muvv_mobile_ui.dart';

class CargoInventorySheet extends StatefulWidget {
  final CargoInventory initial;
  const CargoInventorySheet({super.key, required this.initial});
  @override
  State<CargoInventorySheet> createState() => _CargoInventorySheetState();
}

class _CargoInventorySheetState extends State<CargoInventorySheet> {
  late final Map<String, int> _quantities = Map.of(widget.initial.quantities);
  void _change(String id, int delta) {
    HapticFeedback.selectionClick();
    setState(
        () => _quantities[id] = ((_quantities[id] ?? 0) + delta).clamp(0, 30));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
              child: Row(children: [
                Expanded(
                    child: Text('Objetos de tu carga',
                        style: Theme.of(context).textTheme.titleLarge)),
                IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ])),
          Expanded(
              child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: cargoReferenceItems.length,
            separatorBuilder: (_, __) => const Divider(height: 24),
            itemBuilder: (context, index) {
              final item = cargoReferenceItems[index];
              final quantity = _quantities[item.id] ?? 0;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.label,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(item.detail,
                        style: Theme.of(context).textTheme.bodySmall),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      IconButton(
                          tooltip: 'Quitar ${item.label}',
                          onPressed:
                              quantity > 0 ? () => _change(item.id, -1) : null,
                          icon: const Icon(Icons.remove_circle_outline)),
                      SizedBox(
                          width: 42,
                          child:
                              Text('$quantity', textAlign: TextAlign.center)),
                      IconButton(
                          tooltip: 'Agregar ${item.label}',
                          onPressed:
                              quantity < 30 ? () => _change(item.id, 1) : null,
                          icon: const Icon(Icons.add_circle_outline),
                          color: AppTheme.primary),
                    ]),
                  ]);
            },
          )),
          Padding(
              padding: const EdgeInsets.all(20),
              child: MuvvGradientButton(
                label: 'Guardar objetos',
                icon: Icons.check,
                onPressed: () =>
                    Navigator.pop(context, CargoInventory(_quantities)),
              )),
        ]),
      );
}

class FreightVehicleChoice extends StatelessWidget {
  final FreightVehicleGuide guide;
  final bool selected;
  final bool recommended;
  final bool enabled;
  final String? price;
  final VoidCallback onTap;
  const FreightVehicleChoice(
      {super.key,
      required this.guide,
      required this.selected,
      required this.recommended,
      required this.enabled,
      required this.onTap,
      this.price});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        child: MuvvSurfaceCard(
          emphasized: selected,
          borderColor: selected ? AppTheme.primary : AppTheme.slate200,
          onTap: enabled ? onTap : null,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(
                  guide.type == 'van'
                      ? Icons.airport_shuttle_outlined
                      : Icons.local_shipping_outlined,
                  size: 30,
                  color: enabled ? AppTheme.primary : AppTheme.slate400),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(guide.cargoLabel,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(guide.title,
                        style: Theme.of(context).textTheme.bodySmall),
                  ])),
              const SizedBox(width: 8),
              Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? AppTheme.primary : AppTheme.slate400),
            ]),
            if (recommended) ...[
              const SizedBox(height: 10),
              const Text('Recomendado para tu carga',
                  style: TextStyle(
                      color: AppTheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 10,
              children: [
                for (final id in guide.exampleItems)
                  Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_cargoIcon(id),
                        size: 28,
                        color: enabled ? AppTheme.primary : AppTheme.slate400),
                    const SizedBox(height: 4),
                    Text(
                        cargoReferenceItems
                            .firstWhere((item) => item.id == id)
                            .label,
                        style: Theme.of(context).textTheme.bodySmall),
                  ]),
              ],
            ),
            const SizedBox(height: 12),
            Text(guide.description,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(guide.example, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(
                !enabled
                    ? 'No disponible para esta carga'
                    : price ?? 'Seleccionar para consultar precio',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: enabled ? AppTheme.midnight : AppTheme.slate600)),
          ]),
        ),
      );
}

IconData _cargoIcon(String id) => switch (id) {
      'washer' => Icons.local_laundry_service_outlined,
      'fridge' => Icons.kitchen_outlined,
      'sofa' => Icons.weekend_outlined,
      'table' => Icons.table_restaurant_outlined,
      'chair' => Icons.chair_alt_outlined,
      'bed' => Icons.bed_outlined,
      _ => Icons.inventory_2_outlined,
    };
