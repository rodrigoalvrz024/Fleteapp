import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/muvv_mobile_ui.dart';

class MuvvAccountHubScreen extends ConsumerWidget {
  final bool driver;

  const MuvvAccountHubScreen({super.key, this.driver = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final name = user?.fullName ?? (driver ? 'Conductor Muvv' : 'Cliente Muvv');
    final initial = name.trim().isEmpty ? 'M' : name.trim()[0].toUpperCase();
    final activityPath = driver ? '/app/driver/trips' : '/app/client/freights';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Perfil'),
        actions: [
          IconButton(
            tooltip: 'Editar perfil',
            onPressed: () => context.push('/app/profile'),
            icon: const Icon(Icons.edit_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 116),
        children: [
          MuvvSurfaceCard(
            emphasized: true,
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.midnight,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        user?.email ?? 'Cuenta Muvv',
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
                const Icon(Icons.chevron_right_rounded,
                    color: AppTheme.slate400),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const MuvvSectionHeader(eyebrow: 'Cuenta', title: 'Lo esencial'),
          const SizedBox(height: 12),
          MuvvSurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _MenuRow(
                  icon: Icons.person_outline_rounded,
                  title: 'Editar perfil',
                  subtitle: 'Datos personales y contacto',
                  onTap: () => context.push('/app/profile'),
                ),
                const _MenuDivider(),
                _MenuRow(
                  icon: driver
                      ? Icons.verified_user_outlined
                      : Icons.location_on_outlined,
                  title: driver
                      ? 'Estado de verificacion'
                      : 'Direcciones guardadas',
                  subtitle: driver
                      ? 'Documentos y datos de tu vehiculo'
                      : 'Casa, trabajo y lugares frecuentes',
                  onTap: () => context.push(
                    driver ? '/app/driver/onboarding' : '/app/client/addresses',
                  ),
                ),
                const _MenuDivider(),
                _MenuRow(
                  icon: driver
                      ? Icons.route_outlined
                      : Icons.local_shipping_outlined,
                  title: driver ? 'Historial de viajes' : 'Mis fletes',
                  subtitle: driver
                      ? 'Servicios aceptados y completados'
                      : 'Solicitudes, ruta y comprobantes',
                  onTap: () => context.go(activityPath),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          MuvvSectionHeader(
            eyebrow: driver ? 'Operación' : 'Pagos y beneficios',
            title: driver ? 'Tu operación' : 'Preferencias de pago',
          ),
          const SizedBox(height: 12),
          MuvvSurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _MenuRow(
                  icon: driver
                      ? Icons.account_balance_wallet_outlined
                      : Icons.credit_card_outlined,
                  title: driver ? 'Ganancias' : 'Metodos de pago',
                  subtitle: driver
                      ? 'Liquidaciones programadas y pagadas'
                      : 'Tarjetas y comprobantes',
                  onTap: () => context.push(
                      driver ? '/app/driver/payouts' : '/app/client/payments'),
                ),
                if (!driver) ...[
                  const _MenuDivider(),
                  _MenuRow(
                    icon: Icons.confirmation_number_outlined,
                    title: 'Promociones',
                    subtitle: 'Cupones disponibles para tus fletes',
                    onTap: () => context.push('/app/client/promotions'),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 26),
          const MuvvSectionHeader(eyebrow: 'Muvv', title: 'Ayuda y ajustes'),
          const SizedBox(height: 12),
          MuvvSurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _MenuRow(
                  icon: Icons.notifications_none_rounded,
                  title: 'Notificaciones',
                  subtitle: 'Avisos del estado de tus servicios',
                  onTap: () => context.push('/app/settings/notifications'),
                ),
                const _MenuDivider(),
                _MenuRow(
                  icon: Icons.help_outline_rounded,
                  title: 'Centro de ayuda',
                  subtitle: 'Resuelve dudas o solicita asistencia',
                  onTap: () => context.push('/app/settings/help'),
                ),
                const _MenuDivider(),
                _MenuRow(
                  icon: Icons.tune_rounded,
                  title: 'Configuracion',
                  subtitle: 'Privacidad, seguridad y preferencias',
                  onTap: () => context.push('/app/settings/preferences'),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: MuvvBottomNavigation(
        selected: MuvvNavigationSection.profile,
        driver: driver,
      ),
    );
  }
}

enum MuvvUtilityPage {
  payments,
  addresses,
  notifications,
  promotions,
  help,
  preferences,
  chat
}

class MuvvUtilityScreen extends StatefulWidget {
  final MuvvUtilityPage page;

  const MuvvUtilityScreen({super.key, required this.page});

  @override
  State<MuvvUtilityScreen> createState() => _MuvvUtilityScreenState();
}

class _MuvvUtilityScreenState extends State<MuvvUtilityScreen> {
  bool _tripUpdates = true;
  bool _marketing = false;
  bool _biometrics = false;
  bool _shareLocation = true;
  final _couponController = TextEditingController();
  final _messageController = TextEditingController();
  final List<String> _messages = [];

  @override
  void dispose() {
    _couponController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  _UtilityCopy get _copy => switch (widget.page) {
        MuvvUtilityPage.payments => const _UtilityCopy('Metodos de pago',
            'Configura como pagaras tus fletes.', Icons.credit_card_outlined),
        MuvvUtilityPage.addresses => const _UtilityCopy(
            'Direcciones guardadas',
            'Ahorra tiempo en tus proximas solicitudes.',
            Icons.location_on_outlined),
        MuvvUtilityPage.notifications => const _UtilityCopy(
            'Notificaciones',
            'Elige que avisos quieres recibir.',
            Icons.notifications_none_rounded),
        MuvvUtilityPage.promotions => const _UtilityCopy(
            'Promociones',
            'Agrega un cupon antes de confirmar tu flete.',
            Icons.confirmation_number_outlined),
        MuvvUtilityPage.help => const _UtilityCopy(
            'Centro de ayuda',
            'Estamos aqui para que tu flete avance seguro.',
            Icons.support_agent_outlined),
        MuvvUtilityPage.preferences => const _UtilityCopy('Configuracion',
            'Privacidad, seguridad y preferencias.', Icons.tune_rounded),
        MuvvUtilityPage.chat => const _UtilityCopy(
            'Chat con conductor',
            'Coordina de forma segura dentro de Muvv.',
            Icons.chat_bubble_outline_rounded),
      };

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(title: Text(_copy.title)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
          children: [
            MuvvSectionHeader(eyebrow: 'Muvv', title: _copy.title),
            const SizedBox(height: 6),
            Text(
              _copy.subtitle,
              style: const TextStyle(
                  color: AppTheme.slate600, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 20),
            switch (widget.page) {
              MuvvUtilityPage.payments => _payments(),
              MuvvUtilityPage.addresses => _addresses(),
              MuvvUtilityPage.notifications => _notifications(),
              MuvvUtilityPage.promotions => _promotions(),
              MuvvUtilityPage.help => _help(),
              MuvvUtilityPage.preferences => _preferences(),
              MuvvUtilityPage.chat => _chat(),
            },
          ],
        ),
      );

  Widget _payments() => Column(
        children: [
          MuvvSurfaceCard(
            child: Column(
              children: [
                Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.lock_outline_rounded,
                      color: AppTheme.primary),
                ),
                const SizedBox(height: 14),
                const Text('Tus pagos se protegen dentro de Muvv',
                    style: TextStyle(
                        color: AppTheme.midnight,
                        fontWeight: FontWeight.w800,
                        fontSize: 16)),
                const SizedBox(height: 6),
                const Text('Agrega una tarjeta al activar la pasarela de pago.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.slate600, height: 1.35)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: MuvvGradientButton(
              label: 'Agregar tarjeta',
              icon: Icons.add_card_rounded,
              onPressed: () => _showComingSoon(
                  'La conexión segura de tarjetas se habilitará con Webpay.'),
            ),
          ),
        ],
      );

  Widget _addresses() => Column(
        children: [
          const _AddressRow(
              icon: Icons.home_outlined,
              title: 'Casa',
              address: 'Guarda tu direccion frecuente'),
          const SizedBox(height: 10),
          const _AddressRow(
              icon: Icons.work_outline_rounded,
              title: 'Trabajo',
              address: 'Guarda una segunda direccion'),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: MuvvGradientButton(
              label: 'Agregar direccion',
              icon: Icons.add_location_alt_outlined,
              onPressed: () => _showComingSoon(
                  'La direccion se guardará cuando conectemos este modulo a tu cuenta.'),
            ),
          ),
        ],
      );

  Widget _notifications() => MuvvSurfaceCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _ToggleRow(
              icon: Icons.local_shipping_outlined,
              title: 'Actualizaciones de fletes',
              subtitle: 'Cambios de estado, llegada y entrega',
              value: _tripUpdates,
              onChanged: (value) => setState(() => _tripUpdates = value),
            ),
            const _MenuDivider(),
            _ToggleRow(
              icon: Icons.local_offer_outlined,
              title: 'Promociones Muvv',
              subtitle: 'Beneficios y novedades ocasionales',
              value: _marketing,
              onChanged: (value) => setState(() => _marketing = value),
            ),
          ],
        ),
      );

  Widget _promotions() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _couponController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Codigo promocional',
              prefixIcon: Icon(Icons.confirmation_number_outlined),
            ),
          ),
          const SizedBox(height: 12),
          MuvvGradientButton(
            label: 'Aplicar codigo',
            icon: Icons.check_circle_outline_rounded,
            compact: true,
            onPressed: () => _showComingSoon(
                'El cupon se validará al confirmar tu proximo flete.'),
          ),
          const SizedBox(height: 20),
          const MuvvSurfaceCard(
            child: Row(
              children: [
                Icon(Icons.auto_awesome_outlined, color: AppTheme.primary),
                SizedBox(width: 12),
                Expanded(
                    child: Text('Tus promociones disponibles apareceran aqui.',
                        style:
                            TextStyle(color: AppTheme.slate600, height: 1.35))),
              ],
            ),
          ),
        ],
      );

  Widget _help() => MuvvSurfaceCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _MenuRow(
                icon: Icons.route_outlined,
                title: 'Mi solicitud',
                subtitle: 'Ruta, precio, conductor y estado',
                onTap: () =>
                    _showComingSoon('Abriremos ayuda para tu solicitud.')),
            const _MenuDivider(),
            _MenuRow(
                icon: Icons.receipt_long_outlined,
                title: 'Pagos y comprobantes',
                subtitle: 'Cobros, pagos y liquidaciones',
                onTap: () => _showComingSoon('Abriremos ayuda de pagos.')),
            const _MenuDivider(),
            _MenuRow(
                icon: Icons.shield_outlined,
                title: 'Seguridad y privacidad',
                subtitle: 'Datos, documentos y reportes',
                onTap: () => _showComingSoon('Abriremos ayuda de seguridad.')),
          ],
        ),
      );

  Widget _preferences() => MuvvSurfaceCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            _ToggleRow(
                icon: Icons.fingerprint_outlined,
                title: 'Acceso biometrico',
                subtitle: 'Disponible al activar biometria nativa',
                value: _biometrics,
                onChanged: (value) => setState(() => _biometrics = value)),
            const _MenuDivider(),
            _ToggleRow(
                icon: Icons.my_location_outlined,
                title: 'Ubicacion durante un flete',
                subtitle: 'Necesaria para seguimiento en vivo',
                value: _shareLocation,
                onChanged: (value) => setState(() => _shareLocation = value)),
            const _MenuDivider(),
            _MenuRow(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacidad y datos',
                subtitle: 'Solicitudes y documentos legales',
                onTap: () => context.push('/legal/privacy')),
          ],
        ),
      );

  Widget _chat() => Column(
        children: [
          const MuvvSurfaceCard(
            child: Row(
              children: [
                CircleAvatar(
                    backgroundColor: Color(0xFFEAF0FF),
                    child: Icon(Icons.local_shipping_outlined,
                        color: AppTheme.primary)),
                SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Tu conductor',
                          style: TextStyle(
                              color: AppTheme.midnight,
                              fontWeight: FontWeight.w800)),
                      SizedBox(height: 2),
                      Text('Disponible al asignarse el flete',
                          style:
                              TextStyle(color: AppTheme.slate400, fontSize: 12))
                    ])),
                MuvvStatusPill(
                    label: 'Seguro',
                    color: AppTheme.success,
                    icon: Icons.lock_outline_rounded),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_messages.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Text(
                  'El chat se activará cuando un conductor acepte tu flete.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.slate400, height: 1.4)),
            )
          else
            ..._messages.map(
              (message) => Align(
                alignment: Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8, left: 56),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(14)),
                  child: Text(message,
                      style: const TextStyle(color: Colors.white)),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  enabled: _messages.isNotEmpty,
                  decoration: const InputDecoration(
                      hintText: 'Escribe un mensaje',
                      prefixIcon: Icon(Icons.chat_bubble_outline_rounded)),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _messages.isEmpty ? null : _sendMessage,
                style: IconButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(50, 50)),
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      );

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(text);
      _messageController.clear();
    });
  }

  void _showComingSoon(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
}

class _UtilityCopy {
  final String title;
  final String subtitle;
  final IconData icon;

  const _UtilityCopy(this.title, this.subtitle, this.icon);
}

class _AddressRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String address;

  const _AddressRow(
      {required this.icon, required this.title, required this.address});

  @override
  Widget build(BuildContext context) => MuvvSurfaceCard(
        child: Row(
          children: [
            Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: AppTheme.primary)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppTheme.midnight,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(address,
                      style: const TextStyle(
                          color: AppTheme.slate400, fontSize: 12))
                ])),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.slate400),
          ],
        ),
      );
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuRow(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, size: 19, color: AppTheme.primary)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        style: const TextStyle(
                            color: AppTheme.midnight,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppTheme.slate400, fontSize: 11))
                  ])),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.slate400, size: 20),
            ],
          ),
        ),
      );
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.value,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: AppTheme.primary, size: 19)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppTheme.midnight,
                          fontSize: 14,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppTheme.slate400, fontSize: 11))
                ])),
            Switch(
                value: value,
                activeThumbColor: AppTheme.primary,
                onChanged: onChanged),
          ],
        ),
      );
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 66, endIndent: 16);
}
