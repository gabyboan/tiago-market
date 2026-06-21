import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tiago_market_app/auth/auth_account_button.dart';
import 'package:tiago_market_app/src/config.dart';
import 'package:tiago_market_app/src/controllers/search_controller.dart'
    as local;
import 'package:tiago_market_app/src/models/models.dart';
import 'package:tiago_market_app/src/navigation/app_routes.dart';
import 'package:tiago_market_app/src/widgets/notice_card.dart';
import 'package:tiago_market_app/src/widgets/product_comparison_card.dart';
import 'package:tiago_market_app/src/widgets/favorites_sheet.dart';
import 'package:tiago_market_app/src/widgets/shopping_list_sheet.dart';
import 'package:tiago_market_app/src/widgets/comparison_filters.dart';

part 'search/search_page_components.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<local.SearchController>(
      create: (_) => local.SearchController(),
      child: const SearchPageBody(),
    );
  }
}

class SearchPageBody extends StatelessWidget {
  const SearchPageBody({super.key});

  Future<void> _showFavorites(BuildContext context) async {
    final controller = context.read<local.SearchController>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FavoritesSheet(
        items: controller.favorites,
        onRemove: controller.removeFavorite,
        onAdd: controller.addFavoriteToShoppingList,
      ),
    );
  }

  Future<void> _showShoppingList(BuildContext context) async {
    final controller = context.read<local.SearchController>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => ShoppingListSheet(
        items: controller.shoppingItems,
        onQuantityChanged: controller.updateShoppingItem,
      ),
    );
  }

  Future<void> _showFilters(BuildContext context) async {
    final controller = context.read<local.SearchController>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: ComparisonFilters(
            sortMode: controller.sortMode,
            freshOnly: controller.freshOnly,
            locationEnabled: controller.hasLocation,
            onSortChanged: controller.setSortMode,
            onFreshOnlyChanged: controller.setFreshOnly,
          ),
        ),
      ),
    );
  }

  Future<void> _showLegal(BuildContext context) async {
    await Navigator.of(context).pushNamed(AppRoutes.legalInfo);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<local.SearchController>();
    final filteredResults = controller.filteredResults;
    final groups = controller.groupedResults;

    return Scaffold(
      appBar: _SearchAppBar(
        shoppingCount: controller.shoppingItems.length,
        favoritesCount: controller.favorites.length,
        onShowFavorites: () => _showFavorites(context),
        onShowShoppingList: () => _showShoppingList(context),
        onShowLegal: () => _showLegal(context),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              controller: controller.scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                const _SearchHero(),
                const SizedBox(height: 24),
                _SearchInputRow(
                  controller: controller,
                  onShowFilters: () => _showFilters(context),
                ),
                const SizedBox(height: 14),
                _QuickSearchChips(
                  loading: controller.loading,
                  onSelected: (query) => controller.search(quickQuery: query),
                ),
                const SizedBox(height: 16),
                _CategoryChips(
                  categories: controller.categories,
                  selectedCategory: controller.selectedCategory,
                  onSelected: controller.setCategory,
                ),
                if (controller.searchHistory.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _SearchHistorySection(controller: controller),
                ],
                if (controller.favorites.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _FavoritesSection(controller: controller),
                ],
                const SizedBox(height: 14),
                _LocationControls(controller: controller),
                if (controller.hasLocation) ...[
                  const SizedBox(height: 8),
                  _LocationHint(controller: controller),
                ],
                const SizedBox(height: 22),
                _NoticeSection(controller: controller),
                const SizedBox(height: 22),
                _ResultsHeader(
                  groupsCount: groups.length,
                  pricesCount: filteredResults.length,
                ),
                const SizedBox(height: 12),
                _SearchResults(controller: controller, groups: groups),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
