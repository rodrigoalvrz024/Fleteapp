import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

class AuthBackdrop extends StatelessWidget {
  final Widget child;
  final double overlayStrength;

  const AuthBackdrop({
    super.key,
    required this.child,
    this.overlayStrength = 0.62,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 1400),
          curve: Curves.easeOutCubic,
          tween: Tween(begin: 1.045, end: 1),
          builder: (context, scale, image) => Transform.scale(
            scale: scale,
            child: image,
          ),
          child: Image.asset(
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
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.black.withValues(alpha: overlayStrength + 0.12),
                const Color(0xFF052A3B).withValues(alpha: overlayStrength),
                Colors.black.withValues(alpha: overlayStrength - 0.08),
              ],
              stops: const [0, 0.56, 1],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class MobileAuthPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final bool showRouteMotif;

  const MobileAuthPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.showRouteMotif = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: ColoredBox(
        color: const Color(0xFFF8FAFC),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const _MobileMuvvWordmark(),
                      const SizedBox(height: 28),
                      Container(
                        width: 32,
                        height: 3,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppTheme.midnight,
                          fontSize: 28,
                          height: 1.12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppTheme.slate600,
                          fontSize: 14,
                          height: 1.35,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 22),
                      child,
                      if (showRouteMotif) ...[
                        const SizedBox(height: 22),
                        const Center(child: _MobileRouteMotif()),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MobileMuvvWordmark extends StatelessWidget {
  const _MobileMuvvWordmark();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset(
            'assets/branding/muvv-app-icon.png',
            width: 32,
            height: 32,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 9),
        const Text(
          'Muvv',
          style: TextStyle(
            color: AppTheme.midnight,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _MobileRouteMotif extends StatelessWidget {
  const _MobileRouteMotif();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 216,
        height: 54,
        child: CustomPaint(painter: _MobileRouteMotifPainter()),
      ),
    );
  }
}

class _MobileRouteMotifPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final route = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(14, size.height * 0.72)
      ..lineTo(size.width * 0.5, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.64,
        size.height * 0.72,
        size.width * 0.71,
        size.height * 0.38,
      )
      ..lineTo(size.width - 22, size.height * 0.38);
    canvas.drawPath(path, route);

    canvas.drawCircle(
      const Offset(14, 39),
      7,
      Paint()..color = AppTheme.accent.withValues(alpha: 0.35),
    );
    canvas.drawCircle(
      const Offset(14, 39),
      3.5,
      Paint()..color = AppTheme.accent,
    );

    final cube = Rect.fromCenter(
      center: Offset(size.width - 18, size.height * 0.38),
      width: 18,
      height: 18,
    );
    final cubePaint = Paint()
      ..color = AppTheme.primary.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(cube, const Radius.circular(3)),
      cubePaint,
    );
    canvas.drawLine(cube.topLeft, cube.bottomRight, cubePaint);
  }

  @override
  bool shouldRepaint(covariant _MobileRouteMotifPainter oldDelegate) => false;
}

class AuthReveal extends StatelessWidget {
  final Widget child;
  final double delay;
  final double offsetY;

  const AuthReveal({
    super.key,
    required this.child,
    this.delay = 0,
    this.offsetY = 22,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 820),
      curve: Interval(delay.clamp(0, 0.7), 1, curve: Curves.easeOutCubic),
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, content) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, offsetY * (1 - value)),
            child: Transform.scale(
              scale: 0.985 + (0.015 * value),
              alignment: Alignment.center,
              child: content,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class FloatingAuthPanel extends StatelessWidget {
  final Widget child;
  final bool flat;

  const FloatingAuthPanel({
    super.key,
    required this.child,
    this.flat = false,
  });

  @override
  Widget build(BuildContext context) {
    if (flat) return child;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.72),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 54,
                spreadRadius: -12,
                offset: const Offset(0, 28),
              ),
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.12),
                blurRadius: 36,
                spreadRadius: -16,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class AuthPanelAccent extends StatelessWidget {
  const AuthPanelAccent({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 46,
        height: 4,
        decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
