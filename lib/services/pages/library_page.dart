import 'package:cineby_tv/models/history_item.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/details.dart';
import 'package:cineby_tv/stores/stores.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:cineby_tv/widgets/tv_focus.dart';
import 'package:cineby_tv/widgets/tv_image.dart';
import 'package:cineby_tv/widgets/tv_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int _tab = 0;

  /// True once focus is already resting on the chip row, so arrowing between
  /// the chips previews a tab but arriving from the grid below does not.
  bool _chipsHadFocus = false;

  @override
  void initState() {
    super.initState();
    watchlistStore.fetch();
    historyStore.fetch();
  }

  void _showTab(int tab) {
    if (_tab != tab) setState(() => _tab = tab);
  }

  void _onChipFocus(int tab, bool focused) {
    if (!focused) return;
    if (_chipsHadFocus) _showTab(tab);
    _chipsHadFocus = true;
  }

  @override
  Widget build(BuildContext context) {
    final gutter = kTvGutter.s(context);
    return ColoredBox(
      color: kDeepBlack,
      child: Padding(
        padding: EdgeInsets.only(top: kTvNavHeight.s(context)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                gutter,
                14.s(context),
                gutter,
                8.s(context),
              ),
              // Focus leaving the chip row clears the preview guard, so the
              // next arrival from the grid below only moves the focus ring.
              child: TvSection(
                onFocusChange: (f) {
                  if (!f) _chipsHadFocus = false;
                },
                child: TvRowFocusGroup(
                  child: Row(
                    children: [
                      Text(
                        'My List',
                        style: TextStyle(
                          color: kTextWhite,
                          fontSize: 26.s(context),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(width: 22.s(context)),
                      // Arrowing between the tabs shows one straight away.
                      TvChip(
                        label: 'Watchlist',
                        icon: Icons.bookmark_rounded,
                        selected: _tab == 0,
                        onFocusChange: (f) => _onChipFocus(0, f),
                        onPressed: () => _showTab(0),
                      ),
                      SizedBox(width: 8.s(context)),
                      TvChip(
                        label: 'History',
                        icon: Icons.history_rounded,
                        selected: _tab == 1,
                        onFocusChange: (f) => _onChipFocus(1, f),
                        onPressed: () => _showTab(1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: TvFadeIn(
                key: ValueKey(_tab),
                child:
                    _tab == 0 ? const _WatchlistGrid() : const _HistoryList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _openDetails(
  BuildContext context, {
  required int tmdbId,
  required String mediaType,
  String? title,
  String? backdropPath,
}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder:
          (_) => MovieDetailsPage(
            movieId: tmdbId.toString(),
            mediaType: mediaType,
            preview: DetailPreview(title: title, backdropPath: backdropPath),
          ),
    ),
  );
}

class _WatchlistGrid extends StatelessWidget {
  const _WatchlistGrid();

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final items = watchlistStore.items;
        if (items.isEmpty) {
          if (watchlistStore.isLoading) return const TvPosterGridSkeleton();
          return const TvMessage(
            icon: Icons.bookmark_outline_rounded,
            title: 'Your list is empty',
            detail: 'Add a movie or show with "My List" to find it here.',
          );
        }
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(
            kTvGutter.s(context),
            12.s(context),
            kTvGutter.s(context),
            70.s(context),
          ),
          gridDelegate: tvPosterGridDelegate(context),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            return TvPosterCard(
              width: double.infinity,
              posterPath: item.posterPath,
              title: item.title,
              onPressed:
                  () => _openDetails(
                    context,
                    tmdbId: item.tmdbId,
                    mediaType: item.mediaType,
                    title: item.title,
                  ),
            );
          },
        );
      },
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList();

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final items = historyStore.items;
        if (items.isEmpty) {
          if (historyStore.isLoading) return const _HistoryListSkeleton();
          return const TvMessage(
            icon: Icons.history_rounded,
            title: 'No history yet',
            detail: 'Titles you watch will show up here.',
          );
        }
        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
            kTvGutter.s(context),
            8.s(context),
            kTvGutter.s(context),
            70.s(context),
          ),
          itemCount: items.length,
          itemBuilder:
              (context, i) => Padding(
                padding: EdgeInsets.only(bottom: 8.s(context)),
                child: _HistoryTile(key: ValueKey(items[i].id), item: items[i]),
              ),
        );
      },
    );
  }
}

/// One watched title: OK reopens it; RIGHT reaches the remove button.
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({super.key, required this.item});
  final HistoryItem item;

  String get _subtitle {
    final isEpisode =
        item.mediaType == 'tv' &&
        item.seasonNumber != null &&
        item.episodeNumber != null;
    final kind =
        isEpisode
            ? 'Season ${item.seasonNumber} · Episode ${item.episodeNumber}'
            : (item.mediaType == 'tv' ? 'Series' : 'Film');
    if (item.completed) return '$kind · Watched';
    final duration = item.durationSeconds ?? 0;
    if (duration <= 0) return kind;
    final left = ((duration - item.progressSeconds) / 60).ceil();
    return left > 0 ? '$kind · $left min left' : kind;
  }

  @override
  Widget build(BuildContext context) {
    final thumbWidth = 112.s(context);
    return TvRowFocusGroup(
      child: Row(
        children: [
          Expanded(
            child: TvFocusable(
              onPressed:
                  () => _openDetails(
                    context,
                    tmdbId: item.tmdbId,
                    mediaType: item.mediaType,
                    title: item.title,
                    backdropPath: item.backdropPath,
                  ),
              builder: (context, focused) {
                return AnimatedContainer(
                  duration: TvMotion.focus,
                  curve: TvMotion.curve,
                  padding: EdgeInsets.all(7.s(context)),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(
                      alpha: focused ? 0.14 : 0.05,
                    ),
                    borderRadius: BorderRadius.circular(7.s(context)),
                    border: Border.all(
                      color: focused ? Colors.white : Colors.transparent,
                      width: 2.s(context),
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4.s(context)),
                        child: SizedBox(
                          width: thumbWidth,
                          height: thumbWidth * 9 / 16,
                          child: TvImage(
                            path: item.backdropPath,
                            kind: TmdbImageKind.backdrop,
                            width: thumbWidth,
                            fallback: const ColoredBox(color: kSurfaceHi),
                          ),
                        ),
                      ),
                      SizedBox(width: 14.s(context)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.title ?? 'Untitled',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: kTextWhite,
                                fontSize: 14.5.s(context),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 3.s(context)),
                            Text(
                              _subtitle,
                              style: TextStyle(
                                color: kTextGrey,
                                fontSize: 11.5.s(context),
                              ),
                            ),
                            SizedBox(height: 9.s(context)),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: TvProgressBar(
                                value:
                                    item.completed ? 1 : item.progressFraction,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 10.s(context)),
                    ],
                  ),
                );
              },
            ),
          ),
          SizedBox(width: 10.s(context)),
          TvFocusable(
            onPressed: () {
              // Hand focus to a neighbour BEFORE this row unmounts. Disposing
              // the focused node drops focus to the root scope, which sits
              // above every Shortcuts/Actions in the app, so no key event
              // reaches traversal and the D-pad goes dead until BACK.
              final node = FocusManager.instance.primaryFocus;
              if (node != null &&
                  !node.focusInDirection(TraversalDirection.down)) {
                node.focusInDirection(TraversalDirection.up);
              }
              historyStore.remove(item.id);
            },
            builder: (context, focused) {
              return AnimatedContainer(
                duration: TvMotion.focus,
                curve: TvMotion.curve,
                width: 38.s(context),
                height: 38.s(context),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      focused
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.07),
                ),
                child: Icon(
                  Icons.close_rounded,
                  color: focused ? Colors.black : kTextGrey,
                  size: 20.s(context),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Placeholder rows that match [_HistoryTile]'s geometry, so the swap to real
/// history does not shift anything.
class _HistoryListSkeleton extends StatelessWidget {
  const _HistoryListSkeleton();

  @override
  Widget build(BuildContext context) {
    final thumbWidth = 112.s(context);
    return TvPulse(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          kTvGutter.s(context),
          8.s(context),
          kTvGutter.s(context),
          70.s(context),
        ),
        itemCount: 5,
        itemBuilder:
            (context, _) => Padding(
              padding: EdgeInsets.only(bottom: 8.s(context)),
              child: Container(
                // 7 padding + 2 border of the real tile.
                padding: EdgeInsets.all(9.s(context)),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(7.s(context)),
                ),
                child: Row(
                  children: [
                    TvSkeletonBox(
                      width: thumbWidth,
                      height: thumbWidth * 9 / 16,
                      radius: 4,
                    ),
                    SizedBox(width: 14.s(context)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TvSkeletonBox(
                            width: 180.s(context),
                            height: 13.s(context),
                          ),
                          SizedBox(height: 8.s(context)),
                          TvSkeletonBox(
                            width: 110.s(context),
                            height: 10.s(context),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}
