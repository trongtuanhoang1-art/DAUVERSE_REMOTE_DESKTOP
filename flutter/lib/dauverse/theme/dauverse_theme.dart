import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';

class DauversePalette {
  final bool isDark;
  final Color bg;
  final Color sidebarBg;
  final Color surface;
  final Color surfaceElevated;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color cyan;
  final Color blue;
  final Color purple;
  final Color success;
  final Color warning;
  final Color danger;

  const DauversePalette({
    required this.isDark,
    required this.bg,
    required this.sidebarBg,
    required this.surface,
    required this.surfaceElevated,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.cyan,
    required this.blue,
    required this.purple,
    required this.success,
    required this.warning,
    required this.danger,
  });

  static const dark = DauversePalette(
    isDark: true,
    bg: Color(0xFF070B14),
    sidebarBg: Color(0xFF0B1120),
    surface: Color(0xFF111827),
    surfaceElevated: Color(0xFF182235),
    border: Color(0xFF23324B),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF94A3B8),
    cyan: Color(0xFF06B6D4),
    blue: Color(0xFF3B82F6),
    purple: Color(0xFF8B5CF6),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
    danger: Color(0xFFEF4444),
  );

  static const light = DauversePalette(
    isDark: false,
    bg: Color(0xFFF1F5F9),
    sidebarBg: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceElevated: Color(0xFFF8FAFC),
    border: Color(0xFFCBD5E1),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    cyan: Color(0xFF0891B2),
    blue: Color(0xFF2563EB),
    purple: Color(0xFF7C3AED),
    success: Color(0xFF059669),
    warning: Color(0xFFD97706),
    danger: Color(0xFFDC2626),
  );

  static DauversePalette of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  LinearGradient get brandGradient => LinearGradient(
        colors: [cyan, blue, purple],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

class DauverseTypography {
  static const String uiFont = 'Be Vietnam Pro';
  static const String kpiFont = 'Inter';
  static const List<String> fontFallbacks = [
    'Segoe UI',
    'Noto Sans',
    'DejaVu Sans',
    'sans-serif',
  ];

  static TextStyle heading(DauversePalette p, {double size = 20}) => TextStyle(
        fontFamily: uiFont,
        fontFamilyFallback: fontFallbacks,
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: p.textPrimary,
        letterSpacing: -0.2,
      );

  static TextStyle body(DauversePalette p, {double size = 13, FontWeight weight = FontWeight.w500}) =>
      TextStyle(
        fontFamily: uiFont,
        fontFamilyFallback: fontFallbacks,
        fontSize: size,
        fontWeight: weight,
        color: p.textPrimary,
      );

  static TextStyle caption(DauversePalette p, {double size = 12}) => TextStyle(
        fontFamily: uiFont,
        fontFamilyFallback: fontFallbacks,
        fontSize: size,
        fontWeight: FontWeight.w500,
        color: p.textSecondary,
      );

  static TextStyle kpi(DauversePalette p, {double size = 24, Color? color}) => TextStyle(
        fontFamily: kpiFont,
        fontFamilyFallback: fontFallbacks,
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color ?? p.textPrimary,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

class DauverseTheme {
  static ThemeData buildTheme(bool isDark) {
    final p = isDark ? DauversePalette.dark : DauversePalette.light;
    final base = isDark ? ThemeData.dark(useMaterial3: true) : ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: p.bg,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: p.blue,
        onPrimary: Colors.white,
        secondary: p.cyan,
        onSecondary: Colors.white,
        tertiary: p.purple,
        error: p.danger,
        onError: Colors.white,
        surface: p.surface,
        onSurface: p.textPrimary,
      ),
      cardColor: p.surface,
      dividerColor: p.border,
    );
  }
}

class DauverseEmblem extends StatelessWidget {
  final double size;
  const DauverseEmblem({Key? key, this.size = 36}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _DauverseEmblemPainter(),
    );
  }
}

class _DauverseEmblemPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(size.width * 0.04), Radius.circular(size.width * 0.24));

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF070B14), Color(0xFF1E1B4B)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawRRect(rrect, bgPaint);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06
      ..shader = const LinearGradient(
        colors: [Color(0xFF06B6D4), Color(0xFF3B82F6), Color(0xFF8B5CF6)],
      ).createShader(rect);
    canvas.drawRRect(rrect, borderPaint);

    final dPath = Path()
      ..moveTo(size.width * 0.30, size.height * 0.26)
      ..lineTo(size.width * 0.52, size.height * 0.26)
      ..cubicTo(
        size.width * 0.78,
        size.height * 0.26,
        size.width * 0.78,
        size.height * 0.74,
        size.width * 0.52,
        size.height * 0.74,
      )
      ..lineTo(size.width * 0.30, size.height * 0.74)
      ..close();

    final dPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.11
      ..strokeJoin = StrokeJoin.round
      ..shader = const LinearGradient(
        colors: [Color(0xFF22D3EE), Color(0xFF3B82F6), Color(0xFFA855F7)],
      ).createShader(rect);
    canvas.drawPath(dPath, dPaint);

    final dotPaint = Paint()..color = const Color(0xFF22D3EE);
    canvas.drawCircle(Offset(size.width * 0.49, size.height * 0.50), size.width * 0.08, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DauverseCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accentBorder;

  const DauverseCard({
    Key? key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.accentBorder,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final p = DauversePalette.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentBorder ?? p.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(p.isDark ? 0.28 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: child,
      ),
    );
  }
}

class DauverseStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const DauverseStatusBadge({Key? key, required this.label, required this.color}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: DauverseTypography.kpiFont,
              fontFamilyFallback: DauverseTypography.fontFallbacks,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class DauverseSparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double height;

  const DauverseSparkline({
    Key? key,
    required this.values,
    required this.color,
    this.height = 54,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(values: values, color: color),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _SparklinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final pts = values.length == 1 ? [values[0], values[0]] : values;
    final path = Path();
    final fillPath = Path();
    final stepX = size.width / (pts.length - 1);

    for (var i = 0; i < pts.length; i++) {
      final clamped = pts[i].clamp(0.0, 100.0);
      final x = i * stepX;
      final y = size.height - (clamped / 100.0) * (size.height - 6) - 3;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          colors: [color.withOpacity(0.28), color.withOpacity(0.01)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
