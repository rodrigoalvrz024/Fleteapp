import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/freight_model.dart';
import '../../services/driver_live_location_service.dart';
import '../../services/freight_service.dart';
import '../../core/theme/app_theme.dart';
import '../../utils/api_error_message.dart';
import '../../utils/image_file_picker.dart';
import '../../widgets/muvv_mobile_ui.dart';
import '../../widgets/freight_chat_access_button.dart';
import '../../widgets/trip_feedback_dialog.dart';
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
  List<String> _cargoPhotoUrls = const [];
  static const int _maxEvidenceBytes = 8 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await _service.getFreight(widget.freightId);
      var cargoPhotoUrls = const <String>[];
      if (f.cargoPhotoCount > 0 && f.status != 'pending') {
        try {
          cargoPhotoUrls = await _service.cargoPhotoUrls(widget.freightId);
        } catch (_) {
          // The details still render if a short-lived photo link is unavailable.
        }
      }
      if (!mounted) return;
      setState(() {
        _freight = f;
        _cargoPhotoUrls = cargoPhotoUrls;
        _loading = false;
      });
      if (_canShareLocation(f)) {
        // Tracking is started automatically after a driver accepts a freight
        // and resumes here if the app returned to this detail screen.
        DriverLiveLocationService.instance.start(f.id);
      } else {
        DriverLiveLocationService.instance.stop(
          freightId: f.id,
          clearServer: false,
        );
      }
    } catch (_) {
      setState(() {
        _loading = false;
      });
    }
  }

  bool _canShareLocation(FreightModel freight) =>
      freight.status == 'accepted' || freight.status == 'in_progress';

  Future<void> _submitDriverFeedback() async {
    setState(() => _actionLoading = true);
    try {
      final submitted = await showTripFeedbackDialog(context, widget.freightId);
      if (submitted) {
        await _load();
        _showMessage('Gracias por evaluar a tu cliente.');
      }
    } catch (_) {
      _showMessage('No pudimos guardar la evaluacion.', error: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _accept() async {
    setState(() {
      _actionLoading = true;
    });
    try {
      final locationReady =
          await DriverLiveLocationService.instance.ensurePermission();
      if (!locationReady) {
        _showMessage(
          DriverLiveLocationService.permissionRequiredMessage,
          error: true,
        );
        return;
      }
      await _service.acceptFreight(widget.freightId);
      final trackingStarted =
          await DriverLiveLocationService.instance.start(widget.freightId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            trackingStarted
                ? 'Flete aceptado. Tu ubicacion se comparte con el cliente.'
                : 'Flete aceptado. Revisa que la ubicacion este activa.',
          ),
          backgroundColor: trackingStarted ? AppTheme.success : AppTheme.error,
        ));
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
      if (status == 'completed' || status == 'cancelled') {
        await DriverLiveLocationService.instance.stop(
          freightId: widget.freightId,
          clearServer: false,
        );
      }
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
    PickedImageFile? picked;
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
      picked = await pickImageFile(source);
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
    if (picked == null) return;

    if (picked.bytes.length > _maxEvidenceBytes) {
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
        picked.bytes,
        picked.name,
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
          fallback: 'No pudimos cargar la foto. Intenta nuevamente.',
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
    // `showDialog` resolves when the pop starts, while the route still runs
    // its exit animation. Keep the controller and the detail view intact
    // until that transition has released its descendants.
    await Future<void>.delayed(kThemeAnimationDuration);
    controller.dispose();
    if (!mounted || pin == null) return;

    await _updateStatus('completed', confirmationPin: pin);
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
      bottomNavigationBar: const MuvvBottomNavigation(
        selected: MuvvNavigationSection.activity,
        driver: true,
      ),
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
            if (f.serviceType != null)
              _Row(
                icon: Icons.category_outlined,
                color: AppTheme.primary,
                label: 'Servicio',
                value: _serviceTypeLabel(f.serviceType!),
              ),
            const SizedBox(height: 8),
            _Row(
                icon: Icons.scale_outlined,
                color: AppTheme.accent,
                label: 'Peso',
                value: '${f.cargoWeightKg} kg'),
            if (f.cargoPhotoCount > 0) ...[
              const SizedBox(height: 12),
              if (f.status == 'pending')
                _Row(
                  icon: Icons.photo_library_outlined,
                  color: AppTheme.primary,
                  label: 'Fotos de la carga',
                  value:
                      '${f.cargoPhotoCount} disponible${f.cargoPhotoCount == 1 ? '' : 's'} al aceptar',
                )
              else
                _CargoPhotoGallery(
                    urls: _cargoPhotoUrls, count: f.cargoPhotoCount),
            ],
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
          if (_canShareLocation(f)) ...[
            const SizedBox(height: 12),
            const _LiveLocationRequiredCard(),
          ],
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
          if (f.status == 'completed' && !f.driverFeedbackSubmitted) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _actionLoading ? null : _submitDriverFeedback,
              icon: const Icon(Icons.rate_review_outlined),
              label: const Text('Evaluar a este cliente'),
            ),
          ] else if (f.status == 'completed') ...[
            const SizedBox(height: 12),
            const _Card(children: [
              Text(
                'Tu evaluacion del cliente fue enviada.',
                style: TextStyle(
                    color: AppTheme.success, fontWeight: FontWeight.w700),
              ),
            ]),
          ],
          if (f.status == 'accepted' || f.status == 'in_progress') ...[
            const SizedBox(height: 12),
            FreightChatAccessButton(
              freightId: f.id,
              label: 'Chat con cliente',
            ),
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

String _serviceTypeLabel(String value) => switch (value) {
      'moving' => 'Mudanza',
      'home_office' => 'Hogar u oficina',
      'urgent' => 'Envio urgente',
      _ => 'Paqueteria',
    };

class _LiveLocationRequiredCard extends StatelessWidget {
  const _LiveLocationRequiredCard();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.success.withValues(alpha: 0.18),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.location_on_rounded, color: AppTheme.success),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ubicacion en vivo activa',
                    style: TextStyle(
                      color: AppTheme.midnight,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Solo el cliente asignado puede verla durante este flete.',
                    style: TextStyle(color: AppTheme.slate600, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _CargoPhotoGallery extends StatelessWidget {
  final List<String> urls;
  final int count;

  const _CargoPhotoGallery({required this.urls, required this.count});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fotos de la carga ($count)',
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: AppTheme.midnight),
          ),
          const SizedBox(height: 9),
          if (urls.isEmpty)
            const Text('No pudimos cargar las fotos. Intenta actualizar.',
                style: TextStyle(color: AppTheme.slate600))
          else
            SizedBox(
              height: 104,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: urls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) => ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    urls[index],
                    width: 132,
                    height: 104,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 132,
                      color: AppTheme.slate100,
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined,
                          color: AppTheme.slate400),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
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
