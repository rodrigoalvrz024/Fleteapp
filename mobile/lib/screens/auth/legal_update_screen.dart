import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';

class LegalUpdateScreen extends ConsumerStatefulWidget {
  const LegalUpdateScreen({super.key});

  @override
  ConsumerState<LegalUpdateScreen> createState() => _LegalUpdateScreenState();
}

class _LegalUpdateScreenState extends ConsumerState<LegalUpdateScreen> {
  bool _acceptTerms = false;
  bool _acceptPrivacy = false;

  Future<void> _continue() async {
    if (!_acceptTerms || !_acceptPrivacy) return;
    final accepted = await ref.read(authProvider.notifier).acceptLegalUpdate();
    if (!mounted || !accepted) return;
    switch (ref.read(authProvider).user?.role) {
      case 'admin':
        context.go('/admin');
      case 'driver':
        context.go('/app/driver');
      default:
        context.go('/app/client');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        automaticallyImplyLeading: false,
        title: const Text(
          'Actualizacion de privacidad',
          style:
              TextStyle(color: AppTheme.midnight, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.shield_outlined,
                      color: AppTheme.primary, size: 30),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Antes de continuar',
                  style: TextStyle(
                    color: AppTheme.midnight,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Actualizamos nuestros documentos para explicar mejor como protegemos la operacion, incluidos los controles limitados ante fraude, incidentes o coordinacion de fletes fuera de Muvv.',
                  style: TextStyle(
                    color: AppTheme.slate600,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 25),
                _ConsentTile(
                  value: _acceptTerms,
                  title: 'Acepto los Terminos y condiciones',
                  onChanged: (value) => setState(() => _acceptTerms = value),
                  onView: () => context.push('/legal/terms'),
                ),
                const SizedBox(height: 10),
                _ConsentTile(
                  value: _acceptPrivacy,
                  title: 'Acepto la Politica de privacidad',
                  onChanged: (value) => setState(() => _acceptPrivacy = value),
                  onView: () => context.push('/legal/privacy'),
                ),
                if (auth.error != null) ...[
                  const SizedBox(height: 14),
                  Text(auth.error!,
                      style: const TextStyle(color: AppTheme.error)),
                ],
                const SizedBox(height: 26),
                SizedBox(
                  height: 54,
                  child: FilledButton(
                    onPressed:
                        auth.isLoading || !_acceptTerms || !_acceptPrivacy
                            ? null
                            : _continue,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: auth.isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.4,
                            ),
                          )
                        : const Text(
                            'Aceptar y continuar',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConsentTile extends StatelessWidget {
  final bool value;
  final String title;
  final ValueChanged<bool> onChanged;
  final VoidCallback onView;

  const _ConsentTile({
    required this.value,
    required this.title,
    required this.onChanged,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.slate200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Checkbox(
                value: value, onChanged: (next) => onChanged(next ?? false)),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                    color: AppTheme.midnight, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(onPressed: onView, child: const Text('Ver')),
          ],
        ),
      );
}
