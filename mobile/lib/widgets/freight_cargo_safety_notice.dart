import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/freight_model.dart';

bool needsCargoSafetyNotice(FreightModel freight) =>
    freight.serviceType == 'home_office';

class FreightCargoSafetyNotice extends StatelessWidget {
  const FreightCargoSafetyNotice({super.key});

  @override
  Widget build(BuildContext context) => const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.shield_outlined, color: AppTheme.primary, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Verifica que la carga quepa y no exceda la capacidad de tu '
              'vehículo. Si usas una camioneta de caja abierta, lleva medios '
              'de sujeción y protección contra lluvia, polvo y golpes. '
              'No aceptes si no puedes transportarla de forma segura.',
              style: TextStyle(
                  color: AppTheme.midnight, fontSize: 14, height: 1.45),
            ),
          ),
        ],
      );
}

Future<bool> confirmFreightCargoSafety(
  BuildContext context,
  FreightModel freight,
) async {
  if (!needsCargoSafetyNotice(freight)) return true;
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Antes de aceptar'),
          content: const SingleChildScrollView(
            child: FreightCargoSafetyNotice(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Entendido, continuar'),
            ),
          ],
        ),
      ) ??
      false;
}
