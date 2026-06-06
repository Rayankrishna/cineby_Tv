import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/details.dart';
import 'package:cineby_tv/stores/search_store.dart';
import 'package:cineby_tv/utils/tv_scale.dart';
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
            width: 350.s(context),
            color: kSurfaceGrey,
            padding: EdgeInsets.all(20.s(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 20.s(context)),
                Text(
                  "SEARCH",
                  style: TextStyle(
                    color: kTextGrey,
                    fontSize: 14.s(context),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.s(context),
                  ),
                ),
                SizedBox(height: 10.s(context)),
                Observer(
                  builder: (_) => Text(
                    _searchStore.searchQuery.isEmpty ? "Type to search..." : _searchStore.searchQuery.toUpperCase(),
                    style: TextStyle(
                      color: _searchStore.searchQuery.isEmpty ? kTextGrey : kTextWhite,
                      fontSize: 28.s(context),
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(height: 30.s(context)),
                Expanded(
                  child: GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 6,
                      mainAxisSpacing: 8.s(context),
                      crossAxisSpacing: 8.s(context),
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
              ],
            ),
          ),
          // Search Results
          Expanded(
            child: Observer(
              builder: (_) {
                if (_searchStore.searchQuery.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search, color: kSurfaceGrey, size: 100.s(context)),
                        SizedBox(height: 20.s(context)),
                        Text(
                          "Search for your favorite movies and shows",
                          style: TextStyle(color: kTextGrey, fontSize: 18.s(context)),
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
                  return Center(
                    child: Text("No results found", style: TextStyle(color: kTextGrey, fontSize: 18.s(context))),
                  );
                }

                return GridView.builder(
                  padding: EdgeInsets.all(40.s(context)),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 20.s(context),
                    mainAxisSpacing: 20.s(context),
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
                            builder: (context) => MovieDetailsPage(
                              movieId: result.id.toString(),
                              mediaType: result.mediaType ?? 'movie',
                            ),
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

  const _KeyboardButton({
    required this.label,
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
            child: Container(
              height: null,
              width: null,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hasFocus ? kTextWhite : kSurfaceGrey,
                borderRadius: BorderRadius.circular(4.s(context)),
                border: hasFocus ? null : Border.all(color: Colors.white10),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: hasFocus ? kDeepBlack : kTextWhite,
                  fontSize: (label.length > 1 ? 12 : 18).s(context),
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
                borderRadius: BorderRadius.circular(8.s(context)),
                border: Border.all(
                  color: hasFocus ? Colors.white : Colors.transparent,
                  width: 3.s(context),
                ),
              ),
              transform: hasFocus ? (Matrix4.identity()..scale(1.05)) : Matrix4.identity(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5.s(context)),
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
                              child: Icon(Icons.movie, color: Colors.white54, size: 50.s(context)),
                            ),
                    ),
                    Container(
                      padding: EdgeInsets.all(8.s(context)),
                      width: double.infinity,
                      color: hasFocus ? Colors.white : kSurfaceGrey,
                      child: Text(
                        result.title ?? result.name ?? 'Unknown',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: hasFocus ? kDeepBlack : kTextWhite,
                          fontSize: 12.s(context),
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
