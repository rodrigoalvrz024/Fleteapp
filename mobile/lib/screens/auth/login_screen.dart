import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import 'widgets/auth_visuals.dart';

const _publicHomeUrl = 'https://fleteapp-public-8d8f7.web.app';

Future<void> _openPublicHome() async {
  await launchUrl(Uri.parse(_publicHomeUrl), webOnlyWindowName: '_self');
}

class LoginScreen extends ConsumerStatefulWidget {
  final String? redirectPath;

  const LoginScreen({super.key, this.redirectPath});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  late AnimationController _btnCtrl;
  late Animation<double> _btnScale;

  @override
  void initState() {
    super.initState();
    _btnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _btnScale = Tween(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _btnCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _btnCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();

    final ok = await ref
        .read(authProvider.notifier)
        .login(_emailCtrl.text.trim(), _passCtrl.text);

    if (!mounted) return;
    if (ok) {
      final role = ref.read(authProvider).user?.role;
      context.go(_destinationFor(role));
    }
  }

  String _destinationFor(String? role) {
    final safeRedirect = _safeClientRedirect(widget.redirectPath);
    if (role == 'client' && safeRedirect != null) return safeRedirect;

    return switch (role) {
      'admin' => '/admin',
      'driver' => '/app/driver',
      _ => '/app/client',
    };
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

  String get _registerPath {
    final safeRedirect = _safeClientRedirect(widget.redirectPath);
    if (safeRedirect == null) return '/auth/register';
    return Uri(
      path: '/auth/register',
      queryParameters: {'next': safeRedirect},
    ).toString();
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
            final compact = constraints.maxWidth < 860;
            final horizontalPadding = compact ? 20.0 : 36.0;
            final topBottomPadding = compact ? 18.0 : 26.0;

            return AuthBackdrop(
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
                                child: _LoginNav(
                                  compact: compact,
                                  registerPath: _registerPath,
                                ),
                              ),
                              SizedBox(height: compact ? 24 : 78),
                              AuthReveal(
                                delay: 0.14,
                                child: compact
                                    ? _CompactLoginLayout(
                                        auth: auth,
                                        formKey: _formKey,
                                        emailCtrl: _emailCtrl,
                                        passCtrl: _passCtrl,
                                        obscure: _obscure,
                                        onToggleObscure: () => setState(
                                          () => _obscure = !_obscure,
                                        ),
                                        onLogin: _login,
                                        registerPath: _registerPath,
                                        btnScale: _btnScale,
                                        btnCtrl: _btnCtrl,
                                      )
                                    : _DesktopLoginLayout(
                                        auth: auth,
                                        formKey: _formKey,
                                        emailCtrl: _emailCtrl,
                                        passCtrl: _passCtrl,
                                        obscure: _obscure,
                                        onToggleObscure: () => setState(
                                          () => _obscure = !_obscure,
                                        ),
                                        onLogin: _login,
                                        registerPath: _registerPath,
                                        btnScale: _btnScale,
                                        btnCtrl: _btnCtrl,
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
}

class _LoginNav extends StatelessWidget {
  final bool compact;
  final String registerPath;

  const _LoginNav({
    required this.compact,
    required this.registerPath,
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
          onPressed: () => context.push(registerPath),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
          label: Text(compact ? 'Cuenta' : 'Crear cuenta'),
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
          'FleteApp',
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

class _DesktopLoginLayout extends StatelessWidget {
  final AuthState auth;
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final VoidCallback onLogin;
  final String registerPath;
  final Animation<double> btnScale;
  final AnimationController btnCtrl;

  const _DesktopLoginLayout({
    required this.auth,
    required this.formKey,
    required this.emailCtrl,
    required this.passCtrl,
    required this.obscure,
    required this.onToggleObscure,
    required this.onLogin,
    required this.registerPath,
    required this.btnScale,
    required this.btnCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(
          child: _LoginHeroCopy(),
        ),
        const SizedBox(width: 56),
        SizedBox(
          width: 448,
          child: _LoginPanel(
            auth: auth,
            formKey: formKey,
            emailCtrl: emailCtrl,
            passCtrl: passCtrl,
            obscure: obscure,
            onToggleObscure: onToggleObscure,
            onLogin: onLogin,
            registerPath: registerPath,
            btnScale: btnScale,
            btnCtrl: btnCtrl,
          ),
        ),
      ],
    );
  }
}

class _CompactLoginLayout extends StatelessWidget {
  final AuthState auth;
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final VoidCallback onLogin;
  final String registerPath;
  final Animation<double> btnScale;
  final AnimationController btnCtrl;

  const _CompactLoginLayout({
    required this.auth,
    required this.formKey,
    required this.emailCtrl,
    required this.passCtrl,
    required this.obscure,
    required this.onToggleObscure,
    required this.onLogin,
    required this.registerPath,
    required this.btnScale,
    required this.btnCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _LoginPanel(
          auth: auth,
          formKey: formKey,
          emailCtrl: emailCtrl,
          passCtrl: passCtrl,
          obscure: obscure,
          onToggleObscure: onToggleObscure,
          onLogin: onLogin,
          registerPath: registerPath,
          btnScale: btnScale,
          btnCtrl: btnCtrl,
        ),
        const SizedBox(height: 30),
        const _LoginHeroCopy(compact: true),
      ],
    );
  }
}

class _LoginHeroCopy extends StatelessWidget {
  final bool compact;

  const _LoginHeroCopy({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 620 : 680),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fletes urbanos en Chile'.toUpperCase(),
            style: GoogleFonts.inter(
              color: AppTheme.accent,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'FleteApp',
            style: GoogleFonts.manrope(
              color: Colors.white,
              fontSize: compact ? 48 : 72,
              fontWeight: FontWeight.w900,
              height: 1,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Gestiona solicitudes, conductores, documentos y trazabilidad '
            'operativa desde una sola entrada.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: compact ? 17 : 21,
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
                icon: Icons.verified_user_outlined,
                label: 'Conductores verificados',
              ),
              _TrustBadge(
                icon: Icons.lock_outline_rounded,
                label: 'Documentos privados',
              ),
              _TrustBadge(
                icon: Icons.manage_search_rounded,
                label: 'Historial auditable',
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

class _LoginPanel extends StatelessWidget {
  final AuthState auth;
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final VoidCallback onLogin;
  final String registerPath;
  final Animation<double> btnScale;
  final AnimationController btnCtrl;

  const _LoginPanel({
    required this.auth,
    required this.formKey,
    required this.emailCtrl,
    required this.passCtrl,
    required this.obscure,
    required this.onToggleObscure,
    required this.onLogin,
    required this.registerPath,
    required this.btnScale,
    required this.btnCtrl,
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
                'Ingresar',
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
                'Accede a tu cuenta FleteApp.',
                style: TextStyle(
                  color: AppTheme.slate600,
                  fontSize: 15,
                  height: 1.5,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 22),
              if (auth.error != null) ...[
                _ErrorBanner(message: auth.error!),
                const SizedBox(height: 16),
              ],
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
                controller: passCtrl,
                hint: 'Contraseña',
                icon: Icons.lock_outline_rounded,
                obscureText: obscure,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => onLogin(),
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
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: auth.isLoading
                      ? null
                      : () => context.push('/auth/forgot-password'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryDark,
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ),
              const SizedBox(height: 18),
              _LoginButton(
                isLoading: auth.isLoading,
                onLogin: onLogin,
                btnScale: btnScale,
                btnCtrl: btnCtrl,
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    '¿No tienes cuenta? ',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.slate600,
                      letterSpacing: 0,
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push(registerPath),
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
                    child: const Text('Regístrate'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Al continuar aceptas los Términos de uso y la Política de privacidad.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.slate400,
                  height: 1.45,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onLogin;
  final Animation<double> btnScale;
  final AnimationController btnCtrl;

  const _LoginButton({
    required this.isLoading,
    required this.onLogin,
    required this.btnScale,
    required this.btnCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: btnScale,
      child: GestureDetector(
        onTapDown: (_) => btnCtrl.forward(),
        onTapUp: (_) => btnCtrl.reverse(),
        onTapCancel: () => btnCtrl.reverse(),
        child: SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: isLoading ? null : onLogin,
            icon: isLoading
                ? const SizedBox.shrink()
                : const Icon(Icons.login_rounded, size: 18),
            label: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.4,
                    ),
                  )
                : const Text('Iniciar sesión'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
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
        fontSize: 15,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 19),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppTheme.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.slate200, width: 0.8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.slate200, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.error, width: 0.8),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.error, width: 1.2),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.error.withValues(alpha: 0.24),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppTheme.error,
            size: 17,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFBE123C),
                fontSize: 13,
                height: 1.3,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
