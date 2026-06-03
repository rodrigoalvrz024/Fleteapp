import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../services/auth_service.dart';
import 'widgets/recovery_auth_widgets.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String? token;

  const ResetPasswordScreen({super.key, required this.token});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _authService = AuthService();
  bool _loading = false;
  bool _obscure = true;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final token = widget.token;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'El enlace no es válido o está incompleto.');
      return;
    }

    HapticFeedback.lightImpact();

    setState(() {
      _loading = true;
      _message = null;
      _error = null;
    });

    try {
      final message = await _authService.resetPassword(
        token: token,
        newPassword: _passwordCtrl.text,
      );
      if (!mounted) return;
      setState(() => _message = message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'El enlace expiró o no es válido. Solicita uno nuevo.',
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
        eyebrow: 'Nuevo acceso',
        title: 'Crea una contraseña fuerte y sigue operando',
        subtitle:
            'Actualiza tu contraseña con un enlace temporal y vuelve a tu '
            'cuenta con la misma trazabilidad de siempre.',
        panelTitle: 'Nueva contraseña',
        panelSubtitle: 'Usa al menos 8 caracteres para proteger tu cuenta.',
        panelIcon: Icons.lock_reset_rounded,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RecoveryAuthField(
                controller: _passwordCtrl,
                hint: 'Nueva contraseña',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    (value?.length ?? 0) >= 8 ? null : 'Mínimo 8 caracteres',
                suffix: IconButton(
                  tooltip:
                      _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppTheme.slate400,
                    size: 19,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              const SizedBox(height: 12),
              RecoveryAuthField(
                controller: _confirmCtrl,
                hint: 'Confirmar contraseña',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                validator: (value) => value == _passwordCtrl.text
                    ? null
                    : 'Las contraseñas no coinciden',
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
                label: 'Actualizar contraseña',
                icon: Icons.check_rounded,
                isLoading: _loading,
                onPressed: _message == null ? _submit : null,
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
                child: Text(_message == null ? 'Volver' : 'Iniciar sesión'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
