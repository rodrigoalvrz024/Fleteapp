import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';

class ClientHomeScreen extends ConsumerWidget {
  const ClientHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('FleteApp'),
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
            // Bienvenida
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppTheme.primary, AppTheme.secondary]),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Hola, ${user?.fullName.split(' ').first ?? 'Cliente'} 👋',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('¿Qué necesitas mover hoy?',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ),
            const SizedBox(height: 28),

            const Text('Acciones rápidas',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                    child: _QuickAction(
                        icon: Icons.add_circle_outline,
                        label: 'Solicitar flete',
                        color: AppTheme.primary,
                        onTap: () => context.push('/client/create-freight'))),
                const SizedBox(width: 12),
                Expanded(
                    child: _QuickAction(
                        icon: Icons.history,
                        label: 'Mis fletes',
                        color: AppTheme.accent,
                        onTap: () => context.push('/client/freights'))),
              ],
            ),
            const SizedBox(height: 28),

            const Text('¿Cómo funciona?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            const _StepCard(
                number: '1',
                title: 'Solicita tu flete',
                desc: 'Indica origen, destino y tipo de carga'),
            const SizedBox(height: 10),
            const _StepCard(
                number: '2',
                title: 'Un conductor acepta',
                desc: 'Recibirás confirmación inmediata'),
            const SizedBox(height: 10),
            const _StepCard(
                number: '3',
                title: 'Sigue tu envío',
                desc: 'Monitorea el estado en tiempo real'),
            const SizedBox(height: 10),
            const _StepCard(
                number: '4',
                title: 'Paga y califica',
                desc: 'Pago seguro con Webpay o efectivo'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/client/create-freight'),
        backgroundColor: AppTheme.accent,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo flete'),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QuickAction(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
              ]),
          child: Column(children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 13),
                textAlign: TextAlign.center),
          ]),
        ),
      );
}

class _StepCard extends StatelessWidget {
  final String number, title, desc;
  const _StepCard(
      {required this.number, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE8EAF0))),
        child: Row(children: [
          CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.primary,
              child: Text(number,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold))),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text(desc,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
              ])),
        ]),
      );
}
