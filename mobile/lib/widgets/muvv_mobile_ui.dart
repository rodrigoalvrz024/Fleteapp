import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';

class MuvvGradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool compact;

  const MuvvGradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: enabled ? AppTheme.primaryGradient : null,
            color: enabled ? null : AppTheme.slate200,
            borderRadius: BorderRadius.circular(compact ? 14 : 17),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.20),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(compact ? 14 : 17),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: compact ? 46 : 54),
              child: Center(
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 20, color: Colors.white),
                            const SizedBox(width: 9),
                          ],
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MuvvSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final bool emphasized;

  const MuvvSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.borderColor,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: borderColor ?? AppTheme.slate200,
        width: emphasized ? 1.2 : 0.8,
      ),
      boxShadow: [
        BoxShadow(
          color: AppTheme.midnight.withValues(alpha: emphasized ? 0.08 : 0.035),
          blurRadius: emphasized ? 22 : 14,
          offset: const Offset(0, 7),
        ),
      ],
    );
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: decoration,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class MuvvSectionHeader extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const MuvvSectionHeader({
    super.key,
    required this.title,
    this.eyebrow = '',
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow.isNotEmpty) ...[
                  Text(
                    eyebrow.toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.midnight,
                    fontSize: 20,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: Text(
                actionLabel!,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      );
}

class MuvvStatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const MuvvStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  factory MuvvStatusPill.fromFreight(String status) => MuvvStatusPill(
        label: AppTheme.statusLabel(status),
        color: AppTheme.statusColor(status),
      );

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      );
}

class MuvvRouteStops extends StatelessWidget {
  final String origin;
  final String destination;
  final bool compact;

  const MuvvRouteStops({
    super.key,
    required this.origin,
    required this.destination,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 18.0 : 21.0;
    final textSize = compact ? 13.0 : 14.0;
    return Column(
      children: [
        _RouteStop(
          icon: Icons.radio_button_checked_rounded,
          color: const Color(0xFF11B981),
          label: 'RETIRO',
          value: origin,
          iconSize: iconSize,
          textSize: textSize,
        ),
        Padding(
          padding: EdgeInsets.only(left: (iconSize / 2) - 0.5),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              height: compact ? 12 : 16,
              width: 1.5,
              color: AppTheme.slate200,
            ),
          ),
        ),
        _RouteStop(
          icon: Icons.location_on_rounded,
          color: const Color(0xFFFF5263),
          label: 'DESTINO',
          value: destination,
          iconSize: iconSize,
          textSize: textSize,
        ),
      ],
    );
  }
}

class _RouteStop extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final double iconSize;
  final double textSize;

  const _RouteStop({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.iconSize,
    required this.textSize,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: iconSize, color: color),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.slate400,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.55,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.midnight,
                    fontSize: textSize,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class MuvvPriceCard extends StatelessWidget {
  final String amount;
  final String caption;
  final String? detail;

  const MuvvPriceCard({
    super.key,
    required this.amount,
    required this.caption,
    this.detail,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF0F5FF), Color(0xFFF8FBFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: AppTheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    caption,
                    style: const TextStyle(
                      color: AppTheme.slate600,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    amount,
                    style: const TextStyle(
                      color: AppTheme.midnight,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail!,
                      style: const TextStyle(
                        color: AppTheme.slate400,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
}

class MuvvBottomNavigation extends StatelessWidget {
  final MuvvNavigationSection selected;
  final bool driver;

  const MuvvBottomNavigation({
    super.key,
    required this.selected,
    this.driver = false,
  });

  @override
  Widget build(BuildContext context) {
    final items = driver
        ? const [
            _MuvvNavItem(MuvvNavigationSection.home, 'Inicio',
                Icons.map_outlined, '/app/driver'),
            _MuvvNavItem(MuvvNavigationSection.activity, 'Viajes',
                Icons.route_outlined, '/app/driver/trips'),
            _MuvvNavItem(MuvvNavigationSection.wallet, 'Ganancias',
                Icons.account_balance_wallet_outlined, '/app/driver/payouts'),
            _MuvvNavItem(MuvvNavigationSection.profile, 'Perfil',
                Icons.person_outline_rounded, '/app/driver/account'),
          ]
        : const [
            _MuvvNavItem(MuvvNavigationSection.home, 'Inicio',
                Icons.home_outlined, '/app/client'),
            _MuvvNavItem(MuvvNavigationSection.activity, 'Mis fletes',
                Icons.local_shipping_outlined, '/app/client/freights'),
            _MuvvNavItem(MuvvNavigationSection.wallet, 'Pagos',
                Icons.credit_card_outlined, '/app/client/payments'),
            _MuvvNavItem(MuvvNavigationSection.profile, 'Perfil',
                Icons.person_outline_rounded, '/app/client/account'),
          ];
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.slate200),
          boxShadow: [
            BoxShadow(
              color: AppTheme.midnight.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            for (final item in items)
              Expanded(
                child: _MuvvBottomNavigationItem(
                  item: item,
                  selected: item.section == selected,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum MuvvNavigationSection { home, activity, wallet, profile }

class _MuvvNavItem {
  final MuvvNavigationSection section;
  final String label;
  final IconData icon;
  final String route;

  const _MuvvNavItem(this.section, this.label, this.icon, this.route);
}

class _MuvvBottomNavigationItem extends StatelessWidget {
  final _MuvvNavItem item;
  final bool selected;

  const _MuvvBottomNavigationItem({required this.item, required this.selected});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => context.go(item.route),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.primary.withValues(alpha: 0.11)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  item.icon,
                  size: 20,
                  color: selected ? AppTheme.primary : AppTheme.slate400,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? AppTheme.primary : AppTheme.slate400,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
}
