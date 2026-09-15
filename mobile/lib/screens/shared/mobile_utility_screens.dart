import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/muvv_mobile_ui.dart';
import '../../widgets/muvv_page_scaffold.dart';

class MuvvAccountHubScreen extends ConsumerWidget {
  final bool driver;

  const MuvvAccountHubScreen({super.key, this.driver = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final name = user?.fullName ?? (driver ? 'Conductor Muvv' : 'Cliente Muvv');
    final initial = name.trim().isEmpty ? 'M' : name.trim()[0].toUpperCase();
    final activityPath = driver ? '/app/driver/trips' : '/app/client/freights';

    return MuvvPageScaffold(
      title: 'Perfil',
      fallbackPath: driver ? '/app/driver' : '/app/client',
      actions: [
        IconButton(
          tooltip: 'Editar perfil',
          onPressed: () => context.push('/app/profile'),
          icon: const Icon(Icons.edit_outlined),
        ),
        const SizedBox(width: 6),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          MuvvSurfaceCard(
            emphasized: true,
            onTap: () => context.push('/app/profile'),
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
          const SizedBox(height: 24),
          const MuvvSectionHeader(title: 'Cuenta'),
          const SizedBox(height: 12),
          MuvvSettingsGroup(
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
                title:
                    driver ? 'Estado de verificacion' : 'Direcciones guardadas',
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
          const SizedBox(height: 26),
          MuvvSectionHeader(
              title: driver ? 'Tu operación' : 'Pagos y beneficios'),
          const SizedBox(height: 12),
          MuvvSettingsGroup(
            children: [
              _MenuRow(
                icon: driver
                    ? Icons.account_balance_wallet_outlined
                    : Icons.credit_card_outlined,
                title: driver ? 'Ganancias' : 'Métodos de pago',
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
          const SizedBox(height: 26),
          const MuvvSectionHeader(title: 'Ayuda y ajustes'),
          const SizedBox(height: 12),
          MuvvSettingsGroup(
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
                title: 'Configuración',
                subtitle: 'Privacidad, seguridad y preferencias',
                onTap: () => context.push('/app/settings/preferences'),
              ),
            ],
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

class MuvvUtilityScreen extends ConsumerStatefulWidget {
  final MuvvUtilityPage page;

  const MuvvUtilityScreen({super.key, required this.page});

  @override
  ConsumerState<MuvvUtilityScreen> createState() => _MuvvUtilityScreenState();
}

class _MuvvUtilityScreenState extends ConsumerState<MuvvUtilityScreen> {
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
        MuvvUtilityPage.payments => const _UtilityCopy('Pagos',
            'Métodos de pago y comprobantes', Icons.credit_card_outlined),
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
        MuvvUtilityPage.preferences => const _UtilityCopy('Configuración',
            'Privacidad, seguridad y preferencias.', Icons.tune_rounded),
        MuvvUtilityPage.chat => const _UtilityCopy(
            'Chat con conductor',
            'Coordina de forma segura dentro de Muvv.',
            Icons.chat_bubble_outline_rounded),
      };

  @override
  Widget build(BuildContext context) => MuvvPageScaffold(
        title: _copy.title,
        bottomNavigationBar: widget.page == MuvvUtilityPage.payments
            ? const MuvvBottomNavigation(selected: MuvvNavigationSection.wallet)
            : null,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            if (widget.page != MuvvUtilityPage.payments) ...[
              Text(_copy.subtitle,
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 20),
            ],
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MuvvSectionHeader(title: 'Métodos de pago'),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEDF3FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.credit_card_outlined,
                    color: AppTheme.primary, size: 24),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tarjetas',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text('Aún no tienes tarjetas guardadas.',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 12),
                    const MuvvStatusPill(
                        label: 'Próximamente', color: AppTheme.slate600),
                  ],
                )),
              ],
            ),
          ),
          const SizedBox(height: 16),
          MuvvGradientButton(
            label: 'Agregar tarjeta',
            icon: Icons.add_card_rounded,
            onPressed: () => _showCardAvailability(),
          ),
          const SizedBox(height: 12),
          Text(
              'Webpay aún no está habilitado. No ingreses datos de tu tarjeta.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 28),
          const MuvvSectionHeader(title: 'Actividad'),
          const SizedBox(height: 12),
          MuvvSettingsGroup(children: [
            _MenuRow(
              icon: Icons.receipt_long_outlined,
              title: 'Pagos de mis fletes',
              subtitle: 'Revisa el estado de pago de cada servicio',
              onTap: () => context.go('/app/client/freights'),
            ),
            const _MenuDivider(),
            _MenuRow(
              icon: Icons.help_outline_rounded,
              title: 'Ayuda con un pago',
              subtitle: 'Cobros y comprobantes',
              onTap: () => context.push('/app/settings/help'),
            ),
          ]),
        ],
      );

  Future<void> _showCardAvailability() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MuvvSectionHeader(title: 'Tarjetas con Webpay'),
                const SizedBox(height: 12),
                const Text(
                    'La vinculación de tarjetas todavía no está disponible. '
                    'Por ahora, revisa las opciones de pago en el detalle de tu flete.'),
                const SizedBox(height: 20),
                MuvvGradientButton(
                  label: 'Entendido',
                  icon: Icons.check_rounded,
                  onPressed: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
          ),
        ),
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

  Widget _notifications() => MuvvSettingsGroup(
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

  Widget _help() => MuvvSettingsGroup(
        children: [
          _MenuRow(
              icon: Icons.route_outlined,
              title: 'Mi solicitud',
              subtitle: 'Ruta, precio, conductor y estado',
              onTap: () => context.push(
                  ref.read(authProvider).user?.role == 'driver'
                      ? '/app/driver/trips'
                      : '/app/client/freights')),
          const _MenuDivider(),
          _MenuRow(
              icon: Icons.receipt_long_outlined,
              title: 'Pagos y comprobantes',
              subtitle: 'Cobros, pagos y liquidaciones',
              onTap: () => context.push(
                  ref.read(authProvider).user?.role == 'driver'
                      ? '/app/driver/payouts'
                      : '/app/client/payments')),
          const _MenuDivider(),
          _MenuRow(
              icon: Icons.shield_outlined,
              title: 'Seguridad y privacidad',
              subtitle: 'Datos, documentos y reportes',
              onTap: () => context.push('/legal/privacy')),
        ],
      );

  Widget _preferences() => MuvvSettingsGroup(
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
            Switch.adaptive(
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
