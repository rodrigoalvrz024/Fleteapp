import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {

  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();
  bool _obscure    = true;

  late AnimationController _btnCtrl;
  late Animation<double>   _btnScale;

  @override
  void initState() {
    super.initState();
    _btnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _btnScale = Tween(begin: 1.0, end: 0.96).animate(
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
      context.go(role == 'driver' ? '/driver' : '/client');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  // ── Logo minimal ──────────────────────────
                  const SizedBox(height: 52),
                  Row(children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.local_shipping_rounded,
                          color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 8),
                    const Text('FleteApp',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.slate400,
                          letterSpacing: 0.2,
                        )),
                  ]),

                  // ── Título principal ──────────────────────
                  const SizedBox(height: 48),
                  const Text('Bienvenido\nde vuelta',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.midnight,
                        letterSpacing: -1.0,
                        height: 1.05,
                      )),
                  const SizedBox(height: 10),
                  const Text('Ingresa para gestionar tus fletes',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppTheme.slate400,
                        letterSpacing: 0.1,
                        height: 1.4,
                      )),

                  // ── Card formulario ───────────────────────
                  const SizedBox(height: 36),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFFF0F2F5),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1A1A2E).withValues(alpha: 0.06),
                          blurRadius: 40,
                          spreadRadius: 0,
                          offset: const Offset(0, 12),
                        ),
                        BoxShadow(
                          color: const Color(0xFF1A1A2E).withValues(alpha: 0.03),
                          blurRadius: 8,
                          spreadRadius: 0,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [

                        // Error banner
                        if (auth.error != null) ...[
                          _ErrorBanner(message: auth.error!),
                          const SizedBox(height: 16),
                        ],

                        // Email
                        _PremiumField(
                          controller:   _emailCtrl,
                          hint:         'Correo electrónico',
                          icon:         Icons.mail_outline_rounded,
                          keyboardType: TextInputType.emailAddress,
                          validator:    (v) => (v?.contains('@') ?? false)
                              ? null : 'Correo inválido',
                        ),
                        const SizedBox(height: 12),

                        // Password
                        _PremiumField(
                          controller:  _passCtrl,
                          hint:        'Contraseña',
                          icon:        Icons.lock_outline_rounded,
                          obscureText: _obscure,
                          validator:   (v) => (v?.length ?? 0) >= 8
                              ? null : 'Mínimo 8 caracteres',
                          suffix: GestureDetector(
                            onTap: () => setState(() => _obscure = !_obscure),
                            child: Icon(
                              _obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 17,
                              color: AppTheme.slate400,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Botón principal con scale + gradiente
                        ScaleTransition(
                          scale: _btnScale,
                          child: GestureDetector(
                            onTapDown:   (_) => _btnCtrl.forward(),
                            onTapUp:     (_) => _btnCtrl.reverse(),
                            onTapCancel: ()  => _btnCtrl.reverse(),
                            child: Container(
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: auth.isLoading
                                    ? null
                                    : const LinearGradient(
                                        colors: [
                                          Color(0xFF4F94F8),
                                          Color(0xFF2563EB),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                color: auth.isLoading
                                    ? AppTheme.primary.withValues(alpha: 0.6)
                                    : null,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: auth.isLoading ? [] : [
                                  BoxShadow(
                                    color: const Color(0xFF2563EB)
                                        .withValues(alpha: 0.35),
                                    blurRadius: 20,
                                    spreadRadius: 0,
                                    offset: const Offset(0, 8),
                                  ),
                                  BoxShadow(
                                    color: const Color(0xFF2563EB)
                                        .withValues(alpha: 0.15),
                                    blurRadius: 6,
                                    spreadRadius: 0,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: auth.isLoading ? null : _login,
                                  splashColor:
                                      Colors.white.withValues(alpha: 0.15),
                                  highlightColor:
                                      Colors.white.withValues(alpha: 0.05),
                                  child: Center(
                                    child: auth.isLoading
                                        ? const SizedBox(
                                            height: 20, width: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2.5,
                                            ))
                                        : const Text('Iniciar sesión',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.3,
                                            )),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Registro ──────────────────────────────
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('¿No tienes cuenta? ',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.slate400,
                          )),
                      GestureDetector(
                        onTap: () => context.push('/register'),
                        child: const Text('Regístrate',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            )),
                      ),
                    ],
                  ),

                  // ── Pie de página ─────────────────────────
                  const SizedBox(height: 48),
                  const Text(
                    'Al continuar aceptas los Términos de uso\ny la Política de privacidad',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFBDC5CE),
                      height: 1.7,
                      letterSpacing: 0.1,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Input premium ──────────────────────────────────────────

class _PremiumField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final String? Function(String?)? validator;
  final Widget? suffix;

  const _PremiumField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.validator,
    this.suffix,
  });

  @override
  State<_PremiumField> createState() => _PremiumFieldState();
}

class _PremiumFieldState extends State<_PremiumField>
    with SingleTickerProviderStateMixin {

  bool _focused  = false;
  bool _hasError = false;

  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    setState(() => _focused = focused);
    focused ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _anim,
    builder: (_, __) {
      final borderColor = _hasError
          ? AppTheme.error
          : Color.lerp(
              const Color(0xFFD1D9E0),
              AppTheme.primary,
              _anim.value,
            )!;

      final iconColor = _hasError
          ? AppTheme.error
          : Color.lerp(
              AppTheme.slate400,
              AppTheme.primary,
              _anim.value,
            )!;

      return Focus(
        onFocusChange: _onFocusChange,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _focused ? Colors.white : const Color(0xFFF4F6F8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: _focused ? 1.5 : 0.8,
            ),
          ),
          child: TextFormField(
            controller:   widget.controller,
            keyboardType: widget.keyboardType,
            obscureText:  widget.obscureText,
            style: const TextStyle(
              fontSize: 15,
              color: AppTheme.midnight,
              fontWeight: FontWeight.w400,
            ),
            validator: (v) {
              final result = widget.validator?.call(v);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _hasError = result != null);
              });
              return result;
            },
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: const TextStyle(
                fontSize: 14,
                color: AppTheme.slate400,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 14, right: 10),
                child: Icon(widget.icon, size: 18, color: iconColor),
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 44, minHeight: 44,
              ),
              suffixIcon: widget.suffix != null
                  ? Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: widget.suffix,
                    )
                  : null,
              suffixIconConstraints: const BoxConstraints(
                minWidth: 44, minHeight: 44,
              ),
              border:        InputBorder.none,
              errorBorder:   InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              errorStyle:    const TextStyle(height: 0, fontSize: 0),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 16),
            ),
          ),
        ),
      );
    },
  );
}

// ── Error banner ───────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F2),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: AppTheme.error.withValues(alpha: 0.2),
        width: 0.5,
      ),
    ),
    child: Row(children: [
      const Icon(Icons.error_outline_rounded,
          color: AppTheme.error, size: 16),
      const SizedBox(width: 8),
      Expanded(
        child: Text(message,
            style: const TextStyle(
              color: Color(0xFFBE123C),
              fontSize: 13,
              height: 1.3,
            )),
      ),
    ]),
  );
}