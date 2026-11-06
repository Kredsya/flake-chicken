import 'package:flutter/material.dart';

abstract final class AppColors {
  static const blue = Color(0xFF95B7DE);
  static const blueStrong = Color(0xFF719FCE);
  static const ink = Color(0xFF3C4856);
  static const muted = Color(0xFFA0ACBD);
  static const pink = Color(0xFFDCA5B9);
  static const rose = Color(0xFFA47184);
  static const background = Color(0xFFF7F9FD);
  static const border = Color(0xFFDFE6F0);
  static const red = Color(0xFFC92D32);
}

ThemeData buildAppTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'NotoSansKR',
  scaffoldBackgroundColor: AppColors.background,
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.blue,
    primary: AppColors.blueStrong,
    onPrimary: Colors.white,
    surface: AppColors.background,
    onSurface: AppColors.ink,
    error: AppColors.red,
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: 14, color: AppColors.ink),
    bodySmall: TextStyle(fontSize: 12, color: AppColors.ink),
    titleMedium: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.background,
    foregroundColor: AppColors.ink,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    titleSpacing: 0,
    titleTextStyle: TextStyle(
      fontFamily: 'NotoSansKR',
      fontSize: 19,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFFF2F5FB),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppColors.blueStrong, width: 1.5),
    ),
    hintStyle: const TextStyle(fontSize: 14, color: AppColors.muted),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.blueStrong,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(
        fontFamily: 'NotoSansKR',
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
    ),
  ),
  dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
  textSelectionTheme: const TextSelectionThemeData(
    cursorColor: AppColors.blueStrong,
  ),
);

String formatTime(DateTime date) {
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  return '${date.hour < 12 ? '오전' : '오후'} $hour:${date.minute.toString().padLeft(2, '0')}';
}

String weekday(DateTime date) =>
    const ['월', '화', '수', '목', '금', '토', '일'][date.weekday - 1];

String formatDate(DateTime date) =>
    '${date.month}월 ${date.day}일 (${weekday(date)})';

String formatAppointmentDate(DateTime date) =>
    '${date.month}.${date.day.toString().padLeft(2, '0')} (${weekday(date)}) · ${formatTime(date)}';
