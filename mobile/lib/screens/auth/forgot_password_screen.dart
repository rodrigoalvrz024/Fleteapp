import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import 'widgets/recovery_auth_widgets.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _authService = AuthService();
  bool _loading = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    HapticFeedback.lightImpact();

    setState(() {
      _loading = true;
      _message = null;
      _error = null;
    });

    try {
      final message = await _authService.forgotPassword(_emailCtrl.text.trim());
      if (!mounted) return;
      setState(() => _message = message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'No pudimos procesar la solicitud. Intenta de nuevo.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: RecoveryAuthScaffold(
        eyebrow: 'Recuperación segura',
        title: 'Vuelve a entrar sin perder el control',
        subtitle:
            'Te enviaremos un enlace temporal para crear una contraseña nueva '
            'y mantener tu cuenta protegida.',
        panelTitle: 'Recuperar acceso',
        panelSubtitle: 'Ingresa el correo asociado a tu cuenta Muvv.',
        panelIcon: Icons.mark_email_read_outlined,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RecoveryAuthField(
                controller: _emailCtrl,
                hint: 'Correo electrónico',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                validator: (value) =>
                    (value?.contains('@') ?? false) ? null : 'Correo inválido',
                onFieldSubmitted: (_) => _loading ? null : _submit(),
              ),
              if (_message != null || _error != null) ...[
                const SizedBox(height: 16),
                RecoveryStatusMessage(
                  message: _message ?? _error!,
                  isError: _error != null,
                ),
              ],
              const SizedBox(height: 24),
              RecoveryPrimaryButton(
                label: 'Enviar enlace',
                icon: Icons.send_rounded,
                isLoading: _loading,
                onPressed: _submit,
              ),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => context.go('/auth/login'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryDark,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                child: const Text('Volver al inicio de sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
