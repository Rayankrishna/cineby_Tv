import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/home.dart';
import 'package:cineby_tv/services/pages/library_page.dart';
import 'package:cineby_tv/services/pages/profile_page.dart';
import 'package:cineby_tv/services/pages/search.dart';
import 'package:cineby_tv/stores/stores.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});
  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  final FocusScopeNode _navScope = FocusScopeNode(debugLabel: 'nav');
  final FocusScopeNode _contentScope = FocusScopeNode(debugLabel: 'content');
  bool _navFocused = false;
  DateTime? _lastBackPress;

  late final List<Widget> _pages = const [
    MyHomePage(title: 'Home'),
    SearchPage(),
    LibraryPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    watchlistStore.fetch();
    historyStore.fetchContinueWatching();
  }

  @override
  void dispose() {
    _navScope.dispose();
    _contentScope.dispose();
    super.dispose();
  }

  void _onPopInvoked(bool didPop, Object? result) {
    if (didPop) return;
    // If user is in content, pull focus up to the top nav (Netflix-y).
    if (!_navFocused) {
      _navScope.requestFocus();
      return;
    }
    // Already in nav → confirm exit on second press.
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Press back again to exit'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  KeyEventResult _onShellKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = e.logicalKey;
    final primary = FocusManager.instance.primaryFocus;

    if (key == LogicalKeyboardKey.arrowUp && !_navFocused) {
      // Try ordinary directional traversal first. Only escape to the nav bar
      // when there is no focusable widget above the current one.
      final moved = primary?.focusInDirection(TraversalDirection.up) ?? false;
      if (moved) return KeyEventResult.handled;
      _navScope.requestFocus();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.arrowDown && _navFocused) {
      _contentScope.requestFocus();
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
          child: Column(
            children: [
              FocusScope(
                node: _navScope,
                onFocusChange: (f) {
                  if (_navFocused != f) setState(() => _navFocused = f);
                },
                child: _TopNav(
                  index: _index,
                  onChanged: (i) {
                    // Keep focus on the tab; user must press DOWN to drop into content.
                    setState(() => _index = i);
                  },
                ),
              ),
              Expanded(
                child: FocusScope(
                  node: _contentScope,
                  autofocus: true,
                  child: IndexedStack(
                    index: _index,
                    children: _pages,
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
  final int index;
  final ValueChanged<int> onChanged;
  const _TopNav({required this.index, required this.onChanged});

  static const _items = [
    'Home',
    'Search',
    'My List',
    'Profile',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64.s(context),
      padding: EdgeInsets.symmetric(horizontal: 40.s(context)),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xCC000000),
            Color(0x00000000),
          ],
        ),
      ),
      child: Row(
        children: [
          // Logo
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6.s(context)),
                child: Image.asset(
                  'assets/favicon.jpg',
                  width: 34.s(context),
                  height: 34.s(context),
                  fit: BoxFit.cover,
                ),
              ),
              SizedBox(width: 10.s(context)),
              Text(
                'REELIX',
                style: TextStyle(
                  color: kNetflixRed,
                  fontSize: 20.s(context),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4.s(context),
                ),
              ),
            ],
          ),
          SizedBox(width: 40.s(context)),
          // Nav items
          for (var i = 0; i < _items.length; i++)
            _NavItem(
              label: _items[i],
              selected: index == i,
              onActivate: () => onChanged(i),
            ),
          const Spacer(),
          // Profile avatar (small)
          Observer(
            builder: (_) {
              final avatar = authStore.avatarPath;
              return Padding(
                padding: EdgeInsets.only(left: 8.s(context)),
                child: Container(
                  width: 32.s(context),
                  height: 32.s(context),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kSurfaceHi,
                    image: avatar != null
                        ? DecorationImage(
                            image: NetworkImage('$imgW185$avatar'),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: avatar == null
                      ? Icon(Icons.person, color: kTextGrey, size: 18.s(context))
                      : null,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onActivate;
  const _NavItem({
    required this.label,
    required this.selected,
    required this.onActivate,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.space)) {
          onActivate();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          // Hover-select: arrowing onto a tab switches pages.
          if (focused && !selected) {
            WidgetsBinding.instance.addPostFrameCallback((_) => onActivate());
          }
          final active = focused || selected;
          return GestureDetector(
            onTap: onActivate,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: 18.s(context),
                vertical: 8.s(context),
              ),
              margin: EdgeInsets.symmetric(horizontal: 2.s(context)),
              decoration: BoxDecoration(
                color: focused ? Colors.white.withOpacity(0.06) : Colors.transparent,
                borderRadius: BorderRadius.circular(6.s(context)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    style: TextStyle(
                      color: active ? kTextWhite : Colors.white.withOpacity(0.65),
                      fontSize: 14.s(context),
                      fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                      letterSpacing: 0.3.s(context),
                    ),
                    child: Text(label),
                  ),
                  SizedBox(height: 4.s(context)),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    height: 2.s(context),
                    width: active ? 24.s(context) : 0,
                    decoration: BoxDecoration(
                      color: kNetflixRed,
                      borderRadius: BorderRadius.circular(2.s(context)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
