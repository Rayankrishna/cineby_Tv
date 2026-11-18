import 'package:cineby_tv/models/history_item.dart';
import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/details.dart';
import 'package:cineby_tv/services/tmdb_client.dart';
import 'package:cineby_tv/stores/stores.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
import 'package:cineby_tv/widgets/tv_focus.dart';
import 'package:cineby_tv/widgets/tv_image.dart';
import 'package:cineby_tv/widgets/tv_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int _sectionMask = 0;

  @override
  void initState() {
    super.initState();
    historyStore.fetchContinueWatching();
    historyStore.fetch();
    watchlistStore.fetch();
  }

  /// The three fetches settle in any order, so a rail can be inserted above
  /// one the user has already focused. Re-pin it instead of leaving it
  /// displaced (home.dart does the same for its rows).
  void _syncSections(int mask) {
    if (mask == _sectionMask) return;
    _sectionMask = mask;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final focusContext = FocusManager.instance.primaryFocus?.context;
      if (focusContext == null || !focusContext.mounted) return;
      // Profile is kept alive in RootShell's IndexedStack and rebuilds on
      // another tab's fetches too: only ever re-pin our own focus.
      if (focusContext.findAncestorStateOfType<_ProfilePageState>() != this) {
        return;
      }
      TvSection.maybeOf(focusContext)?.reveal();
    });
  }

  void _open({
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

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.8),
      builder:
          (dialogContext) => Dialog(
            backgroundColor: kSurfaceGrey,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.s(context)),
            ),
            child: Padding(
              padding: EdgeInsets.all(26.s(context)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Sign out of ReelixTv?',
                    style: TextStyle(
                      color: kTextWhite,
                      fontSize: 18.s(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6.s(context)),
                  Text(
                    "You'll need your email and password to sign back in.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: kTextGrey,
                      fontSize: 12.5.s(context),
                    ),
                  ),
                  SizedBox(height: 22.s(context)),
                  TvRowFocusGroup(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TvButton(
                          label: 'Cancel',
                          autofocus: true,
                          onPressed: () => Navigator.pop(dialogContext, false),
                        ),
                        SizedBox(width: 12.s(context)),
                        TvButton(
                          label: 'Sign Out',
                          icon: Icons.logout_rounded,
                          onPressed: () => Navigator.pop(dialogContext, true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
    if (confirmed == true) await authStore.logout();
  }

  Widget _historyRail(String id, List<HistoryItem> items) {
    return TvPosterRail(
      storageId: id,
      count: items.length,
      cardBuilder: (context, i) {
        final it = items[i];
        final isEpisode =
            it.mediaType == 'tv' &&
            it.seasonNumber != null &&
            it.episodeNumber != null;
        return TvPosterCard(
          posterPath: it.posterPath ?? it.backdropPath,
          title: it.title,
          progress: it.progressFraction,
          badge:
              isEpisode ? 'S${it.seasonNumber} · E${it.episodeNumber}' : null,
          onPressed:
              () => _open(
                tmdbId: it.tmdbId,
                mediaType: it.mediaType,
                title: it.title,
                backdropPath: it.backdropPath,
              ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kDeepBlack,
      child: Observer(
        builder: (_) {
          final user = authStore.user;
          final continueWatching = historyStore.continueWatching.toList();
          final watchlist = watchlistStore.items.take(12).toList();
          final recent = historyStore.items.take(12).toList();
          final nothingYet =
              continueWatching.isEmpty && watchlist.isEmpty && recent.isEmpty;

          _syncSections(
            (continueWatching.isNotEmpty ? 1 : 0) |
                (watchlist.isNotEmpty ? 2 : 0) |
                (recent.isNotEmpty ? 4 : 0),
          );

          // Padded (not list padding) so rails scroll away under the nav bar's
          // edge instead of sliding behind its labels.
          return Padding(
            padding: EdgeInsets.only(top: kTvNavHeight.s(context)),
            child: ListView(
              padding: EdgeInsets.only(bottom: 90.s(context)),
              children: [
                TvSection(
                  key: const ValueKey('header'),
                  alignment: 0,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      kTvGutter.s(context),
                      18.s(context),
                      kTvGutter.s(context),
                      14.s(context),
                    ),
                    child: Row(
                      children: [
                        _Avatar(path: authStore.avatarPath),
                        SizedBox(width: 20.s(context)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                user?.name ?? 'Guest',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: kTextWhite,
                                  fontSize: 26.s(context),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if ((user?.email ?? '').isNotEmpty)
                                Text(
                                  user!.email,
                                  style: TextStyle(
                                    color: kTextGrey,
                                    fontSize: 12.5.s(context),
                                  ),
                                ),
                              SizedBox(height: 12.s(context)),
                              TvRowFocusGroup(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TvButton(
                                      label: 'Change Avatar',
                                      icon: Icons.face_rounded,
                                      onPressed:
                                          () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder:
                                                  (_) =>
                                                      const AvatarPickerPage(),
                                            ),
                                          ),
                                    ),
                                    SizedBox(width: 10.s(context)),
                                    TvButton(
                                      label: 'Sign Out',
                                      icon: Icons.logout_rounded,
                                      onPressed: _confirmSignOut,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (continueWatching.isNotEmpty)
                  TvRailSection(
                    key: const ValueKey('continue'),
                    title: 'Continue Watching',
                    child: _historyRail('profile-continue', continueWatching),
                  ),
                if (watchlist.isNotEmpty)
                  TvRailSection(
                    key: const ValueKey('list'),
                    title: 'My List',
                    child: TvPosterRail(
                      storageId: 'profile-list',
                      count: watchlist.length,
                      cardBuilder: (context, i) {
                        final it = watchlist[i];
                        return TvPosterCard(
                          posterPath: it.posterPath,
                          title: it.title,
                          onPressed:
                              () => _open(
                                tmdbId: it.tmdbId,
                                mediaType: it.mediaType,
                                title: it.title,
                              ),
                        );
                      },
                    ),
                  ),
                if (recent.isNotEmpty)
                  TvRailSection(
                    key: const ValueKey('recent'),
                    title: 'Recently Watched',
                    child: _historyRail('profile-recent', recent),
                  ),
                if (nothingYet)
                  Padding(
                    padding: EdgeInsets.only(top: 60.s(context)),
                    child: const TvMessage(
                      icon: Icons.movie_filter_outlined,
                      title: 'Nothing here yet',
                      detail:
                          'What you watch and save will be collected on this page.',
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.path});
  final String? path;

  @override
  Widget build(BuildContext context) {
    final size = 84.s(context);
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: TvImage(
          path: path,
          kind: TmdbImageKind.profile,
          width: size,
          alignment: Alignment.topCenter,
          fallback: Container(
            color: kSurfaceHi,
            alignment: Alignment.center,
            child: Icon(
              Icons.person_rounded,
              color: kTextGrey,
              size: 44.s(context),
            ),
          ),
        ),
      ),
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
  List<String> _paths = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<String>> _peoplePage(int page) async {
    try {
      final r = await tmdbDio.get('$popularPeopleUrl$page');
      return [
        for (final p in (r.data['results'] as List? ?? []))
          if (p is Map && p['profile_path'] is String)
            p['profile_path'] as String,
      ];
    } catch (_) {
      // One page failing must not discard the other page's faces.
      return const [];
    }
  }

  Future<void> _load() async {
    if (!_loading) setState(() => _loading = true);
    final pages = await Future.wait([_peoplePage(1), _peoplePage(2)]);
    if (!mounted) return;
    setState(() {
      _paths = [for (final p in pages) ...p];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gutter = kTvGutter.s(context);
    final Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator(color: kNetflixRed));
    } else if (_paths.isEmpty) {
      body = TvMessage(
        icon: Icons.cloud_off_rounded,
        title: "Couldn't load avatars",
        actions: [
          TvButton(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            autofocus: true,
            onPressed: _load,
          ),
        ],
      );
    } else {
      // Start on the avatar in use, not face #1 — the stored one can be gone
      // from TMDB's popular list, in which case nothing would autofocus.
      final current = authStore.avatarPath;
      final currentIndex = current == null ? -1 : _paths.indexOf(current);
      final startIndex = currentIndex < 0 ? 0 : currentIndex;
      body = GridView.builder(
        padding: EdgeInsets.fromLTRB(
          gutter,
          14.s(context),
          gutter,
          70.s(context),
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 8,
          mainAxisSpacing: 20.s(context),
          crossAxisSpacing: 20.s(context),
        ),
        itemCount: _paths.length,
        itemBuilder: (context, i) {
          final path = _paths[i];
          return TvFocusable(
            autofocus: i == startIndex,
            onPressed: () {
              authStore.setAvatarPath(path);
              Navigator.pop(context);
            },
            builder:
                (context, focused) => TvFocusFrame(
                  focused: focused,
                  circle: true,
                  scale: 1.1,
                  ringWidth: 3.s(context),
                  child: TvImage(
                    path: path,
                    kind: TmdbImageKind.profile,
                    width: 96.s(context),
                    alignment: Alignment.topCenter,
                  ),
                ),
          );
        },
      );
    }
    return Scaffold(
      backgroundColor: kDeepBlack,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TvPageTitle(title: 'Choose an Avatar', subtitle: 'Profile'),
          Expanded(child: body),
        ],
      ),
    );
  }
}
