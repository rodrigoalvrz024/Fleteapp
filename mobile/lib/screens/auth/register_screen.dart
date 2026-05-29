import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import 'widgets/auth_widgets.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

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
      context.go(
        _role == 'driver' ? '/app/driver/onboarding' : '/app/client',
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppTheme.error),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return AuthShell(
      appBarTitle: 'Crear cuenta',
      onBack: () => context.go('/auth/login'),
      title: 'Empieza con FleteApp',
      subtitle:
          'Crea tu cuenta como cliente o conductor para gestionar fletes.',
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (auth.error != null) ...[
                AuthStatusMessage(message: auth.error!, isError: true),
                const SizedBox(height: 16),
              ],
              AuthTextField(
                controller: _nameCtrl,
                label: 'Nombre completo',
                icon: Icons.person_outline_rounded,
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    (value?.length ?? 0) > 2 ? null : 'Ingresa tu nombre',
              ),
              const SizedBox(height: 14),
              AuthTextField(
                controller: _emailCtrl,
                label: 'Correo electrónico',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    (value?.contains('@') ?? false) ? null : 'Correo inválido',
              ),
              const SizedBox(height: 14),
              AuthTextField(
                controller: _phoneCtrl,
                label: 'Teléfono (+56...)',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                validator: (value) =>
                    (value?.length ?? 0) >= 9 ? null : 'Teléfono inválido',
              ),
              const SizedBox(height: 14),
              AuthTextField(
                controller: _passCtrl,
                label: 'Contraseña',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscure,
                validator: (value) =>
                    (value?.length ?? 0) >= 8 ? null : 'Mínimo 8 caracteres',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Tipo de cuenta',
                style: TextStyle(
                  color: AppTheme.midnight,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _RoleCard(
                      label: 'Cliente',
                      icon: Icons.person_rounded,
                      selected: _role == 'client',
                      onTap: () => setState(() {
                        _role = 'client';
                        _acceptDriverDocuments = false;
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _RoleCard(
                      label: 'Conductor',
                      icon: Icons.drive_eta_rounded,
                      selected: _role == 'driver',
                      onTap: () => setState(() => _role = 'driver'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              _ConsentRow(
                value: _acceptTerms,
                onChanged: (value) =>
                    setState(() => _acceptTerms = value ?? false),
                text: 'Acepto los términos y condiciones',
                linkText: 'Ver',
                onLink: () => context.push('/legal/terms'),
              ),
              _ConsentRow(
                value: _acceptPrivacy,
                onChanged: (value) =>
                    setState(() => _acceptPrivacy = value ?? false),
                text: 'Acepto la política de privacidad',
                linkText: 'Ver',
                onLink: () => context.push('/legal/privacy'),
              ),
              if (_role == 'driver')
                _ConsentRow(
                  value: _acceptDriverDocuments,
                  onChanged: (value) =>
                      setState(() => _acceptDriverDocuments = value ?? false),
                  text:
                      'Autorizo a FleteApp a revisar mi licencia y documentos del vehículo para validar mi cuenta',
                ),
              const SizedBox(height: 26),
              AuthPrimaryButton(
                label: 'Crear cuenta',
                isLoading: auth.isLoading,
                onPressed: _register,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 92,
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.slate200,
            width: selected ? 1.4 : 0.8,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? Colors.white : AppTheme.slate600,
              size: 26,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppTheme.midnight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConsentRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final String text;
  final String? linkText;
  final VoidCallback? onLink;

  const _ConsentRow({
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
            width: 36,
            height: 36,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
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
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
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
