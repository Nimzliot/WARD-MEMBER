import 'package:flutter/material.dart';

/// Brand chart colours: one green hue, dark → light (validated as an ordinal
/// ramp: monotone lightness, visible steps, lightest step ≥ 2:1 on white).
/// Use it for ranked parts of a whole (budget lines, funded proposals), darkest
/// = largest / first. Past [kMaxSeries] items, fold the rest into "Other".
const kGreenRamp = [
  Color(0xFF0B5D3B),
  Color(0xFF167050),
  Color(0xFF218463),
  Color(0xFF2E9A74),
  Color(0xFF46AE86),
  Color(0xFF6CC09C),
];

const kMaxSeries = 6;

/// Neutral for "Other" / "Unallocated".
const kNeutralChart = Color(0xFFD5DDD8);

Color rampColor(int rank) => rank < kMaxSeries ? kGreenRamp[rank] : kNeutralChart;
