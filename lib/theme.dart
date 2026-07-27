import 'package:flutter/material.dart';

/// Video vs audio is the split the whole app is organised around — two folders, two
/// library tabs, two download paths. Colour carries that split everywhere rather than
/// decorating: amber means video, cyan means music, in tiles, lists and players alike.
const kVideoAccent = Color(0xFFFFC24B);
const kAudioAccent = Color(0xFF5BD1D7);

// The dark-theme accents are too pale to read on white, so light mode uses deeper
// shades of the same two hues.
const _videoAccentLight = Color(0xFF9A6100);
const _audioAccentLight = Color(0xFF00696E);

Color accentFor(BuildContext context, {required bool audio}) {
  final light = Theme.of(context).brightness == Brightness.light;
  if (audio) return light ? _audioAccentLight : kAudioAccent;
  return light ? _videoAccentLight : kVideoAccent;
}

const _base = Color(
  0xFF12141A,
); // ink, shifted slightly blue so it is not flat black
const _raised = Color(0xFF1B1E26);
const _baseLight = Color(0xFFFAF9F7);
const _raisedLight = Color(0xFFEFEDE9);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: kVideoAccent,
    brightness: brightness,
  ).copyWith(surface: dark ? _base : _baseLight);
  final accent = dark ? kVideoAccent : _videoAccentLight;

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? _base : _baseLight,
    cardColor: dark ? _raised : _raisedLight,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? _base : _baseLight,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? _raised : _raisedLight,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      // Material derives a muddy olive container from an amber seed; a translucent
      // tint of the accent itself keeps the indicator clean.
      indicatorColor: accent.withValues(alpha: 0.18),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? accent
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    dividerTheme: const DividerThemeData(space: 1, thickness: 1),
    // Same fix as the nav indicator: an amber seed derives a muddy olive "on" track.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? accent : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? accent.withValues(alpha: 0.5)
            : null,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? accent.withValues(alpha: 0.18)
              : null,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : null,
        ),
        side: WidgetStatePropertyAll(
          BorderSide(color: accent.withValues(alpha: 0.4)),
        ),
      ),
    ),
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
