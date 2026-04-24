import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../models/freight_model.dart';
import '../../core/theme/app_theme.dart';

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});
  @override
  ConsumerState<DriverHomeScreen> createState() =>
      _DriverHomeScreenState();
}

class _DriverHomeScreenState
    extends ConsumerState<DriverHomeScreen> {

  int _statusIndex = 0;
  final List<String> _statusMsgs = [
    'Escuchando nuevos pedidos…',
    'Buscando fletes cerca…',
    'Conectado y listo…',
    'En espera de solicitudes…',
  ];

  @override
  void initState() {
    super.initState();
    _rotateStatus();
  }

  void _rotateStatus() async {
    while (mounted) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      setState(() =>
          _statusIndex = (_statusIndex + 1) % _statusMsgs.length);
    }
  }

  void _showProfileMenu() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DriverProfileMenu(
        onProfile: () {
          Navigator.pop(context);
          context.push('/profile');
        },
        onLogout: () async {
          Navigator.pop(context);
          await ref.read(driverProvider.notifier).goOffline();
          await ref.read(authProvider.notifier).logout();
          if (mounted) context.go('/login');
        },
        onSupport: () {
          Navigator.pop(context);
          _showSupportSheet();
        },
      ),
    );
  }

  void _showSupportSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SupportSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user    = ref.watch(authProvider).user;
    final driver  = ref.watch(driverProvider);
    final name    = user?.fullName.split(' ').first ?? 'Conductor';
    final fmt     = NumberFormat('#,##0', 'es_CL');

    // Mostrar alerta de flete entrante
    if (driver.incomingFreight != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showIncomingFreight(driver.incomingFreight!);
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primary,
          onRefresh: () =>
              ref.read(driverProvider.notifier).refreshFreights(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [

              // ── Header ────────────────────────────
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Hola, $name 👋',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.midnight,
                          )),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration:
                            const Duration(milliseconds: 400),
                        child: Text(
                          driver.isOnline
                              ? _statusMsgs[_statusIndex]
                              : 'Estás desconectado',
                          key: ValueKey(driver.isOnline
                              ? _statusIndex
                              : -1),
                          style: TextStyle(
                            fontSize: 13,
                            color: driver.isOnline
                                ? AppTheme.success
                                : AppTheme.slate400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _showProfileMenu,
                  child: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppTheme.slate200, width: 0.5),
                    ),
                    child: const Icon(
                        Icons.person_outline_rounded,
                        size: 20,
                        color: AppTheme.midnight),
                  ),
                ),
              ]),
              const SizedBox(height: 16),

              // ── Toggle online/offline ──────────────
              GestureDetector(
                onTap: driver.isLoading
                    ? null
                    : () async {
                        HapticFeedback.mediumImpact();
                        if (driver.isOnline) {
                          await ref
                              .read(driverProvider.notifier)
                              .goOffline();
                        } else {
                          await ref
                              .read(driverProvider.notifier)
                              .goOnline();
                        }
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: driver.isOnline
                        ? const LinearGradient(
                            colors: [
                              Color(0xFF059669),
                              Color(0xFF10B981),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: driver.isOnline
                        ? null
                        : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: driver.isOnline
                        ? null
                        : Border.all(
                            color: AppTheme.slate200,
                            width: 0.5),
                    boxShadow: driver.isOnline
                        ? [
                            BoxShadow(
                              color: AppTheme.success
                                  .withValues(alpha: 0.28),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ]
                        : [],
                  ),
                  child: Row(children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: driver.isOnline
                            ? Colors.white
                                .withValues(alpha: 0.18)
                            : AppTheme.slate100,
                        shape: BoxShape.circle,
                      ),
                      child: driver.isLoading
                          ? Padding(
                              padding: const EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: driver.isOnline
                                    ? Colors.white
                                    : AppTheme.slate400,
                              ),
                            )
                          : Icon(
                              driver.isOnline
                                  ? Icons.wifi_rounded
                                  : Icons.wifi_off_rounded,
                              size: 22,
                              color: driver.isOnline
                                  ? Colors.white
                                  : AppTheme.slate400,
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            driver.isOnline
                                ? 'En línea'
                                : 'Desconectado',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: driver.isOnline
                                  ? Colors.white
                                  : AppTheme.midnight,
                            ),
                          ),
                          Text(
                            driver.isOnline
                                ? 'Toca para desconectarte'
                                : 'Toca para recibir fletes',
                            style: TextStyle(
                              fontSize: 12,
                              color: driver.isOnline
                                  ? Colors.white
                                      .withValues(alpha: 0.75)
                                  : AppTheme.slate400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Toggle pill
                    AnimatedContainer(
                      duration:
                          const Duration(milliseconds: 300),
                      width: 48, height: 28,
                      decoration: BoxDecoration(
                        color: driver.isOnline
                            ? Colors.white
                                .withValues(alpha: 0.28)
                            : AppTheme.slate200,
                        borderRadius:
                            BorderRadius.circular(14),
                      ),
                      child: AnimatedAlign(
                        duration:
                            const Duration(milliseconds: 300),
                        alignment: driver.isOnline
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          width: 22, height: 22,
                          margin: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: driver.isOnline
                                ? Colors.white
                                : AppTheme.slate400,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 14),

              // ── Viaje activo ───────────────────────
              if (driver.activeFreight != null) ...[
                _ActiveFreightCard(
                  freight: driver.activeFreight!,
                  fmt: fmt,
                  onUpdateStatus: (status) => ref
                      .read(driverProvider.notifier)
                      .updateFreightStatus(
                          driver.activeFreight!.id, status),
                  onViewRoute: () => context.push(
                      '/driver/freights/${driver.activeFreight!.id}'),
                ),
                const SizedBox(height: 14),
              ],

              // ── Stats ──────────────────────────────
              Row(children: [
                Expanded(
                  child: _StatCard(
                    icon:  Icons.check_circle_outline_rounded,
                    label: 'Hoy',
                    value: '${driver.completedToday} fletes',
                    color: AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    icon:  Icons.attach_money_rounded,
                    label: 'Ganancias',
                    value: '\$${fmt.format(driver.earningsToday)}',
                    color: AppTheme.success,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatCard(
                    icon:  Icons.star_rounded,
                    label: 'Rating',
                    value: '${driver.rating} ★',
                    color: const Color(0xFFF59E0B),
                  ),
                ),
              ]),
              const SizedBox(height: 14),

              // ── Fletes disponibles ─────────────────
              _FreightsCounter(
                isOnline: driver.isOnline,
                count:    driver.availableFreights.length,
                onTap:    driver.isOnline
                    ? () => context.push('/driver/available')
                    : null,
              ),
              const SizedBox(height: 20),

              // ── Acciones ───────────────────────────
              const _SectionLabel('Acciones'),
              const SizedBox(height: 10),

              // CTA principal
              GestureDetector(
                onTap: driver.isOnline
                    ? () => context.push('/driver/available')
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: driver.isOnline
                        ? const LinearGradient(
                            colors: [
                              Color(0xFF4F94F8),
                              Color(0xFF2563EB),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: driver.isOnline
                        ? null
                        : AppTheme.slate200,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: driver.isOnline
                        ? [
                            BoxShadow(
                              color: AppTheme.primary
                                  .withValues(alpha: 0.28),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_rounded,
                          color: driver.isOnline
                              ? Colors.white
                              : AppTheme.slate400,
                          size: 20),
                      const SizedBox(width: 10),
                      Text('Ver fletes disponibles',
                          style: TextStyle(
                            color: driver.isOnline
                                ? Colors.white
                                : AppTheme.slate400,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          )),
                      if (driver.isOnline &&
                          driver.availableFreights.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white
                                .withValues(alpha: 0.25),
                            borderRadius:
                                BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${driver.availableFreights.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              _ActionTile(
                icon:     Icons.history_rounded,
                label:    'Mis viajes',
                subtitle: 'Fletes aceptados y completados',
                onTap:    () =>
                    context.push('/driver/available'),
                color:    AppTheme.slate600,
              ),
              const SizedBox(height: 10),

              _ActionTile(
                icon:     Icons.help_outline_rounded,
                label:    'Ayuda y soporte',
                subtitle: 'Reportar problema o contactarnos',
                onTap:    _showSupportSheet,
                color:    AppTheme.slate600,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showIncomingFreight(FreightModel freight) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _IncomingFreightDialog(
        freight: freight,
        onAccept: () async {
          Navigator.pop(context);
          final ok = await ref
              .read(driverProvider.notifier)
              .acceptFreight(freight.id);
          if (ok && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('✅ Flete aceptado'),
                backgroundColor: AppTheme.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        },
        onDecline: () {
          Navigator.pop(context);
          ref.read(driverProvider.notifier).dismissIncoming();
        },
      ),
    );
  }
}

// ── Dialog flete entrante ───────────────────────────────────

class _IncomingFreightDialog extends StatefulWidget {
  final FreightModel freight;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _IncomingFreightDialog({
    required this.freight,
    required this.onAccept,
    required this.onDecline,
  });
  @override
  State<_IncomingFreightDialog> createState() =>
      _IncomingFreightDialogState();
}

class _IncomingFreightDialogState
    extends State<_IncomingFreightDialog> {

  static const int _total = 15;
  int _remaining = _total;
  late final timer = Stream.periodic(
    const Duration(seconds: 1),
    (i) => _total - i - 1,
  ).take(_total);

  @override
  void initState() {
    super.initState();
    timer.listen((t) {
      if (!mounted) return;
      setState(() => _remaining = t);
      if (t <= 0) widget.onDecline();
    });
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'es_CL');
    final pct = _remaining / _total;

    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // Countdown
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 64, height: 64,
                  child: CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 4,
                    backgroundColor:
                        AppTheme.slate200,
                    color: pct > 0.4
                        ? AppTheme.success
                        : AppTheme.urgent,
                  ),
                ),
                Text('$_remaining',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.midnight,
                    )),
              ],
            ),
            const SizedBox(height: 12),

            // Badge
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.urgent
                    .withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('⚡ Nuevo flete',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.urgent,
                  )),
            ),
            const SizedBox(height: 16),

            // Ruta
            _RouteRow(
              origin: widget.freight.originAddress,
              destination:
                  widget.freight.destinationAddress,
            ),
            const SizedBox(height: 14),

            // Precio + distancia
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceEvenly,
              children: [
                _InfoChip(
                  icon: Icons.attach_money_rounded,
                  label: widget.freight.estimatedPrice != null
                      ? '\$${fmt.format(widget.freight.estimatedPrice)}'
                      : 'Por calcular',
                  color: AppTheme.success,
                ),
                if (widget.freight.distanceKm != null)
                  _InfoChip(
                    icon: Icons.route_rounded,
                    label:
                        '${widget.freight.distanceKm!.toStringAsFixed(1)} km',
                    color: AppTheme.primary,
                  ),
                _InfoChip(
                  icon: Icons.scale_outlined,
                  label:
                      '${widget.freight.cargoWeightKg} kg',
                  color: AppTheme.slate600,
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Botones
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onDecline,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.slate600,
                    minimumSize:
                        const Size(double.infinity, 48),
                    side: const BorderSide(
                        color: AppTheme.slate200),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(12)),
                  ),
                  child: const Text('Rechazar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: widget.onAccept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    minimumSize:
                        const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Aceptar',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      )),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Card viaje activo ───────────────────────────────────────

class _ActiveFreightCard extends StatelessWidget {
  final FreightModel freight;
  final NumberFormat fmt;
  final Future<void> Function(String) onUpdateStatus;
  final VoidCallback onViewRoute;
  const _ActiveFreightCard({
    required this.freight,
    required this.fmt,
    required this.onUpdateStatus,
    required this.onViewRoute,
  });

  String get _nextStatus {
    switch (freight.status) {
      case 'accepted':   return 'in_transit';
      case 'in_transit': return 'completed';
      default:           return '';
    }
  }

  String get _nextLabel {
    switch (freight.status) {
      case 'accepted':   return 'Iniciar viaje';
      case 'in_transit': return 'Completar flete';
      default:           return '';
    }
  }

  String get _statusLabel {
    switch (freight.status) {
      case 'accepted':   return 'Aceptado · En camino';
      case 'in_transit': return 'En tránsito';
      default:           return freight.status;
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: AppTheme.success.withValues(alpha: 0.3),
        width: 0.8,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.success
                  .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(_statusLabel,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.success,
                )),
          ),
          const Spacer(),
          if (freight.estimatedPrice != null)
            Text(
              '\$${fmt.format(freight.estimatedPrice)}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.midnight,
              ),
            ),
        ]),
        const SizedBox(height: 12),
        _RouteRow(
          origin: freight.originAddress,
          destination: freight.destinationAddress,
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onViewRoute,
              icon: const Icon(Icons.map_outlined,
                  size: 15),
              label: const Text('Ver ruta'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                minimumSize:
                    const Size(double.infinity, 42),
                side: BorderSide(
                  color: AppTheme.primary
                      .withValues(alpha: 0.4),
                ),
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(10)),
              ),
            ),
          ),
          if (_nextStatus.isNotEmpty) ...[
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () =>
                    onUpdateStatus(_nextStatus),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  minimumSize:
                      const Size(double.infinity, 42),
                  shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: Text(_nextLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            ),
          ],
        ]),
      ],
    ),
  );
}

// ── Widgets auxiliares ──────────────────────────────────────

class _RouteRow extends StatelessWidget {
  final String origin, destination;
  const _RouteRow(
      {required this.origin, required this.destination});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(children: [
        const Icon(Icons.my_location_rounded,
            size: 14, color: AppTheme.success),
        const SizedBox(width: 8),
        Expanded(
          child: Text(origin,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.midnight,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Column(children: [
          Container(
              width: 1, height: 8,
              color: AppTheme.slate200),
        ]),
      ),
      Row(children: [
        const Icon(Icons.location_on_rounded,
            size: 14, color: AppTheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(destination,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.midnight,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    ],
  );
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
        horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 5),
      Text(label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: color,
          )),
    ]),
  );
}

class _FreightsCounter extends StatelessWidget {
  final bool isOnline;
  final int count;
  final VoidCallback? onTap;
  const _FreightsCounter({
    required this.isOnline,
    required this.count,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppTheme.slate200, width: 0.5),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: isOnline && count > 0
                ? AppTheme.primary
                    .withValues(alpha: 0.10)
                : AppTheme.slate100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.local_shipping_rounded,
            size: 20,
            color: isOnline && count > 0
                ? AppTheme.primary
                : AppTheme.slate400,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isOnline
                    ? (count > 0
                        ? '$count fletes disponibles'
                        : 'Sin fletes por ahora')
                    : 'Conéctate para ver fletes',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isOnline && count > 0
                      ? AppTheme.midnight
                      : AppTheme.slate400,
                ),
              ),
              Text(
                isOnline
                    ? (count > 0
                        ? 'En tu zona de cobertura'
                        : 'Te avisaremos cuando haya uno')
                    : 'Activa el modo en línea',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.slate400,
                ),
              ),
            ],
          ),
        ),
        if (isOnline && count > 0)
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primary
                  .withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$count',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                )),
          ),
      ]),
    ),
  );
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
          color: AppTheme.slate200, width: 0.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.midnight,
            )),
        Text(label,
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.slate400,
            )),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: AppTheme.slate400,
        letterSpacing: 0.6,
      ));
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final VoidCallback onTap;
  final Color color;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppTheme.slate200, width: 0.5),
      ),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.midnight,
                  )),
              Text(subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.slate400,
                  )),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded,
            size: 16, color: AppTheme.slate400),
      ]),
    ),
  );
}

// ── Menú perfil ─────────────────────────────────────────────

class _DriverProfileMenu extends StatelessWidget {
  final VoidCallback onProfile;
  final VoidCallback onLogout;
  final VoidCallback onSupport;
  const _DriverProfileMenu({
    required this.onProfile,
    required this.onLogout,
    required this.onSupport,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(24)),
    ),
    padding: EdgeInsets.fromLTRB(
        20, 16, 20,
        MediaQuery.of(context).padding.bottom + 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: AppTheme.slate200,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 20),
        _MenuOpt(
          icon:  Icons.person_outline_rounded,
          label: 'Mi perfil',
          sub:   'Datos personales y vehículo',
          onTap: onProfile,
        ),
        _MenuOpt(
          icon:  Icons.help_outline_rounded,
          label: 'Ayuda y soporte',
          sub:   'Reportar problema',
          onTap: onSupport,
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onLogout,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                vertical: 14),
            decoration: BoxDecoration(
              color:
                  AppTheme.error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.error
                    .withValues(alpha: 0.15),
                width: 0.5,
              ),
            ),
            child: const Row(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                Icon(Icons.logout_rounded,
                    size: 16, color: AppTheme.error),
                SizedBox(width: 8),
                Text('Cerrar sesión',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.error,
                    )),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _MenuOpt extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final VoidCallback onTap;
  const _MenuOpt({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(
          vertical: 12, horizontal: 4),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppTheme.slate100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              size: 18, color: AppTheme.slate600),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.midnight,
                  )),
              Text(sub,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.slate400,
                  )),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded,
            size: 16, color: AppTheme.slate400),
      ]),
    ),
  );
}

// ── Sheet de soporte ────────────────────────────────────────

class _SupportSheet extends StatelessWidget {
  const _SupportSheet();

  Future<void> _whatsapp() async {
    final uri = Uri.parse(
      'https://wa.me/56912345678?text='
      '${Uri.encodeComponent("Hola, soy conductor de FleteApp y necesito ayuda.")}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri,
          mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _email() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'conductores@fleteapp.cl',
      query:
          'subject=${Uri.encodeComponent("Soporte conductor")}'
          '&body=${Uri.encodeComponent("Hola,\n\n")}',
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(24)),
    ),
    padding: EdgeInsets.fromLTRB(
        20, 16, 20,
        MediaQuery.of(context).padding.bottom + 20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: AppTheme.slate200,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Ayuda y soporte',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.midnight,
            )),
        const SizedBox(height: 16),
        _SupportOpt(
          icon:  Icons.chat_outlined,
          label: 'WhatsApp',
          sub:   'Respuesta en minutos',
          color: const Color(0xFF25D366),
          onTap: _whatsapp,
        ),
        const SizedBox(height: 8),
        _SupportOpt(
          icon:  Icons.mail_outline_rounded,
          label: 'Correo',
          sub:   'conductores@fleteapp.cl',
          color: AppTheme.primary,
          onTap: _email,
        ),
        const SizedBox(height: 8),
        _SupportOpt(
          icon:  Icons.bug_report_outlined,
          label: 'Reportar problema',
          sub:   'App, pago o ruta',
          color: AppTheme.urgent,
          onTap: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                    'Reporte enviado. Te contactaremos pronto.'),
                backgroundColor: AppTheme.success,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(12)),
              ),
            );
          },
        ),
      ],
    ),
  );
}

class _SupportOpt extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final Color color;
  final VoidCallback onTap;
  const _SupportOpt({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: color.withValues(alpha: 0.15),
            width: 0.5),
      ),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: color,
                  )),
              Text(sub,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.slate400,
                  )),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded,
            size: 14, color: color),
      ]),
    ),
  );
}