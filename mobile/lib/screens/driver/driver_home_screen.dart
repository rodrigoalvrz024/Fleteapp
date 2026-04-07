import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';

class DriverHomeScreen extends ConsumerWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Panel Conductor'),
        actions: [
          IconButton(
              icon: const Icon(Icons.person_outline),
              onPressed: () => context.push('/profile')),
          IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              }),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF1B5E20), Color(0xFF388E3C)]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                const Icon(Icons.drive_eta, color: Colors.white, size: 40),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                      'Hola, ${user?.fullName.split(' ').first ?? 'Conductor'} 👋',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const Text('Modo conductor activo',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ]),
              ]),
            ),
            const SizedBox(height: 28),
            const Text('Acciones',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            _DriverAction(
                icon: Icons.search,
                label: 'Ver fletes disponibles',
                subtitle: 'Acepta nuevos trabajos',
                onTap: () => context.push('/driver/available'),
                color: AppTheme.primary),
            const SizedBox(height: 10),
            _DriverAction(
                icon: Icons.history,
                label: 'Mis viajes',
                subtitle: 'Fletes aceptados y completados',
                onTap: () => context.push('/driver/available'),
                color: AppTheme.accent),
          ],
        ),
      ),
    );
  }
}

class _DriverAction extends StatelessWidget {
  final IconData icon;
  final String label, subtitle;
  final VoidCallback onTap;
  final Color color;
  const _DriverAction(
      {required this.icon,
      required this.label,
      required this.subtitle,
      required this.onTap,
      required this.color});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
              ]),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle),
                child: Icon(icon, color: color)),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                ])),
            const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
          ]),
        ),
      );
}
