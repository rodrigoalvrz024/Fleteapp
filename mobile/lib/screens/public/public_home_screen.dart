import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

class PublicHomeScreen extends StatelessWidget {
  const PublicHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final compact = width < 760;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _PublicHero(compact: compact),
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 20 : 32,
                    28,
                    compact ? 20 : 32,
                    44,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PathSelector(compact: compact),
                      const SizedBox(height: 28),
                      _TrustStrip(compact: compact),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicHero extends StatelessWidget {
  final bool compact;

  const _PublicHero({required this.compact});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: compact ? 560 : 620),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            'https://images.unsplash.com/photo-1601584115197-04ecc0da31d7'
            '?auto=format&fit=crop&w=1800&q=80',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: AppTheme.midnight,
              alignment: Alignment.center,
              child: const Icon(
                Icons.local_shipping_rounded,
                color: Colors.white,
                size: 88,
              ),
            ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.46)),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 20 : 32,
                    18,
                    compact ? 20 : 32,
                    34,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PublicNav(compact: compact),
                      const Spacer(),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'FleteApp',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 56,
                                  fontWeight: FontWeight.w800,
                                  height: 0.98,
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Fletes urbanos con conductores verificados, '
                                'seguimiento operativo y respaldo documental '
                                'desde el primer viaje.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.88),
                                  fontSize: compact ? 18 : 21,
                                  height: 1.45,
                                ),
                              ),
                              const SizedBox(height: 28),
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _HeroAction(
                                    label: 'Entrar a la app',
                                    icon: Icons.arrow_forward_rounded,
                                    filled: true,
                                    onTap: () => context.go('/auth/login'),
                                  ),
                                  _HeroAction(
                                    label: 'Crear cuenta',
                                    icon: Icons.person_add_alt_1_rounded,
                                    filled: false,
                                    onTap: () => context.go('/auth/register'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 44),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PublicNav extends StatelessWidget {
  final bool compact;

  const _PublicNav({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: const Icon(
            Icons.local_shipping_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'FleteApp',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        if (!compact) ...[
          _NavLink(label: 'Cliente', onTap: () => context.go('/auth/register')),
          _NavLink(
            label: 'Conductor',
            onTap: () => context.go('/auth/register'),
          ),
          _NavLink(label: 'Admin', onTap: () => context.go('/admin')),
        ],
        TextButton.icon(
          onPressed: () => context.go('/auth/login'),
          icon: const Icon(Icons.login_rounded, size: 18),
          label: const Text('Ingresar'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _NavLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _NavLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white.withValues(alpha: 0.86),
        ),
        child: Text(label),
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _HeroAction({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: filled
          ? ElevatedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18),
              label: Text(label),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.midnight,
              ),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(icon, size: 18),
              label: Text(label),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 48),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.72)),
              ),
            ),
    );
  }
}

class _PathSelector extends StatelessWidget {
  final bool compact;

  const _PathSelector({required this.compact});

  @override
  Widget build(BuildContext context) {
    final items = [
      _WebPath(
        title: 'Web publica',
        description: 'Presentacion, confianza, terminos y entrada comercial.',
        icon: Icons.language_rounded,
        action: 'Ver inicio',
        onTap: () => context.go('/'),
      ),
      _WebPath(
        title: 'App cliente/conductor',
        description: 'Solicitudes, viajes, perfil, onboarding y operacion.',
        icon: Icons.apps_rounded,
        action: 'Entrar a la app',
        onTap: () => context.go('/auth/login'),
      ),
      _WebPath(
        title: 'Panel admin',
        description: 'Metricas, aprobaciones, documentos, historial y alertas.',
        icon: Icons.admin_panel_settings_rounded,
        action: 'Ir al admin',
        onTap: () => context.go('/admin'),
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: compact ? 1 : 3,
        mainAxisExtent: 206,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemBuilder: (_, index) => items[index],
    );
  }
}

class _WebPath extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final String action;
  final VoidCallback onTap;

  const _WebPath({
    required this.title,
    required this.description,
    required this.icon,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.slate200, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppTheme.primary, size: 30),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.midnight,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                color: AppTheme.slate600,
                fontSize: 13,
                height: 1.38,
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.arrow_forward_rounded, size: 17),
              label: Text(action),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
                padding: EdgeInsets.zero,
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrustStrip extends StatelessWidget {
  final bool compact;

  const _TrustStrip({required this.compact});

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Documentos privados', Icons.verified_user_outlined),
      ('Conductores revisados', Icons.badge_outlined),
      ('Historial auditable', Icons.manage_search_rounded),
      ('Panel operacional', Icons.monitor_heart_outlined),
    ];

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: compact ? 8 : 14,
      runSpacing: 10,
      children: [
        for (final item in items)
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppTheme.slate100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.slate200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.$2, size: 18, color: AppTheme.slate600),
                const SizedBox(width: 8),
                Text(
                  item.$1,
                  style: const TextStyle(
                    color: AppTheme.slate600,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
