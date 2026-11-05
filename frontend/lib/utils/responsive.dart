import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Width for dialog bodies: the preferred width on desktop/tablet, but never
/// wider than the current viewport (so phones never overflow sideways).
double dialogWidth(BuildContext context, [double preferred = 520]) {
  final available = MediaQuery.sizeOf(context).width - 64;
  return math.max(240.0, math.min(preferred, available));
}

/// Column count for small stat grids based on the available width.
int statColumns(double width, {int maxColumns = 4}) {
  if (width >= 900) return maxColumns;
  if (width >= 620) return math.min(3, maxColumns);
  if (width >= 340) return 2;
  return 1;
}
