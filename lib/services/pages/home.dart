import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/webview.dart';
import 'package:cineby_tv/services/pages/search.dart';

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
      body: SafeArea(
        child: FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.select ||
                            event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.space)) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SearchPage(),
                        ),
                      );
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Builder(
                    builder: (context) {
                      final bool hasFocus = Focus.of(context).hasFocus;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: hasFocus ? Colors.blue : Colors.grey,
                            width: hasFocus ? 3 : 1,
                          ),
                          color: hasFocus ? Colors.blue.withOpacity(0.1) : Colors.transparent,
                        ),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const SearchPage()),
                            );
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Icon(Icons.search, color: Colors.grey),
                                SizedBox(width: 8),
                                Text(
                                  'Search movies, TV shows...',
                                  style: TextStyle(color: Colors.grey, fontSize: 16),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Expanded(
                child: Observer(
                  builder: (_) {
                    if (_searchStore.isLoading &&
                        _searchStore.searchResults.isEmpty &&
                        _searchStore.trendingResults.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (_searchStore.errorMessage != null) {
                      return Center(child: Text(_searchStore.errorMessage!));
                    }

                    final results =
                        _searchStore.searchQuery.isNotEmpty
                            ? _searchStore.searchResults
                            : _searchStore.trendingResults;

                    if (results.isEmpty) {
                      return const Center(child: Text("No results found"));
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_searchStore.searchQuery.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Text(
                              "Trending Today",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        Expanded(
                          child: GridView.builder(
                            padding: const EdgeInsets.all(8),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  childAspectRatio: 0.6,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                ),
                            itemCount: results.length,
                            itemBuilder: (context, index) {
                              final result = results[index];
                              return Focus(
                                onKeyEvent: (node, event) {
                                  if (event is KeyDownEvent &&
                                      (event.logicalKey ==
                                              LogicalKeyboardKey.select ||
                                          event.logicalKey ==
                                              LogicalKeyboardKey.enter ||
                                          event.logicalKey ==
                                              LogicalKeyboardKey.space)) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (context) => MyWidget(
                                              url: "$serverurl${result.id}",
                                            ),
                                      ),
                                    );
                                    return KeyEventResult.handled;
                                  }
                                  return KeyEventResult.ignored;
                                },
                                child: Builder(
                                  builder: (context) {
                                    final bool hasFocus =
                                        Focus.of(context).hasFocus;
                                    return AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color:
                                              hasFocus
                                                  ? Colors.blue
                                                  : Colors.transparent,
                                          width: 3,
                                        ),
                                      ),
                                      transform:
                                          hasFocus
                                              ? (Matrix4.identity()
                                                ..scale(1.05))
                                              : Matrix4.identity(),
                                      child: InkWell(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder:
                                                  (context) => MyWidget(
                                                    url:
                                                        "$serverurl${result.id}",
                                                  ),
                                            ),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(8),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child:
                                                    result.posterPath != null
                                                        ? Image.network(
                                                          "https://image.tmdb.org/t/p/w300${result.posterPath}",
                                                          fit: BoxFit.cover,
                                                          errorBuilder:
                                                              (
                                                                context,
                                                                error,
                                                                stackTrace,
                                                              ) => const Center(
                                                                child: Icon(
                                                                  Icons.movie,
                                                                ),
                                                              ),
                                                        )
                                                        : const Center(
                                                          child: Icon(
                                                            Icons.movie,
                                                          ),
                                                        ),
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              result.title ??
                                                  result.name ??
                                                  'Unknown',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
