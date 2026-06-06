import 'package:cineby_tv/models/history_item.dart';
import 'package:cineby_tv/models/watchlist_item.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/details.dart';
import 'package:cineby_tv/stores/stores.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    watchlistStore.fetch();
    historyStore.fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32.s(context), vertical: 24.s(context)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Library',
            style: TextStyle(
              color: kTextWhite,
              fontSize: 36.s(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 16.s(context)),
          Row(
            children: [
              _Tab(
                label: 'Watchlist',
                selected: _tab == 0,
                onTap: () => setState(() => _tab = 0),
              ),
              SizedBox(width: 12.s(context)),
              _Tab(
                label: 'History',
                selected: _tab == 1,
                onTap: () => setState(() => _tab = 1),
              ),
            ],
          ),
          SizedBox(height: 24.s(context)),
          Expanded(
            child: _tab == 0 ? const _WatchlistGrid() : const _HistoryList(),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Tab({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.space)) {
          onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.symmetric(
                horizontal: 22.s(context),
                vertical: 10.s(context),
              ),
              decoration: BoxDecoration(
                color: focused
                    ? kNetflixRed
                    : (selected ? kSurfaceHi : Colors.transparent),
                borderRadius: BorderRadius.circular(24.s(context)),
                border: Border.all(
                  color: selected || focused ? Colors.transparent : Colors.white12,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: kTextWhite,
                  fontSize: 16.s(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WatchlistGrid extends StatelessWidget {
  const _WatchlistGrid();

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) {
      if (watchlistStore.isLoading && watchlistStore.items.isEmpty) {
        return const Center(child: CircularProgressIndicator(color: kNetflixRed));
      }
      if (watchlistStore.items.isEmpty) {
        return _EmptyState(
          icon: Icons.bookmark_outline,
          text: 'Your watchlist is empty.\nBookmark a movie or show to see it here.',
        );
      }
      return GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 16.s(context),
          crossAxisSpacing: 16.s(context),
          childAspectRatio: 0.65,
        ),
        itemCount: watchlistStore.items.length,
        itemBuilder: (ctx, i) {
          final it = watchlistStore.items[i];
          return _WatchlistCard(item: it);
        },
      );
    });
  }
}

class _WatchlistCard extends StatelessWidget {
  final WatchlistItem item;
  const _WatchlistCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
                e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.space)) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => MovieDetailsPage(
              movieId: item.tmdbId.toString(),
              mediaType: item.mediaType,
            ),
          ));
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12.s(context)),
              border: Border.all(
                color: focused ? kTextWhite : Colors.transparent,
                width: 3.s(context),
              ),
              boxShadow: focused
                  ? [BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 18.s(context))]
                  : [],
            ),
            transform: focused
                ? (Matrix4.identity()..scale(1.06))
                : Matrix4.identity(),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10.s(context)),
              child: item.posterPath != null
                  ? Image.network('$imgW300${item.posterPath}', fit: BoxFit.cover)
                  : Container(
                      color: kSurfaceGrey,
                      alignment: Alignment.center,
                      child: Text(
                        item.title ?? '?',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kTextWhite, fontSize: 14.s(context)),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList();

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) {
      if (historyStore.isLoading && historyStore.items.isEmpty) {
        return const Center(child: CircularProgressIndicator(color: kNetflixRed));
      }
      if (historyStore.items.isEmpty) {
        return _EmptyState(
          icon: Icons.history,
          text: 'No history yet.\nStart watching to build a queue.',
        );
      }
      return ListView.separated(
        itemCount: historyStore.items.length,
        separatorBuilder: (_, __) => SizedBox(height: 12.s(context)),
        itemBuilder: (ctx, i) => _HistoryRow(item: historyStore.items[i]),
      );
    });
  }
}

class _HistoryRow extends StatelessWidget {
  final HistoryItem item;
  const _HistoryRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent) {
          if (e.logicalKey == LogicalKeyboardKey.select ||
              e.logicalKey == LogicalKeyboardKey.enter) {
            Navigator.push(context, MaterialPageRoute(
              builder: (_) => MovieDetailsPage(
                movieId: item.tmdbId.toString(),
                mediaType: item.mediaType,
              ),
            ));
            return KeyEventResult.handled;
          }
          if (e.logicalKey == LogicalKeyboardKey.delete ||
              e.logicalKey == LogicalKeyboardKey.contextMenu) {
            historyStore.remove(item.id);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (ctx) {
          final focused = Focus.of(ctx).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.all(12.s(context)),
            decoration: BoxDecoration(
              color: focused ? kSurfaceHi : kSurfaceGrey,
              borderRadius: BorderRadius.circular(12.s(context)),
              border: Border.all(
                color: focused ? kAccent : Colors.transparent,
                width: 2.s(context),
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6.s(context)),
                  child: SizedBox(
                    width: 100.s(context),
                    height: 60.s(context),
                    child: item.backdropPath != null
                        ? Image.network('$imgW300${item.backdropPath}', fit: BoxFit.cover)
                        : Container(color: kSurfaceHi),
                  ),
                ),
                SizedBox(width: 16.s(context)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title ?? 'Untitled',
                        style: TextStyle(
                          color: kTextWhite,
                          fontSize: 16.s(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4.s(context)),
                      Text(
                        item.mediaType == 'tv' &&
                                item.seasonNumber != null &&
                                item.episodeNumber != null
                            ? 'S${item.seasonNumber} E${item.episodeNumber}'
                            : item.mediaType.toUpperCase(),
                        style: TextStyle(color: kTextGrey, fontSize: 12.s(context)),
                      ),
                      SizedBox(height: 8.s(context)),
                      LinearProgressIndicator(
                        value: item.progressFraction,
                        backgroundColor: kSurfaceHi,
                        valueColor: const AlwaysStoppedAnimation(kNetflixRed),
                        minHeight: 4.s(context).clamp(2.0, 8.0),
                      ),
                    ],
                  ),
                ),
                if (focused)
                  Padding(
                    padding: EdgeInsets.only(left: 12.s(context)),
                    child: Text('DEL to remove',
                        style: TextStyle(color: kTextGrey, fontSize: 11.s(context))),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyState({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: kSurfaceHi, size: 96.s(context)),
          SizedBox(height: 16.s(context)),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: kTextGrey, fontSize: 16.s(context)),
          ),
        ],
      ),
    );
  }
}
