import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../models/freight_model.dart';
import '../../services/freight_service.dart';
import '../../services/payment_service.dart';
import '../../services/rating_service.dart';
import '../../widgets/common/status_tracker_widget.dart';
import '../shared/web_layout.dart';
import 'widgets/freight_widgets.dart';

class FreightDetailScreen extends StatefulWidget {
  final int freightId;

  const FreightDetailScreen({super.key, required this.freightId});

  @override
  State<FreightDetailScreen> createState() => _FreightDetailScreenState();
}

class _FreightDetailScreenState extends State<FreightDetailScreen> {
  final _service = FreightService();
  final _paymentService = PaymentService();
  final _ratingService = RatingService();
  FreightModel? _freight;
  bool _loading = true;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPaymentResult());
  }

  void _showPaymentResult() {
    final fragment = Uri.base.fragment;
    if (!fragment.contains('?')) return;
    final result = Uri.tryParse(fragment)?.queryParameters['payment'];
    if (result == 'success') {
      _showMessage('Pago confirmado correctamente.');
    } else if (result == 'cancelled') {
      _showMessage('Pago cancelado. Puedes intentarlo nuevamente.',
          error: true);
    } else if (result == 'failed') {
      _showMessage('Webpay no autorizó el pago. Intenta otra vez.',
          error: true);
    }
  }

  Future<void> _load() async {
    try {
      final freight = await _service.getFreight(widget.freightId);
      if (!mounted) return;
      setState(() {
        _freight = freight;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: const Text('Cancelar flete'),
        content: const Text('¿Estás seguro de que deseas cancelar este flete?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _service.updateStatus(
      widget.freightId,
      'cancelled',
      note: 'Cancelado por cliente',
    );
    if (mounted) _load();
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

  Future<void> _generatePin() async {
    setState(() => _actionLoading = true);
    try {
      final pin = await _service.generateDeliveryPin(widget.freightId);
      await _load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: const Text('PIN de entrega'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Compártelo con el conductor únicamente cuando recibas la carga.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              SelectableText(
                pin,
                style: const TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  color: AppTheme.midnight,
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } catch (_) {
      _showMessage('No pudimos generar el PIN.', error: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _viewEvidence(String kind) async {
    try {
      final url = await _service.getEvidenceViewUrl(widget.freightId, kind);
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      _showMessage('No pudimos abrir la evidencia.', error: true);
    }
  }

  Future<void> _payWithWebpay() async {
    setState(() => _actionLoading = true);
    try {
      final payment = await _paymentService.initiateWebpay(widget.freightId);
      final launched = await launchUrl(
        Uri.parse(payment.redirectUrl),
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
        webOnlyWindowName: kIsWeb ? '_self' : null,
      );
      if (!launched) {
        _showMessage('No pudimos abrir Webpay.', error: true);
      }
    } catch (_) {
      _showMessage('No pudimos iniciar el pago.', error: true);
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _rateService() async {
    double score = 5;
    final comment = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: const Text('Califica tu experiencia'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final value = index + 1.0;
                  return IconButton(
                    tooltip: '$value estrellas',
                    onPressed: () => setDialogState(() => score = value),
                    icon: Icon(
                      value <= score
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: AppTheme.accent,
                      size: 34,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: comment,
                maxLines: 3,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Comentario opcional',
                  hintText: 'Cuéntanos cómo fue el servicio',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Ahora no'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Enviar'),
            ),
          ],
        ),
      ),
    );
    if (result != true) {
      comment.dispose();
      return;
    }
    setState(() => _actionLoading = true);
    try {
      await _ratingService.createRating(
        freightId: widget.freightId,
        score: score,
        comment: comment.text,
      );
      await _load();
      _showMessage('Gracias por tu calificación.');
    } catch (_) {
      _showMessage('No pudimos guardar la calificación.', error: true);
    } finally {
      comment.dispose();
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final freight = _freight;

    if (_loading) {
      return const WebPageScaffold(
        title: 'Detalle de flete',
        actions: [WebAppBarActions(homePath: '/app/client')],
        child: WebLoadingState(),
      );
    }

    if (freight == null) {
      return WebPageScaffold(
        title: 'Detalle de flete',
        actions: const [WebAppBarActions(homePath: '/app/client')],
        child: WebPageBody(
          children: [
            WebEmptyState(
              icon: Icons.search_off_rounded,
              title: 'Flete no encontrado',
              description: 'No pudimos encontrar el detalle de este flete.',
              actionLabel: 'Reintentar',
              onAction: _load,
            ),
          ],
        ),
      );
    }

    final fmt = NumberFormat('#,##0', 'es_CL');
    final dateFmt = DateFormat('d MMM yyyy, HH:mm', 'es_CL');
    final canCancel =
        freight.status == 'pending' || freight.status == 'accepted';

    return WebPageScaffold(
      title: 'Flete #${freight.id}',
      subtitle: 'Seguimiento operativo, ruta, carga y precio',
      actions: const [WebAppBarActions(homePath: '/app/client')],
      child: WebPageBody(
        onRefresh: _load,
        children: [
          _FreightDetailHero(
            freight: freight,
            fmt: fmt,
            dateFmt: dateFmt,
          ),
          const SizedBox(height: 24),
          StatusTrackerWidget(currentStatus: freight.status),
          if (freight.driverSummary != null) ...[
            const SizedBox(height: 16),
            _AssignedDriverCard(driver: freight.driverSummary!),
          ],
          const SizedBox(height: 16),
          FreightInfoCard(
            title: 'Ruta',
            icon: Icons.route_rounded,
            children: [
              FreightInfoRow(
                icon: Icons.my_location_rounded,
                color: AppTheme.success,
                label: 'Origen',
                value: freight.originAddress,
              ),
              const SizedBox(height: 10),
              FreightInfoRow(
                icon: Icons.location_on_rounded,
                color: AppTheme.error,
                label: 'Destino',
                value: freight.destinationAddress,
              ),
              if (freight.distanceKm != null) ...[
                const SizedBox(height: 10),
                FreightInfoRow(
                  icon: Icons.social_distance_rounded,
                  color: AppTheme.primary,
                  label: 'Distancia',
                  value: '${freight.distanceKm!.toStringAsFixed(1)} km',
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          FreightInfoCard(
            title: 'Carga',
            icon: Icons.inventory_2_outlined,
            children: [
              FreightInfoRow(
                icon: Icons.description_outlined,
                color: AppTheme.accent,
                label: 'Descripción',
                value: freight.cargoDescription,
              ),
              const SizedBox(height: 10),
              FreightInfoRow(
                icon: Icons.scale_outlined,
                color: AppTheme.accent,
                label: 'Peso',
                value: '${freight.cargoWeightKg.toStringAsFixed(0)} kg',
              ),
              if ((freight.requiresHelpers ?? 0) > 0) ...[
                const SizedBox(height: 10),
                FreightInfoRow(
                  icon: Icons.people_outline_rounded,
                  color: AppTheme.accent,
                  label: 'Ayudantes',
                  value: '${freight.requiresHelpers}',
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          FreightInfoCard(
            title: 'Precio',
            icon: Icons.payments_outlined,
            children: [
              if (freight.clientPays != null)
                FreightInfoRow(
                  icon: Icons.account_balance_wallet_outlined,
                  color: AppTheme.success,
                  label: 'Cliente paga',
                  value: '\$${fmt.format(freight.clientPays)} CLP',
                )
              else if (freight.estimatedPrice != null)
                FreightInfoRow(
                  icon: Icons.request_quote_outlined,
                  color: AppTheme.primary,
                  label: 'Estimado',
                  value: '\$${fmt.format(freight.estimatedPrice)} CLP',
                ),
              if (freight.finalPrice != null) ...[
                const SizedBox(height: 10),
                FreightInfoRow(
                  icon: Icons.check_circle_outline_rounded,
                  color: AppTheme.success,
                  label: 'Final',
                  value: '\$${fmt.format(freight.finalPrice)} CLP',
                ),
              ],
              if (freight.driverReceives != null) ...[
                const SizedBox(height: 10),
                FreightInfoRow(
                  icon: Icons.person_outline_rounded,
                  color: AppTheme.accent,
                  label: 'Conductor',
                  value: '\$${fmt.format(freight.driverReceives)} CLP',
                ),
              ],
              if (freight.platformFee != null) ...[
                const SizedBox(height: 10),
                FreightInfoRow(
                  icon: Icons.receipt_long_outlined,
                  color: AppTheme.slate600,
                  label: 'Comisión',
                  value: '\$${fmt.format(freight.platformFee)} CLP',
                ),
              ],
              if (freight.estimatedPrice == null && freight.finalPrice == null)
                const Text(
                  'El precio se informará cuando el flete sea evaluado.',
                  style: TextStyle(
                    color: AppTheme.slate600,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
            ],
          ),
          if (freight.status == 'accepted' ||
              freight.status == 'in_progress' ||
              freight.status == 'completed') ...[
            const SizedBox(height: 14),
            FreightInfoCard(
              title: 'Respaldo del servicio',
              icon: Icons.verified_user_outlined,
              children: [
                FreightInfoRow(
                  icon: freight.hasPickupPhoto
                      ? Icons.check_circle_rounded
                      : Icons.hourglass_empty_rounded,
                  color: freight.hasPickupPhoto
                      ? AppTheme.success
                      : AppTheme.slate600,
                  label: 'Foto de retiro',
                  value: freight.hasPickupPhoto ? 'Registrada' : 'Pendiente',
                ),
                if (freight.hasPickupPhoto) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _viewEvidence('pickup'),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Ver foto de retiro'),
                  ),
                ],
                const SizedBox(height: 12),
                FreightInfoRow(
                  icon: freight.hasDeliveryPhoto
                      ? Icons.check_circle_rounded
                      : Icons.hourglass_empty_rounded,
                  color: freight.hasDeliveryPhoto
                      ? AppTheme.success
                      : AppTheme.slate600,
                  label: 'Foto de entrega',
                  value: freight.hasDeliveryPhoto ? 'Registrada' : 'Pendiente',
                ),
                if (freight.hasDeliveryPhoto) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _viewEvidence('delivery'),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Ver foto de entrega'),
                  ),
                ],
                if (freight.status != 'completed') ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Genera el PIN y entrégalo al conductor únicamente cuando recibas la carga.',
                    style: TextStyle(color: AppTheme.slate600, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _actionLoading ? null : _generatePin,
                    icon: const Icon(Icons.pin_outlined),
                    label: Text(
                      freight.deliveryPinReady
                          ? 'Generar un PIN nuevo'
                          : 'Generar PIN de entrega',
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (freight.status == 'completed') ...[
            const SizedBox(height: 14),
            FreightInfoCard(
              title: 'Pago y calificación',
              icon: Icons.receipt_long_outlined,
              children: [
                FreightInfoRow(
                  icon: freight.paymentStatus == 'authorized'
                      ? Icons.check_circle_rounded
                      : freight.paymentStatus == 'failed'
                          ? Icons.error_outline_rounded
                          : Icons.payments_outlined,
                  color: freight.paymentStatus == 'authorized'
                      ? AppTheme.success
                      : freight.paymentStatus == 'failed'
                          ? AppTheme.error
                          : AppTheme.primary,
                  label: 'Pago',
                  value: freight.paymentStatus == 'authorized'
                      ? 'Pagado con Webpay'
                      : freight.paymentStatus == 'failed'
                          ? 'No completado'
                          : 'Pendiente',
                ),
                if (freight.paymentStatus == 'failed') ...[
                  const SizedBox(height: 8),
                  const Text(
                    'El intento anterior no generó ningún cobro. Puedes volver a intentarlo.',
                    style: TextStyle(color: AppTheme.slate600, height: 1.4),
                  ),
                ],
                if (freight.paymentStatus != 'authorized') ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _actionLoading ? null : _payWithWebpay,
                    icon: const Icon(Icons.lock_outline_rounded),
                    label: const Text('Pagar con Webpay'),
                  ),
                ] else if (freight.ratingScore == null) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _actionLoading ? null : _rateService,
                    icon: const Icon(Icons.star_outline_rounded),
                    label: const Text('Calificar servicio'),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  FreightInfoRow(
                    icon: Icons.star_rounded,
                    color: AppTheme.accent,
                    label: 'Tu calificación',
                    value: '${freight.ratingScore!.toStringAsFixed(0)} de 5',
                  ),
                ],
              ],
            ),
          ],
          if (canCancel) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.error,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: _cancel,
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancelar flete'),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssignedDriverCard extends StatelessWidget {
  final FreightDriverSummary driver;

  const _AssignedDriverCard({required this.driver});

  @override
  Widget build(BuildContext context) {
    final vehicle = driver.vehicle;
    final ratingText = driver.ratingCount > 0
        ? '${driver.ratingAverage.toStringAsFixed(1)} (${driver.ratingCount})'
        : 'Nuevo';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  image: driver.profileImageUrl != null &&
                          driver.profileImageUrl!.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(driver.profileImageUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: driver.profileImageUrl == null ||
                        driver.profileImageUrl!.isEmpty
                    ? Center(
                        child: Text(
                          driver.firstName.characters.first.toUpperCase(),
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            driver.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.midnight,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (driver.isVerified)
                          const _DriverVerifiedBadge(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vehicle?.displayName ?? 'Vehiculo por confirmar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.slate600,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vehicle?.displayDetail ??
                          'Datos visibles cuando el conductor este asignado',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.slate400,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _DriverSignal(
                  icon: Icons.star_rounded,
                  label: 'Rating',
                  value: ratingText,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DriverSignal(
                  icon: Icons.route_outlined,
                  label: 'Viajes',
                  value: '${driver.totalTrips}',
                  color: AppTheme.success,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DriverSignal(
                  icon: Icons.verified_user_outlined,
                  label: 'Estado',
                  value: driver.isVerified ? 'Verificado' : 'En revision',
                  color:
                      driver.isVerified ? AppTheme.success : AppTheme.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DriverVerifiedBadge extends StatelessWidget {
  const _DriverVerifiedBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 13, color: AppTheme.success),
            SizedBox(width: 4),
            Text(
              'Verificado',
              style: TextStyle(
                color: AppTheme.success,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}

class _DriverSignal extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DriverSignal({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 17),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.midnight,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.slate400,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class _FreightDetailHero extends StatelessWidget {
  final FreightModel freight;
  final NumberFormat fmt;
  final DateFormat dateFmt;

  const _FreightDetailHero({
    required this.freight,
    required this.fmt,
    required this.dateFmt,
  });

  @override
  Widget build(BuildContext context) {
    final amount =
        freight.finalPrice ?? freight.clientPays ?? freight.estimatedPrice;
    final isUrgent = freight.isUrgent ?? false;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.cardDecoration(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      amount != null
                          ? '\$${fmt.format(amount)} CLP'
                          : 'Precio por confirmar',
                      style: const TextStyle(
                        color: AppTheme.midnight,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Creado ${dateFmt.format(freight.createdAt)}',
                      style: const TextStyle(
                        color: AppTheme.slate600,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FreightStatusBadge(
                status: freight.status,
                label: freight.statusLabel,
                color: freight.statusColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FreightPill(
                isUrgent ? 'Urgente' : 'Programado',
                color: isUrgent ? AppTheme.urgent : AppTheme.primary,
              ),
              if (freight.scheduledAt != null)
                FreightPill('Agenda: ${dateFmt.format(freight.scheduledAt!)}'),
              if (freight.distanceKm != null)
                FreightPill('${freight.distanceKm!.toStringAsFixed(1)} km'),
              if ((freight.requiresHelpers ?? 0) > 0)
                FreightPill('${freight.requiresHelpers} ayudante(s)'),
            ],
          ),
        ],
      ),
    );
  }
}
