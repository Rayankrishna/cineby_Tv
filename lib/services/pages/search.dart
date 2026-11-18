import 'dart:async';

import 'package:cineby_tv/models/search_model.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/details.dart';
import 'package:cineby_tv/services/tmdb_client.dart';
import 'package:cineby_tv/stores/search_store.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:cineby_tv/widgets/tv_focus.dart';
import 'package:cineby_tv/widgets/tv_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

/// How long to wait after the last key before querying, so results don't
/// reload (and flicker) on every letter.
const Duration _searchDelay = Duration(milliseconds: 350);

const int _resultColumns = 5;

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.tab});
  final TvTabHandle? tab;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final SearchStore _store = SearchStore();

  static const List<String> _keys = [
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '0',
  ];

  String _query = '';

  /// True between a key press and the debounced request actually starting.
  bool _pending = false;
  Timer? _debounce;

  /// Owns the results grid's scroll view, so a new query can start at the top
  /// instead of inheriting the offset the previous one was left at.
  final ScrollController _results = ScrollController();

  /// Shown before the user types anything.
  List<SearchResult> _suggestions = const [];

  /// The "A" key: where focus lands when entering the page, so the user can
  /// start typing straight away rather than landing in the suggestions.
  final FocusNode _firstKeyNode = FocusNode(debugLabel: 'search-key-a');

  @override
  void initState() {
    super.initState();
    widget.tab?.entryNode = _firstKeyNode;
    _loadSuggestions();
  }

  @override
  void dispose() {
    if (widget.tab?.entryNode == _firstKeyNode) widget.tab?.entryNode = null;
    _debounce?.cancel();
    _results.dispose();
    _firstKeyNode.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    try {
      final res = await tmdbDio.get(homeUrl);
      final items =
          SearchResponse.fromJson(res.data).results
              .where((r) => r.posterPath != null && r.mediaType != 'person')
              .toList();
      if (mounted) setState(() => _suggestions = items);
    } catch (_) {
      // Suggestions are optional; the keyboard still works.
    }
  }

  void _setQuery(String value) {
    _debounce?.cancel();
    final empty = value.trim().isEmpty;
    // A new query is a new result set: start it at the top instead of
    // inheriting the offset the last one was scrolled to.
    if (value != _query && _results.hasClients) _results.jumpTo(0);
    setState(() {
      _query = value;
      _pending = !empty;
    });
    if (empty) {
      _store.setSearchQuery('');
      return;
    }
    _debounce = Timer(_searchDelay, () {
      if (!mounted) return;
      setState(() => _pending = false);
      _store.setSearchQuery(value);
    });
  }

  void _open(SearchResult r) {
    final date = r.releaseDate ?? r.firstAirDate;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => MovieDetailsPage(
              movieId: r.id.toString(),
              mediaType: r.mediaType ?? 'movie',
              preview: DetailPreview(
                title: r.title ?? r.name,
                backdropPath: r.backdropPath,
                overview: r.overview,
                year:
                    (date != null && date.length >= 4)
                        ? date.substring(0, 4)
                        : null,
                rating: r.voteAverage,
              ),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kDeepBlack,
      child: Padding(
        padding: EdgeInsets.only(top: kTvNavHeight.s(context)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 292.s(context),
              child: TvSection(
                onKeyEvent: _onKeyboardKey,
                child: _buildKeyboard(context),
              ),
            ),
            Expanded(child: Observer(builder: (_) => _buildResults(context))),
          ],
        ),
      ),
    );
  }

  // ============== KEYBOARD ==============

  /// Nothing sits below the Space/Backspace/Clear row, so Flutter's
  /// out-of-band directional fallback would throw focus sideways into the
  /// middle of the results grid. Swallow DOWN whenever the keyboard itself
  /// holds no node the policy could have moved to.
  KeyEventResult _onKeyboardKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    final cur = FocusManager.instance.primaryFocus;
    if (cur == null || cur.context == null) return KeyEventResult.ignored;
    final below = node.descendants.any(
      (n) =>
          n.canRequestFocus &&
          !n.skipTraversal &&
          n.context != null &&
          n.rect.center.dy >= cur.rect.bottom,
    );
    return below ? KeyEventResult.ignored : KeyEventResult.handled;
  }

  Widget _buildKeyboard(BuildContext context) {
    final gap = 6.s(context);
    final typed = _query.isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        kTvGutter.s(context),
        14.s(context),
        12.s(context),
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 40.s(context),
            padding: EdgeInsets.symmetric(horizontal: 10.s(context)),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(5.s(context)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: typed ? kTextWhite : kTextGrey,
                  size: 20.s(context),
                ),
                SizedBox(width: 8.s(context)),
                Expanded(
                  child: Text(
                    typed ? _query : 'Search movies and shows',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: typed ? kTextWhite : kTextGrey,
                      fontSize: (typed ? 16 : 13).s(context),
                      fontWeight: typed ? FontWeight.w700 : FontWeight.w400,
                      letterSpacing: typed ? 1.s(context) : 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 14.s(context)),
          for (var row = 0; row < _keys.length ~/ 6; row++)
            Padding(
              padding: EdgeInsets.only(bottom: gap),
              child: Row(
                children: [
                  for (var col = 0; col < 6; col++) ...[
                    if (col > 0) SizedBox(width: gap),
                    Expanded(
                      child: _Key(
                        label: _keys[row * 6 + col],
                        focusNode: row == 0 && col == 0 ? _firstKeyNode : null,
                        onPressed:
                            () => _setQuery('$_query${_keys[row * 6 + col]}'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _Key(
                  icon: Icons.space_bar_rounded,
                  label: 'Space',
                  onPressed: () {
                    if (_query.isNotEmpty && !_query.endsWith(' ')) {
                      _setQuery('$_query ');
                    }
                  },
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                flex: 2,
                child: _Key(
                  icon: Icons.backspace_outlined,
                  onPressed: () {
                    if (_query.isNotEmpty) {
                      _setQuery(_query.substring(0, _query.length - 1));
                    }
                  },
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                flex: 2,
                child: _Key(label: 'Clear', onPressed: () => _setQuery('')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============== RESULTS ==============

  Widget _buildResults(BuildContext context) {
    final query = _query.trim();
    final padding = EdgeInsets.fromLTRB(
      16.s(context),
      10.s(context),
      kTvGutter.s(context),
      70.s(context),
    );

    if (query.isEmpty) {
      if (_suggestions.isEmpty) {
        return const TvMessage(
          icon: Icons.search_rounded,
          title: 'Find something to watch',
          detail: 'Search by title using the keyboard.',
        );
      }
      return _grid(context, 'Trending Searches', _suggestions, padding);
    }

    final results = _store.searchResults;
    final busy = _pending || _store.isLoading;
    // Results on screen belong to an older query while the next one loads.
    final stale = busy || _store.searchQuery.trim() != query;

    // A failed query must never leave the previous query's results on screen.
    if (!busy &&
        _store.errorMessage != null &&
        _store.searchQuery.trim() == query) {
      return TvMessage(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't search",
        detail: 'Check your connection and try again.',
        actions: [
          TvButton(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            onPressed: () {
              // This card unmounts the instant the refetch flips `busy`, so
              // hand focus back to the keyboard first; otherwise it falls to
              // the root scope and the D-pad goes dead until BACK.
              FocusManager.instance.primaryFocus
                  ?.focusInDirection(TraversalDirection.left);
              _store.fetchSearchResults(query);
            },
          ),
        ],
      );
    }

    if (results.isEmpty) {
      if (stale) {
        return Padding(
          padding: EdgeInsets.only(top: 34.s(context)),
          child: TvPosterGridSkeleton(
            columns: _resultColumns,
            padding: padding,
          ),
        );
      }
      return TvMessage(
        icon: Icons.search_off_rounded,
        title: 'No matches for "$query"',
        detail: 'Check the spelling or try a shorter title.',
      );
    }
    return AnimatedOpacity(
      opacity: stale ? 0.45 : 1,
      duration: TvMotion.focus,
      child: _grid(context, 'Results for "$query"', results, padding),
    );
  }

  Widget _grid(
    BuildContext context,
    String heading,
    List<SearchResult> items,
    EdgeInsets padding,
  ) {
    return CustomScrollView(
      controller: _results,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(
              left: padding.left,
              top: 16.s(context),
              bottom: 4.s(context),
            ),
            child: Text(
              heading,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: kTextWhite,
                fontSize: 16.s(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: padding,
          sliver: SliverGrid(
            gridDelegate: tvPosterGridDelegate(
              context,
              columns: _resultColumns,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              final r = items[i];
              return TvPosterCard(
                width: double.infinity,
                posterPath: r.posterPath,
                title: r.title ?? r.name,
                onPressed: () => _open(r),
              );
            }, childCount: items.length),
          ),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.onPressed, this.label, this.icon, this.focusNode});

  final String? label;
  final IconData? icon;
  final FocusNode? focusNode;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    return TvFocusable(
      reveal: false,
      focusNode: focusNode,
      onPressed: onPressed,
      builder: (context, focused) {
        final fg = focused ? Colors.black : kTextWhite;
        return AnimatedContainer(
          duration: TvMotion.focus,
          curve: TvMotion.curve,
          height: 34.s(context),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                focused ? Colors.white : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(5.s(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) Icon(icon, color: fg, size: 17.s(context)),
              if (icon != null && label != null) SizedBox(width: 5.s(context)),
              if (label != null)
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: (label.length > 1 ? 12 : 15).s(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
