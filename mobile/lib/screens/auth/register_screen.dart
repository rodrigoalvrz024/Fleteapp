import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';

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

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref.read(authProvider.notifier).register(
          _emailCtrl.text.trim(),
          _phoneCtrl.text.trim(),
          _nameCtrl.text.trim(),
          _passCtrl.text,
          _role,
        );
    if (!mounted) return;
    if (ok) context.go(_role == 'driver' ? '/driver' : '/client');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (auth.error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFFEBEE),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(auth.error!,
                      style:
                          const TextStyle(color: AppTheme.error, fontSize: 13)),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Nombre completo',
                    prefixIcon: Icon(Icons.person_outline)),
                validator: (v) =>
                    (v?.length ?? 0) > 2 ? null : 'Ingresa tu nombre',
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: Icon(Icons.email_outlined)),
                validator: (v) =>
                    (v?.contains('@') ?? false) ? null : 'Correo inválido',
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Teléfono (+56...)',
                    prefixIcon: Icon(Icons.phone_outlined)),
                validator: (v) =>
                    (v?.length ?? 0) >= 9 ? null : 'Teléfono inválido',
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure)),
                ),
                validator: (v) =>
                    (v?.length ?? 0) >= 8 ? null : 'Mínimo 8 caracteres',
              ),
              const SizedBox(height: 20),
              const Text('Tipo de cuenta',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                      child: _RoleCard(
                          label: 'Cliente',
                          icon: Icons.person,
                          value: 'client',
                          selected: _role == 'client',
                          onTap: () => setState(() => _role = 'client'))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _RoleCard(
                          label: 'Conductor',
                          icon: Icons.drive_eta,
                          value: 'driver',
                          selected: _role == 'driver',
                          onTap: () => setState(() => _role = 'driver'))),
                ],
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: auth.isLoading ? null : _register,
                child: auth.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Crear cuenta'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard(
      {required this.label,
      required this.icon,
      required this.value,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: selected ? AppTheme.primary : const Color(0xFFE0E0E0),
                width: selected ? 2 : 1),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected ? Colors.white : AppTheme.textSecondary,
                  size: 28),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppTheme.textPrimary)),
            ],
          ),
        ),
      );
}
