import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Paleta principal ────────────────────────────────────
  static const Color primary     = Color(0xFF3B82F6);  // azul moderno
  static const Color primaryDark = Color(0xFF1D4ED8);
  static const Color accent      = Color(0xFF06B6D4);  // cyan
  static const Color urgent      = Color(0xFFF97316);  // naranja urgente
  static const Color success     = Color(0xFF10B981);
  static const Color error       = Color(0xFFEF4444);
  static const Color warning     = Color(0xFFF59E0B);

  // ── Neutros ─────────────────────────────────────────────
  static const Color midnight    = Color(0xFF0F172A);  // texto principal
  static const Color slate600    = Color(0xFF475569);
  static const Color slate400    = Color(0xFF94A3B8);
  static const Color slate200    = Color(0xFFE2E8F0);
  static const Color slate100    = Color(0xFFF1F5F9);
  static const Color background  = Color(0xFFF8FAFC);
  static const Color surface     = Color(0xFFFFFFFF);

  // ── Alias para compatibilidad con código existente ──────
  static const Color textPrimary   = midnight;
  static const Color textSecondary = slate400;
  static const Color secondary     = accent;

  // ── Status colors ───────────────────────────────────────
  static Color statusColor(String status) => switch (status) {
    'pending'     => const Color(0xFFC2410C),
    'accepted'    => const Color(0xFF1D4ED8),
    'in_progress' => const Color(0xFF0369A1),
    'completed'   => const Color(0xFF15803D),
    'cancelled'   => const Color(0xFFBE123C),
    _             => slate400,
  };

  static Color statusBg(String status) => switch (status) {
    'pending'     => const Color(0xFFFFF7ED),
    'accepted'    => const Color(0xFFEFF6FF),
    'in_progress' => const Color(0xFFE0F2FE),
    'completed'   => const Color(0xFFF0FDF4),
    'cancelled'   => const Color(0xFFFFF1F2),
    _             => slate100,
  };

  static String statusLabel(String status) => switch (status) {
    'pending'     => 'Pendiente',
    'accepted'    => 'Aceptado',
    'in_progress' => 'En camino',
    'completed'   => 'Completado',
    'cancelled'   => 'Cancelado',
    _             => status,
  };

  // ── Tema principal ──────────────────────────────────────
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: background,
    );

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: midnight,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: midnight,
        ),
        iconTheme: const IconThemeData(color: midnight),
        shape: const Border(
          bottom: BorderSide(color: slate200, width: 0.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          textStyle: GoogleFonts.inter(
              fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(double.infinity, 52),
          side: const BorderSide(color: slate200),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.inter(
              fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: slate200, width: 0.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: slate200, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: error, width: 0.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
        labelStyle: GoogleFonts.inter(
            fontSize: 14, color: slate400),
        hintStyle: GoogleFonts.inter(
            fontSize: 14, color: slate400),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
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
    double radius = 16,
    Color? borderColor,
  }) => BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: borderColor ?? slate200,
      width: 0.5,
    ),
  );

  static BoxDecoration urgentDecoration() => BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: urgent.withValues(alpha: 0.4), width: 0.5),
  );
}