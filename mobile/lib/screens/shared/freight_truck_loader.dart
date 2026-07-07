import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

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
