import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  File? _avatarFile;

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
      setState(() => _avatarFile = File(picked.path));
    }
  }

  void _showEditProfile(BuildContext ctx, String name, String phone) =>
      showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _EditProfileSheet(name: name, phone: phone),
      );

  void _showChangePassword(BuildContext ctx) =>
      showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _ChangePasswordSheet(),
      );

  void _showAddresses(BuildContext ctx) =>
      showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _AddressesSheet(),
      );

  void _showPayments(BuildContext ctx) =>
      showModalBottomSheet(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _PaymentsSheet(),
      );

  void _showHelp(BuildContext ctx) =>
      showModalBottomSheet(
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
    const phone   = '56912345678';
    const message = 'Hola, necesito ayuda con mi cuenta de FleteApp.';
    final uri = Uri.parse(
        'https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _confirmLogout(BuildContext ctx) => showDialog(
    context: ctx,
    builder: (_) => _ConfirmDialog(
      title:        'Cerrar sesión',
      message:      '¿Estás seguro de que quieres salir?',
      confirmLabel: 'Salir',
      confirmColor: AppTheme.error,
      onConfirm: () async {
        Navigator.pop(ctx);
        await ref.read(authProvider.notifier).logout();
        if (mounted) context.go('/login');
      },
    ),
  );

  void _confirmDeleteAccount(BuildContext ctx) => showDialog(
    context: ctx,
    builder: (_) => _ConfirmDialog(
      title:   'Eliminar cuenta',
      message: 'Esta acción es irreversible. Se eliminarán '
          'todos tus datos, historial de fletes y métodos de pago.',
      confirmLabel: 'Eliminar cuenta',
      confirmColor: AppTheme.error,
      onConfirm: () {
        Navigator.pop(ctx);
        ScaffoldMessenger.of(ctx).showSnackBar(_snack(
          'Solicitud enviada al equipo de soporte',
          AppTheme.slate600,
        ));
      },
    ),
  );

  SnackBar _snack(String msg, Color color) => SnackBar(
    content: Text(msg),
    backgroundColor: color,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12)),
  );

  @override
  Widget build(BuildContext context) {
    final user     = ref.watch(authProvider).user;
    final name     = user?.fullName ?? 'Usuario';
    final email    = user?.email ?? '';
    final phone    = user?.phone ?? 'Sin teléfono';
    final role     = user?.role ?? 'client';
    final initials = name.trim().split(' ')
        .take(2).map((w) => w[0].toUpperCase()).join();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Mi perfil'),
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.midnight,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(height: 0.5, color: AppTheme.slate200),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
        children: [

          // ── Avatar ───────────────────────────────────
          Center(
            child: Column(children: [
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      color: AppTheme.primary
                          .withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppTheme.primary
                            .withValues(alpha: 0.2),
                        width: 2,
                      ),
                    ),
                    child: _avatarFile != null
                        ? ClipOval(
                            child: Image.file(
                                _avatarFile!,
                                fit: BoxFit.cover))
                        : Center(
                            child: Text(initials,
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.primary,
                                ))),
                  ),
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      width: 26, height: 26,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                          Icons.camera_alt_rounded,
                          size: 12,
                          color: Colors.white),
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
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.slate400)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.success
                      .withValues(alpha: 0.10),
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
          const _SectionTitle('Información personal'),
          const SizedBox(height: 8),
          _Card(children: [
            _Item(
              icon:  Icons.person_outline_rounded,
              label: 'Nombre',
              value: name,
              onTap: () => _showEditProfile(context, name, phone),
            ),
            _Div(),
            _Item(
              icon:  Icons.phone_outlined,
              label: 'Teléfono',
              value: phone,
              onTap: () => _showEditProfile(context, name, phone),
            ),
            _Div(),
            _Item(
              icon:     Icons.mail_outline_rounded,
              label:    'Correo',
              value:    email,
              onTap:    null,
              trailing: const _Badge('Verificado'),
            ),
          ]),
          const SizedBox(height: 16),

          // ── 2. Direcciones ───────────────────────────
          const _SectionTitle('Mis direcciones'),
          const SizedBox(height: 8),
          _Card(children: [
            _Item(
              icon:  Icons.home_outlined,
              label: 'Casa',
              value: 'Sin dirección guardada',
              onTap: () => _showAddresses(context),
            ),
            _Div(),
            _Item(
              icon:  Icons.work_outline_rounded,
              label: 'Trabajo',
              value: 'Sin dirección guardada',
              onTap: () => _showAddresses(context),
            ),
            _Div(),
            _Item(
              icon:     Icons.add_rounded,
              label:    'Agregar dirección',
              value:    '',
              onTap:    () => _showAddresses(context),
              isAction: true,
            ),
          ]),
          const SizedBox(height: 16),

          // ── 3. Métodos de pago ───────────────────────
          const _SectionTitle('Métodos de pago'),
          const SizedBox(height: 8),
          _Card(children: [
            _Item(
              icon:  Icons.credit_card_outlined,
              label: 'Tarjetas',
              value: 'Ninguna guardada',
              onTap: () => _showPayments(context),
            ),
            _Div(),
            _Item(
              icon:     Icons.add_rounded,
              label:    'Agregar tarjeta',
              value:    '',
              onTap:    () => _showPayments(context),
              isAction: true,
            ),
          ]),
          const SizedBox(height: 16),

          // ── 4. Seguridad ─────────────────────────────
          const _SectionTitle('Seguridad'),
          const SizedBox(height: 8),
          _Card(children: [
            _Item(
              icon:  Icons.lock_outline_rounded,
              label: 'Cambiar contraseña',
              value: '',
              onTap: () => _showChangePassword(context),
            ),
            _Div(),
            _Item(
              icon:  Icons.logout_rounded,
              label: 'Cerrar sesión',
              value: '',
              onTap: () => _confirmLogout(context),
              color: AppTheme.error,
            ),
          ]),
          const SizedBox(height: 16),

          // ── 5. Ayuda y soporte ───────────────────────
          const _SectionTitle('Ayuda y soporte'),
          const SizedBox(height: 8),
          _Card(children: [
            _Item(
              icon:  Icons.help_outline_rounded,
              label: 'Centro de ayuda',
              value: 'Preguntas frecuentes',
              onTap: () => _showHelp(context),
            ),
            _Div(),
            _Item(
              icon:  Icons.mail_outline_rounded,
              label: 'Contactar soporte',
              value: 'soporte@fleteapp.cl',
              onTap: () => _launchEmail(
                'soporte@fleteapp.cl',
                'Ayuda con mi cuenta FleteApp',
              ),
            ),
            _Div(),
            _Item(
              icon:  Icons.chat_outlined,
              label: 'WhatsApp',
              value: 'Respuesta en minutos',
              onTap: _launchWhatsApp,
              color: const Color(0xFF25D366),
            ),
            _Div(),
            _Item(
              icon:  Icons.star_outline_rounded,
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
              icon:  Icons.delete_outline_rounded,
              label: 'Eliminar cuenta',
              value: 'Esta acción es irreversible',
              onTap: () => _confirmDeleteAccount(context),
              color: AppTheme.error,
            ),
          ]),

          const SizedBox(height: 32),
          const Center(
            child: Text('FleteApp v1.0.0',
                style: TextStyle(
                    fontSize: 11, color: AppTheme.slate400)),
          ),
        ],
      ),
    );
  }
}

// ── Widgets base ────────────────────────────────────────────

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
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 13),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: isAction
                ? AppTheme.primary.withValues(alpha: 0.08)
                : (color ?? AppTheme.slate600)
                    .withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18,
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
                        fontSize: 12,
                        color: AppTheme.slate400),
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
              color: onTap != null
                  ? AppTheme.slate400
                  : AppTheme.slate200,
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
    padding: const EdgeInsets.symmetric(
        horizontal: 8, vertical: 3),
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
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(24)),
    ),
    padding: EdgeInsets.fromLTRB(
        20, 16, 20,
        MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            20),
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
      controller:   controller,
      keyboardType: keyboardType,
      obscureText:  obscure,
      style: const TextStyle(
          fontSize: 14, color: AppTheme.midnight),
      decoration: InputDecoration(
        hintText: label,
        hintStyle: const TextStyle(
            fontSize: 14, color: AppTheme.slate400),
        prefixIcon: Icon(icon, size: 18, color: AppTheme.slate400),
        suffixIcon: onToggleObscure != null
            ? IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 17, color: AppTheme.slate400,
                ),
                onPressed: onToggleObscure,
              )
            : null,
        border: InputBorder.none,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
      ),
    ),
  );
}

// ── Sheets específicos ──────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  final String name, phone;
  const _EditProfileSheet(
      {required this.name, required this.phone});
  @override
  State<_EditProfileSheet> createState() =>
      _EditProfileSheetState();
}

class _EditProfileSheetState
    extends State<_EditProfileSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(text: widget.name);
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
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();
  @override
  State<_ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState
    extends State<_ChangePasswordSheet> {
  final _c1 = TextEditingController();
  final _c2 = TextEditingController();
  final _c3 = TextEditingController();
  bool _o1 = true, _o2 = true, _o3 = true;

  @override
  void dispose() { _c1.dispose(); _c2.dispose(); _c3.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => _Sheet(
    title: 'Cambiar contraseña',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SheetField(label: 'Contraseña actual', controller: _c1,
            icon: Icons.lock_outline_rounded, obscure: _o1,
            onToggleObscure: () => setState(() => _o1 = !_o1)),
        const SizedBox(height: 12),
        _SheetField(label: 'Nueva contraseña', controller: _c2,
            icon: Icons.lock_outline_rounded, obscure: _o2,
            onToggleObscure: () => setState(() => _o2 = !_o2)),
        const SizedBox(height: 12),
        _SheetField(label: 'Confirmar contraseña', controller: _c3,
            icon: Icons.lock_outline_rounded, obscure: _o3,
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
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600)),
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
    {'icon': Icons.home_outlined,       'label': 'Casa',    'address': '', 'set': false},
    {'icon': Icons.work_outline_rounded, 'label': 'Trabajo', 'address': '', 'set': false},
    {'icon': Icons.warehouse_outlined,   'label': 'Bodega',  'address': '', 'set': false},
  ];

  void _editAddress(int i) {
    final ctrl = TextEditingController(
        text: _addresses[i]['address'] as String);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(_addresses[i]['label'] as String,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600)),
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
                _addresses[i]['set']     = ctrl.text.isNotEmpty;
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
                  width: 38, height: 38,
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
                            fontSize: 11,
                            color: AppTheme.slate400),
                      ),
                    ],
                  ),
                ),
                Icon(
                  (a['set'] as bool)
                      ? Icons.edit_outlined
                      : Icons.add_rounded,
                  size: 16, color: AppTheme.slate400,
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
            width: 42, height: 28,
            decoration: BoxDecoration(
              color: AppTheme.slate100,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: AppTheme.slate200, width: 0.5),
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
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.slate400)),
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
          side: const BorderSide(
              color: AppTheme.primary, width: 0.8),
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
              style: TextStyle(
                  fontSize: 11, color: AppTheme.primary),
            ),
          ),
        ]),
      ),
    ]),
  );
}

class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) => _Sheet(
    title: 'Ayuda y soporte',
    child: Column(children: [

      // FAQ
      _HelpItem(
        icon:  Icons.help_outline_rounded,
        label: '¿Cómo solicitar un flete?',
        onTap: () => showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('Cómo solicitar un flete',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
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
        icon:  Icons.payments_outlined,
        label: '¿Cómo funciona el cobro?',
        onTap: () => showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('Cómo funciona el cobro',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
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
        icon:  Icons.cancel_outlined,
        label: '¿Puedo cancelar un flete?',
        onTap: () => showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('Cancelación de fletes',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
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
        icon:  Icons.mail_outline_rounded,
        label: 'Enviar correo al soporte',
        sub:   'soporte@fleteapp.cl',
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
        icon:  Icons.chat_outlined,
        label: 'Chatear por WhatsApp',
        sub:   'Respuesta en minutos',
        color: const Color(0xFF25D366),
        onTap: () async {
          final uri = Uri.parse(
            'https://wa.me/56912345678?text='
            '${Uri.encodeComponent("Hola, necesito ayuda con FleteApp.")}',
          );
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri,
                mode: LaunchMode.externalApplication);
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
      padding: const EdgeInsets.symmetric(
          vertical: 12, horizontal: 4),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: (color ?? AppTheme.primary)
                .withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18,
              color: color ?? AppTheme.primary),
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
                        fontSize: 11,
                        color: AppTheme.slate400)),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded,
            size: 14,
            color: color ?? AppTheme.slate400),
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
    shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16)),
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