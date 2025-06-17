import 'package:flutter/material.dart';

class AppTheme {
  // Primary colors - Futuristic dark theme with neon accents
  static const Color primaryColor = Color(0xFF0B132B);       // Deep blue
  static const Color accentColor = Color(0xFF00F0FF);        // Neon cyan
  static const Color lightAccentColor = Color(0xFF00E676);   // Neon green
  
  // Background colors
  static const Color backgroundColor = Color(0xFF1A1A2E);    // Charcoal black
  static const Color secondaryBackgroundColor = Color(0xFF222642); // Dark navy
  
  // Text colors
  static const Color primaryTextColor = Color(0xFFE0E0E0);  // Light silver
  static const Color secondaryTextColor = Color(0xFFA0A0A0); // Medium gray
  static const Color lightTextColor = Colors.white;
  
  // Message bubble colors
  static const Color sentMessageColor = Color(0xFF2E3566);   // Metallic blue
  static const Color receivedMessageColor = Color(0xFF404461); // Metallic silver
  
  // Status colors
  static const Color onlineColor = Color(0xFF00E676);       // Neon green
  static const Color errorColor = Color(0xFFFF5252);        // Bright red

  // Additional colors needed for message bubbles
  static const Color darkSecondaryColor = Color(0xFF1C2541); // Dark secondary color
  static const Color secondaryColor = Color(0xFF3A506B);     // Secondary color
  static const Color darkPrimaryColor = Color(0xFF0B132B);   // Dark primary color

  // Text styles
  static const TextStyle headingTextStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    color: primaryTextColor,
    letterSpacing: 0.5,
  );
  
  static const TextStyle bodyTextStyle = TextStyle(
    fontSize: 16,
    color: primaryTextColor,
    letterSpacing: 0.3,
  );
  
  static const TextStyle subtitleTextStyle = TextStyle(
    fontSize: 14,
    color: secondaryTextColor,
    letterSpacing: 0.2,
  );
  
  static const TextStyle buttonTextStyle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: lightTextColor,
    letterSpacing: 0.5,
  );

  // Gradients
  static const LinearGradient neonGradient = LinearGradient(
    colors: [Color(0xFF00F0FF), Color(0xFF00E676)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient metalGradient = LinearGradient(
    colors: [Color(0xFF2E3566), Color(0xFF404461)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Light theme (actually dark futuristic theme)
  static final ThemeData lightTheme = ThemeData(
    brightness: Brightness.dark,
    primaryColor: primaryColor,
    colorScheme: const ColorScheme.dark(
      primary: accentColor,
      secondary: lightAccentColor,
      onPrimary: Colors.white,
      background: backgroundColor,
      error: errorColor,
      onSecondary: Colors.white,
      surface: secondaryBackgroundColor,
      onSurface: primaryTextColor,
    ),
    scaffoldBackgroundColor: backgroundColor,
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryColor,
      foregroundColor: lightTextColor,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: lightTextColor,
        letterSpacing: 0.7,
      ),
      iconTheme: IconThemeData(
        color: accentColor,
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: accentColor,
      unselectedLabelColor: Color(0xAAFFFFFF),
      indicatorSize: TabBarIndicatorSize.tab,
      indicator: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: accentColor,
            width: 3.0,
          ),
        ),
      ),
      labelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
      unselectedLabelStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        letterSpacing: 0.5,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: secondaryBackgroundColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: accentColor.withOpacity(0.3), width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: accentColor, width: 2.0),
      ),
      hintStyle: TextStyle(color: secondaryTextColor.withOpacity(0.7)),
      labelStyle: const TextStyle(color: accentColor),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: lightTextColor,
        backgroundColor: accentColor,
        elevation: 8,
        shadowColor: accentColor.withOpacity(0.5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accentColor,
        textStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    ),
    iconTheme: const IconThemeData(color: accentColor),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: lightAccentColor,
      foregroundColor: Colors.white,
      elevation: 8,
      splashColor: accentColor,
    ),
    cardTheme: CardThemeData(
      elevation: 6,
      shadowColor: accentColor.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      color: secondaryBackgroundColor,
    ),
    dividerTheme: const DividerThemeData(
      thickness: 1,
      color: Color(0xFF303451),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: secondaryBackgroundColor,
      disabledColor: secondaryBackgroundColor.withOpacity(0.3),
      selectedColor: accentColor,
      secondarySelectedColor: lightAccentColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      labelStyle: const TextStyle(color: lightTextColor),
      secondaryLabelStyle: const TextStyle(color: lightTextColor),
      brightness: Brightness.dark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accentColor.withOpacity(0.3)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: secondaryBackgroundColor,
      contentTextStyle: const TextStyle(color: lightTextColor),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    fontFamily: 'Roboto',
    textTheme: const TextTheme(
      displayLarge: headingTextStyle,
      bodyLarge: bodyTextStyle,
      bodyMedium: bodyTextStyle,
      bodySmall: subtitleTextStyle,
      labelLarge: buttonTextStyle,
    ),
  );
  
  // Dark theme (same as light theme since our app is already dark-themed)
  static final ThemeData darkTheme = lightTheme;
} 