import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/webview.dart';
import 'package:cineby_tv/services/pages/search.dart';
import 'package:cineby_tv/services/pages/details.dart';

import 'package:cineby_tv/stores/search_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter/services.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final SearchStore _searchStore = SearchStore();

  @override
  void initState() {
    super.initState();
    _searchStore.fetchTrendingResults();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDeepBlack,
      body: Observer(
        builder: (_) {
          if (_searchStore.isLoading &&
              _searchStore.searchResults.isEmpty &&
              _searchStore.trendingResults.isEmpty) {
            return const Center(child: CircularProgressIndicator(color: kNetflixRed));
          }

          if (_searchStore.errorMessage != null) {
            return Center(child: Text(_searchStore.errorMessage!, style: const TextStyle(color: kTextWhite)));
          }

          final trending = _searchStore.trendingResults;
          if (trending.isEmpty) {
            return const Center(child: Text("No content available", style: TextStyle(color: kTextWhite)));
          }

          final heroMovie = trending.first;

          return CustomScrollView(
            slivers: [
              // Hero Section
              SliverToBoxAdapter(
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.7,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      // Hero Background Image with Gradient
                      Positioned.fill(
                        child: ShaderMask(
                          shaderCallback: (rect) {
                            return LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withOpacity(0.0),
                                Colors.black.withOpacity(0.5),
                                kDeepBlack,
                              ],
                              stops: const [0, 0.5, 1.0],
                            ).createShader(rect);
                          },
                          blendMode: BlendMode.dstIn,
                          child: heroMovie.posterPath != null
                              ? Image.network(
                                  "https://image.tmdb.org/t/p/original${heroMovie.posterPath}",
                                  fit: BoxFit.cover,
                                )
                              : Container(color: kSurfaceGrey),
                        ),
                      ),
                      // Hero Info
                      Positioned(
                        left: 40,
                        bottom: 40,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (heroMovie.title ?? heroMovie.name ?? 'Featured Content').toUpperCase(),
                              style: const TextStyle(
                                color: kTextWhite,
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: MediaQuery.of(context).size.width * 0.4,
                              child: Text(
                                heroMovie.overview ?? '',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: kTextGrey,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(height: 30),
                            Row(
                              children: [
                                _HeroButton(
                                  label: 'Play',
                                  icon: Icons.play_arrow,
                                  isPrimary: true,
                                  onPressed: () => _navigateToWebview(context, heroMovie.id.toString()),
                                ),
                                const SizedBox(width: 20),
                                  _HeroButton(
                                    label: 'Details',
                                    icon: Icons.info_outline,
                                    isPrimary: false,
                                    onPressed: () => _navigateToDetails(context, heroMovie.id.toString()),
                                  ),
                                  const SizedBox(width: 20),
                                  _HeroButton(
                                    label: 'Search',
                                    icon: Icons.search,
                                    isPrimary: false,
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (context) => const SearchPage()),
                                      );
                                    },
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
              // Content Rows
              _buildRow(context, "Trending Now", trending),
              _buildRow(context, "Popular on Cineby", trending.reversed.toList()),
              _buildRow(context, "New Releases", trending.skip(5).toList()),
              const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
            ],
          );
        },
      ),
    );
  }

  void _navigateToWebview(BuildContext context, String id) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MyWidget(url: "$serverurl$id"),
      ),
    );
  }

  void _navigateToDetails(BuildContext context, String id) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MovieDetailsPage(movieId: id),
      ),
    );
  }

  Widget _buildRow(BuildContext context, String title, List results) {
    if (results.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 40, top: 30, bottom: 10),
            child: Text(
              title,
              style: const TextStyle(
                color: kTextWhite,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            height: 220,
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              scrollDirection: Axis.horizontal,
              itemCount: results.length,
              itemBuilder: (context, index) {
                final result = results[index];
                return _MovieCard(
                  result: result,
                  onPressed: () => _navigateToDetails(context, result.id.toString()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onPressed;

  const _HeroButton({
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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: isPrimary 
                    ? (hasFocus ? Colors.white : Colors.white.withOpacity(0.9))
                    : (hasFocus ? Colors.grey.withOpacity(0.5) : Colors.grey.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(4),
                border: hasFocus ? Border.all(color: Colors.blue, width: 3) : null,
              ),
              child: Row(
                children: [
                  Icon(icon, color: isPrimary ? Colors.black : Colors.white, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: isPrimary ? Colors.black : Colors.white,
                      fontSize: 18,
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

class _MovieCard extends StatelessWidget {
  final dynamic result;
  final VoidCallback onPressed;

  const _MovieCard({required this.result, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Focus(
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
                width: 140,
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
                  child: result.posterPath != null
                      ? Image.network(
                          "https://image.tmdb.org/t/p/w300${result.posterPath}",
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: kSurfaceGrey,
                          child: const Icon(Icons.movie, color: Colors.white54, size: 50),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
