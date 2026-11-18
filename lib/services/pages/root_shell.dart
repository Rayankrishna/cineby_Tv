import 'dart:async';

import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/home.dart';
import 'package:cineby_tv/services/pages/library_page.dart';
import 'package:cineby_tv/services/pages/profile_page.dart';
import 'package:cineby_tv/services/pages/search.dart';
import 'package:cineby_tv/stores/stores.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:cineby_tv/widgets/tv_focus.dart';
import 'package:cineby_tv/widgets/tv_image.dart';
import 'package:cineby_tv/widgets/tv_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

const int _tabHome = 0;
const int _tabSearch = 1;
const int _tabList = 2;
const int _tabProfile = 3;
const int _tabCount = 4;

class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell>
    with SingleTickerProviderStateMixin {
  int _index = _tabHome;
  final FocusScopeNode _navScope = FocusScopeNode(debugLabel: 'nav');
  final FocusScopeNode _contentScope = FocusScopeNode(debugLabel: 'content');
  final List<FocusNode> _tabNodes = List.generate(
    _tabCount,
    (i) => FocusNode(debugLabel: 'tab-$i'),
  );
  final List<TvTabHandle> _tabHandles = List.generate(
    _tabCount,
    (_) => TvTabHandle(),
  );

  /// Tab pages are built the first time they are opened, then kept alive so
  /// they hold their scroll position and data.
  final Map<int, Widget> _pages = {};

  late final AnimationController _pageFade = AnimationController(
    vsync: this,
    duration: TvMotion.fade,
    value: 1,
  );

  bool _navFocused = false;
  DateTime? _lastBackPress;
  Timer? _tabTimer;

  @override
  void initState() {
    super.initState();
    watchlistStore.fetch();
    historyStore.fetchContinueWatching();
  }

  @override
  void dispose() {
    _tabTimer?.cancel();
    _pageFade.dispose();
    _navScope.dispose();
    _contentScope.dispose();
    for (final node in _tabNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _pageFor(int index) {
    return _pages.putIfAbsent(index, () {
      switch (index) {
        case _tabHome:
          return MyHomePage(title: 'Home', tab: _tabHandles[_tabHome]);
        case _tabSearch:
          return SearchPage(tab: _tabHandles[_tabSearch]);
        case _tabList:
          return const LibraryPage();
        default:
          return const ProfilePage();
      }
    });
  }

  void _selectTab(int index) {
    _tabTimer?.cancel();
    if (index == _index) return;
    setState(() => _index = index);
    _pageFade.forward(from: 0);
  }

  /// Arrowing across the tabs previews each page, but only once focus rests
  /// on one — otherwise sweeping from Home to Profile would build and fetch
  /// every page in between. The dwell has to outlast a deliberate press-to-
  /// press gap, or ordinary stepping still commits every tab on the way.
  void _onTabFocused(int index) {
    _tabTimer?.cancel();
    if (index == _index) return;
    _tabTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _selectTab(index);
    });
  }

  void _onTabPressed(int index) {
    _selectTab(index);
    // Let the page build before looking for something to focus in it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusContent();
    });
  }

  void _focusNav() => _tabNodes[_index].requestFocus();

  void _focusContent() {
    _contentScope.requestFocus();
    if (_contentScope.focusedChild != null) return;
    // Nothing remembered on this page yet: start where the page asks to,
    // otherwise at its top-left control.
    final entry = _tabHandles[_index].entryNode;
    if (entry != null && entry.context != null && entry.canRequestFocus) {
      entry.requestFocus();
      return;
    }
    FocusNode? first;
    Rect? firstRect;
    for (final node in _contentScope.traversalDescendants) {
      if (node.context == null) continue;
      final rect = node.rect;
      final better =
          firstRect == null ||
          rect.top < firstRect.top - 1 ||
          ((rect.top - firstRect.top).abs() <= 1 && rect.left < firstRect.left);
      if (better) {
        first = node;
        firstRect = rect;
      }
    }
    first?.requestFocus();
  }

  void _onPopInvoked(bool didPop, Object? result) {
    if (didPop) return;
    // A tab preview armed by the last arrow press must not land after BACK
    // has already moved on — otherwise the tab silently changes behind the
    // exit confirmation.
    _tabTimer?.cancel();
    if (!_navFocused) {
      // Give the page first refusal (Home returns to its hero), then pull
      // focus up to the nav bar.
      if (_tabHandles[_index].onBack?.call() ?? false) return;
      _focusNav();
      return;
    }
    if (_index != _tabHome) {
      _selectTab(_tabHome);
      _tabNodes[_tabHome].requestFocus();
      return;
    }
    // On Home in the nav bar → confirm exit on a second press.
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    tvToast(context, 'Press back again to exit');
  }

  KeyEventResult _onShellKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = e.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp) {
      if (_navFocused) return KeyEventResult.handled;
      if (TvInput.shouldDropVerticalRepeat(e)) return KeyEventResult.handled;
      // Try ordinary directional traversal first. Only escape to the nav bar
      // when there is no focusable widget above the current one — and never
      // on auto-repeat, so holding UP stops at the top of the page.
      final primary = FocusManager.instance.primaryFocus;
      final moved = primary?.focusInDirection(TraversalDirection.up) ?? false;
      if (!moved && e is KeyDownEvent) _focusNav();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown && _navFocused) {
      // Commit whichever tab is highlighted before dropping into it.
      final focusedTab = _tabNodes.indexWhere((n) => n.hasFocus);
      if (focusedTab >= 0 && focusedTab != _index) {
        _onTabPressed(focusedTab);
      } else {
        _focusContent();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopInvoked,
      child: Scaffold(
        backgroundColor: kDeepBlack,
        body: Focus(
          canRequestFocus: false,
          descendantsAreFocusable: true,
          onKeyEvent: _onShellKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FocusScope(
                node: _contentScope,
                autofocus: true,
                child: FadeTransition(
                  // Dip rather than cut: stepping across the nav restarts
                  // this fade mid-flight, and starting from 0 would strobe
                  // the whole content area to black at every step.
                  opacity: Tween<double>(begin: 0.62, end: 1.0)
                      .chain(CurveTween(curve: Curves.easeOut))
                      .animate(_pageFade),
                  child: IndexedStack(
                    index: _index,
                    sizing: StackFit.expand,
                    children: [
                      for (var i = 0; i < _tabCount; i++)
                        if (i == _index || _pages.containsKey(i))
                          _pageFor(i)
                        else
                          const SizedBox.shrink(),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: FocusScope(
                  node: _navScope,
                  onFocusChange: (f) {
                    if (_navFocused != f) setState(() => _navFocused = f);
                  },
                  child: _TopNav(
                    index: _index,
                    navFocused: _navFocused,
                    nodes: _tabNodes,
                    onFocused: _onTabFocused,
                    onPressed: _onTabPressed,
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

class _TopNav extends StatelessWidget {
  const _TopNav({
    required this.index,
    required this.navFocused,
    required this.nodes,
    required this.onFocused,
    required this.onPressed,
  });

  final int index;
  final bool navFocused;
  final List<FocusNode> nodes;
  final ValueChanged<int> onFocused;
  final ValueChanged<int> onPressed;

  static const _labels = ['Home', 'Search', 'My List'];
  static const _icons = <IconData?>[null, Icons.search_rounded, null];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kTvNavHeight.s(context),
      padding: EdgeInsets.symmetric(horizontal: kTvGutter.s(context)),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Color(0x00000000)],
        ),
      ),
      child: TvRowFocusGroup(
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5.s(context)),
              child: Image.asset(
                'assets/favicon.jpg',
                width: 26.s(context),
                height: 26.s(context),
                fit: BoxFit.cover,
              ),
            ),
            SizedBox(width: 9.s(context)),
            Text(
              'REELIX',
              style: TextStyle(
                color: kNetflixRed,
                fontSize: 17.s(context),
                fontWeight: FontWeight.w900,
                letterSpacing: 3.5.s(context),
              ),
            ),
            SizedBox(width: 26.s(context)),
            for (var i = 0; i < _labels.length; i++)
              _NavTab(
                label: _labels[i],
                icon: _icons[i],
                selected: index == i,
                navFocused: navFocused,
                focusNode: nodes[i],
                onFocused: () => onFocused(i),
                onPressed: () => onPressed(i),
              ),
            const Spacer(),
            _NavAvatar(
              selected: index == _tabProfile,
              focusNode: nodes[_tabProfile],
              onFocused: () => onFocused(_tabProfile),
              onPressed: () => onPressed(_tabProfile),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.label,
    required this.selected,
    required this.navFocused,
    required this.focusNode,
    required this.onFocused,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final bool navFocused;
  final FocusNode focusNode;
  final VoidCallback onFocused;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      focusNode: focusNode,
      reveal: false,
      onPressed: onPressed,
      onFocusChange: (f) {
        if (f) onFocused();
      },
      builder: (context, focused) {
        final fg =
            focused
                ? Colors.black
                : Colors.white.withValues(alpha: selected ? 1 : 0.62);
        return AnimatedContainer(
          duration: TvMotion.focus,
          curve: TvMotion.curve,
          height: 30.s(context),
          margin: EdgeInsets.symmetric(horizontal: 2.s(context)),
          padding: EdgeInsets.symmetric(horizontal: 13.s(context)),
          decoration: BoxDecoration(
            color: focused ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(100),
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: fg, size: 16.s(context)),
                    SizedBox(width: 5.s(context)),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 13.5.s(context),
                      fontWeight:
                          selected || focused
                              ? FontWeight.w700
                              : FontWeight.w500,
                    ),
                  ),
                ],
              ),
              // Marks the open tab while focus is down in the page.
              Positioned(
                bottom: 1.s(context),
                child: AnimatedContainer(
                  duration: TvMotion.focus,
                  curve: TvMotion.curve,
                  height: 2.s(context),
                  width: selected && !focused ? 16.s(context) : 0,
                  decoration: BoxDecoration(
                    color: kNetflixRed,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NavAvatar extends StatelessWidget {
  const _NavAvatar({
    required this.selected,
    required this.focusNode,
    required this.onFocused,
    required this.onPressed,
  });

  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onFocused;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final size = 28.s(context);
    return TvFocusable(
      focusNode: focusNode,
      reveal: false,
      onPressed: onPressed,
      onFocusChange: (f) {
        if (f) onFocused();
      },
      builder: (context, focused) {
        return AnimatedScale(
          scale: focused ? 1.12 : 1.0,
          duration: TvMotion.focus,
          curve: TvMotion.curve,
          child: AnimatedContainer(
            duration: TvMotion.focus,
            padding: EdgeInsets.all(2.s(context)),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color:
                    focused
                        ? Colors.white
                        : (selected ? kNetflixRed : Colors.transparent),
                width: 2.s(context),
              ),
            ),
            child: ClipOval(
              child: SizedBox(
                width: size,
                height: size,
                child: Observer(
                  builder:
                      (_) => TvImage(
                        path: authStore.avatarPath,
                        kind: TmdbImageKind.profile,
                        width: size,
                        alignment: Alignment.topCenter,
                        fallback: Container(
                          color: kSurfaceHi,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.person_rounded,
                            color: kTextGrey,
                            size: 18.s(context),
                          ),
                        ),
                      ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
