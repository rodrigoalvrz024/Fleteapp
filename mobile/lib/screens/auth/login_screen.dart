import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/google_auth_service.dart';
import 'widgets/auth_visuals.dart';

const _publicHomeUrl = String.fromEnvironment(
  'PUBLIC_HOME_URL',
  defaultValue: 'https://fleteapp-public-8d8f7.web.app',
);

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
  bool _isGoogleLoading = false;
  String _selectedRole = 'client';

  String? get _preferredRole =>
      MediaQuery.sizeOf(context).shortestSide < 600 ? _selectedRole : null;

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
    if (ref.read(authProvider).isLoading || _isGoogleLoading) return;
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    HapticFeedback.lightImpact();

    final ok = await ref.read(authProvider.notifier).login(
        _emailCtrl.text.trim(), _passCtrl.text,
        preferredRole: _preferredRole);

    _completeLogin(ok);
  }

  Future<void> _loginWithGoogle() async {
    if (ref.read(authProvider).isLoading || _isGoogleLoading) return;
    final preferredRole = _preferredRole;
    FocusScope.of(context).unfocus();
    setState(() => _isGoogleLoading = true);

    try {
      final idToken = await GoogleAuthService().requestIdToken();
      if (idToken == null) return;

      final ok = await ref
          .read(authProvider.notifier)
          .loginWithGoogle(idToken, preferredRole: preferredRole);
      _completeLogin(ok);
    } on GoogleAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  void _completeLogin(bool ok) {
    if (!mounted) return;
    if (ok) {
      if (ref.read(authProvider).user?.legalReacceptanceRequired == true) {
        context.go('/auth/legal-update');
        return;
      }
      final role = ref.read(authProvider).user?.role;
      context.go(_destinationFor(role));
    }
  }

  void _showSocialAuthInfo(String provider) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('El acceso con $provider se habilitara proximamente.'),
      ),
    );
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
    final role = _preferredRole;
    if (safeRedirect == null && role == null) return '/auth/register';
    return Uri(
      path: '/auth/register',
      queryParameters: {
        if (role != null) 'role': role,
        if (safeRedirect != null && role != 'driver') 'next': safeRedirect,
      },
    ).toString();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final phone = MediaQuery.sizeOf(context).shortestSide < 600;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: phone ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: phone ? AppTheme.background : AppTheme.midnight,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 860;
            final horizontalPadding = compact ? 20.0 : 36.0;
            final topBottomPadding = compact ? 18.0 : 26.0;

            if (phone) {
              return _SketchMobileLogin(
                selectedRole: _selectedRole,
                onRoleChanged: (role) {
                  if (role == _selectedRole) return;
                  HapticFeedback.selectionClick();
                  setState(() => _selectedRole = role);
                },
                auth: auth,
                formKey: _formKey,
                emailCtrl: _emailCtrl,
                passCtrl: _passCtrl,
                obscure: _obscure,
                onToggleObscure: () => setState(() => _obscure = !_obscure),
                onLogin: _login,
                onGoogle: _loginWithGoogle,
                onApple: () => _showSocialAuthInfo('Apple'),
                isGoogleLoading: _isGoogleLoading,
                registerPath: _registerPath,
                btnScale: _btnScale,
                btnCtrl: _btnCtrl,
              );
            }

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
            textStyle: const TextStyle(
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
        const Text(
          'Muvv',
          style: TextStyle(
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

class _SketchMobileLogin extends StatelessWidget {
  final String selectedRole;
  final ValueChanged<String> onRoleChanged;
  final AuthState auth;
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController passCtrl;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final VoidCallback onLogin;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final bool isGoogleLoading;
  final String registerPath;
  final Animation<double> btnScale;
  final AnimationController btnCtrl;

  const _SketchMobileLogin({
    required this.selectedRole,
    required this.onRoleChanged,
    required this.auth,
    required this.formKey,
    required this.emailCtrl,
    required this.passCtrl,
    required this.obscure,
    required this.onToggleObscure,
    required this.onLogin,
    required this.onGoogle,
    required this.onApple,
    required this.isGoogleLoading,
    required this.registerPath,
    required this.btnScale,
    required this.btnCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _SketchCornerPattern()),
          ),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Keep the compact layout scrollable for the keyboard and large text.
              final compact = constraints.maxHeight < 940;
              final veryCompact = constraints.maxHeight < 700;
              const horizontalPadding = 24.0;

              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  veryCompact ? 6 : (compact ? 12 : 46),
                  horizontalPadding,
                  veryCompact ? 6 : (compact ? 12 : 30),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight -
                            (veryCompact ? 12 : (compact ? 24 : 76)))
                        .clamp(0.0, double.infinity),
                  ),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SketchMuvvBrand(
                            compact: compact, logoSize: veryCompact ? 56 : 60),
                        SizedBox(height: compact ? 8 : 64),
                        Text(
                          'Bienvenido de nuevo',
                          style: TextStyle(
                            color: AppTheme.midnight,
                            fontSize: compact ? 22 : 28,
                            fontWeight: FontWeight.w800,
                            height: 1.12,
                            letterSpacing: 0,
                          ),
                        ),
                        SizedBox(height: compact ? 4 : 10),
                        Text(
                          'Gestiona tus fletes de forma simple y segura.',
                          style: TextStyle(
                            color: const Color(0xFF6B7280),
                            fontSize: compact ? 13 : 17,
                            fontWeight: FontWeight.w400,
                            height: 1.42,
                            letterSpacing: 0,
                          ),
                        ),
                        SizedBox(height: compact ? 10 : 30),
                        if (auth.error != null) ...[
                          _ErrorBanner(message: auth.error!),
                          const SizedBox(height: 14),
                        ],
                        AbsorbPointer(
                          absorbing: auth.isLoading || isGoogleLoading,
                          child: CupertinoSlidingSegmentedControl<String>(
                            key: ValueKey(
                                MediaQuery.disableAnimationsOf(context)
                                    ? selectedRole
                                    : 'login-role'),
                            groupValue: selectedRole,
                            backgroundColor: const Color(0xFFF0F2F5),
                            thumbColor: Colors.white,
                            padding: const EdgeInsets.all(4),
                            onValueChanged: (role) {
                              if (role != null) onRoleChanged(role);
                            },
                            children: {
                              for (final entry in const {
                                'client': 'Cliente',
                                'driver': 'Conductor',
                              }.entries)
                                entry.key: Semantics(
                                  selected: selectedRole == entry.key,
                                  enabled: !auth.isLoading && !isGoogleLoading,
                                  child: ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(minHeight: 40),
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 8),
                                        child: Text(
                                          entry.value,
                                          style: TextStyle(
                                            fontSize: 14,
                                            height: 1.2,
                                            letterSpacing: 0,
                                            fontWeight: FontWeight.w600,
                                            color: selectedRole == entry.key
                                                ? AppTheme.primary
                                                : AppTheme.midnight,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        _SketchAuthField(
                          label: 'Correo electrónico',
                          controller: emailCtrl,
                          hint: 'ejemplo@correo.com',
                          icon: Icons.mail_outline_rounded,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          compact: compact,
                          validator: (value) => (value?.contains('@') ?? false)
                              ? null
                              : 'Correo inválido',
                        ),
                        SizedBox(height: compact ? 8 : 14),
                        _SketchAuthField(
                          label: 'Contraseña',
                          controller: passCtrl,
                          hint: '••••••••••',
                          icon: Icons.lock_outline_rounded,
                          keyboardType: TextInputType.visiblePassword,
                          obscureText: obscure,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => onLogin(),
                          compact: compact,
                          validator: (value) => (value?.length ?? 0) >= 8
                              ? null
                              : 'Mínimo 8 caracteres',
                          suffix: IconButton(
                            tooltip: obscure
                                ? 'Mostrar contraseña'
                                : 'Ocultar contraseña',
                            onPressed: onToggleObscure,
                            icon: Icon(
                              obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: const Color(0xFF6B7280),
                              size: 25,
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
                              foregroundColor: const Color(0xFF1269F3),
                              padding: EdgeInsets.only(
                                top: compact ? 6 : 8,
                                bottom: compact ? 2 : 4,
                              ),
                              textStyle: TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: compact ? 13 : 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0,
                              ),
                            ),
                            child: const Text('¿Olvidaste tu contraseña?'),
                          ),
                        ),
                        SizedBox(height: compact ? 4 : 12),
                        _SketchLoginButton(
                          isLoading: auth.isLoading,
                          onLogin: onLogin,
                          btnScale: btnScale,
                          btnCtrl: btnCtrl,
                          compact: compact,
                        ),
                        SizedBox(height: compact ? 6 : 24),
                        _SocialDivider(compact: compact),
                        SizedBox(height: compact ? 4 : 16),
                        _SocialSignInButton(
                          label: 'Continuar con Google',
                          icon: const _GoogleGlyph(),
                          onPressed: onGoogle,
                          compact: compact,
                          isLoading: isGoogleLoading,
                          disabled: auth.isLoading || isGoogleLoading,
                        ),
                        SizedBox(height: compact ? 6 : 10),
                        _SocialSignInButton(
                          label: 'Continuar con Apple',
                          icon: Icon(
                            Icons.apple,
                            color: Colors.black,
                            size: compact ? 24 : 27,
                          ),
                          onPressed: onApple,
                          compact: compact,
                          disabled: auth.isLoading || isGoogleLoading,
                        ),
                        SizedBox(height: compact ? 6 : 34),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '¿No tienes cuenta? ',
                              style: TextStyle(
                                color: const Color(0xFF6B7280),
                                fontSize: compact ? 13 : 15,
                                letterSpacing: 0,
                              ),
                            ),
                            TextButton(
                              onPressed: () => context.push(registerPath),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF1269F3),
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                textStyle: TextStyle(
                                  fontFamily: AppTheme.fontFamily,
                                  fontSize: compact ? 13 : 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0,
                                ),
                              ),
                              child: const Text('Crear cuenta'),
                            ),
                          ],
                        ),
                        SizedBox(height: compact ? 2 : 16),
                        _LegalFooter(
                          onTerms: () => context.push('/legal/terms'),
                          onPrivacy: () => context.push('/legal/privacy'),
                          compact: compact,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SketchMuvvBrand extends StatelessWidget {
  final bool compact;
  final double logoSize;

  const _SketchMuvvBrand({required this.compact, required this.logoSize});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 14 : 18),
          child: Image.asset(
            'assets/branding/muvv-app-icon.png',
            width: compact ? logoSize : 72,
            height: compact ? logoSize : 72,
            fit: BoxFit.cover,
          ),
        ),
        SizedBox(width: compact ? 10 : 18),
        Text(
          'Muvv',
          style: TextStyle(
            color: AppTheme.midnight,
            fontSize: compact ? 24 : 32,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _SketchAuthField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final bool obscureText;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final bool compact;

  const _SketchAuthField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.icon,
    required this.keyboardType,
    required this.textInputAction,
    this.obscureText = false,
    this.suffix,
    this.validator,
    this.onFieldSubmitted,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: (compact ? 60 : 78) +
          (MediaQuery.textScalerOf(context).scale(15) - 15) * 3,
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 16,
        compact ? 7 : 10,
        8,
        compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8DDE6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          SizedBox(height: compact ? 0 : 2),
          Expanded(
            child: Row(
              children: [
                Icon(
                  icon,
                  color: const Color(0xFF6B7280),
                  size: compact ? 21 : 24,
                ),
                SizedBox(width: compact ? 10 : 14),
                Expanded(
                  child: TextFormField(
                    controller: controller,
                    keyboardType: keyboardType,
                    textInputAction: textInputAction,
                    obscureText: obscureText,
                    validator: validator,
                    onFieldSubmitted: onFieldSubmitted,
                    style: TextStyle(
                      color: AppTheme.midnight,
                      fontSize: compact ? 14 : 16,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0,
                    ),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: TextStyle(
                        color: const Color(0xFFA0A6B0),
                        fontSize: compact ? 14 : 16,
                        letterSpacing: 0,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      errorStyle: const TextStyle(fontSize: 0, height: 0),
                    ),
                  ),
                ),
                if (suffix != null) suffix!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SketchLoginButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onLogin;
  final Animation<double> btnScale;
  final AnimationController btnCtrl;
  final bool compact;

  const _SketchLoginButton({
    required this.isLoading,
    required this.onLogin,
    required this.btnScale,
    required this.btnCtrl,
    required this.compact,
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
          height: (compact ? 48 : 56) +
              (MediaQuery.textScalerOf(context).scale(16) - 16) * 3,
          child: ElevatedButton(
            onPressed: isLoading ? null : onLogin,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1269F3),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(compact ? 13 : 14),
              ),
              textStyle: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: compact ? 15 : 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.4,
                    ),
                  )
                : const Text('Iniciar sesión'),
          ),
        ),
      ),
    );
  }
}

class _SocialDivider extends StatelessWidget {
  final bool compact;

  const _SocialDivider({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFD1D5DB))),
        Expanded(
          flex: 3,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20),
            child: Text(
              'o continúa con',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF6B7280),
                fontSize: compact ? 13 : 14,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFFD1D5DB))),
      ],
    );
  }
}

class _SocialSignInButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback onPressed;
  final bool compact;
  final bool isLoading;
  final bool disabled;

  const _SocialSignInButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.compact,
    this.isLoading = false,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: (compact ? 48 : 52) +
          (MediaQuery.textScalerOf(context).scale(15) - 15) * 4,
      child: OutlinedButton(
        onPressed: disabled ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.midnight,
          backgroundColor: Colors.white.withValues(alpha: 0.8),
          side: const BorderSide(color: Color(0xFFD8DDE6)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(compact ? 13 : 14),
          ),
          padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 20),
          textStyle: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: compact ? 14 : 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            : Row(
                children: [
                  SizedBox(width: 28, child: Center(child: icon)),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label, textAlign: TextAlign.center)),
                  const SizedBox(width: 40),
                ],
              ),
      ),
    );
  }
}

class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'G',
      style: TextStyle(
        color: Color(0xFF4285F4),
        fontSize: 26,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }
}

class _LegalFooter extends StatelessWidget {
  final VoidCallback onTerms;
  final VoidCallback onPrivacy;
  final bool compact;

  const _LegalFooter({
    required this.onTerms,
    required this.onPrivacy,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Al continuar, aceptas los ',
          style: TextStyle(
            color: const Color(0xFF7C8494),
            fontSize: compact ? 12 : 13,
            letterSpacing: 0,
          ),
        ),
        TextButton(
          onPressed: onTerms,
          style: _legalLinkStyle(compact),
          child: const Text('Términos de uso'),
        ),
        Text(
          ' y la ',
          style: TextStyle(
            color: const Color(0xFF7C8494),
            fontSize: compact ? 12 : 13,
            letterSpacing: 0,
          ),
        ),
        TextButton(
          onPressed: onPrivacy,
          style: _legalLinkStyle(compact),
          child: const Text('Política de privacidad.'),
        ),
      ],
    );
  }
}

ButtonStyle _legalLinkStyle(bool compact) => TextButton.styleFrom(
      foregroundColor: const Color(0xFF1269F3),
      padding: EdgeInsets.zero,
      minimumSize: const Size(0, 24),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: compact ? 12 : 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
    );

class _SketchCornerPattern extends CustomPainter {
  const _SketchCornerPattern();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.055)
      ..strokeWidth = 1;

    for (var offset = -size.height * 0.15; offset < size.width; offset += 16) {
      canvas.drawLine(
        Offset(offset, size.height),
        Offset(offset + size.height * 0.55, size.height * 0.45),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SketchCornerPattern oldDelegate) => false;
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
            style: TextStyle(
              color: AppTheme.accent,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Muvv',
            style: TextStyle(
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
      flat: false,
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
              const Text(
                'Ingresar',
                style: TextStyle(
                  color: AppTheme.midnight,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Accede a tu cuenta Muvv.',
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
