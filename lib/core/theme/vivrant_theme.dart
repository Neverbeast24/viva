import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'vivrant_colors.dart';

abstract final class VivrantTheme {
  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: VivrantColors.accent,
        onPrimary: VivrantColors.onAccent,
        secondary: VivrantColors.cyan,
        onSecondary: VivrantColors.onAccent,
        surface: VivrantColors.card,
        onSurface: VivrantColors.ink,
        error: const Color(0xFFB42318),
        outline: VivrantColors.line,
      ),
      scaffoldBackgroundColor: VivrantColors.body0,
    );

    return _apply(base, dark: false);
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: VivrantColors.darkAccent,
        onPrimary: VivrantColors.darkOnAccent,
        secondary: VivrantColors.darkCyan,
        onSecondary: VivrantColors.darkOnAccent,
        surface: VivrantColors.darkCard,
        onSurface: VivrantColors.darkInk,
        error: const Color(0xFFF97066),
        outline: VivrantColors.darkLine,
      ),
      scaffoldBackgroundColor: VivrantColors.darkBody0,
    );

    return _apply(base, dark: true);
  }

  static ThemeData _apply(ThemeData base, {required bool dark}) {
    final ink = dark ? VivrantColors.darkInk : VivrantColors.ink;
    final muted = dark ? VivrantColors.darkMuted : VivrantColors.muted;
    final card = dark ? VivrantColors.darkCard : VivrantColors.card;
    final panel = dark ? VivrantColors.darkPanel : VivrantColors.panel;
    final accent = dark ? VivrantColors.darkAccent : VivrantColors.accent;
    final inverse = dark ? VivrantColors.darkInk : VivrantColors.inverse;
    final inverseFg = dark ? VivrantColors.darkSolid : VivrantColors.inverseFg;

    final body = GoogleFonts.spaceGroteskTextTheme(base.textTheme).apply(
      bodyColor: ink,
      displayColor: ink,
    );
    final display = GoogleFonts.bricolageGrotesqueTextTheme(body);

    return base.copyWith(
      canvasColor: card,
      textTheme: display.copyWith(
        displayLarge: display.displayLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          height: 1.05,
        ),
        headlineMedium: display.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
        ),
        titleLarge: display.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        bodyMedium: GoogleFonts.spaceGrotesk(
          color: ink,
          fontSize: 15,
          height: 1.45,
        ),
        bodySmall: GoogleFonts.spaceGrotesk(
          color: muted,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
        labelSmall: GoogleFonts.spaceGrotesk(
          color: muted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: ink,
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: GoogleFonts.bricolageGrotesque(
          color: ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: ink.withValues(alpha: 0.08)),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? VivrantColors.darkSurfaceSoft
            : VivrantColors.surface.withValues(alpha: 0.7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: ink.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: ink.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        labelStyle: TextStyle(color: muted, fontSize: 15),
        floatingLabelStyle: TextStyle(color: accent, fontSize: 13),
        hintStyle: TextStyle(
          color: muted.withValues(alpha: 0.7),
          fontSize: 15,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: inverse,
          foregroundColor: inverseFg,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w800,
            fontSize: 16.5,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: inverse,
          foregroundColor: inverseFg,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: ink.withValues(alpha: 0.14)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: panel,
        selectedColor: dark
            ? VivrantColors.darkAccentSoft
            : VivrantColors.accentSoft,
        labelStyle: TextStyle(color: ink, fontWeight: FontWeight.w700),
        secondaryLabelStyle: TextStyle(color: accent, fontWeight: FontWeight.w700),
        side: BorderSide(color: ink.withValues(alpha: 0.12)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      dividerTheme: DividerThemeData(color: ink.withValues(alpha: 0.08)),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        textStyle: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(card),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(
          dark ? VivrantColors.darkOnAccent : VivrantColors.onAccent,
        ),
        side: BorderSide(color: ink.withValues(alpha: 0.35), width: 1.8),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: panel,
        selectedItemColor: accent,
        unselectedItemColor: muted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: dark
            ? VivrantColors.darkAccentSoft
            : VivrantColors.accentSoft,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? accent : muted,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.spaceGrotesk(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? accent : muted,
          );
        }),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? VivrantColors.darkCard : VivrantColors.panel,
        contentTextStyle: GoogleFonts.spaceGrotesk(
          color: ink,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.35,
        ),
        actionTextColor: accent,
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return dark ? VivrantColors.darkOnAccent : VivrantColors.onAccent;
          }
          return muted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return ink.withValues(alpha: 0.18);
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: ink.withValues(alpha: 0.12),
        thumbColor: accent,
        overlayColor: accent.withValues(alpha: 0.16),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return ink.withValues(alpha: 0.45);
        }),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: card,
        headerBackgroundColor: accent,
        headerForegroundColor:
            dark ? VivrantColors.darkOnAccent : VivrantColors.onAccent,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: card,
      ),
    );
  }
}
