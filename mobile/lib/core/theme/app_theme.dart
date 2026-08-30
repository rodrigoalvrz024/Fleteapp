import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  static const String fontFamily = 'Inter';
  // ── Paleta principal ────────────────────────────────────
  static const Color primary = Color(0xFF1463FF); // azul electrico Muvv
  static const Color primaryDark = Color(0xFF0B43D8);
  static const Color accent = Color(0xFF15B8F3); // cyan de apoyo
  static const Color urgent = Color(0xFFF97316); // naranja urgente
  static const Color success = Color(0xFF10B981);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

  // ── Neutros ─────────────────────────────────────────────
  static const Color midnight = Color(0xFF0A1638); // navy Muvv
  static const Color slate600 = Color(0xFF56637D);
  static const Color slate400 = Color(0xFF8B96AB);
  static const Color slate200 = Color(0xFFE2E6EF);
  static const Color slate100 = Color(0xFFF4F6FA);
  static const Color background = Color(0xFFFBFCFF);
  static const Color surface = Color(0xFFFFFFFF);

  // ── Alias para compatibilidad con código existente ──────
  static const Color textPrimary = midnight;
  static const Color textSecondary = slate400;
  static const Color secondary = accent;

  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF2476FF), Color(0xFF0E54EB)],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient navyGradient = LinearGradient(
    colors: [Color(0xFF0A1638), Color(0xFF10245A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Status colors ───────────────────────────────────────
  static Color statusColor(String status) => switch (status) {
        'pending' => const Color(0xFFC2410C),
        'accepted' => const Color(0xFF1D4ED8),
        'in_progress' => const Color(0xFF0369A1),
        'completed' => const Color(0xFF15803D),
        'cancelled' => const Color(0xFFBE123C),
        _ => slate400,
      };

  static Color statusBg(String status) => switch (status) {
        'pending' => const Color(0xFFFFF7ED),
        'accepted' => const Color(0xFFEFF6FF),
        'in_progress' => const Color(0xFFE0F2FE),
        'completed' => const Color(0xFFF0FDF4),
        'cancelled' => const Color(0xFFFFF1F2),
        _ => slate100,
      };

  static String statusLabel(String status) => switch (status) {
        'pending' => 'Pendiente',
        'accepted' => 'Aceptado',
        'in_progress' => 'En camino',
        'completed' => 'Completado',
        'cancelled' => 'Cancelado',
        _ => status,
      };

  // ── Tema principal ──────────────────────────────────────
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: background,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: fontFamily),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: fontFamily),
      appBarTheme: const AppBarTheme(
        backgroundColor: surface,
        foregroundColor: midnight,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: midnight,
        ),
        iconTheme: IconThemeData(color: midnight),
        shape: Border(
          bottom: BorderSide(color: slate200, width: 0.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(double.infinity, 52),
          side: const BorderSide(color: slate200),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: slate200, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: slate200, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: error, width: 0.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(fontSize: 14, color: slate400),
        hintStyle: const TextStyle(fontSize: 14, color: slate400),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: slate200, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: slate200,
        thickness: 0.5,
        space: 1,
      ),
    );
  }

  // ── Helpers de estilos ──────────────────────────────────
  static BoxDecoration cardDecoration({
    double radius = 18,
    Color? borderColor,
  }) =>
      BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: borderColor ?? slate200,
          width: 0.5,
        ),
      );

  static BoxDecoration urgentDecoration() => BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: urgent.withValues(alpha: 0.4), width: 0.5),
      );
}
