import 'package:flutter/material.dart';

/// Categorical chart palette (colour-blind-validated order). Assign slots in this
/// fixed order and never cycle — anything past 8 series is folded into "Other".
const _light = [
  Color(0xFF2A78D6), // blue
  Color(0xFFEB6834), // orange
  Color(0xFF1BAF7A), // aqua
  Color(0xFFEDA100), // yellow
  Color(0xFFE87BA4), // magenta
  Color(0xFF008300), // green
  Color(0xFF4A3AA7), // violet
  Color(0xFFE34948), // red
];

const _dark = [
  Color(0xFF3987E5),
  Color(0xFFD95926),
  Color(0xFF199E70),
  Color(0xFFC98500),
  Color(0xFFD55181),
  Color(0xFF008300),
  Color(0xFF9085E9),
  Color(0xFFE66767),
];

const kMaxSeries = 8;

Color seriesColor(BuildContext context, int slot) {
  final palette = Theme.of(context).brightness == Brightness.dark ? _dark : _light;
  return palette[slot.clamp(0, kMaxSeries - 1)];
}

/// Neutral colour for "Other" / "Unallocated" and any series past slot 8.
Color neutralColor(BuildContext context) => Theme.of(context).colorScheme.outlineVariant;

/// Colour for a series slot, falling back to neutral past the 8 palette slots.
Color slotColor(BuildContext context, int slot) =>
    slot < kMaxSeries ? seriesColor(context, slot) : neutralColor(context);
