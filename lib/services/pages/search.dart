import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/details.dart';
import 'package:cineby_tv/stores/search_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter/services.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final SearchStore _searchStore = SearchStore();
  final List<String> _keyboard = [
    'A', 'B', 'C', 'D', 'E', 'F',
    'G', 'H', 'I', 'J', 'K', 'L',
    'M', 'N', 'O', 'P', 'Q', 'R',
    'S', 'T', 'U', 'V', 'W', 'X',
    'Y', 'Z', '1', '2', '3', '4',
    '5', '6', '7', '8', '9', '0',
    'SPACE', 'BACK', 'CLEAR'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDeepBlack,
      body: Row(
        children: [
          // Custom TV Sidebar Keyboard
          Container(
            width: 350,
            color: kSurfaceGrey,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                const Text(
                  "SEARCH",
                  style: TextStyle(
                    color: kTextGrey,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 10),
                Observer(
                  builder: (_) => Text(
                    _searchStore.searchQuery.isEmpty ? "Type to search..." : _searchStore.searchQuery.toUpperCase(),
                    style: TextStyle(
                      color: _searchStore.searchQuery.isEmpty ? kTextGrey : kTextWhite,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 30),
                Expanded(
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 6,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1,
                    ),
                    itemCount: _keyboard.length,
                    itemBuilder: (context, index) {
                      final key = _keyboard[index];
                      return _KeyboardButton(
                        label: key,
                        onPressed: () {
                          if (key == 'BACK') {
                            if (_searchStore.searchQuery.isNotEmpty) {
                              _searchStore.setSearchQuery(
                                _searchStore.searchQuery.substring(0, _searchStore.searchQuery.length - 1),
                              );
                            }
                          } else if (key == 'CLEAR') {
                            _searchStore.setSearchQuery('');
                          } else if (key == 'SPACE') {
                            _searchStore.setSearchQuery('${_searchStore.searchQuery} ');
                          } else {
                            _searchStore.setSearchQuery('${_searchStore.searchQuery}$key');
                          }
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                _KeyboardButton(
                  label: "BACK TO HOME",
                  isLong: true,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Search Results
          Expanded(
            child: Observer(
              builder: (_) {
                if (_searchStore.searchQuery.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search, color: kSurfaceGrey, size: 100),
                        SizedBox(height: 20),
                        Text(
                          "Search for your favorite movies and shows",
                          style: TextStyle(color: kTextGrey, fontSize: 18),
                        ),
                      ],
                    ),
                  );
                }

                if (_searchStore.isLoading) {
                  return const Center(child: CircularProgressIndicator(color: kNetflixRed));
                }

                final results = _searchStore.searchResults;
                if (results.isEmpty) {
                  return const Center(
                    child: Text("No results found", style: TextStyle(color: kTextGrey, fontSize: 18)),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(40),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                  ),
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final result = results[index];
                    return _SearchResultCard(
                      result: result,
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MovieDetailsPage(movieId: result.id.toString()),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyboardButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isLong;

  const _KeyboardButton({
    required this.label,
    required this.onPressed,
    this.isLong = false,
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
            child: Container(
              height: isLong ? 50 : null,
              width: isLong ? double.infinity : null,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hasFocus ? kTextWhite : kSurfaceGrey,
                borderRadius: BorderRadius.circular(4),
                border: hasFocus ? null : Border.all(color: Colors.white10),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: hasFocus ? kDeepBlack : kTextWhite,
                  fontSize: label.length > 1 ? 12 : 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  final dynamic result;
  final VoidCallback onPressed;

  const _SearchResultCard({required this.result, required this.onPressed});

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
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: 3,
                ),
              ),
              transform: hasFocus ? (Matrix4.identity()..scale(1.05)) : Matrix4.identity(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: Column(
                  children: [
                    Expanded(
                      child: result.posterPath != null
                          ? Image.network(
                              "https://image.tmdb.org/t/p/w300${result.posterPath}",
                              fit: BoxFit.cover,
                              width: double.infinity,
                            )
                          : Container(
                              color: kSurfaceGrey,
                              width: double.infinity,
                              child: const Icon(Icons.movie, color: Colors.white54, size: 50),
                            ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      width: double.infinity,
                      color: hasFocus ? Colors.white : kSurfaceGrey,
                      child: Text(
                        result.title ?? result.name ?? 'Unknown',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: hasFocus ? kDeepBlack : kTextWhite,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
