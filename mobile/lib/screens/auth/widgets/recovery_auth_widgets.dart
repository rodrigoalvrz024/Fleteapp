import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';

const _publicHomeUrl = String.fromEnvironment(
  'PUBLIC_HOME_URL',
  defaultValue: 'https://fleteapp-public-8d8f7.web.app',
);

Future<void> _openPublicHome() async {
  await launchUrl(Uri.parse(_publicHomeUrl), webOnlyWindowName: '_self');
}

class RecoveryAuthScaffold extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final String panelTitle;
  final String panelSubtitle;
  final IconData panelIcon;
  final Widget child;

  const RecoveryAuthScaffold({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.panelTitle,
    required this.panelSubtitle,
    required this.panelIcon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.midnight,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 860;
          final horizontalPadding = compact ? 20.0 : 36.0;
          final topBottomPadding = compact ? 18.0 : 26.0;

          return Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/images/hero-truck.jpg',
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
              Container(color: Colors.black.withValues(alpha: 0.6)),
              SafeArea(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight -
                          MediaQuery.paddingOf(context).top -
                          MediaQuery.paddingOf(context).bottom,
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        topBottomPadding,
                        horizontalPadding,
                        topBottomPadding,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1180),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _RecoveryNav(compact: compact),
                              SizedBox(height: compact ? 42 : 78),
                              compact
                                  ? _CompactLayout(
                                      eyebrow: eyebrow,
                                      title: title,
                                      subtitle: subtitle,
                                      panelTitle: panelTitle,
                                      panelSubtitle: panelSubtitle,
                                      panelIcon: panelIcon,
                                      child: child,
                                    )
                                  : _DesktopLayout(
                                      eyebrow: eyebrow,
                                      title: title,
                                      subtitle: subtitle,
                                      panelTitle: panelTitle,
                                      panelSubtitle: panelSubtitle,
                                      panelIcon: panelIcon,
                                      child: child,
                                    ),
                              SizedBox(height: compact ? 28 : 44),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RecoveryNav extends StatelessWidget {
  final bool compact;

  const _RecoveryNav({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _BrandMark(),
        const Spacer(),
        if (!compact)
          TextButton(
            onPressed: _openPublicHome,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.86),
            ),
            child: const Text('Inicio'),
          ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: () => context.go('/auth/login'),
          icon: const Icon(Icons.login_rounded, size: 18),
          label: const Text('Ingresar'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.66)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
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
          'muvv',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final String panelTitle;
  final String panelSubtitle;
  final IconData panelIcon;
  final Widget child;

  const _DesktopLayout({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.panelTitle,
    required this.panelSubtitle,
    required this.panelIcon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _RecoveryHeroCopy(
            eyebrow: eyebrow,
            title: title,
            subtitle: subtitle,
          ),
        ),
        const SizedBox(width: 56),
        SizedBox(
          width: 448,
          child: RecoveryPanel(
            title: panelTitle,
            subtitle: panelSubtitle,
            icon: panelIcon,
            child: child,
          ),
        ),
      ],
    );
  }
}

class _CompactLayout extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final String panelTitle;
  final String panelSubtitle;
  final IconData panelIcon;
  final Widget child;

  const _CompactLayout({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.panelTitle,
    required this.panelSubtitle,
    required this.panelIcon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RecoveryHeroCopy(
          eyebrow: eyebrow,
          title: title,
          subtitle: subtitle,
          compact: true,
        ),
        const SizedBox(height: 28),
        RecoveryPanel(
          title: panelTitle,
          subtitle: panelSubtitle,
          icon: panelIcon,
          child: child,
        ),
      ],
    );
  }
}

class _RecoveryHeroCopy extends StatelessWidget {
  final String eyebrow;
  final String title;
  final String subtitle;
  final bool compact;

  const _RecoveryHeroCopy({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 620 : 680),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow.toUpperCase(),
            style: TextStyle(
              color: AppTheme.accent,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 42 : 64,
              fontWeight: FontWeight.w900,
              height: 1.02,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: compact ? 16 : 20,
              height: 1.45,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 24),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _TrustBadge(
                icon: Icons.lock_outline_rounded,
                label: 'Acceso protegido',
              ),
              _TrustBadge(
                icon: Icons.mail_outline_rounded,
                label: 'Correo verificado',
              ),
              _TrustBadge(
                icon: Icons.manage_search_rounded,
                label: 'Historial auditable',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrustBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustBadge({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.88), size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class RecoveryPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  const RecoveryPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.38)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppTheme.primaryDark, size: 24),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                color: AppTheme.midnight,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1.05,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppTheme.slate600,
                fontSize: 15,
                height: 1.4,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 22),
            child,
          ],
        ),
      ),
    );
  }
}

class RecoveryAuthField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onFieldSubmitted;

  const RecoveryAuthField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.suffix,
    this.validator,
    this.onFieldSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
      style: const TextStyle(
        color: AppTheme.midnight,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppTheme.background,
        prefixIcon: Icon(icon, color: AppTheme.slate600, size: 20),
        suffixIcon: suffix,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.slate200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.slate200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.error, width: 1.0),
        ),
      ),
    );
  }
}

class RecoveryPrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isLoading;
  final VoidCallback? onPressed;

  const RecoveryPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : Icon(icon, size: 20),
      label: Text(isLoading ? 'Procesando' : label),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.62),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class RecoveryStatusMessage extends StatelessWidget {
  final String message;
  final bool isError;

  const RecoveryStatusMessage({
    super.key,
    required this.message,
    required this.isError,
  });

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppTheme.error : AppTheme.success;
    final icon = isError
        ? Icons.error_outline_rounded
        : Icons.check_circle_outline_rounded;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 13,
                height: 1.35,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
