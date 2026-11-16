import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:cineby_tv/widgets/tv_focus.dart';
import 'package:cineby_tv/widgets/tv_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// ---- Layout tokens (design px at 960 wide; scale with `.s(context)`) ----

/// Left/right page margin shared by every screen.
const double kTvGutter = 40;

/// Height of the top navigation bar that floats over tab pages.
const double kTvNavHeight = 56;

/// Standard 2:3 poster card.
const double kTvPosterWidth = 124;
const double kTvPosterHeight = 186;
const double kTvPosterGap = 12;

/// Vertical room a rail leaves around its cards for the focus scale + ring.
const double kTvRailHeadroom = 11;

/// Lets a tab page take part in shell-level navigation.
class TvTabHandle {
  /// Return true if the page consumed BACK (for example by returning to its
  /// top) so the shell should not move focus to the nav bar.
  bool Function()? onBack;

  /// Where focus should land when the user first drops into the page from
  /// the nav bar. Without it the shell picks the top-left control.
  FocusNode? entryNode;
}

/// Fade + slight push-in between pages. Replaces Android's default zoom
/// transition, which is both off-brand for a TV app and heavier to render.
class TvPageTransitionsBuilder extends PageTransitionsBuilder {
  const TvPageTransitionsBuilder();

  static final Animatable<double> _fade = CurveTween(curve: Curves.easeOut);
  static final Animatable<double> _scale = Tween<double>(
    begin: 0.985,
    end: 1.0,
  ).chain(CurveTween(curve: Curves.easeOutCubic));

  @override
  Duration get transitionDuration => const Duration(milliseconds: 260);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: animation.drive(_fade),
      child: ScaleTransition(scale: animation.drive(_scale), child: child),
    );
  }
}

/// Small pill message at the bottom of the screen.
void tvToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      duration: const Duration(seconds: 2),
      backgroundColor: Colors.white,
      width: 300.s(context),
      shape: const StadiumBorder(),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.black,
          fontSize: 13.s(context),
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

/// Text button used everywhere: translucent at rest, solid white on focus.
class TvButton extends StatelessWidget {
  const TvButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.subLabel,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
    this.skipTraversal = false,
    this.reveal = true,
  });

  final String label;
  final String? subLabel;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final bool skipTraversal;
  final bool reveal;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onPressed: onPressed,
      onFocusChange: onFocusChange,
      skipTraversal: skipTraversal,
      reveal: reveal,
      builder: (context, focused) {
        final fg = focused ? Colors.black : Colors.white;
        return AnimatedScale(
          scale: focused ? 1.06 : 1.0,
          duration: TvMotion.focus,
          curve: TvMotion.curve,
          child: AnimatedContainer(
            duration: TvMotion.focus,
            curve: TvMotion.curve,
            height: 36.s(context),
            padding: EdgeInsets.symmetric(horizontal: 18.s(context)),
            decoration: BoxDecoration(
              color:
                  focused ? Colors.white : Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(5.s(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: fg, size: 20.s(context)),
                  SizedBox(width: 6.s(context)),
                ],
                Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      style: TextStyle(
                        color: fg,
                        fontSize: 14.s(context),
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                      ),
                    ),
                    if (subLabel != null)
                      Text(
                        subLabel!,
                        maxLines: 1,
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.6),
                          fontSize: 9.5.s(context),
                          height: 1.15,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Pill used for genres, tabs and season pickers. [selected] marks the
/// current choice while focus is elsewhere.
class TvChip extends StatelessWidget {
  const TvChip({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.autofocus = false,
    this.onFocusChange,
    this.icon,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChange;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      onPressed: onPressed,
      onFocusChange: onFocusChange,
      builder: (context, focused) {
        final fg = focused ? Colors.black : Colors.white;
        return AnimatedScale(
          scale: focused ? 1.06 : 1.0,
          duration: TvMotion.focus,
          curve: TvMotion.curve,
          child: AnimatedContainer(
            duration: TvMotion.focus,
            curve: TvMotion.curve,
            height: 32.s(context),
            padding: EdgeInsets.symmetric(horizontal: 16.s(context)),
            decoration: BoxDecoration(
              color:
                  focused
                      ? Colors.white
                      : Colors.white.withValues(alpha: selected ? 0.2 : 0.08),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color:
                    focused
                        ? Colors.white
                        : Colors.white.withValues(alpha: selected ? 0.9 : 0.18),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: fg, size: 15.s(context)),
                  SizedBox(width: 6.s(context)),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13.s(context),
                      fontWeight:
                          selected || focused
                              ? FontWeight.w700
                              : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 2:3 poster with the shared focus treatment, plus an optional watch
/// progress bar and corner badge.
class TvPosterCard extends StatelessWidget {
  const TvPosterCard({
    super.key,
    required this.posterPath,
    required this.title,
    required this.onPressed,
    this.width,
    this.progress,
    this.badge,
    this.autofocus = false,
    this.onFocused,
  });

  final String? posterPath;
  final String? title;
  final VoidCallback onPressed;

  /// Logical width; defaults to the standard rail poster. Pass
  /// `double.infinity` to fill a grid cell.
  final double? width;
  final double? progress;
  final String? badge;
  final bool autofocus;
  final VoidCallback? onFocused;

  @override
  Widget build(BuildContext context) {
    final fill = width == double.infinity;
    final w = fill ? null : (width ?? kTvPosterWidth.s(context));
    return TvFocusable(
      autofocus: autofocus,
      onPressed: onPressed,
      onFocusChange: (focused) {
        if (focused) onFocused?.call();
      },
      builder: (context, focused) {
        return TvFocusFrame(
          focused: focused,
          radius: 5.s(context),
          ringWidth: 2.5.s(context),
          child: SizedBox(
            width: w,
            height: w == null ? null : w * 1.5,
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  TvImage(
                    path: posterPath,
                    kind: TmdbImageKind.poster,
                    width: w ?? kTvPosterWidth.s(context) * 1.25,
                    fallback: _PosterFallback(title: title),
                  ),
                  if (badge != null)
                    Positioned(
                      top: 6.s(context),
                      left: 6.s(context),
                      child: TvBadge(label: badge!),
                    ),
                  if (progress != null && progress! > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: TvProgressBar(value: progress!),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.title});
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kSurfaceGrey,
      alignment: Alignment.center,
      padding: EdgeInsets.all(8.s(context)),
      child: Text(
        title ?? '',
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: kTextGrey,
          fontSize: 12.s(context),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class TvBadge extends StatelessWidget {
  const TvBadge({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 6.s(context),
        vertical: 2.s(context),
      ),
      decoration: BoxDecoration(
        color: kDeepBlack.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(3.s(context)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: kTextWhite,
          fontSize: 9.5.s(context),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Thin red watch-progress bar.
class TvProgressBar extends StatelessWidget {
  const TvProgressBar({super.key, required this.value, this.height = 3});
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height.s(context),
      color: Colors.white.withValues(alpha: 0.28),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0),
        heightFactor: 1,
        child: const ColoredBox(color: kNetflixRed),
      ),
    );
  }
}

/// A horizontally scrolling strip of equally spaced items.
///
/// The focused item is kept at a fixed "anchor" slot at the left gutter while
/// the strip glides underneath, rather than the highlight wandering to the
/// screen edge and the list jumping to catch up. LEFT/RIGHT never leave the
/// strip.
class TvRail extends StatelessWidget {
  const TvRail({
    super.key,
    required this.itemCount,
    required this.itemExtent,
    required this.height,
    required this.itemBuilder,
    this.storageId,
    this.onItemFocused,
  });

  final int itemCount;

  /// Item width plus the gap to the next item, in logical px.
  final double itemExtent;

  /// Full strip height, including headroom for the focus scale.
  final double height;
  final IndexedWidgetBuilder itemBuilder;

  /// Remembers the scroll offset across rebuilds (e.g. when a home row is
  /// recycled while off-screen) when set.
  final String? storageId;
  final ValueChanged<int>? onItemFocused;

  @override
  Widget build(BuildContext context) {
    final gutter = kTvGutter.s(context);
    return TvRowFocusGroup(
      child: SizedBox(
        height: height,
        child: ListView.builder(
          key: storageId == null ? null : PageStorageKey<String>(storageId!),
          scrollDirection: Axis.horizontal,
          // The focused card grows past its slot; let it draw outside the
          // strip instead of being sliced by the viewport.
          clipBehavior: Clip.none,
          padding: EdgeInsets.symmetric(horizontal: gutter),
          itemExtent: itemExtent,
          itemCount: itemCount,
          scrollCacheExtent: ScrollCacheExtent.pixels(itemExtent * 2),
          itemBuilder: (context, index) {
            return Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (focused) {
                if (!focused) return;
                final scrollable = Scrollable.maybeOf(context);
                if (scrollable != null) {
                  tvScrollTo(scrollable, index * itemExtent);
                }
                onItemFocused?.call(index);
              },
              child: Align(
                alignment: Alignment.centerLeft,
                child: itemBuilder(context, index),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Like [TvRail], for children of differing widths (chips). The focused
/// child is anchored at the left gutter in the same way.
class TvFlowRail extends StatelessWidget {
  const TvFlowRail({
    super.key,
    required this.children,
    required this.height,
    this.spacing = 8,
  });

  final List<Widget> children;
  final double height;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final gutter = kTvGutter.s(context);
    return TvRowFocusGroup(
      child: SizedBox(
        height: height,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.symmetric(horizontal: gutter),
          child: Row(
            children: [
              for (var i = 0; i < children.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    right: i == children.length - 1 ? 0 : spacing.s(context),
                  ),
                  child: Builder(
                    builder:
                        (context) => Focus(
                          canRequestFocus: false,
                          skipTraversal: true,
                          onFocusChange: (focused) {
                            if (focused) {
                              tvAnchorHorizontal(context, inset: gutter);
                            }
                          },
                          child: children[i],
                        ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Heading + rail (or any body), revealed together as one unit.
class TvRailSection extends StatelessWidget {
  const TvRailSection({
    super.key,
    required this.title,
    required this.child,
    this.alignment = 0.5,
    this.trailing,
  });

  final String title;
  final Widget child;
  final double alignment;

  /// Optional muted note after the title.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return TvSection(
      alignment: alignment,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [TvSectionTitle(title: title, trailing: trailing), child],
      ),
    );
  }
}

class TvSectionTitle extends StatelessWidget {
  const TvSectionTitle({super.key, required this.title, this.trailing});
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: kTvGutter.s(context),
        right: kTvGutter.s(context),
        top: 8.s(context),
        bottom: 2.s(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: TextStyle(
              color: kTextWhite,
              fontSize: 16.s(context),
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: 10.s(context)),
            Text(
              trailing!,
              style: TextStyle(color: kTextGrey, fontSize: 12.s(context)),
            ),
          ],
        ],
      ),
    );
  }
}

/// A standard poster rail: [count] posters built by [cardBuilder].
class TvPosterRail extends StatelessWidget {
  const TvPosterRail({
    super.key,
    required this.count,
    required this.cardBuilder,
    this.storageId,
  });

  final int count;
  final IndexedWidgetBuilder cardBuilder;
  final String? storageId;

  static double heightOf(BuildContext context) =>
      (kTvPosterHeight + 2 * kTvRailHeadroom).s(context);

  @override
  Widget build(BuildContext context) {
    return TvRail(
      storageId: storageId,
      itemCount: count,
      itemExtent: (kTvPosterWidth + kTvPosterGap).s(context),
      height: heightOf(context),
      itemBuilder: cardBuilder,
    );
  }
}

/// Gently pulses its child; wrap a group of [TvSkeletonBox]es for a loading
/// state that hints at the layout to come instead of a bare spinner.
class TvPulse extends StatefulWidget {
  const TvPulse({super.key, required this.child});
  final Widget child;

  @override
  State<TvPulse> createState() => _TvPulseState();
}

class _TvPulseState extends State<TvPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(
    begin: 0.4,
    end: 0.9,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}

class TvSkeletonBox extends StatelessWidget {
  const TvSkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 5,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: kSurfaceHi,
        borderRadius: BorderRadius.circular(radius.s(context)),
      ),
    );
  }
}

/// A row of placeholder posters under a placeholder heading.
class TvPosterRailSkeleton extends StatelessWidget {
  const TvPosterRailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final w = kTvPosterWidth.s(context);
    final gap = kTvPosterGap.s(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: kTvGutter.s(context),
            top: 12.s(context),
            bottom: 14.s(context),
          ),
          child: TvSkeletonBox(width: 150.s(context), height: 14.s(context)),
        ),
        SizedBox(
          height: w * 1.5,
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: double.infinity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(width: kTvGutter.s(context)),
                for (var i = 0; i < 8; i++)
                  Padding(
                    padding: EdgeInsets.only(right: gap),
                    child: TvSkeletonBox(width: w, height: w * 1.5),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Centred icon + message for empty and error states, with optional actions.
class TvMessage extends StatelessWidget {
  const TvMessage({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String? detail;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white24, size: 56.s(context)),
          SizedBox(height: 14.s(context)),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kTextWhite,
              fontSize: 18.s(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (detail != null) ...[
            SizedBox(height: 6.s(context)),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kTextGrey,
                fontSize: 13.s(context),
                height: 1.4,
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            SizedBox(height: 20.s(context)),
            TvRowFocusGroup(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) SizedBox(width: 12.s(context)),
                    actions[i],
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Large title at the top of a pushed page (genre, filmography, avatars).
class TvPageTitle extends StatelessWidget {
  const TvPageTitle({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        kTvGutter.s(context),
        28.s(context),
        kTvGutter.s(context),
        10.s(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (subtitle != null)
            Text(
              subtitle!.toUpperCase(),
              style: TextStyle(
                color: kTextGrey,
                fontSize: 10.5.s(context),
                fontWeight: FontWeight.w700,
                letterSpacing: 2.s(context),
              ),
            ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: kTextWhite,
              fontSize: 28.s(context),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades its child in once, when first built. Give it a new [key] to replay
/// the fade for new content (e.g. a different season's episodes).
class TvFadeIn extends StatefulWidget {
  const TvFadeIn({super.key, required this.child});
  final Widget child;

  @override
  State<TvFadeIn> createState() => _TvFadeInState();
}

class _TvFadeInState extends State<TvFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: TvMotion.fade,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: CurveTween(curve: Curves.easeOut).animate(_controller),
    child: widget.child,
  );
}

/// "★ 7.8 · 2024 · Series" line shown under a title.
class TvMetaLine extends StatelessWidget {
  const TvMetaLine({super.key, this.rating, this.items = const []});

  final double? rating;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: Colors.white.withValues(alpha: 0.8),
      fontSize: 12.5.s(context),
      fontWeight: FontWeight.w600,
    );
    final children = <Widget>[];
    final rating = this.rating;
    if (rating != null && rating > 0) {
      children.addAll([
        Icon(
          Icons.star_rounded,
          color: const Color(0xFFFACC15),
          size: 15.s(context),
        ),
        SizedBox(width: 3.s(context)),
        Text(
          rating.toStringAsFixed(1),
          style: style.copyWith(color: kTextWhite),
        ),
      ]);
    }
    for (final item in items) {
      if (children.isNotEmpty) {
        children.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 7.s(context)),
            child: Text('\u00B7', style: style),
          ),
        );
      }
      children.add(Text(item, style: style));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// Grid layout for a wall of 2:3 posters.
SliverGridDelegate tvPosterGridDelegate(
  BuildContext context, {
  int columns = 6,
}) {
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    childAspectRatio: 2 / 3,
    crossAxisSpacing: 14.s(context),
    mainAxisSpacing: 18.s(context),
  );
}

/// Pulsing placeholder wall shown while a poster grid loads.
class TvPosterGridSkeleton extends StatelessWidget {
  const TvPosterGridSkeleton({
    super.key,
    this.columns = 6,
    this.rows = 2,
    this.padding,
  });

  final int columns;
  final int rows;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return TvPulse(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding:
            padding ??
            EdgeInsets.symmetric(
              horizontal: kTvGutter.s(context),
              vertical: 12.s(context),
            ),
        gridDelegate: tvPosterGridDelegate(context, columns: columns),
        itemCount: columns * rows,
        itemBuilder:
            (context, _) => DecoratedBox(
              decoration: BoxDecoration(
                color: kSurfaceHi,
                borderRadius: BorderRadius.circular(5.s(context)),
              ),
            ),
      ),
    );
  }
}
