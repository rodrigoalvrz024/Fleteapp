import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/freight_model.dart';
import '../../services/freight_service.dart';
import '../../core/theme/app_theme.dart';
import '../../utils/api_error_message.dart';
import '../shared/web_layout.dart';
import 'widgets/driver_app_bar_actions.dart';

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
  static const int _maxEvidenceBytes = 8 * 1024 * 1024;

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Flete aceptado'),
            backgroundColor: AppTheme.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Error al aceptar'),
            backgroundColor: AppTheme.error));
      }
    } finally {
      setState(() {
        _actionLoading = false;
      });
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppTheme.error : AppTheme.success,
      ),
    );
  }

  Future<void> _updateStatus(String status, {String? confirmationPin}) async {
    setState(() {
      _actionLoading = true;
    });
    try {
      await _service.updateStatus(
        widget.freightId,
        status,
        confirmationPin: confirmationPin,
      );
      await _load();
      _showMessage(
        status == 'completed' ? 'Entrega confirmada' : 'Estado actualizado',
      );
    } catch (_) {
      _showMessage(
        status == 'completed'
            ? 'No pudimos confirmar la entrega. Revisa el PIN.'
            : 'No pudimos actualizar el estado.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _pickEvidence(String kind) async {
    XFile? file;
    try {
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Tomar foto'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Elegir de galería'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (source == null) return;
      file = await ImagePicker().pickImage(
        source: source,
        imageQuality: kIsWeb ? null : 78,
        maxWidth: kIsWeb ? null : 1800,
        requestFullMetadata: false,
      );
    } catch (e) {
      _showMessage(
        apiErrorMessage(
          e,
          fallback: 'No pudimos abrir la camara o galeria.',
        ),
        error: true,
      );
      return;
    }
    if (file == null) return;

    late final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (e) {
      _showMessage(
        'No pudimos leer la foto seleccionada. Prueba con otro archivo JPG o toma la foto nuevamente.',
        error: true,
      );
      return;
    }

    if (bytes.length > _maxEvidenceBytes) {
      _showMessage(
        'La foto supera el maximo de 8 MB. Prueba con una imagen mas liviana.',
        error: true,
      );
      return;
    }

    setState(() => _actionLoading = true);
    try {
      await _service.uploadEvidenceBytes(
        widget.freightId,
        kind,
        bytes,
        file.name,
      );
      await _load();
      _showMessage(
        kind == 'pickup'
            ? 'Foto de retiro registrada'
            : 'Foto de entrega registrada',
      );
    } catch (e) {
      _showMessage(
        apiErrorMessage(
          e,
          fallback: 'No pudimos cargar la foto. Detalle: ${e.toString()}',
        ),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _viewEvidence(String kind) async {
    try {
      final url = await _service.getEvidenceViewUrl(widget.freightId, kind);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      _showMessage('No pudimos abrir la evidencia.', error: true);
    }
  }

  Future<void> _completeWithPin() async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('Confirmar entrega'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pide al cliente el PIN de cuatro dígitos después de entregar la carga.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
              decoration: const InputDecoration(
                labelText: 'PIN de entrega',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length == 4) Navigator.pop(dialogContext, value);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (pin != null) await _updateStatus('completed', confirmationPin: pin);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const WebPageScaffold(
        title: 'Detalle de flete',
        actions: [DriverAppBarActions()],
        child: WebLoadingState(),
      );
    }
    if (_freight == null) {
      return const WebPageScaffold(
        title: 'Detalle de flete',
        actions: [DriverAppBarActions()],
        child: WebPageBody(
          children: [
            WebEmptyState(
              icon: Icons.search_off_rounded,
              title: 'No encontrado',
              description: 'No pudimos cargar esta solicitud.',
            ),
          ],
        ),
      );
    }

    final f = _freight!;
    final fmt = NumberFormat('#,##0', 'es_CL');

    return WebPageScaffold(
      title: 'Flete #${f.id}',
      subtitle: 'Detalle operativo para conductor',
      actions: const [DriverAppBarActions()],
      child: WebPageBody(
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
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
          if (f.status == 'accepted' ||
              f.status == 'in_progress' ||
              f.status == 'completed') ...[
            const SizedBox(height: 12),
            _Card(children: [
              const Text(
                'Evidencia del servicio',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.midnight,
                ),
              ),
              const SizedBox(height: 12),
              _Row(
                icon: f.hasPickupPhoto
                    ? Icons.check_circle_rounded
                    : Icons.photo_camera_outlined,
                color: f.hasPickupPhoto ? AppTheme.success : AppTheme.primary,
                label: 'Retiro',
                value: f.hasPickupPhoto ? 'Foto registrada' : 'Foto pendiente',
              ),
              if (f.hasPickupPhoto) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _viewEvidence('pickup'),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Ver retiro'),
                ),
              ],
              const SizedBox(height: 12),
              _Row(
                icon: f.hasDeliveryPhoto
                    ? Icons.check_circle_rounded
                    : Icons.photo_camera_outlined,
                color: f.hasDeliveryPhoto ? AppTheme.success : AppTheme.primary,
                label: 'Entrega',
                value:
                    f.hasDeliveryPhoto ? 'Foto registrada' : 'Foto pendiente',
              ),
              if (f.hasDeliveryPhoto) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _viewEvidence('delivery'),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Ver entrega'),
                ),
              ],
              if (f.status == 'in_progress') ...[
                const SizedBox(height: 12),
                _Row(
                  icon: f.deliveryPinReady
                      ? Icons.pin_outlined
                      : Icons.hourglass_empty_rounded,
                  color:
                      f.deliveryPinReady ? AppTheme.success : AppTheme.slate600,
                  label: 'PIN',
                  value: f.deliveryPinReady
                      ? 'Preparado por el cliente'
                      : 'Esperando al cliente',
                ),
              ],
            ]),
          ],
          if (f.status == 'completed' && f.ratingScore != null) ...[
            const SizedBox(height: 12),
            _Card(children: [
              const Text(
                'Calificación del cliente',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.midnight,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.star_rounded, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Text(
                    '${f.ratingScore!.toStringAsFixed(0)} de 5',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              if (f.ratingComment != null &&
                  f.ratingComment!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  f.ratingComment!,
                  style: const TextStyle(
                    color: AppTheme.slate600,
                    height: 1.4,
                  ),
                ),
              ],
            ]),
          ],
          const SizedBox(height: 24),
          if (_actionLoading)
            const Center(child: CircularProgressIndicator())
          else ...[
            if (f.status == 'pending')
              ElevatedButton.icon(
                onPressed: _accept,
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Aceptar flete'),
              ),
            if (f.status == 'accepted')
              if (!f.hasPickupPhoto)
                ElevatedButton.icon(
                  onPressed: () => _pickEvidence('pickup'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Registrar foto de retiro'),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => _updateStatus('in_progress'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.secondary),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar viaje'),
                ),
            if (f.status == 'in_progress')
              if (!f.hasDeliveryPhoto)
                ElevatedButton.icon(
                  onPressed: () => _pickEvidence('delivery'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Registrar foto de entrega'),
                )
              else
                ElevatedButton.icon(
                  onPressed: f.deliveryPinReady ? _completeWithPin : null,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success),
                  icon: const Icon(Icons.pin_outlined),
                  label: Text(
                    f.deliveryPinReady
                        ? 'Confirmar con PIN'
                        : 'Esperando PIN del cliente',
                  ),
                ),
          ],
        ],
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
