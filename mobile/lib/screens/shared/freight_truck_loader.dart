import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

class MuvvLaunchLoader extends StatefulWidget {
  final double width;
  final Color routeColor;
  final Color accentColor;

  const MuvvLaunchLoader({
    super.key,
    this.width = 148,
    this.routeColor = AppTheme.primary,
    this.accentColor = AppTheme.accent,
  });

  @override
  State<MuvvLaunchLoader> createState() => _MuvvLaunchLoaderState();
}

class _MuvvLaunchLoaderState extends State<MuvvLaunchLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Preparando tu flete',
      child: SizedBox(
        width: widget.width,
        height: widget.width * 0.48,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return CustomPaint(
              painter: _MuvvLaunchPainter(
                progress: Curves.easeInOutCubic.transform(_controller.value),
                routeColor: widget.routeColor,
                accentColor: widget.accentColor,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MuvvLaunchPainter extends CustomPainter {
  final double progress;
  final Color routeColor;
  final Color accentColor;

  const _MuvvLaunchPainter({
    required this.progress,
    required this.routeColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(size.width * 0.1, size.height * 0.69);
    final end = Offset(size.width * 0.89, size.height * 0.34);
    final routePath = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(size.width * 0.47, start.dy)
      ..quadraticBezierTo(
        size.width * 0.64,
        start.dy,
        size.width * 0.7,
        end.dy,
      )
      ..lineTo(end.dx, end.dy);

    final routePaint = Paint()
      ..color = routeColor.withValues(alpha: 0.24)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.2, size.width * 0.022)
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(routePath, routePaint);

    canvas.drawCircle(
      start,
      size.width * 0.045,
      Paint()..color = accentColor.withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      start,
      size.width * 0.024,
      Paint()..color = accentColor,
    );

    final packageSize =
        size.width * (0.1 + (0.015 * math.sin(progress * math.pi)));
    final package = Rect.fromCenter(
      center: end,
      width: packageSize,
      height: packageSize,
    );
    final packagePaint = Paint()
      ..color = accentColor.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.7, size.width * 0.016)
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        package,
        Radius.circular(size.width * 0.012),
      ),
      packagePaint,
    );
    canvas.drawLine(package.topCenter, package.center, packagePaint);
    canvas.drawLine(package.center, package.bottomCenter, packagePaint);

    final metric = routePath.computeMetrics().first;
    final tangent = metric.getTangentForOffset(metric.length * progress)!;
    canvas.save();
    canvas.translate(tangent.position.dx, tangent.position.dy);
    canvas.rotate(tangent.angle);
    _paintTruck(canvas, size);
    canvas.restore();
  }

  void _paintTruck(Canvas canvas, Size size) {
    final unit = size.width * 0.07;
    final body = Paint()..color = routeColor;
    final detail = Paint()..color = Colors.white.withValues(alpha: 0.78);
    final wheel = Paint()..color = AppTheme.midnight;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-unit * 1.3, -unit * 0.64, unit * 1.2, unit * 0.75),
        Radius.circular(unit * 0.12),
      ),
      body,
    );
    final cab = Path()
      ..moveTo(-unit * 0.04, unit * 0.1)
      ..lineTo(-unit * 0.04, -unit * 0.43)
      ..lineTo(unit * 0.46, -unit * 0.43)
      ..lineTo(unit * 0.74, -unit * 0.08)
      ..lineTo(unit * 0.74, unit * 0.1)
      ..close();
    canvas.drawPath(cab, body);
    canvas.drawRect(
      Rect.fromLTWH(unit * 0.1, -unit * 0.34, unit * 0.28, unit * 0.2),
      detail,
    );
    for (final x in [-unit * 0.9, unit * 0.46]) {
      canvas.drawCircle(Offset(x, unit * 0.18), unit * 0.18, wheel);
      canvas.drawCircle(
        Offset(x, unit * 0.18),
        unit * 0.07,
        Paint()..color = Colors.white.withValues(alpha: 0.78),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MuvvLaunchPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.routeColor != routeColor ||
        oldDelegate.accentColor != accentColor;
  }
}

/// A single, non-repeating launch story. Its keyframes mirror the Muvv
/// storyboard: mark, route, journey, curve, arrival, and confirmation.
class MuvvIntroSequence extends StatefulWidget {
  const MuvvIntroSequence({super.key});

  @override
  State<MuvvIntroSequence> createState() => _MuvvIntroSequenceState();
}

class _MuvvIntroSequenceState extends State<MuvvIntroSequence>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Muvv, tu flete en movimiento',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 700;

          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final progress = _controller.value;
              final identityIn = _introStage(progress, 0, 0.13);
              final identityMove = _introStage(progress, 0.13, 0.48);
              final taglineOut = 1 - _introStage(progress, 0.55, 0.68);
              final complete = _introStage(progress, 0.84, 0.98);
              final logoAlignment = Alignment(
                _introLerp(0, -0.72, identityMove),
                _introLerp(-0.12, -0.8, identityMove),
              );
              final nameAlignment = Alignment(
                _introLerp(0, -0.28, identityMove),
                _introLerp(0.1, -0.8, identityMove),
              );
              final taglineAlignment = Alignment(
                0,
                _introLerp(0.21, -0.59, identityMove),
              );
              final identityScale = _introLerp(1, 0.58, identityMove);
              final nameScale = _introLerp(1, 0.62, identityMove);

              return Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    painter: _MuvvIntroScenePainter(progress: progress),
                  ),
                  Align(
                    alignment: logoAlignment,
                    child: Opacity(
                      opacity: identityIn,
                      child: Transform.scale(
                        scale: identityScale,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            _introLerp(22, 14, identityMove),
                          ),
                          child: Image.asset(
                            'assets/branding/muvv-app-icon.png',
                            width: compact ? 84 : 96,
                            height: compact ? 84 : 96,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: nameAlignment,
                    child: Opacity(
                      opacity: identityIn,
                      child: Transform.scale(
                        scale: nameScale,
                        child: const Text(
                          'Muvv',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: taglineAlignment,
                    child: Opacity(
                      opacity: identityIn * taglineOut,
                      child: Transform.scale(
                        scale: _introLerp(1, 0.9, identityMove),
                        child: const _IntroTagline(),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment(0, compact ? 0.5 : 0.46),
                    child: Opacity(
                      opacity: complete,
                      child: Transform.scale(
                        scale: _introLerp(0.88, 1, complete),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 62,
                              height: 62,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF4ADE80),
                                  width: 2,
                                ),
                                color: const Color(0xFF4ADE80)
                                    .withValues(alpha: 0.08),
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Color(0xFF4ADE80),
                                size: 38,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '¡Listo!',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(height: 7),
                            const _IntroTagline(finalState: true),
                            const SizedBox(height: 15),
                            Container(
                              width: 48,
                              height: 3,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1687FF),
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _IntroTagline extends StatelessWidget {
  final bool finalState;

  const _IntroTagline({this.finalState = false});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: finalState ? 'Tu flete está ' : 'Tu flete, en ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.86),
              fontSize: 15,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          TextSpan(
            text: finalState ? 'en camino.' : 'movimiento.',
            style: const TextStyle(
              color: Color(0xFF4ADE80),
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

double _introStage(double value, double start, double end) {
  if (value <= start) return 0;
  if (value >= end) return 1;
  return Curves.easeInOutCubic.transform((value - start) / (end - start));
}

double _introLerp(double begin, double end, double progress) =>
    begin + ((end - begin) * progress);

class _MuvvIntroScenePainter extends CustomPainter {
  final double progress;

  const _MuvvIntroScenePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final sceneIn = _introStage(progress, 0.16, 0.34);
    final cityOpacity = sceneIn;
    _paintCity(canvas, size, cityOpacity);

    final start = Offset(size.width * 0.03, size.height * 0.74);
    final end = Offset(size.width * 0.9, size.height * 0.56);
    final route = Path()
      ..moveTo(start.dx, start.dy)
      ..lineTo(size.width * 0.42, start.dy)
      ..quadraticBezierTo(
        size.width * 0.61,
        start.dy,
        size.width * 0.7,
        end.dy,
      )
      ..lineTo(end.dx, end.dy);
    final metric = route.computeMetrics().first;
    final journeyProgress = _introStage(progress, 0.24, 0.82);
    final routeProgress = math.min(1.0, journeyProgress + 0.085);
    final routeStroke = math.max(3.0, size.width * 0.017);

    canvas.drawPath(
      route,
      Paint()
        ..color = const Color(0xFF1269F3).withValues(alpha: 0.14 * sceneIn)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = routeStroke,
    );
    canvas.drawPath(
      metric.extractPath(0, metric.length * routeProgress),
      Paint()
        ..color = const Color(0xFF1687FF)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = routeStroke,
    );

    final destinationVisibility = _introStage(progress, 0.67, 0.78);
    if (destinationVisibility > 0) {
      _paintDestination(canvas, end, size.width, destinationVisibility);
    }

    final truckVisibility = _introStage(progress, 0.21, 0.32);
    if (truckVisibility > 0) {
      final tangent = metric.getTangentForOffset(
        metric.length * math.max(0.005, journeyProgress),
      )!;
      canvas.save();
      canvas.translate(tangent.position.dx, tangent.position.dy);
      canvas.rotate(tangent.angle);
      canvas.scale(_introLerp(0.78, 1, truckVisibility));
      _paintIntroTruck(canvas, size.width);
      canvas.restore();
      _paintMotionMarks(canvas, tangent.position, size.width, journeyProgress);
    }

    final completed = _introStage(progress, 0.9, 1);
    if (completed > 0) {
      _paintConfetti(canvas, size, completed);
    }
  }

  void _paintCity(Canvas canvas, Size size, double opacity) {
    if (opacity == 0) return;
    final paint = Paint()
      ..color = const Color(0xFF123566).withValues(alpha: 0.24 * opacity);
    final baseline = size.height * 0.74;
    final buildings = <({double x, double w, double h})>[
      (x: 0.06, w: 0.052, h: 0.08),
      (x: 0.125, w: 0.042, h: 0.12),
      (x: 0.18, w: 0.068, h: 0.2),
      (x: 0.265, w: 0.075, h: 0.13),
      (x: 0.36, w: 0.05, h: 0.09),
      (x: 0.51, w: 0.064, h: 0.15),
      (x: 0.6, w: 0.04, h: 0.23),
      (x: 0.67, w: 0.068, h: 0.17),
      (x: 0.77, w: 0.052, h: 0.12),
    ];

    for (final building in buildings) {
      final rect = Rect.fromLTWH(
        size.width * building.x,
        baseline - (size.height * building.h),
        size.width * building.w,
        size.height * building.h,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        paint,
      );
    }
  }

  void _paintDestination(
    Canvas canvas,
    Offset center,
    double width,
    double visibility,
  ) {
    final side = width * (0.092 * visibility);
    final rect = Rect.fromCenter(center: center, width: side, height: side);
    final paint = Paint()
      ..color = const Color(0xFF4ADE80).withValues(alpha: visibility)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, width * 0.012)
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(width * 0.011)),
      paint,
    );
    canvas.drawLine(rect.topCenter, rect.bottomCenter, paint);
  }

  void _paintIntroTruck(Canvas canvas, double width) {
    final unit = width * 0.065;
    final cargo = Paint()..color = const Color(0xFF1687FF);
    final cab = Paint()..color = const Color(0xFF27B8E8);
    final window = Paint()..color = const Color(0xFFC7ECFF);
    final wheel = Paint()..color = const Color(0xFF4ADE80);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-unit * 1.45, -unit * 0.62, unit * 1.32, unit * 0.8),
        Radius.circular(unit * 0.12),
      ),
      cargo,
    );
    final cabPath = Path()
      ..moveTo(-unit * 0.09, unit * 0.18)
      ..lineTo(-unit * 0.09, -unit * 0.42)
      ..lineTo(unit * 0.43, -unit * 0.42)
      ..lineTo(unit * 0.78, -unit * 0.05)
      ..lineTo(unit * 0.78, unit * 0.18)
      ..close();
    canvas.drawPath(cabPath, cab);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(unit * 0.06, -unit * 0.32, unit * 0.32, unit * 0.23),
        Radius.circular(unit * 0.04),
      ),
      window,
    );
    for (final x in [-unit * 0.98, unit * 0.48]) {
      canvas.drawCircle(Offset(x, unit * 0.2), unit * 0.2, wheel);
      canvas.drawCircle(
        Offset(x, unit * 0.2),
        unit * 0.09,
        Paint()..color = const Color(0xFF020914),
      );
    }
  }

  void _paintMotionMarks(
    Canvas canvas,
    Offset center,
    double width,
    double progress,
  ) {
    if (progress < 0.12 || progress > 0.95) return;
    final paint = Paint()
      ..color = const Color(0xFF4ADE80).withValues(alpha: 0.7)
      ..strokeWidth = math.max(1.5, width * 0.008)
      ..strokeCap = StrokeCap.round;
    final offset = width * 0.065;
    canvas.drawLine(
      Offset(center.dx - offset * 1.8, center.dy + offset * 0.8),
      Offset(center.dx - offset, center.dy + offset * 0.8),
      paint,
    );
    canvas.drawLine(
      Offset(center.dx - offset * 2.55, center.dy + offset * 0.8),
      Offset(center.dx - offset * 2.1, center.dy + offset * 0.8),
      paint,
    );
  }

  void _paintConfetti(Canvas canvas, Size size, double visibility) {
    final paint = Paint()..style = PaintingStyle.fill;
    final pieces = <({double x, double y, Color color})>[
      (x: 0.17, y: 0.34, color: const Color(0xFF4ADE80)),
      (x: 0.28, y: 0.24, color: const Color(0xFF1687FF)),
      (x: 0.43, y: 0.31, color: const Color(0xFF4ADE80)),
      (x: 0.57, y: 0.2, color: const Color(0xFF1687FF)),
      (x: 0.73, y: 0.3, color: const Color(0xFF4ADE80)),
      (x: 0.84, y: 0.23, color: const Color(0xFF1687FF)),
    ];
    for (final piece in pieces) {
      paint.color = piece.color.withValues(alpha: visibility);
      final x = size.width * piece.x;
      final y = size.height * (piece.y + ((1 - visibility) * 0.08));
      final path = Path()
        ..moveTo(x, y - 4)
        ..lineTo(x + 3.5, y + 3)
        ..lineTo(x - 3.5, y + 3)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MuvvIntroScenePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class FreightTruckLoader extends StatefulWidget {
  final String label;
  final bool showLabel;
  final double width;
  final Color color;
  final Color? fillColor;
  final Color? trackColor;
  final Color? textColor;

  const FreightTruckLoader({
    super.key,
    this.label = 'Cargando',
    this.showLabel = true,
    this.width = 132,
    this.color = AppTheme.primary,
    this.fillColor,
    this.trackColor,
    this.textColor,
  });

  @override
  State<FreightTruckLoader> createState() => _FreightTruckLoaderState();
}

class _FreightTruckLoaderState extends State<FreightTruckLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fillColor = widget.fillColor ?? widget.color;
    final trackColor =
        widget.trackColor ?? widget.color.withValues(alpha: 0.12);
    final textColor = widget.textColor ?? AppTheme.slate600;

    return Semantics(
      label: widget.label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: widget.width,
            height: widget.width * 0.54,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final value = _controller.value;
                final progress = Curves.easeInOutCubic.transform(value);
                final pulse = 0.55 + 0.45 * math.sin(value * math.pi).abs();

                return CustomPaint(
                  painter: _FreightTruckPainter(
                    progress: progress,
                    pulse: pulse,
                    color: widget.color,
                    fillColor: fillColor,
                    trackColor: trackColor,
                  ),
                );
              },
            ),
          ),
          if (widget.showLabel) ...[
            const SizedBox(height: 10),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final dots = (_controller.value * 4).floor() % 4;
                return Text(
                  '${widget.label}${'.' * dots}',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _FreightTruckPainter extends CustomPainter {
  final double progress;
  final double pulse;
  final Color color;
  final Color fillColor;
  final Color trackColor;

  const _FreightTruckPainter({
    required this.progress,
    required this.pulse,
    required this.color,
    required this.fillColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = math.max(1.6, w * 0.018);
    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final softFill = Paint()
      ..color = trackColor
      ..style = PaintingStyle.fill;
    final cargoFill = Paint()
      ..color = fillColor.withValues(alpha: 0.18 + (0.16 * pulse))
      ..style = PaintingStyle.fill;

    final cargoRect = Rect.fromLTWH(w * 0.08, h * 0.24, w * 0.54, h * 0.38);
    final cargoRRect = RRect.fromRectAndRadius(
      cargoRect,
      Radius.circular(w * 0.035),
    );

    canvas.drawRRect(cargoRRect, softFill);

    final innerCargo = cargoRect.deflate(stroke * 1.55);
    final fillRect = Rect.fromLTWH(
      innerCargo.left,
      innerCargo.top,
      innerCargo.width * progress,
      innerCargo.height,
    );
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(innerCargo, Radius.circular(w * 0.025)),
    );
    canvas.drawRect(fillRect, cargoFill);

    final stripePaint = Paint()
      ..color = fillColor.withValues(alpha: 0.16)
      ..strokeWidth = stroke * 0.8
      ..strokeCap = StrokeCap.round;
    for (var x = innerCargo.left - innerCargo.height;
        x < fillRect.right;
        x += innerCargo.height * 0.52) {
      canvas.drawLine(
        Offset(x, innerCargo.bottom),
        Offset(x + innerCargo.height, innerCargo.top),
        stripePaint,
      );
    }
    canvas.restore();

    canvas.drawRRect(cargoRRect, outline);

    final cabPath = Path()
      ..moveTo(w * 0.64, h * 0.62)
      ..lineTo(w * 0.64, h * 0.38)
      ..quadraticBezierTo(w * 0.64, h * 0.31, w * 0.71, h * 0.31)
      ..lineTo(w * 0.76, h * 0.31)
      ..lineTo(w * 0.87, h * 0.45)
      ..lineTo(w * 0.87, h * 0.62)
      ..close();
    canvas.drawPath(cabPath, softFill);
    canvas.drawPath(cabPath, outline);

    final windowPath = Path()
      ..moveTo(w * 0.70, h * 0.38)
      ..lineTo(w * 0.76, h * 0.38)
      ..lineTo(w * 0.82, h * 0.46)
      ..lineTo(w * 0.70, h * 0.46)
      ..close();
    canvas.drawPath(
      windowPath,
      Paint()
        ..color = color.withValues(alpha: 0.16)
        ..style = PaintingStyle.fill,
    );

    canvas.drawLine(
      Offset(w * 0.06, h * 0.66),
      Offset(w * 0.91, h * 0.66),
      outline,
    );

    _drawWheel(canvas, Offset(w * 0.25, h * 0.70), w * 0.062, outline);
    _drawWheel(canvas, Offset(w * 0.72, h * 0.70), w * 0.062, outline);

    final road = Paint()
      ..color = color.withValues(alpha: 0.18)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(w * 0.12, h * 0.86), Offset(w * 0.32, h * 0.86), road);
    canvas.drawLine(
        Offset(w * 0.44, h * 0.86), Offset(w * 0.60, h * 0.86), road);
    canvas.drawLine(
        Offset(w * 0.70, h * 0.86), Offset(w * 0.84, h * 0.86), road);
  }

  void _drawWheel(Canvas canvas, Offset center, double radius, Paint outline) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = AppTheme.surface
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(center, radius, outline);
    canvas.drawCircle(
      center,
      radius * 0.34,
      Paint()
        ..color = outline.color.withValues(alpha: 0.18)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _FreightTruckPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.pulse != pulse ||
        oldDelegate.color != color ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.trackColor != trackColor;
  }
}
