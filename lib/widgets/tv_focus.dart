import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Motion tokens shared by every screen, so focus, scrolling and page changes
/// all move with one rhythm instead of each widget picking its own timing.
abstract final class TvMotion {
  /// Focus ring / scale on a card or button.
  static const Duration focus = Duration(milliseconds: 170);

  /// A single D-pad step scrolling content into place.
  static const Duration scroll = Duration(milliseconds: 300);

  /// One step while a D-pad key is held is linear, so consecutive steps chain
  /// into constant-speed motion instead of pulsing. Its length is derived
  /// from the remote's actual repeat rate — see [TvInput.heldStep].

  /// Ease-out that finishes a held scroll once the key is released.
  static const Duration settle = Duration(milliseconds: 240);

  /// Content swaps: billboard text, backdrops, tab pages.
  static const Duration fade = Duration(milliseconds: 260);

  static const Curve curve = Curves.easeOutCubic;
}

bool tvIsSelectKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.select ||
    key == LogicalKeyboardKey.enter ||
    key == LogicalKeyboardKey.numpadEnter ||
    key == LogicalKeyboardKey.space ||
    key == LogicalKeyboardKey.gameButtonA;

/// Tracks whether the remote is being held down, and finishes held scrolls
/// with a soft landing when the key is released.
abstract final class TvInput {
  static bool _installed = false;
  static bool _held = false;
  static final Map<ScrollableState, double> _heldTargets = {};
  static final Stopwatch _clock = Stopwatch()..start();
  static int? _lastRepeatMs;

  /// Smoothed gap between auto-repeat events. Android's default is 50ms but
  /// IR remotes are often twice that, so it is measured rather than assumed.
  static double _repeatGapMs = 50;

  /// True while a key is auto-repeating.
  static bool get isHeld => _held;

  /// How long one scroll step should take while a key is held: a little
  /// longer than the gap between repeats, so each step is still in flight
  /// when the next arrives (continuous motion) without the highlight running
  /// far ahead of the scroll (which a fixed, longer step causes on fast
  /// remotes).
  static Duration get heldStep =>
      Duration(milliseconds: (_repeatGapMs * 1.5).clamp(70, 220).round());

  /// Shortest time between row changes while UP/DOWN is held. Key repeat
  /// fires ~20 times a second; changing rows that fast outruns both the
  /// scroll and the eye, so vertical repeats are thinned to a browsable pace.
  static const int _verticalGapMs = 140;
  static int _lastVerticalMs = 0;
  static KeyEvent? _throttledEvent;
  static bool _throttledResult = false;

  /// Step length for a held key along [axis].
  static Duration heldStepFor(Axis axis) {
    if (axis == Axis.horizontal) return heldStep;
    final floor = (_verticalGapMs * 1.25).round();
    final step = heldStep.inMilliseconds;
    return Duration(milliseconds: step > floor ? step : floor);
  }

  /// Whether this UP/DOWN auto-repeat should be dropped (see
  /// [_verticalGapMs]). Safe to ask more than once about the same event as
  /// it bubbles up the focus tree.
  static bool shouldDropVerticalRepeat(KeyEvent event) {
    if (identical(event, _throttledEvent)) return _throttledResult;
    final key = event.logicalKey;
    var drop = false;
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      final now = _clock.elapsedMilliseconds;
      if (event is KeyRepeatEvent && now - _lastVerticalMs < _verticalGapMs) {
        drop = true;
      } else if (event is! KeyUpEvent) {
        _lastVerticalMs = now;
      }
    }
    _throttledEvent = event;
    _throttledResult = drop;
    return drop;
  }

  static void ensureInstalled() {
    if (_installed) return;
    _installed = true;
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  static bool _onKey(KeyEvent event) {
    if (event is KeyRepeatEvent) {
      final now = _clock.elapsedMilliseconds;
      final last = _lastRepeatMs;
      if (last != null) {
        final gap = now - last;
        if (gap >= 20 && gap <= 400) {
          _repeatGapMs = _repeatGapMs * 0.7 + gap * 0.3;
        }
      }
      _lastRepeatMs = now;
      _held = true;
    } else {
      final wasHeld = _held;
      _held = false;
      _lastRepeatMs = null;
      if (wasHeld && event is KeyUpEvent) {
        _settle();
      } else if (event is KeyDownEvent) {
        // A hold that never delivered its key-up (app was backgrounded).
        _heldTargets.clear();
      }
    }
    return false;
  }

  static void _settle() {
    final targets = Map<ScrollableState, double>.of(_heldTargets);
    _heldTargets.clear();
    targets.forEach((scrollable, target) {
      if (!scrollable.mounted) return;
      final position = scrollable.position;
      if (!position.hasContentDimensions) return;
      final clamped =
          target
              .clamp(position.minScrollExtent, position.maxScrollExtent)
              .toDouble();
      if ((clamped - position.pixels).abs() < 0.5) return;
      position.animateTo(
        clamped,
        duration: TvMotion.settle,
        curve: Curves.decelerate,
      );
    });
  }
}

/// Animates [scrollable] to [offset] with motion suited to how the user is
/// driving the remote: an eased glide for a single press, constant speed
/// while a key is held.
void tvScrollTo(ScrollableState scrollable, double offset) {
  final position = scrollable.position;
  if (!position.hasContentDimensions) return;
  final target =
      offset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
  if ((target - position.pixels).abs() < 0.5) {
    TvInput._heldTargets.remove(scrollable);
    return;
  }
  if (TvInput.isHeld) {
    TvInput._heldTargets[scrollable] = target;
    position.animateTo(
      target,
      duration: TvInput.heldStepFor(position.axis),
      curve: Curves.linear,
    );
  } else {
    TvInput._heldTargets.remove(scrollable);
    position.animateTo(
      target,
      duration: TvMotion.scroll,
      curve: TvMotion.curve,
    );
  }
}

/// Smoothly brings the box behind [context] into view in its nearest vertical
/// scrollable. [alignment] is where it should rest in the viewport: 0 pins it
/// to the top, 0.5 centres it, 1 pins it to the bottom.
void tvRevealVertical(BuildContext context, {double alignment = 0.5}) {
  final target = context.findRenderObject();
  if (target is! RenderBox || !target.attached || !target.hasSize) return;

  // Walk outwards through nested scrollables (a card sits in a horizontal rail
  // inside the vertical page) until we reach the vertical one.
  BuildContext current = context;
  ScrollableState? scrollable = Scrollable.maybeOf(current);
  while (scrollable != null) {
    if (scrollable.position.axis == Axis.vertical) {
      final child = current.findRenderObject();
      if (child == null || !child.attached) return;
      final viewport = RenderAbstractViewport.maybeOf(child);
      if (viewport == null) return;
      Rect? rect;
      if (!identical(child, target)) {
        rect = MatrixUtils.transformRect(
          target.getTransformTo(child),
          Offset.zero & target.size,
        );
      }
      final offset =
          viewport
              .getOffsetToReveal(
                child,
                alignment,
                rect: rect,
                axis: Axis.vertical,
              )
              .offset;
      tvScrollTo(scrollable, offset);
      return;
    }
    current = scrollable.context;
    scrollable = Scrollable.maybeOf(current);
  }
}

/// Scrolls the nearest horizontal scrollable so the box behind [context] sits
/// [inset] px from the viewport's leading edge — the fixed "anchor" slot that
/// the focused item of a rail always returns to.
void tvAnchorHorizontal(BuildContext context, {double inset = 0}) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return;
  final scrollable = Scrollable.maybeOf(context);
  if (scrollable == null || scrollable.position.axis != Axis.horizontal) return;
  final viewport = RenderAbstractViewport.maybeOf(box);
  if (viewport == null) return;
  final offset =
      viewport.getOffsetToReveal(box, 0.0, axis: Axis.horizontal).offset;
  tvScrollTo(scrollable, offset - inset);
}

/// Wrap the app's navigator in this so held UP/DOWN moves at a browsable pace
/// on every screen (see [TvInput.shouldDropVerticalRepeat]).
class TvKeyPacer extends StatelessWidget {
  const TvKeyPacer({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent:
          (_, event) =>
              TvInput.shouldDropVerticalRepeat(event)
                  ? KeyEventResult.handled
                  : KeyEventResult.ignored,
      child: child,
    );
  }
}

/// Focus nodes owned by [TvFocusable]; they scroll themselves into view, so
/// the traversal policy must not also do it.
final Expando<bool> _selfRevealing = Expando<bool>('tvSelfRevealing');

/// App-wide D-pad traversal.
///
/// Flutter's default policy *jumps* a scroll view the instant focus moves to
/// an off-screen widget, which is what makes remote navigation feel choppy.
/// This policy only moves focus; scrolling is always animated — either by
/// [TvFocusable] itself or, for any other focusable, by the fallback below.
class TvTraversalPolicy extends ReadingOrderTraversalPolicy {
  TvTraversalPolicy() : super(requestFocusCallback: _requestFocus);

  static void _requestFocus(
    FocusNode node, {
    ScrollPositionAlignmentPolicy? alignmentPolicy,
    double? alignment,
    Duration? duration,
    Curve? curve,
  }) {
    node.requestFocus();
    if (_selfRevealing[node] == true) return;
    final context = node.context;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: alignment ?? 0.5,
      alignmentPolicy:
          alignmentPolicy ?? ScrollPositionAlignmentPolicy.explicit,
      duration: duration ?? TvMotion.scroll,
      curve: curve ?? TvMotion.curve,
    );
  }
}

/// Marks a block — a hero, or a heading plus its rail — as the unit to bring
/// into view when anything inside it takes focus. Without it only the focused
/// card is revealed and its heading can end up cut off.
class TvSection extends StatefulWidget {
  const TvSection({
    super.key,
    required this.child,
    this.alignment = 0.5,
    this.onFocusChange,
    this.onKeyEvent,
  });

  final Widget child;

  /// Where the section rests in the viewport once revealed (0 top … 1 bottom).
  final double alignment;

  /// Called when focus enters or leaves the section.
  final ValueChanged<bool>? onFocusChange;

  /// Sees key presses that nothing inside the section handled — use it to
  /// override where an arrow key leads from this block.
  final FocusOnKeyEventCallback? onKeyEvent;

  static TvSectionState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<TvSectionState>();

  @override
  State<TvSection> createState() => TvSectionState();
}

class TvSectionState extends State<TvSection> {
  void reveal() => tvRevealVertical(context, alignment: widget.alignment);

  @override
  Widget build(BuildContext context) {
    if (widget.onFocusChange == null && widget.onKeyEvent == null) {
      return widget.child;
    }
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: widget.onFocusChange,
      onKeyEvent: widget.onKeyEvent,
      child: widget.child,
    );
  }
}

/// The one way to make something D-pad focusable.
///
/// Handles OK/Enter, tap, and smoothly scrolling itself (or its enclosing
/// [TvSection]) into view when focused. [builder] receives the focus state so
/// the child can draw its own highlight.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.builder,
    this.onPressed,
    this.onFocusChange,
    this.onKeyEvent,
    this.focusNode,
    this.autofocus = false,
    this.enabled = true,
    this.skipTraversal = false,
    this.reveal = true,
    this.revealAlignment = 0.5,
  });

  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onPressed;
  final ValueChanged<bool>? onFocusChange;

  /// Extra key handling, consulted before OK/Enter.
  final FocusOnKeyEventCallback? onKeyEvent;
  final FocusNode? focusNode;
  final bool autofocus;
  final bool enabled;

  /// Hides this from arrow-key traversal while still allowing an explicit
  /// `requestFocus()`.
  final bool skipTraversal;

  /// Whether to scroll into view on focus. Turn off when a parent positions
  /// the scroll view itself.
  final bool reveal;
  final double revealAlignment;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  FocusNode? _ownNode;
  bool _focused = false;

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _selfRevealing[_node] = true;
  }

  @override
  void didUpdateWidget(TvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _selfRevealing[_node] = true;
    }
  }

  @override
  void dispose() {
    _ownNode?.dispose();
    super.dispose();
  }

  void _reveal() {
    if (!mounted) return;
    final section = TvSection.maybeOf(context);
    if (section != null) {
      section.reveal();
    } else {
      tvRevealVertical(context, alignment: widget.revealAlignment);
    }
  }

  void _onFocusChange(bool focused) {
    if (focused != _focused) setState(() => _focused = focused);
    if (focused && widget.reveal) {
      final box = context.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        _reveal();
      } else {
        // Focused before its first layout (autofocus on a new page).
        WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
      }
    }
    widget.onFocusChange?.call(focused);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final custom = widget.onKeyEvent?.call(node, event);
    if (custom != null && custom != KeyEventResult.ignored) return custom;
    if (widget.onPressed != null && tvIsSelectKey(event.logicalKey)) {
      if (event is KeyUpEvent) return KeyEventResult.ignored;
      if (event is KeyDownEvent) widget.onPressed!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
      skipTraversal: widget.skipTraversal,
      onFocusChange: _onFocusChange,
      onKeyEvent: _onKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap:
            widget.enabled
                ? () {
                  _node.requestFocus();
                  widget.onPressed?.call();
                }
                : null,
        child: widget.builder(context, _focused),
      ),
    );
  }
}

/// Keeps LEFT/RIGHT inside one horizontal strip (a rail, a button row).
///
/// Flutter's directional traversal falls back to "nearest widget anywhere"
/// when nothing lies directly to the side, so pressing RIGHT on the last card
/// of a row could leap to a different row. Inside this group, sideways moves
/// only ever land on a neighbour in the same strip, and stop at the ends.
class TvRowFocusGroup extends StatelessWidget {
  const TvRowFocusGroup({super.key, required this.child});

  final Widget child;

  KeyEventResult _onKeyEvent(
    BuildContext context,
    FocusNode node,
    KeyEvent event,
  ) {
    final key = event.logicalKey;
    final right = key == LogicalKeyboardKey.arrowRight;
    if (!right && key != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    final current = FocusManager.instance.primaryFocus;
    if (current == null || current.context == null) {
      return KeyEventResult.ignored;
    }
    final from = current.rect;
    FocusNode? best;
    var bestDistance = double.infinity;
    for (final candidate in node.descendants) {
      if (identical(candidate, current)) continue;
      if (!candidate.canRequestFocus || candidate.skipTraversal) continue;
      if (candidate.context == null) continue;
      final rect = candidate.rect;
      // Same visual line only.
      if (rect.bottom <= from.top || rect.top >= from.bottom) continue;
      final distance =
          right
              ? rect.center.dx - from.center.dx
              : from.center.dx - rect.center.dx;
      if (distance <= 0.5) continue;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = candidate;
      }
    }
    if (best != null) {
      // We bypassed the policy, so drop its "go back the way you came" memory.
      final policy = FocusTraversalGroup.maybeOf(context);
      final scope = current.nearestScope;
      if (policy is DirectionalFocusTraversalPolicyMixin && scope != null) {
        policy.invalidateScopeData(scope);
      }
      best.requestFocus();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) => _onKeyEvent(context, node, event),
      child: child,
    );
  }
}

/// The shared focus highlight: a gentle scale-up plus a white ring.
///
/// Deliberately has no blurred glow — animating a blur re-rasterises it every
/// frame, which TV chipsets can't keep up with. Scale and a stroke are cheap.
class TvFocusFrame extends StatelessWidget {
  const TvFocusFrame({
    super.key,
    required this.focused,
    required this.child,
    this.radius = 6,
    this.scale = 1.08,
    this.ringWidth = 2.5,
    this.circle = false,
  });

  final bool focused;
  final Widget child;
  final double radius;
  final double scale;
  final double ringWidth;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(
      color: focused ? Colors.white : Colors.transparent,
      width: ringWidth,
      strokeAlign: BorderSide.strokeAlignOutside,
    );
    return AnimatedScale(
      scale: focused ? scale : 1.0,
      duration: TvMotion.focus,
      curve: TvMotion.curve,
      child: AnimatedContainer(
        duration: TvMotion.focus,
        curve: TvMotion.curve,
        foregroundDecoration:
            circle
                ? ShapeDecoration(shape: CircleBorder(side: side))
                : BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.fromBorderSide(side),
                ),
        child:
            circle
                ? ClipOval(child: child)
                : ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: child,
                ),
      ),
    );
  }
}
