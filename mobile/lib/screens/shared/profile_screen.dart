import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/driver_model.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../services/driver_onboarding_service.dart';
import '../../services/privacy_service.dart';
import 'web_layout.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _privacyService = PrivacyService();
  final _driverService = DriverOnboardingService();
  Uint8List? _avatarBytes;
  bool _privacyLoading = false;
  bool _driverProfileRequested = false;
  bool _driverProfileLoading = false;
  DriverModel? _driverProfile;
  String? _driverProfileError;

  void _ensureDriverProfile(String role) {
    if (role != 'driver' || _driverProfileRequested) return;
    _driverProfileRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDriverProfile());
  }

  Future<void> _loadDriverProfile() async {
    if (!mounted) return;
    setState(() {
      _driverProfileLoading = true;
      _driverProfileError = null;
    });
    try {
      final driver = await _driverService.getMyDriver();
      if (!mounted) return;
      setState(() => _driverProfile = driver);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _driverProfile = null;
        _driverProfileError = 'No pudimos cargar tu perfil de conductor.';
      });
    } finally {
      if (mounted) setState(() => _driverProfileLoading = false);
    }
  }

  Future<void> _pickAvatar() async {
    HapticFeedback.lightImpact();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (picked != null && mounted) {
      final bytes = await picked.readAsBytes();
      setState(() => _avatarBytes = bytes);
    }
  }

  void _showEditProfile(BuildContext ctx, String name, String phone) =>
      showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _EditProfileSheet(name: name, phone: phone),
      );

  void _showChangePassword(BuildContext ctx) => showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _ChangePasswordSheet(),
      );

  void _showAddresses(BuildContext ctx) => showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _AddressesSheet(),
      );

  void _showPayments(BuildContext ctx) => showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _PaymentsSheet(),
      );

  void _showHelp(BuildContext ctx) => showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _HelpSheet(),
      );

  Future<void> _launchEmail(String email, String subject) async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      query: 'subject=${Uri.encodeComponent(subject)}'
          '&body=${Uri.encodeComponent("Hola equipo FleteApp,\n\n")}',
    );
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _launchWhatsApp() async {
    const phone = '56912345678';
    const message = 'Hola, necesito ayuda con mi cuenta de FleteApp.';
    final uri =
        Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _confirmLogout(BuildContext ctx) => showDialog(
        context: ctx,
        builder: (_) => _ConfirmDialog(
          title: 'Cerrar sesión',
          message: '¿Estás seguro de que quieres salir?',
          confirmLabel: 'Salir',
          confirmColor: AppTheme.error,
          onConfirm: () async {
            Navigator.pop(ctx);
            await ref.read(authProvider.notifier).logout();
            if (mounted) context.go('/auth/login');
          },
        ),
      );

  Future<void> _submitPrivacyRequest(
    BuildContext ctx,
    String requestType,
    String success,
  ) async {
    if (_privacyLoading) return;
    setState(() => _privacyLoading = true);
    try {
      await _privacyService.createRequest(requestType: requestType);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        _snack(success, AppTheme.success),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        _snack('No se pudo crear la solicitud', AppTheme.error),
      );
    } finally {
      if (mounted) setState(() => _privacyLoading = false);
    }
  }

  void _confirmPrivacyRequest(
    BuildContext ctx, {
    required String title,
    required String message,
    required String requestType,
    required String confirmLabel,
    required String success,
    Color confirmColor = AppTheme.primary,
  }) =>
      showDialog(
        context: ctx,
        builder: (_) => _ConfirmDialog(
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          confirmColor: confirmColor,
          onConfirm: () async {
            Navigator.pop(ctx);
            await _submitPrivacyRequest(ctx, requestType, success);
          },
        ),
      );

  void _confirmDeleteAccount(BuildContext ctx) => showDialog(
        context: ctx,
        builder: (_) => _ConfirmDialog(
          title: 'Eliminar cuenta',
          message: 'Crearemos una solicitud para revisar tu cuenta, fletes, '
              'pagos y documentos asociados.',
          confirmLabel: 'Solicitar',
          confirmColor: AppTheme.error,
          onConfirm: () async {
            Navigator.pop(ctx);
            await _submitPrivacyRequest(
              ctx,
              'account_deletion',
              'Solicitud de eliminación creada',
            );
          },
        ),
      );

  SnackBar _snack(String msg, Color color) => SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    final name = user?.fullName ?? 'Usuario';
    final email = user?.email ?? '';
    final phone = user?.phone ?? 'Sin teléfono';
    final role = user?.role ?? 'client';
    _ensureDriverProfile(role);
    final initials =
        name.trim().split(' ').take(2).map((w) => w[0].toUpperCase()).join();

    return WebPageScaffold(
      title: 'Mi perfil',
      subtitle: 'Cuenta, privacidad, soporte y seguridad',
      actions: [
        WebAppBarActions(
          homePath: role == 'driver'
              ? '/app/driver'
              : role == 'admin'
                  ? '/admin'
                  : '/app/client',
        ),
      ],
      child: WebPageBody(
        maxWidth: 780,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          // ── Avatar ───────────────────────────────────
          Center(
            child: Column(children: [
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                        width: 2,
                      ),
                    ),
                    child: _avatarBytes != null
                        ? ClipOval(
                            child:
                                Image.memory(_avatarBytes!, fit: BoxFit.cover))
                        : Center(
                            child: Text(initials,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primary,
                                ))),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt_rounded,
                          size: 12, color: Colors.white),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Text(name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.midnight,
                  )),
              const SizedBox(height: 4),
              Text(email,
                  style:
                      const TextStyle(fontSize: 13, color: AppTheme.slate400)),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  role == 'driver' ? 'Conductor' : 'Cliente',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.success,
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // ── 1. Información personal ──────────────────
          if (role == 'driver') ...[
            _DriverProfilePanel(
              driver: _driverProfile,
              loading: _driverProfileLoading,
              error: _driverProfileError,
              onRefresh: _loadDriverProfile,
              onOnboarding: () => context.push('/app/driver/onboarding'),
              onTrips: () => context.push('/app/driver/trips'),
              onPayouts: () => context.push('/app/driver/payouts'),
            ),
            const SizedBox(height: 16),
          ],

          const _SectionTitle('Información personal'),
          const SizedBox(height: 8),
          _Card(children: [
            _Item(
              icon: Icons.person_outline_rounded,
              label: 'Nombre',
              value: name,
              onTap: () => _showEditProfile(context, name, phone),
            ),
            _Div(),
            _Item(
              icon: Icons.phone_outlined,
              label: 'Teléfono',
              value: phone,
              onTap: () => _showEditProfile(context, name, phone),
            ),
            _Div(),
            _Item(
              icon: Icons.mail_outline_rounded,
              label: 'Correo',
              value: email,
              onTap: null,
              trailing: const _Badge('Verificado'),
            ),
          ]),
          const SizedBox(height: 16),

          // ── 2. Direcciones ───────────────────────────
          const _SectionTitle('Mis direcciones'),
          const SizedBox(height: 8),
          _Card(children: [
            _Item(
              icon: Icons.home_outlined,
              label: 'Casa',
              value: 'Sin dirección guardada',
              onTap: () => _showAddresses(context),
            ),
            _Div(),
            _Item(
              icon: Icons.work_outline_rounded,
              label: 'Trabajo',
              value: 'Sin dirección guardada',
              onTap: () => _showAddresses(context),
            ),
            _Div(),
            _Item(
              icon: Icons.add_rounded,
              label: 'Agregar dirección',
              value: '',
              onTap: () => _showAddresses(context),
              isAction: true,
            ),
          ]),
          const SizedBox(height: 16),

          // ── 3. Métodos de pago ───────────────────────
          const _SectionTitle('Métodos de pago'),
          const SizedBox(height: 8),
          _Card(children: [
            _Item(
              icon: Icons.credit_card_outlined,
              label: 'Tarjetas',
              value: 'Ninguna guardada',
              onTap: () => _showPayments(context),
            ),
            _Div(),
            _Item(
              icon: Icons.add_rounded,
              label: 'Agregar tarjeta',
              value: '',
              onTap: () => _showPayments(context),
              isAction: true,
            ),
          ]),
          const SizedBox(height: 16),

          // ── 4. Seguridad ─────────────────────────────
          const _SectionTitle('Seguridad'),
          const SizedBox(height: 8),
          _Card(children: [
            _Item(
              icon: Icons.lock_outline_rounded,
              label: 'Cambiar contraseña',
              value: '',
              onTap: () => _showChangePassword(context),
            ),
            _Div(),
            _Item(
              icon: Icons.logout_rounded,
              label: 'Cerrar sesión',
              value: '',
              onTap: () => _confirmLogout(context),
              color: AppTheme.error,
            ),
          ]),
          const SizedBox(height: 16),

          // ── 5. Ayuda y soporte ───────────────────────
          const _SectionTitle('Privacidad y datos'),
          const SizedBox(height: 8),
          _Card(children: [
            _Item(
              icon: Icons.file_download_outlined,
              label: 'Solicitar copia de datos',
              value: 'Acceso a tus datos personales',
              onTap: () => _confirmPrivacyRequest(
                context,
                title: 'Copia de datos',
                message: 'Crearemos una solicitud para preparar la informacion '
                    'asociada a tu cuenta.',
                requestType: 'data_export',
                confirmLabel: 'Solicitar',
                success: 'Solicitud de copia creada',
              ),
            ),
            _Div(),
            _Item(
              icon: Icons.edit_note_rounded,
              label: 'Rectificar datos',
              value: 'Actualizar informacion incorrecta',
              onTap: () => _confirmPrivacyRequest(
                context,
                title: 'Rectificar datos',
                message: 'Crearemos una solicitud para revisar y corregir '
                    'informacion de tu cuenta.',
                requestType: 'data_rectification',
                confirmLabel: 'Solicitar',
                success: 'Solicitud de rectificacion creada',
              ),
            ),
            _Div(),
            _Item(
              icon: Icons.privacy_tip_outlined,
              label: 'Politica de privacidad',
              value: 'Version vigente',
              onTap: () => context.push('/legal/privacy'),
            ),
          ]),
          const SizedBox(height: 16),

          const _SectionTitle('Ayuda y soporte'),
          const SizedBox(height: 8),
          _Card(children: [
            _Item(
              icon: Icons.help_outline_rounded,
              label: 'Centro de ayuda',
              value: 'Preguntas frecuentes',
              onTap: () => _showHelp(context),
            ),
            _Div(),
            _Item(
              icon: Icons.mail_outline_rounded,
              label: 'Contactar soporte',
              value: 'soporte@fleteapp.cl',
              onTap: () => _launchEmail(
                'soporte@fleteapp.cl',
                'Ayuda con mi cuenta FleteApp',
              ),
            ),
            _Div(),
            _Item(
              icon: Icons.chat_outlined,
              label: 'WhatsApp',
              value: 'Respuesta en minutos',
              onTap: _launchWhatsApp,
              color: const Color(0xFF25D366),
            ),
            _Div(),
            _Item(
              icon: Icons.star_outline_rounded,
              label: 'Calificar la app',
              value: 'Ayúdanos a mejorar',
              onTap: () {},
            ),
          ]),
          const SizedBox(height: 16),

          // ── 6. Zona de peligro ───────────────────────
          const _SectionTitle('Zona de peligro'),
          const SizedBox(height: 8),
          _Card(children: [
            _Item(
              icon: Icons.delete_outline_rounded,
              label: 'Eliminar cuenta',
              value: 'Crear solicitud de eliminacion',
              onTap: () => _confirmDeleteAccount(context),
              color: AppTheme.error,
            ),
          ]),

          const SizedBox(height: 32),
          const Center(
            child: Text('FleteApp v1.0.0',
                style: TextStyle(fontSize: 11, color: AppTheme.slate400)),
          ),
        ],
      ),
    );
  }
}

// ── Widgets base ────────────────────────────────────────────

class _DriverProfilePanel extends StatelessWidget {
  final DriverModel? driver;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;
  final VoidCallback onOnboarding;
  final VoidCallback onTrips;
  final VoidCallback onPayouts;

  const _DriverProfilePanel({
    required this.driver,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onOnboarding,
    required this.onTrips,
    required this.onPayouts,
  });

  Color get _statusColor {
    final status = driver?.status;
    if (status == 'approved') return AppTheme.success;
    if (status == 'pending' || status == 'under_review') {
      return AppTheme.warning;
    }
    if (status == 'rejected' || status == 'suspended') return AppTheme.error;
    return AppTheme.slate400;
  }

  String get _statusLabel {
    final current = driver;
    if (current == null) return 'Sin perfil';
    if (current.isApproved) return 'Aprobado para operar';
    if (current.isUnderReview) return 'En revision';
    if (current.isRejected) return 'Requiere actualizacion';
    return 'Perfil incompleto';
  }

  String _licenseExpiryLabel(DateTime? value) {
    if (value == null) return 'Sin vencimiento registrado';
    return 'Vence ${DateFormat('dd/MM/yyyy').format(value.toLocal())}';
  }

  @override
  Widget build(BuildContext context) {
    final current = driver;
    if (loading && current == null) {
      return const _Card(
        children: [
          SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ],
      );
    }

    if (error != null && current == null) {
      return _Card(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppTheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        error!,
                        style: const TextStyle(
                          color: AppTheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (current == null) {
      return _Card(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _DriverPanelHeader(
                  icon: Icons.badge_outlined,
                  title: 'Perfil de conductor',
                  subtitle: 'Crea tu perfil para comenzar la revision.',
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: onOnboarding,
                  icon: const Icon(Icons.assignment_ind_outlined, size: 18),
                  label: const Text('Crear perfil de conductor'),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final vehicle = current.vehicles.isNotEmpty ? current.vehicles.first : null;
    final documents = [
      _DriverDocState('Licencia', current.licenseImageUrl != null),
      _DriverDocState(
        'Permiso/certificado vehiculo',
        current.circulationPermitUrl != null || current.vehicleDocUrl != null,
      ),
      _DriverDocState('Revision tecnica', current.technicalReviewUrl != null),
      _DriverDocState('SOAP', current.soapUrl != null),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('Perfil de conductor'),
        const SizedBox(height: 8),
        _Card(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _DriverPanelHeader(
                          icon: Icons.verified_user_outlined,
                          title: _statusLabel,
                          subtitle: current.rejectionReason?.isNotEmpty == true
                              ? current.rejectionReason!
                              : 'ID conductor #${current.id} - RUT ${current.rut}',
                        ),
                      ),
                      IconButton(
                        tooltip: 'Actualizar perfil',
                        onPressed: loading ? null : onRefresh,
                        icon: loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _DriverStatusBanner(
                    label: _statusLabel,
                    color: _statusColor,
                    message: current.isApproved
                        ? 'Tu cuenta puede recibir y aceptar fletes.'
                        : current.isUnderReview
                            ? 'El equipo esta revisando tus documentos.'
                            : 'Completa o actualiza tus documentos para operar.',
                  ),
                  const SizedBox(height: 14),
                  _DriverReadinessPanel(
                    driver: current,
                    onAction: onOnboarding,
                  ),
                  const SizedBox(height: 14),
                  _DriverOperationalStats(driver: current),
                  const SizedBox(height: 14),
                  _DriverExpiryPanel(driver: current),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 620;
                      final license = _DriverInfoTile(
                        icon: Icons.credit_card_rounded,
                        label: 'Licencia',
                        value: current.licenseNumber ?? 'Sin numero',
                        helper: _licenseExpiryLabel(current.licenseExpiry),
                      );
                      final vehicleTile = _DriverInfoTile(
                        icon: Icons.local_shipping_outlined,
                        label: 'Vehiculo',
                        value: vehicle == null
                            ? 'Sin vehiculo registrado'
                            : '${vehicle.brand} ${vehicle.model} ${vehicle.year}',
                        helper: vehicle == null
                            ? 'Agrega un vehiculo en onboarding'
                            : '${vehicle.plate} - ${vehicle.color}',
                      );
                      if (compact) {
                        return Column(
                          children: [
                            license,
                            const SizedBox(height: 10),
                            vehicleTile,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: license),
                          const SizedBox(width: 10),
                          Expanded(child: vehicleTile),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _DriverDocumentChecklist(documents: documents),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _DriverQuickAction(
                        icon: Icons.assignment_outlined,
                        label: 'Documentos',
                        onTap: onOnboarding,
                      ),
                      _DriverQuickAction(
                        icon: Icons.route_outlined,
                        label: 'Mis viajes',
                        onTap: onTrips,
                      ),
                      _DriverQuickAction(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Liquidaciones',
                        onTap: onPayouts,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DriverPanelHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DriverPanelHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.midnight,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.slate400,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _DriverStatusBanner extends StatelessWidget {
  final String label;
  final String message;
  final Color color;

  const _DriverStatusBanner({
    required this.label,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: const TextStyle(
                      color: AppTheme.slate600,
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _DriverReadinessPanel extends StatelessWidget {
  final DriverModel driver;
  final VoidCallback onAction;

  const _DriverReadinessPanel({
    required this.driver,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final ready = driver.canOperate;
    final color = ready ? AppTheme.success : AppTheme.warning;
    final blockers = driver.operationalBlockers.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                ready
                    ? Icons.check_circle_outline_rounded
                    : Icons.warning_amber_rounded,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ready ? 'Listo para operar' : 'No listo para operar',
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ready
                ? 'Puedes conectarte y aceptar fletes disponibles.'
                : blockers.isEmpty
                    ? 'Revisa tu aprobacion, vehiculo y documentos vigentes.'
                    : 'Resuelve estos puntos antes de conectarte.',
            style: const TextStyle(
              color: AppTheme.slate600,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          if (!ready && blockers.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final blocker in blockers) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.error_outline_rounded,
                      color: color,
                      size: 15,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      blocker,
                      style: const TextStyle(
                        color: AppTheme.midnight,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
          ],
          if (!ready) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.assignment_outlined, size: 16),
                label: const Text('Actualizar documentos'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DriverOperationalStats extends StatelessWidget {
  final DriverModel driver;

  const _DriverOperationalStats({required this.driver});

  @override
  Widget build(BuildContext context) {
    final rating = driver.ratingCount > 0
        ? driver.ratingAverage.toStringAsFixed(1)
        : 'Nuevo';
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final items = [
          _DriverMetricData(
            icon: Icons.power_settings_new_rounded,
            label: 'Disponibilidad',
            value: driver.isAvailable ? 'En linea' : 'Fuera de linea',
            color: driver.isAvailable ? AppTheme.success : AppTheme.slate400,
          ),
          _DriverMetricData(
            icon: Icons.star_rounded,
            label: 'Rating',
            value: rating,
            helper: driver.ratingCount > 0
                ? '${driver.ratingCount} calificaciones'
                : 'Sin calificaciones',
            color: AppTheme.accent,
          ),
          _DriverMetricData(
            icon: Icons.route_outlined,
            label: 'Viajes',
            value: '${driver.totalTrips}',
            helper: 'Completados',
            color: AppTheme.primary,
          ),
        ];
        if (compact) {
          return Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                _DriverMetricTile(data: items[i]),
                if (i != items.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              Expanded(child: _DriverMetricTile(data: items[i])),
              if (i != items.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }
}

class _DriverMetricData {
  final IconData icon;
  final String label;
  final String value;
  final String? helper;
  final Color color;

  const _DriverMetricData({
    required this.icon,
    required this.label,
    required this.value,
    this.helper,
    required this.color,
  });
}

class _DriverMetricTile extends StatelessWidget {
  final _DriverMetricData data;

  const _DriverMetricTile({required this.data});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: data.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: data.color.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Icon(data.icon, color: data.color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.slate400,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.midnight,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if ((data.helper ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      data.helper!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.slate400,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

class _DriverExpiryPanel extends StatelessWidget {
  final DriverModel driver;

  const _DriverExpiryPanel({required this.driver});

  List<_DriverExpiryItem> get _items => [
        _DriverExpiryItem(
          label: 'Licencia',
          expiry: driver.licenseExpiry,
          uploaded: driver.licenseImageUrl != null,
        ),
        _DriverExpiryItem(
          label: 'Permiso circulacion',
          expiry: driver.circulationPermitExpiry ?? driver.vehicleDocExpiry,
          uploaded:
              driver.circulationPermitUrl != null || driver.vehicleDocUrl != null,
        ),
        _DriverExpiryItem(
          label: 'Revision tecnica',
          expiry: driver.technicalReviewExpiry,
          uploaded: driver.technicalReviewUrl != null,
        ),
        _DriverExpiryItem(
          label: 'SOAP',
          expiry: driver.soapExpiry,
          uploaded: driver.soapUrl != null,
        ),
      ];

  Color _colorFor(_DriverExpiryItem item) {
    final days = driver.daysUntil(item.expiry);
    if (!item.uploaded || item.expiry == null) return AppTheme.slate400;
    if (days != null && days < 0) return AppTheme.error;
    if (days != null && days <= 30) return AppTheme.warning;
    return AppTheme.success;
  }

  String _statusFor(_DriverExpiryItem item) {
    final days = driver.daysUntil(item.expiry);
    if (!item.uploaded) return 'Pendiente';
    if (item.expiry == null) return 'Sin fecha';
    if (days == null) return 'Registrado';
    if (days < 0) return 'Vencido';
    if (days == 0) return 'Vence hoy';
    if (days <= 30) return '$days dias';
    return 'Vigente';
  }

  String _detailFor(_DriverExpiryItem item) {
    if (!item.uploaded) return 'Documento no cargado';
    final expiry = item.expiry;
    if (expiry == null) return 'Agrega vencimiento para activar alertas';
    return DateFormat('dd/MM/yyyy').format(expiry.toLocal());
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.slate200, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Vencimientos documentales',
              style: TextStyle(
                color: AppTheme.midnight,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < _items.length; i++) ...[
              _DriverExpiryRow(
                item: _items[i],
                color: _colorFor(_items[i]),
                status: _statusFor(_items[i]),
                detail: _detailFor(_items[i]),
              ),
              if (i != _items.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
      );
}

class _DriverExpiryItem {
  final String label;
  final DateTime? expiry;
  final bool uploaded;

  const _DriverExpiryItem({
    required this.label,
    required this.expiry,
    required this.uploaded,
  });
}

class _DriverExpiryRow extends StatelessWidget {
  final _DriverExpiryItem item;
  final Color color;
  final String status;
  final String detail;

  const _DriverExpiryRow({
    required this.item,
    required this.color,
    required this.status,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(
            status == 'Vencido'
                ? Icons.error_outline_rounded
                : Icons.event_available_outlined,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    color: AppTheme.slate600,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  detail,
                  style: const TextStyle(
                    color: AppTheme.slate400,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            status,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
}

class _DriverInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String helper;

  const _DriverInfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.slate200, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.slate400, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppTheme.slate400,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.midnight,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    helper,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.slate400,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _DriverDocState {
  final String label;
  final bool done;

  const _DriverDocState(this.label, this.done);
}

class _DriverDocumentChecklist extends StatelessWidget {
  final List<_DriverDocState> documents;

  const _DriverDocumentChecklist({required this.documents});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.slate200, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Documentos operativos',
              style: TextStyle(
                color: AppTheme.midnight,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < documents.length; i++) ...[
              _DriverDocumentRow(document: documents[i]),
              if (i != documents.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
      );
}

class _DriverDocumentRow extends StatelessWidget {
  final _DriverDocState document;

  const _DriverDocumentRow({required this.document});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(
            document.done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: document.done ? AppTheme.success : AppTheme.slate400,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              document.label,
              style: const TextStyle(
                color: AppTheme.slate600,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            document.done ? 'Cargado' : 'Pendiente',
            style: TextStyle(
              color: document.done ? AppTheme.success : AppTheme.warning,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
}

class _DriverQuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DriverQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 42),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.slate400,
              letterSpacing: 0.6,
            )),
      );
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.slate200, width: 0.5),
        ),
        child: Column(children: children),
      );
}

class _Div extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 52),
        child: Container(height: 0.5, color: AppTheme.slate200),
      );
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final VoidCallback? onTap;
  final Color? color;
  final Widget? trailing;
  final bool isAction;

  const _Item({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    this.color,
    this.trailing,
    this.isAction = false,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isAction
                    ? AppTheme.primary.withValues(alpha: 0.08)
                    : (color ?? AppTheme.slate600).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  size: 18,
                  color: isAction
                      ? AppTheme.primary
                      : (color ?? AppTheme.slate600)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: color ?? AppTheme.midnight,
                      )),
                  if (value.isNotEmpty)
                    Text(value,
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.slate400),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            trailing ??
                Icon(
                  onTap != null
                      ? Icons.chevron_right_rounded
                      : Icons.lock_outline_rounded,
                  size: 16,
                  color: onTap != null ? AppTheme.slate400 : AppTheme.slate200,
                ),
          ]),
        ),
      );
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: AppTheme.success,
            )),
      );
}

// ── Sheet base ──────────────────────────────────────────────

class _Sheet extends StatelessWidget {
  final String title;
  final Widget child;
  const _Sheet({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            20,
            16,
            20,
            MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).padding.bottom +
                20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.slate200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.midnight,
                )),
            const SizedBox(height: 16),
            child,
          ],
        ),
      );
}

class _SheetField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final VoidCallback? onToggleObscure;

  const _SheetField({
    required this.label,
    required this.controller,
    required this.icon,
    this.keyboardType,
    this.obscure = false,
    this.onToggleObscure,
  });

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6F8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.slate200, width: 0.5),
        ),
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          style: const TextStyle(fontSize: 14, color: AppTheme.midnight),
          decoration: InputDecoration(
            hintText: label,
            hintStyle: const TextStyle(fontSize: 14, color: AppTheme.slate400),
            prefixIcon: Icon(icon, size: 18, color: AppTheme.slate400),
            suffixIcon: onToggleObscure != null
                ? IconButton(
                    icon: Icon(
                      obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 17,
                      color: AppTheme.slate400,
                    ),
                    onPressed: onToggleObscure,
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      );
}

// ── Sheets específicos ──────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  final String name, phone;
  const _EditProfileSheet({required this.name, required this.phone});
  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.name);
    _phoneCtrl = TextEditingController(text: widget.phone);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Sheet(
        title: 'Editar perfil',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetField(
                label: 'Nombre completo',
                controller: _nameCtrl,
                icon: Icons.person_outline_rounded),
            const SizedBox(height: 12),
            _SheetField(
                label: 'Teléfono',
                controller: _phoneCtrl,
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Perfil actualizado'),
                    backgroundColor: AppTheme.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Guardar cambios',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();
  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _c1 = TextEditingController();
  final _c2 = TextEditingController();
  final _c3 = TextEditingController();
  bool _o1 = true, _o2 = true, _o3 = true;

  @override
  void dispose() {
    _c1.dispose();
    _c2.dispose();
    _c3.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Sheet(
        title: 'Cambiar contraseña',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetField(
                label: 'Contraseña actual',
                controller: _c1,
                icon: Icons.lock_outline_rounded,
                obscure: _o1,
                onToggleObscure: () => setState(() => _o1 = !_o1)),
            const SizedBox(height: 12),
            _SheetField(
                label: 'Nueva contraseña',
                controller: _c2,
                icon: Icons.lock_outline_rounded,
                obscure: _o2,
                onToggleObscure: () => setState(() => _o2 = !_o2)),
            const SizedBox(height: 12),
            _SheetField(
                label: 'Confirmar contraseña',
                controller: _c3,
                icon: Icons.lock_outline_rounded,
                obscure: _o3,
                onToggleObscure: () => setState(() => _o3 = !_o3)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (_c2.text != _c3.text) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('Las contraseñas no coinciden'),
                    backgroundColor: AppTheme.error,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ));
                  return;
                }
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Contraseña actualizada'),
                  backgroundColor: AppTheme.success,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Actualizar contraseña',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

class _AddressesSheet extends StatefulWidget {
  const _AddressesSheet();
  @override
  State<_AddressesSheet> createState() => _AddressesSheetState();
}

class _AddressesSheetState extends State<_AddressesSheet> {
  final List<Map<String, dynamic>> _addresses = [
    {'icon': Icons.home_outlined, 'label': 'Casa', 'address': '', 'set': false},
    {
      'icon': Icons.work_outline_rounded,
      'label': 'Trabajo',
      'address': '',
      'set': false
    },
    {
      'icon': Icons.warehouse_outlined,
      'label': 'Bodega',
      'address': '',
      'set': false
    },
  ];

  void _editAddress(int i) {
    final ctrl =
        TextEditingController(text: _addresses[i]['address'] as String);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_addresses[i]['label'] as String,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Ej: Av. Providencia 1234',
            filled: true,
            fillColor: const Color(0xFFF4F6F8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar',
                style: TextStyle(color: AppTheme.slate400)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _addresses[i]['address'] = ctrl.text;
                _addresses[i]['set'] = ctrl.text.isNotEmpty;
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _Sheet(
        title: 'Mis direcciones',
        child: Column(
          children: List.generate(_addresses.length, (i) {
            final a = _addresses[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => _editAddress(i),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: (a['set'] as bool)
                        ? AppTheme.primary.withValues(alpha: 0.04)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (a['set'] as bool)
                          ? AppTheme.primary.withValues(alpha: 0.2)
                          : AppTheme.slate200,
                      width: 0.8,
                    ),
                  ),
                  child: Row(children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(a['icon'] as IconData,
                          size: 18, color: AppTheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a['label'] as String,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.midnight,
                              )),
                          Text(
                            (a['set'] as bool)
                                ? a['address'] as String
                                : 'Toca para agregar',
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.slate400),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      (a['set'] as bool)
                          ? Icons.edit_outlined
                          : Icons.add_rounded,
                      size: 16,
                      color: AppTheme.slate400,
                    ),
                  ]),
                ),
              ),
            );
          }),
        ),
      );
}

class _PaymentsSheet extends StatelessWidget {
  const _PaymentsSheet();
  @override
  Widget build(BuildContext context) => _Sheet(
        title: 'Métodos de pago',
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.slate200, width: 0.5),
            ),
            child: Row(children: [
              Container(
                width: 42,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.slate100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.slate200, width: 0.5),
                ),
                child: const Icon(Icons.credit_card_outlined,
                    size: 16, color: AppTheme.slate400),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sin tarjetas guardadas',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.midnight)),
                    Text('Agrega una tarjeta para pagar',
                        style:
                            TextStyle(fontSize: 11, color: AppTheme.slate400)),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Agregar tarjeta'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              minimumSize: const Size(double.infinity, 48),
              side: const BorderSide(color: AppTheme.primary, width: 0.8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded,
                  size: 14, color: AppTheme.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Integración con Flow disponible próximamente',
                  style: TextStyle(fontSize: 11, color: AppTheme.primary),
                ),
              ),
            ]),
          ),
        ]),
      );
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  @override
  Widget build(BuildContext context) => _Sheet(
        title: 'Ayuda y soporte',
        child: Column(children: [
          // FAQ
          _HelpItem(
            icon: Icons.help_outline_rounded,
            label: '¿Cómo solicitar un flete?',
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: const Text('Cómo solicitar un flete',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                content: const Text(
                  '1. Toca "Solicitar flete" en la pantalla principal.\n'
                  '2. Marca el origen y destino en el mapa.\n'
                  '3. Describe la carga y su peso.\n'
                  '4. Elige el modo (Programado o Urgente).\n'
                  '5. Confirma y espera un conductor.',
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Entendido'),
                  ),
                ],
              ),
            ),
          ),
          _HelpItem(
            icon: Icons.payments_outlined,
            label: '¿Cómo funciona el cobro?',
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: const Text('Cómo funciona el cobro',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                content: const Text(
                  'El precio se calcula según distancia, '
                  'peso de la carga y modo elegido.\n\n'
                  '• Programado: mínimo \$20.000\n'
                  '• Urgente día: mínimo \$30.000\n'
                  '• Urgente noche: mínimo \$40.000\n\n'
                  'La peoneta adicional tiene un costo de \$10.000.',
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Entendido'),
                  ),
                ],
              ),
            ),
          ),
          _HelpItem(
            icon: Icons.cancel_outlined,
            label: '¿Puedo cancelar un flete?',
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                title: const Text('Cancelación de fletes',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                content: const Text(
                  'Puedes cancelar un flete mientras esté '
                  'en estado "Pendiente" o "Aceptado".\n\n'
                  'Una vez que el conductor está en camino, '
                  'la cancelación puede tener costo.',
                  style: TextStyle(fontSize: 13, height: 1.6),
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Entendido'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(height: 0.5, color: AppTheme.slate200),
          const SizedBox(height: 8),

          // Contacto
          _HelpItem(
            icon: Icons.mail_outline_rounded,
            label: 'Enviar correo al soporte',
            sub: 'soporte@fleteapp.cl',
            onTap: () async {
              final uri = Uri(
                scheme: 'mailto',
                path: 'soporte@fleteapp.cl',
                query: 'subject=${Uri.encodeComponent("Ayuda con mi cuenta")}'
                    '&body=${Uri.encodeComponent("Hola equipo FleteApp,\n\n")}',
              );
              if (await canLaunchUrl(uri)) await launchUrl(uri);
            },
          ),
          _HelpItem(
            icon: Icons.chat_outlined,
            label: 'Chatear por WhatsApp',
            sub: 'Respuesta en minutos',
            color: const Color(0xFF25D366),
            onTap: () async {
              final uri = Uri.parse(
                'https://wa.me/56912345678?text='
                '${Uri.encodeComponent("Hola, necesito ayuda con FleteApp.")}',
              );
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ]),
      );
}

class _HelpItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final VoidCallback onTap;
  final Color? color;

  const _HelpItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.sub = '',
    this.color,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: (color ?? AppTheme.primary).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color ?? AppTheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: color ?? AppTheme.midnight,
                      )),
                  if (sub.isNotEmpty)
                    Text(sub,
                        style: const TextStyle(
                            fontSize: 11, color: AppTheme.slate400)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                size: 14, color: color ?? AppTheme.slate400),
          ]),
        ),
      );
}

class _ConfirmDialog extends StatelessWidget {
  final String title, message, confirmLabel;
  final Color confirmColor;
  final VoidCallback onConfirm;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.midnight,
            )),
        content: Text(message,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.slate400,
              height: 1.5,
            )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar',
                style: TextStyle(color: AppTheme.slate400)),
          ),
          ElevatedButton(
            onPressed: onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text(confirmLabel),
          ),
        ],
      );
}
