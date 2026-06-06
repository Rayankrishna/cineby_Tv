import 'package:flutter/widgets.dart';

/// Design baseline in *logical* pixels — i.e. what `MediaQuery.size.width`
/// reports on the Android TV emulator the UI was originally authored against.
///
/// Note: the Television (4K) emulator runs 3840x2160 physical px at density
/// 640 (devicePixelRatio 4.0), so Flutter sees 960 logical px wide. Real TVs
/// often report 1920 logical, so this scales 2x there.
const double kTvDesignWidth = 960.0;

extension TvScale on num {
  double s(BuildContext ctx) {
    final factor = MediaQuery.of(ctx).size.width / kTvDesignWidth;
    return this * factor.clamp(0.75, 3.0);
  }
}

double tvScaleFactor(BuildContext ctx) =>
    (MediaQuery.of(ctx).size.width / kTvDesignWidth).clamp(0.75, 3.0);
