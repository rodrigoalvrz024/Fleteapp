import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import 'widgets/auth_visuals.dart';

const _publicHomeUrl = String.fromEnvironment(
  'PUBLIC_HOME_URL',
  defaultValue: 'https://fleteapp-public-8d8f7.web.app',
);

Future<void> _openPublicHome() async {
  await launchUrl(Uri.parse(_publicHomeUrl), webOnlyWindowName: '_self');
}

class RegisterScreen extends ConsumerStatefulWidget {
  final String? redirectPath;
  final String? initialRole;

  const RegisterScreen({super.key, this.redirectPath, this.initialRole});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  String _role = 'client';
  bool _obscure = true;
  bool _acceptTerms = false;
  bool _acceptPrivacy = false;
  bool _acceptDriverDocuments = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialRole == 'driver') _role = 'driver';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptTerms || !_acceptPrivacy) {
      _showError('Debes aceptar los términos y la política de privacidad.');
      return;
    }
    if (_role == 'driver' && !_acceptDriverDocuments) {
      _showError('Debes autorizar la revisión de documentos de conductor.');
      return;
    }

    HapticFeedback.lightImpact();

    final ok = await ref.read(authProvider.notifier).register(
          _emailCtrl.text.trim(),
          _phoneCtrl.text.trim(),
          _nameCtrl.text.trim(),
          _passCtrl.text,
          _role,
          acceptsTerms: _acceptTerms,
          acceptsPrivacy: _acceptPrivacy,
          acceptsDriverDocuments: _role == 'driver' && _acceptDriverDocuments,
        );
    if (!mounted) return;
    if (ok) {
      context.go(_destinationAfterRegister);
    }
  }

  String get _destinationAfterRegister {
    if (_role == 'driver') return '/app/driver/onboarding';
    return _safeClientRedirect(widget.redirectPath) ?? '/app/client';
  }

  String? _safeClientRedirect(String? value) {
    final path = value?.trim();
    if (path == null || path.isEmpty) return null;
    final isClientRoute = path == '/app/client' ||
        path.startsWith('/app/client/') ||
        path.startsWith('/app/client?');
    if (!isClientRoute) return null;
    if (path.contains('://') || path.startsWith('//')) return null;
    return path;
  }

  String get _loginPath {
    final safeRedirect = _safeClientRedirect(widget.redirectPath);
    if (safeRedirect == null) return '/auth/login';
    return Uri(
      path: '/auth/login',
      queryParameters: {'next': safeRedirect},
    ).toString();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppTheme.midnight,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 920;
            final horizontalPadding = compact ? 20.0 : 36.0;
            final topBottomPadding = compact ? 18.0 : 26.0;

            return AuthBackdrop(
              overlayStrength: 0.64,
              child: SafeArea(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight -
                          MediaQuery.paddingOf(context).top -
                          MediaQuery.paddingOf(context).bottom,
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        topBottomPadding,
                        horizontalPadding,
                        topBottomPadding,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1180),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AuthReveal(
                                delay: 0.04,
                                offsetY: -12,
                                child: _RegisterNav(
                                  compact: compact,
                                  loginPath: _loginPath,
                                ),
                              ),
                              SizedBox(height: compact ? 24 : 58),
                              AuthReveal(
                                delay: 0.14,
                                child: compact
                                    ? _CompactRegisterLayout(
                                        auth: auth,
                                        formKey: _formKey,
                                        nameCtrl: _nameCtrl,
                                        emailCtrl: _emailCtrl,
                                        phoneCtrl: _phoneCtrl,
                                        passCtrl: _passCtrl,
                                        role: _role,
                                        obscure: _obscure,
                                        acceptTerms: _acceptTerms,
                                        acceptPrivacy: _acceptPrivacy,
                                        acceptDriverDocuments:
                                            _acceptDriverDocuments,
                                        loginPath: _loginPath,
                                        onRoleChanged: _setRole,
                                        onToggleObscure: () => setState(
                                          () => _obscure = !_obscure,
                                        ),
                                        onAcceptTerms: (value) => setState(
                                          () => _acceptTerms = value,
                                        ),
                                        onAcceptPrivacy: (value) => setState(
                                          () => _acceptPrivacy = value,
                                        ),
                                        onAcceptDriverDocuments: (value) =>
                                            setState(
                                          () => _acceptDriverDocuments = value,
                                        ),
                                        onRegister: _register,
                                      )
                                    : _DesktopRegisterLayout(
                                        auth: auth,
                                        formKey: _formKey,
                                        nameCtrl: _nameCtrl,
                                        emailCtrl: _emailCtrl,
                                        phoneCtrl: _phoneCtrl,
                                        passCtrl: _passCtrl,
                                        role: _role,
                                        obscure: _obscure,
                                        acceptTerms: _acceptTerms,
                                        acceptPrivacy: _acceptPrivacy,
                                        acceptDriverDocuments:
                                            _acceptDriverDocuments,
                                        loginPath: _loginPath,
                                        onRoleChanged: _setRole,
                                        onToggleObscure: () => setState(
                                          () => _obscure = !_obscure,
                                        ),
                                        onAcceptTerms: (value) => setState(
                                          () => _acceptTerms = value,
                                        ),
                                        onAcceptPrivacy: (value) => setState(
                                          () => _acceptPrivacy = value,
                                        ),
                                        onAcceptDriverDocuments: (value) =>
                                            setState(
                                          () => _acceptDriverDocuments = value,
                                        ),
                                        onRegister: _register,
                                      ),
                              ),
                              SizedBox(height: compact ? 28 : 44),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _setRole(String role) {
    setState(() {
      _role = role;
      if (role == 'client') _acceptDriverDocuments = false;
    });
  }
}

class _RegisterNav extends StatelessWidget {
  final bool compact;
  final String loginPath;

  const _RegisterNav({
    required this.compact,
    required this.loginPath,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _BrandMark(),
        const Spacer(),
        if (!compact)
          TextButton(
            onPressed: _openPublicHome,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.86),
            ),
            child: const Text('Inicio'),
          ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => context.go(loginPath),
          icon: const Icon(Icons.login_rounded, size: 18),
          label: Text(compact ? 'Ingresar' : 'Iniciar sesión'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.66)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: const Icon(
            Icons.local_shipping_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'muvv',
          style: GoogleFonts.manrope(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _DesktopRegisterLayout extends StatelessWidget {
  final AuthState auth;
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController passCtrl;
  final String role;
  final bool obscure;
  final bool acceptTerms;
  final bool acceptPrivacy;
  final bool acceptDriverDocuments;
  final String loginPath;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback onToggleObscure;
  final ValueChanged<bool> onAcceptTerms;
  final ValueChanged<bool> onAcceptPrivacy;
  final ValueChanged<bool> onAcceptDriverDocuments;
  final VoidCallback onRegister;

  const _DesktopRegisterLayout({
    required this.auth,
    required this.formKey,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.passCtrl,
    required this.role,
    required this.obscure,
    required this.acceptTerms,
    required this.acceptPrivacy,
    required this.acceptDriverDocuments,
    required this.loginPath,
    required this.onRoleChanged,
    required this.onToggleObscure,
    required this.onAcceptTerms,
    required this.onAcceptPrivacy,
    required this.onAcceptDriverDocuments,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(
          child: _RegisterHeroCopy(),
        ),
        const SizedBox(width: 56),
        SizedBox(
          width: 500,
          child: _RegisterPanel(
            auth: auth,
            formKey: formKey,
            nameCtrl: nameCtrl,
            emailCtrl: emailCtrl,
            phoneCtrl: phoneCtrl,
            passCtrl: passCtrl,
            role: role,
            obscure: obscure,
            acceptTerms: acceptTerms,
            acceptPrivacy: acceptPrivacy,
            acceptDriverDocuments: acceptDriverDocuments,
            loginPath: loginPath,
            onRoleChanged: onRoleChanged,
            onToggleObscure: onToggleObscure,
            onAcceptTerms: onAcceptTerms,
            onAcceptPrivacy: onAcceptPrivacy,
            onAcceptDriverDocuments: onAcceptDriverDocuments,
            onRegister: onRegister,
          ),
        ),
      ],
    );
  }
}

class _CompactRegisterLayout extends StatelessWidget {
  final AuthState auth;
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController passCtrl;
  final String role;
  final bool obscure;
  final bool acceptTerms;
  final bool acceptPrivacy;
  final bool acceptDriverDocuments;
  final String loginPath;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback onToggleObscure;
  final ValueChanged<bool> onAcceptTerms;
  final ValueChanged<bool> onAcceptPrivacy;
  final ValueChanged<bool> onAcceptDriverDocuments;
  final VoidCallback onRegister;

  const _CompactRegisterLayout({
    required this.auth,
    required this.formKey,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.passCtrl,
    required this.role,
    required this.obscure,
    required this.acceptTerms,
    required this.acceptPrivacy,
    required this.acceptDriverDocuments,
    required this.loginPath,
    required this.onRoleChanged,
    required this.onToggleObscure,
    required this.onAcceptTerms,
    required this.onAcceptPrivacy,
    required this.onAcceptDriverDocuments,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RegisterPanel(
          auth: auth,
          formKey: formKey,
          nameCtrl: nameCtrl,
          emailCtrl: emailCtrl,
          phoneCtrl: phoneCtrl,
          passCtrl: passCtrl,
          role: role,
          obscure: obscure,
          acceptTerms: acceptTerms,
          acceptPrivacy: acceptPrivacy,
          acceptDriverDocuments: acceptDriverDocuments,
          loginPath: loginPath,
          onRoleChanged: onRoleChanged,
          onToggleObscure: onToggleObscure,
          onAcceptTerms: onAcceptTerms,
          onAcceptPrivacy: onAcceptPrivacy,
          onAcceptDriverDocuments: onAcceptDriverDocuments,
          onRegister: onRegister,
        ),
        const SizedBox(height: 30),
        const _RegisterHeroCopy(compact: true),
      ],
    );
  }
}

class _RegisterHeroCopy extends StatelessWidget {
  final bool compact;

  const _RegisterHeroCopy({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 620 : 680),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cuenta verificada'.toUpperCase(),
            style: GoogleFonts.inter(
              color: AppTheme.accent,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Empieza a mover fletes con control',
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontSize: compact ? 40 : 62,
              fontWeight: FontWeight.w900,
              height: 1.06,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Registra clientes y conductores con aceptación legal, trazabilidad '
            'de datos y revisión documental para operar de forma seria desde '
            'el primer viaje.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: compact ? 16 : 20,
              height: 1.45,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 24),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _TrustBadge(
                icon: Icons.assignment_turned_in_outlined,
                label: 'Consentimiento registrado',
              ),
              _TrustBadge(
                icon: Icons.badge_outlined,
                label: 'Conductores verificados',
              ),
              _TrustBadge(
                icon: Icons.lock_outline_rounded,
                label: 'Documentos privados',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustBadge({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.88), size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterPanel extends StatelessWidget {
  final AuthState auth;
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController passCtrl;
  final String role;
  final bool obscure;
  final bool acceptTerms;
  final bool acceptPrivacy;
  final bool acceptDriverDocuments;
  final String loginPath;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback onToggleObscure;
  final ValueChanged<bool> onAcceptTerms;
  final ValueChanged<bool> onAcceptPrivacy;
  final ValueChanged<bool> onAcceptDriverDocuments;
  final VoidCallback onRegister;

  const _RegisterPanel({
    required this.auth,
    required this.formKey,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.passCtrl,
    required this.role,
    required this.obscure,
    required this.acceptTerms,
    required this.acceptPrivacy,
    required this.acceptDriverDocuments,
    required this.loginPath,
    required this.onRoleChanged,
    required this.onToggleObscure,
    required this.onAcceptTerms,
    required this.onAcceptPrivacy,
    required this.onAcceptDriverDocuments,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingAuthPanel(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const AuthPanelAccent(),
              const SizedBox(height: 20),
              Text(
                'Crear cuenta',
                style: GoogleFonts.manrope(
                  color: AppTheme.midnight,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Elige tu perfil y completa los datos iniciales.',
                style: TextStyle(
                  color: AppTheme.slate600,
                  fontSize: 15,
                  height: 1.4,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 22),
              if (auth.error != null) ...[
                _ErrorBanner(message: auth.error!),
                const SizedBox(height: 16),
              ],
              _RoleSelector(
                role: role,
                onChanged: auth.isLoading ? null : onRoleChanged,
              ),
              const SizedBox(height: 16),
              _AuthField(
                controller: nameCtrl,
                hint: 'Nombre completo',
                icon: Icons.person_outline_rounded,
                textInputAction: TextInputAction.next,
                validator: (value) => (value?.trim().length ?? 0) > 2
                    ? null
                    : 'Ingresa tu nombre',
              ),
              const SizedBox(height: 12),
              _AuthField(
                controller: emailCtrl,
                hint: 'Correo electrónico',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    (value?.contains('@') ?? false) ? null : 'Correo inválido',
              ),
              const SizedBox(height: 12),
              _AuthField(
                controller: phoneCtrl,
                hint: 'Teléfono (+56...)',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                validator: (value) => (value?.trim().length ?? 0) >= 9
                    ? null
                    : 'Teléfono inválido',
              ),
              const SizedBox(height: 12),
              _AuthField(
                controller: passCtrl,
                hint: 'Contraseña',
                icon: Icons.lock_outline_rounded,
                obscureText: obscure,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => onRegister(),
                validator: (value) =>
                    (value?.length ?? 0) >= 8 ? null : 'Mínimo 8 caracteres',
                suffix: IconButton(
                  tooltip:
                      obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                  onPressed: onToggleObscure,
                  icon: Icon(
                    obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 19,
                    color: AppTheme.slate400,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _ConsentRow(
                value: acceptTerms,
                onChanged: auth.isLoading ? null : onAcceptTerms,
                text: 'Acepto los términos y condiciones',
                linkText: 'Ver',
                onLink: () => context.push('/legal/terms'),
              ),
              _ConsentRow(
                value: acceptPrivacy,
                onChanged: auth.isLoading ? null : onAcceptPrivacy,
                text: 'Acepto la política de privacidad',
                linkText: 'Ver',
                onLink: () => context.push('/legal/privacy'),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: role == 'driver'
                    ? _ConsentRow(
                        key: const ValueKey('driver-consent'),
                        value: acceptDriverDocuments,
                        onChanged:
                            auth.isLoading ? null : onAcceptDriverDocuments,
                        text:
                            'Autorizo la revisión de mi licencia y documentos del vehículo',
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('no-driver-consent'),
                      ),
              ),
              const SizedBox(height: 20),
              _RegisterButton(
                isLoading: auth.isLoading,
                onRegister: onRegister,
              ),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    '¿Ya tienes cuenta? ',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.slate600,
                      letterSpacing: 0,
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go(loginPath),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.primaryDark,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    child: const Text('Ingresa'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleSelector extends StatelessWidget {
  final String role;
  final ValueChanged<String>? onChanged;

  const _RoleSelector({
    required this.role,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 360;
        final client = _RoleOption(
          label: 'Cliente',
          description: 'Pedir fletes',
          icon: Icons.person_rounded,
          selected: role == 'client',
          onTap: onChanged == null ? null : () => onChanged!('client'),
        );
        final driver = _RoleOption(
          label: 'Conductor',
          description: 'Aceptar viajes',
          icon: Icons.drive_eta_rounded,
          selected: role == 'driver',
          onTap: onChanged == null ? null : () => onChanged!('driver'),
        );

        if (stacked) {
          return Column(
            children: [
              client,
              const SizedBox(height: 10),
              driver,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: client),
            const SizedBox(width: 10),
            Expanded(child: driver),
          ],
        );
      },
    );
  }
}

class _RoleOption extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  const _RoleOption({
    required this.label,
    required this.description,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEFF6FF) : AppTheme.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.slate200,
              width: selected ? 1.4 : 0.8,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected ? AppTheme.primary : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? AppTheme.primary : AppTheme.slate200,
                  ),
                ),
                child: Icon(
                  icon,
                  color: selected ? Colors.white : AppTheme.slate600,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            selected ? AppTheme.primaryDark : AppTheme.midnight,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsentRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String text;
  final String? linkText;
  final VoidCallback? onLink;

  const _ConsentRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.text,
    this.linkText,
    this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Checkbox(
              value: value,
              onChanged: onChanged == null
                  ? null
                  : (checked) => onChanged!(checked ?? false),
              activeColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 2,
                children: [
                  Text(
                    text,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.slate600,
                      height: 1.35,
                      letterSpacing: 0,
                    ),
                  ),
                  if (linkText != null && onLink != null)
                    InkWell(
                      onTap: onLink,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 1,
                        ),
                        child: Text(
                          linkText!,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryDark,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;

  const _AuthField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.suffix,
    this.validator,
    this.onFieldSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      style: const TextStyle(
        color: AppTheme.midnight,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppTheme.background,
        prefixIcon: Icon(icon, color: AppTheme.slate600, size: 20),
        suffixIcon: suffix,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.slate200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.slate200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.error, width: 1.0),
        ),
      ),
    );
  }
}

class _RegisterButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onRegister;

  const _RegisterButton({
    required this.isLoading,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: isLoading ? null : onRegister,
      icon: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.person_add_alt_1_rounded, size: 20),
      label: Text(isLoading ? 'Creando cuenta' : 'Crear cuenta'),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.62),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppTheme.error,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppTheme.error,
                fontSize: 13,
                height: 1.35,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
