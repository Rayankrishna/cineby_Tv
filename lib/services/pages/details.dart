import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/webview.dart';
import 'package:cineby_tv/stores/search_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter/services.dart';

class MovieDetailsPage extends StatefulWidget {
  final String movieId;

  const MovieDetailsPage({super.key, required this.movieId});

  @override
  State<MovieDetailsPage> createState() => _MovieDetailsPageState();
}

class _MovieDetailsPageState extends State<MovieDetailsPage> {
  final SearchStore _searchStore = SearchStore();

  @override
  void initState() {
    super.initState();
    _searchStore.fetchMovieDetails(widget.movieId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDeepBlack,
      body: Observer(
        builder: (_) {
          if (_searchStore.isLoading) {
            return const Center(child: CircularProgressIndicator(color: kNetflixRed));
          }

          final movie = _searchStore.movieDetails;
          if (movie == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Failed to load details", style: TextStyle(color: kTextWhite)),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Go Back"),
                  ),
                ],
              ),
            );
          }

          return CustomScrollView(
            slivers: [
              // Hero Section with Backdrop
              SliverToBoxAdapter(
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.8,
                  child: Stack(
                    children: [
                      // Backdrop Image
                      Positioned.fill(
                        child: ShaderMask(
                          shaderCallback: (rect) {
                            return LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.0),
                                Colors.black.withOpacity(0.3),
                                kDeepBlack,
                              ],
                              stops: const [0, 0.4, 0.9],
                            ).createShader(rect);
                          },
                          blendMode: BlendMode.dstIn,
                          child: movie.backdropPath != null
                              ? Image.network(
                                  "https://image.tmdb.org/t/p/original${movie.backdropPath}",
                                  fit: BoxFit.cover,
                                )
                              : Container(color: kSurfaceGrey),
                        ),
                      ),
                      // Gradient Overlay from Left
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                kDeepBlack.withOpacity(0.8),
                                kDeepBlack.withOpacity(0.4),
                                Colors.transparent,
                              ],
                              stops: const [0, 0.5, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // Movie Content
                      Positioned(
                        left: 60,
                        top: 100,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              movie.title?.toUpperCase() ?? 'UNTITLED',
                              style: const TextStyle(
                                color: kTextWhite,
                                fontSize: 60,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Text(
                                  movie.releaseDate?.split('-').first ?? '',
                                  style: const TextStyle(color: kTextGrey, fontSize: 18),
                                ),
                                const SizedBox(width: 20),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: kTextGrey),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: const Text("13+", style: TextStyle(color: kTextGrey, fontSize: 14)),
                                ),
                                const SizedBox(width: 20),
                                Text(
                                  "${movie.runtime}m",
                                  style: const TextStyle(color: kTextGrey, fontSize: 18),
                                ),
                                const SizedBox(width: 20),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    border: Border.all(color: kTextGrey.withOpacity(0.5)),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    "HD",
                                    style: TextStyle(color: kTextWhite.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            if (movie.tagline != null && movie.tagline!.isNotEmpty)
                              Text(
                                movie.tagline!,
                                style: const TextStyle(
                                  color: kTextWhite,
                                  fontSize: 20,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w300,
                                ),
                              ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: MediaQuery.of(context).size.width * 0.45,
                              child: Text(
                                movie.overview ?? '',
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: kTextWhite,
                                  fontSize: 18,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 40),
                            Row(
                              children: [
                                _ActionButton(
                                  label: "Play",
                                  icon: Icons.play_arrow,
                                  isPrimary: true,
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => MyWidget(url: "$serverurl${movie.id}"),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 20),
                                _ActionButton(
                                  label: "Trailer",
                                  icon: Icons.movie_outlined,
                                  isPrimary: false,
                                  onPressed: () {},
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Cast List
              if (movie.credits?.cast != null && movie.credits!.cast!.isNotEmpty) ...[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(left: 60, top: 40, bottom: 20),
                    child: Text(
                      "Cast",
                      style: TextStyle(
                        color: kTextWhite,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Container(
                    height: 250,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 50),
                      scrollDirection: Axis.horizontal,
                      itemCount: movie.credits!.cast!.length,
                      itemBuilder: (context, index) {
                        final actor = movie.credits!.cast![index];
                        return _CastCard(actor: actor);
                      },
                    ),
                  ),
                ),
              ],
              const SliverPadding(padding: EdgeInsets.only(bottom: 60)),
            ],
          );
        },
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              decoration: BoxDecoration(
                color: isPrimary
                    ? (hasFocus ? Colors.white : Colors.white.withOpacity(0.9))
                    : (hasFocus ? Colors.grey.withOpacity(0.5) : Colors.grey.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(4),
                border: hasFocus ? Border.all(color: Colors.blue, width: 3) : null,
              ),
              child: Row(
                children: [
                  Icon(icon, color: isPrimary ? Colors.black : Colors.white, size: 30),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: isPrimary ? Colors.black : Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
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

class _CastCard extends StatelessWidget {
  final dynamic actor;

  const _CastCard({required this.actor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Focus(
        child: Builder(
          builder: (context) {
            final hasFocus = Focus.of(context).hasFocus;
            return Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 160,
                  width: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hasFocus ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  transform: hasFocus ? (Matrix4.identity()..scale(1.1)) : Matrix4.identity(),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: actor.profilePath != null
                        ? Image.network(
                            "https://image.tmdb.org/t/p/w200${actor.profilePath}",
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: kSurfaceGrey,
                            child: const Icon(Icons.person, color: Colors.white54, size: 50),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  actor.name ?? '',
                  style: TextStyle(color: kTextWhite, fontSize: 14, fontWeight: hasFocus ? FontWeight.bold : FontWeight.normal),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  actor.character ?? '',
                  style: const TextStyle(color: kTextGrey, fontSize: 12),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
