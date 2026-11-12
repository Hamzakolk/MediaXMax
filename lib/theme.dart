import 'package:flutter/material.dart';

const kBg = Color(0xFF0B0B14);
const kCard = Color(0xFF171726);
const kCard2 = Color(0xFF1F1F33);
const kAccent = Color(0xFF8B5CF6);
const kAccent2 = Color(0xFF3B82F6);
const kMuted = Color(0xFF8C90A8);

const accentGradient = LinearGradient(
  colors: [kAccent, kAccent2],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const artGradients = [
  LinearGradient(colors: [Color(0xFFEC4899), Color(0xFF8B5CF6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
  LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF22D3EE)], begin: Alignment.topLeft, end: Alignment.bottomRight),
  LinearGradient(colors: [Color(0xFFF97316), Color(0xFFEF4444)], begin: Alignment.topLeft, end: Alignment.bottomRight),
  LinearGradient(colors: [Color(0xFF10B981), Color(0xFF3B82F6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
  LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF0EA5E9)], begin: Alignment.topLeft, end: Alignment.bottomRight),
];

LinearGradient artFor(int i) => artGradients[i.abs() % artGradients.length];

ThemeData appTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: kBg,
      colorScheme: const ColorScheme.dark(primary: kAccent, secondary: kAccent2, surface: kCard),
      iconTheme: const IconThemeData(color: Colors.white70),
    );
