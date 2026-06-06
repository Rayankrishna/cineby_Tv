import 'package:cineby_tv/models/history_item.dart';
import 'package:cineby_tv/models/watchlist_item.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/details.dart';
import 'package:cineby_tv/stores/stores.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  void initState() {
    super.initState();
    historyStore.fetchContinueWatching();
    historyStore.fetch();
    watchlistStore.fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Observer(builder: (_) {
      final user = authStore.user;
      return ListView(
        padding: EdgeInsets.symmetric(horizontal: 32.s(context), vertical: 24.s(context)),
        children: [
          Row(
            children: [
              _Avatar(path: authStore.avatarPath),
              SizedBox(width: 24.s(context)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.name ?? 'Guest',
                      style: TextStyle(
                        color: kTextWhite,
                        fontSize: 32.s(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4.s(context)),
                    Text(
                      user?.email ?? '',
                      style: TextStyle(color: kTextGrey, fontSize: 14.s(context)),
                    ),
                  ],
                ),
              ),
              _PillButton(
                icon: Icons.image_outlined,
                label: 'Avatar',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AvatarPickerPage()),
                ),
              ),
              SizedBox(width: 12.s(context)),
              _PillButton(
                icon: Icons.logout,
                label: 'Log out',
                danger: true,
                onTap: () async {
                  await authStore.logout();
                },
              ),
            ],
          ),
          SizedBox(height: 32.s(context)),
          _SectionTitle(
            title: 'Continue Watching',
            empty: historyStore.continueWatching.isEmpty,
          ),
          if (historyStore.continueWatching.isNotEmpty)
            _HistoryRail(items: historyStore.continueWatching),
          SizedBox(height: 24.s(context)),
          _SectionTitle(
            title: 'My Watchlist',
            empty: watchlistStore.items.isEmpty,
          ),
          if (watchlistStore.items.isNotEmpty)
            _WatchlistRail(items: watchlistStore.items.take(8).toList()),
          SizedBox(height: 24.s(context)),
          _SectionTitle(
            title: 'Recent History',
            empty: historyStore.items.isEmpty,
          ),
          if (historyStore.items.isNotEmpty)
            _HistoryRail(items: historyStore.items.take(8).toList()),
          SizedBox(height: 40.s(context)),
        ],
      );
    });
  }
}

class _Avatar extends StatelessWidget {
  final String? path;
  const _Avatar({this.path});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 96.s(context),
      height: 96.s(context),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kSurfaceHi,
        border: Border.all(color: kAccent, width: 3.s(context)),
        image: path != null
            ? DecorationImage(
                image: NetworkImage('$imgW185$path'),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: path == null
          ? Icon(Icons.person, color: kTextGrey, size: 48.s(context))
          : null,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final bool empty;
  const _SectionTitle({required this.title, required this.empty});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.s(context)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            style: TextStyle(
              color: kTextWhite,
              fontSize: 22.s(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (empty) ...[
            SizedBox(width: 12.s(context)),
            Text(
              '— nothing yet',
              style: TextStyle(color: kTextGrey, fontSize: 13.s(context)),
            ),
          ],
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

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
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              horizontal: 18.s(context),
              vertical: 10.s(context),
            ),
            decoration: BoxDecoration(
              color: focused
                  ? (danger ? kNetflixRed : kAccent)
                  : kSurfaceHi,
              borderRadius: BorderRadius.circular(20.s(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: kTextWhite, size: 16.s(context)),
                SizedBox(width: 6.s(context)),
                Text(
                  label,
                  style: TextStyle(
                    color: kTextWhite,
                    fontSize: 13.s(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _WatchlistRail extends StatelessWidget {
  final List<WatchlistItem> items;
  const _WatchlistRail({required this.items});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220.s(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(width: 12.s(context)),
        itemBuilder: (ctx, i) {
          final it = items[i];
          return _RailCard(
            posterPath: it.posterPath,
            label: it.title,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MovieDetailsPage(
                  movieId: it.tmdbId.toString(),
                  mediaType: it.mediaType,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HistoryRail extends StatelessWidget {
  final List<HistoryItem> items;
  const _HistoryRail({required this.items});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 240.s(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => SizedBox(width: 12.s(context)),
        itemBuilder: (ctx, i) {
          final it = items[i];
          return _RailCard(
            posterPath: it.posterPath ?? it.backdropPath,
            label: it.title,
            progress: it.progressFraction,
            badge: it.mediaType == 'tv' &&
                    it.seasonNumber != null &&
                    it.episodeNumber != null
                ? 'S${it.seasonNumber} • E${it.episodeNumber}'
                : null,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MovieDetailsPage(
                  movieId: it.tmdbId.toString(),
                  mediaType: it.mediaType,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RailCard extends StatelessWidget {
  final String? posterPath;
  final String? label;
  final double? progress;
  final String? badge;
  final VoidCallback onTap;

  const _RailCard({
    required this.posterPath,
    required this.label,
    this.progress,
    this.badge,
    required this.onTap,
  });

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
      child: Builder(builder: (ctx) {
        final focused = Focus.of(ctx).hasFocus;
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 140.s(context),
            transform: focused
                ? (Matrix4.identity()..scale(1.08))
                : Matrix4.identity(),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12.s(context)),
              border: Border.all(
                color: focused ? kTextWhite : Colors.transparent,
                width: 3.s(context),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10.s(context)),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: posterPath != null
                        ? Image.network('$imgW300$posterPath', fit: BoxFit.cover)
                        : Container(
                            color: kSurfaceGrey,
                            alignment: Alignment.center,
                            child: Text(
                              label ?? '?',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: kTextWhite, fontSize: 12.s(context)),
                            ),
                          ),
                  ),
                  if (badge != null)
                    Positioned(
                      top: 8.s(context),
                      left: 8.s(context),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.s(context),
                          vertical: 3.s(context),
                        ),
                        decoration: BoxDecoration(
                          color: kDeepBlack.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(4.s(context)),
                        ),
                        child: Text(
                          badge!,
                          style: TextStyle(
                            color: kTextWhite,
                            fontSize: 10.s(context),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (progress != null && progress! > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.black54,
                        valueColor: const AlwaysStoppedAnimation(kNetflixRed),
                        minHeight: 4.s(context).clamp(2.0, 6.0),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ============ AVATAR PICKER ============
class AvatarPickerPage extends StatefulWidget {
  const AvatarPickerPage({super.key});

  @override
  State<AvatarPickerPage> createState() => _AvatarPickerPageState();
}

class _AvatarPickerPageState extends State<AvatarPickerPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _people = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = Dio();
      final results = await Future.wait([
        dio.get('${popularPeopleUrl}1'),
        dio.get('${popularPeopleUrl}2'),
      ]);
      final all = <Map<String, dynamic>>[];
      for (final r in results) {
        final list = (r.data['results'] as List? ?? []);
        for (final p in list) {
          if (p is Map && p['profile_path'] != null) {
            all.add(Map<String, dynamic>.from(p));
          }
        }
      }
      if (mounted) {
        setState(() {
          _people = all;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDeepBlack,
      appBar: AppBar(
        backgroundColor: kDeepBlack,
        title: const Text('Choose an Avatar', style: TextStyle(color: kTextWhite)),
        iconTheme: const IconThemeData(color: kTextWhite),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kNetflixRed))
          : GridView.builder(
              padding: EdgeInsets.all(32.s(context)),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                mainAxisSpacing: 16.s(context),
                crossAxisSpacing: 16.s(context),
              ),
              itemCount: _people.length,
              itemBuilder: (ctx, i) {
                final p = _people[i];
                final path = p['profile_path'] as String;
                return Focus(
                  autofocus: i == 0,
                  onKeyEvent: (n, e) {
                    if (e is KeyDownEvent &&
                        (e.logicalKey == LogicalKeyboardKey.select ||
                            e.logicalKey == LogicalKeyboardKey.enter ||
                            e.logicalKey == LogicalKeyboardKey.space)) {
                      authStore.setAvatarPath(path);
                      Navigator.pop(context);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Builder(builder: (c) {
                    final focused = Focus.of(c).hasFocus;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: focused ? kAccent : Colors.transparent,
                          width: 4.s(context),
                        ),
                        image: DecorationImage(
                          image: NetworkImage('$imgW185$path'),
                          fit: BoxFit.cover,
                        ),
                      ),
                      transform: focused
                          ? (Matrix4.identity()..scale(1.12))
                          : Matrix4.identity(),
                    );
                  }),
                );
              },
            ),
    );
  }
}
