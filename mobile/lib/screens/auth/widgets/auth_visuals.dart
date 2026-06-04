import 'dart:ui';

import 'package:flutter/material.dart';

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

  const FloatingAuthPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
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
