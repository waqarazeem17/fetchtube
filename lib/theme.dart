import 'package:flutter/material.dart';

/// Video vs audio is the split the whole app is organised around — two folders, two
/// library tabs, two download paths. Colour carries that split everywhere rather than
/// decorating: amber means video, cyan means music, in tiles, lists and tabs alike.
const kVideoAccent = Color(0xFFFFC24B);
const kAudioAccent = Color(0xFF5BD1D7);

Color accentFor({required bool audio}) => audio ? kAudioAccent : kVideoAccent;

const _base = Color(0xFF12141A); // ink, shifted slightly blue so it is not flat black
const _raised = Color(0xFF1B1E26);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kVideoAccent,
    brightness: Brightness.dark,
  ).copyWith(surface: _base);

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: _base,
    cardColor: _raised,
    appBarTheme: const AppBarTheme(
      backgroundColor: _base,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: _raised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      // Material derives a muddy olive container from an amber seed; a translucent
      // tint of the accent itself keeps the indicator clean.
      indicatorColor: kVideoAccent.withValues(alpha: 0.18),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? kVideoAccent
              : const Color(0xFF8A8F9E),
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(space: 1, thickness: 1),
  );
}

/// Section markers. Wide tracking and small caps do the work a heavier font would,
/// which keeps the app free of bundled type.
TextStyle eyebrowStyle(BuildContext context) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 1.5,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

/// The wordmark: tightened tracking so it reads as a mark rather than a sentence.
const kWordmarkStyle = TextStyle(
  fontSize: 22,
  fontWeight: FontWeight.w700,
  letterSpacing: -0.5,
);

/// Sizes, bitrates and counts line up when stacked.
const kNumericStyle = TextStyle(
  fontSize: 12,
  fontFeatures: [FontFeature.tabularFigures()],
);

class Eyebrow extends StatelessWidget {
  final String label;
  const Eyebrow(this.label, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
        child: Text(label.toUpperCase(), style: eyebrowStyle(context)),
      );
}
