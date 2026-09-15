/// Planning allowances, not measured weights or guaranteed vehicle fit.
/// The server still selects compatible vehicle classes and owns every price.
class CargoReferenceItem {
  final String id;
  final String label;
  final String detail;
  final double weightKg;
  final double volumeM3;

  const CargoReferenceItem(
      this.id, this.label, this.detail, this.weightKg, this.volumeM3);
}

const cargoReferenceItems = [
  CargoReferenceItem(
      'box', 'Caja mediana', 'Ropa u objetos livianos, no libros', 15, 0.15),
  CargoReferenceItem('washer', 'Lavadora', 'Tamaño doméstico', 80, 0.8),
  CargoReferenceItem('fridge', 'Refrigerador',
      'Una puerta; sin modelos industriales', 100, 1.5),
  CargoReferenceItem(
      'sofa', 'Sofá', 'Hasta 3 asientos; sin chaise longue', 100, 3),
  CargoReferenceItem('table', 'Mesa', 'Hasta 4 personas; sin sillas', 60, 1.5),
  CargoReferenceItem('chair', 'Silla', 'Una silla de comedor', 12, 0.35),
  CargoReferenceItem(
      'bed', 'Cama', 'Dos plazas, base desmontada y colchón', 100, 2.5),
];

class CargoInventory {
  final Map<String, int> quantities;
  CargoInventory(Map<String, int> values)
      : quantities = Map.unmodifiable({
          for (final item in cargoReferenceItems)
            if ((values[item.id] ?? 0) > 0)
              item.id: values[item.id]!.clamp(0, 30),
        });

  bool get isEmpty => quantities.isEmpty;
  double get weightKg => cargoReferenceItems.fold(
      0.0, (sum, item) => sum + item.weightKg * (quantities[item.id] ?? 0));
  double get volumeM3 => double.parse(cargoReferenceItems
      .fold(
          0.0, (sum, item) => sum + item.volumeM3 * (quantities[item.id] ?? 0))
      .toStringAsFixed(3));
  String get summary => cargoReferenceItems
      .where((item) => quantities.containsKey(item.id))
      .map((item) => '${quantities[item.id]} x ${item.label}')
      .join(', ');
}

class FreightVehicleGuide {
  final String type;
  final String title;
  final String description;
  final String example;
  final String cargoLabel;
  final List<String> exampleItems;
  const FreightVehicleGuide(
      this.type, this.title, this.description, this.example,
      {required this.cargoLabel, required this.exampleItems});
}

// Ordered exactly like the server's supported vehicle classes. These descriptions
// are orientation only; do not duplicate capacity thresholds or pricing here.
const freightVehicleGuides = [
  FreightVehicleGuide(
      'pickup',
      'Camioneta',
      'Espacio de carga abierto. Para pocos objetos.',
      'Cajas o un electrodoméstico. La carga necesita protección al viajar al aire libre.',
      cargoLabel: 'Pocos objetos',
      exampleItems: ['box', 'washer']),
  FreightVehicleGuide(
      'van',
      'Furgón cerrado',
      'La carga viaja dentro de un espacio cubierto.',
      'Cajas, sillas o muebles pequeños que necesitan viajar bajo techo.',
      cargoLabel: 'Cajas y muebles pequeños',
      exampleItems: ['box', 'chair']),
  FreightVehicleGuide(
      'truck_small',
      'Camión pequeño',
      'Más espacio para combinar muebles y cajas.',
      'Por ejemplo, trasladar un sofá con cajas o un juego de comedor.',
      cargoLabel: 'Muebles y cajas',
      exampleItems: ['sofa', 'table', 'box']),
  FreightVehicleGuide(
      'truck_medium',
      'Camión mediano',
      'Para mudanzas y varios muebles grandes.',
      'Por ejemplo, trasladar cama, refrigerador y otros muebles de un departamento.',
      cargoLabel: 'Varios muebles grandes',
      exampleItems: ['bed', 'fridge', 'sofa']),
  FreightVehicleGuide(
      'truck_large',
      'Camión grande',
      'Para una carga voluminosa que necesita más espacio.',
      'Muebles de varias habitaciones y muchas cajas. Puede necesitar revisión previa.',
      cargoLabel: 'Mudanza voluminosa',
      exampleItems: ['bed', 'sofa', 'fridge', 'box']),
];

FreightVehicleGuide? vehicleGuide(String? type) {
  for (final guide in freightVehicleGuides) {
    if (guide.type == type) return guide;
  }
  return null;
}

bool isVehicleCandidate(String type, String? recommended) {
  final minimum = freightVehicleGuides.indexWhere((v) => v.type == recommended);
  final index = freightVehicleGuides.indexWhere((v) => v.type == type);
  return minimum >= 0 && index >= minimum;
}
