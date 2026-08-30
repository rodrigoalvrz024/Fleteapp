import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/driver_provider.dart';

class DriverAppBarActions extends ConsumerWidget {
  const DriverAppBarActions({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(driverProvider.notifier).goOffline();
    await ref.read(authProvider.notifier).logout();
    if (context.mounted) context.go('/auth/login');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Inicio',
          child: IconButton(
            onPressed: () => context.go('/app/driver'),
            icon: const Icon(Icons.home_outlined),
          ),
        ),
        Tooltip(
          message: 'Perfil',
          child: IconButton(
            onPressed: () => context.push('/app/driver/account'),
            icon: const Icon(Icons.person_outline_rounded),
          ),
        ),
        Tooltip(
          message: 'Cerrar sesion',
          child: IconButton(
            onPressed: () => _logout(context, ref),
            color: AppTheme.error,
            icon: const Icon(Icons.logout_rounded),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
