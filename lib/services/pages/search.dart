import 'package:cineby_tv/services/config.dart';
import 'package:cineby_tv/services/pages/webview.dart';
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
  final TextEditingController _searchController = TextEditingController();
  final SearchStore _searchStore = SearchStore();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Auto-focus the search field after a short delay to trigger the keyboard
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        
        // If keyboard is visible, dismiss it first
        if (_searchFocusNode.hasFocus) {
          _searchFocusNode.unfocus();
          // Small delay to allow keyboard animation
          await Future.delayed(const Duration(milliseconds: 100));
          return;
        }
        
        // Otherwise, allow pop
        if (mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Search movies, TV shows...',
              hintStyle: TextStyle(color: Colors.white70),
              border: InputBorder.none,
            ),
            onChanged: (value) {
              _searchStore.setSearchQuery(value);
            },
            onSubmitted: (value) {
              // On TV, 'Enter' on keyboard should probably move focus to results
              _searchFocusNode.nextFocus();
            },
          ),
          backgroundColor: Colors.black87,
        ),
        body: Observer(
          builder: (_) {
            if (_searchStore.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (_searchStore.errorMessage != null) {
              return Center(child: Text(_searchStore.errorMessage!));
            }

            final results = _searchStore.searchResults;

            if (results.isEmpty && _searchStore.searchQuery.isNotEmpty) {
              return const Center(child: Text("No results found"));
            }
            
            if (_searchStore.searchQuery.isEmpty) {
              return const Center(child: Text("Type something to search"));
            }

            return GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
                        (event.logicalKey == LogicalKeyboardKey.select ||
                            event.logicalKey == LogicalKeyboardKey.enter ||
                            event.logicalKey == LogicalKeyboardKey.space)) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MyWidget(
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
                      final bool hasFocus = Focus.of(context).hasFocus;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: hasFocus ? Colors.blue : Colors.transparent,
                            width: 3,
                          ),
                        ),
                        transform: hasFocus
                            ? (Matrix4.identity()..scale(1.05))
                            : Matrix4.identity(),
                        child: InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MyWidget(
                                  url: "$serverurl${result.id}",
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: result.posterPath != null
                                      ? Image.network(
                                          "https://image.tmdb.org/t/p/w300${result.posterPath}",
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) =>
                                              const Center(child: Icon(Icons.movie, size: 50)),
                                        )
                                      : const Center(child: Icon(Icons.movie, size: 50)),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                result.title ?? result.name ?? 'Unknown',
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
            );
          },
        ),
      ),
    );
  }
}
