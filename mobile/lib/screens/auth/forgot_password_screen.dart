import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import 'widgets/auth_widgets.dart';

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
    return AuthShell(
      appBarTitle: 'Recuperar contraseña',
      onBack: () => context.go('/auth/login'),
      icon: Icons.mark_email_read_outlined,
      title: 'Recupera tu acceso',
      subtitle:
          'Ingresa tu correo y enviaremos un enlace para crear una contraseña nueva.',
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthTextField(
                controller: _emailCtrl,
                label: 'Correo electrónico',
                icon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                validator: (value) =>
                    (value?.contains('@') ?? false) ? null : 'Correo inválido',
                onFieldSubmitted: (_) => _loading ? null : _submit(),
              ),
              if (_message != null || _error != null) ...[
                const SizedBox(height: 16),
                AuthStatusMessage(
                  message: _message ?? _error!,
                  isError: _error != null,
                ),
              ],
              const SizedBox(height: 24),
              AuthPrimaryButton(
                label: 'Enviar enlace',
                isLoading: _loading,
                onPressed: _submit,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.go('/auth/login'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
                child: const Text('Volver al inicio de sesión'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
