part of 'package:tiago_market_app/src/pages/search_page.dart';

class _SearchAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _SearchAppBar({
    required this.shoppingCount,
    required this.favoritesCount,
    required this.onShowFavorites,
    required this.onShowShoppingList,
    required this.onShowLegal,
  });

  final int shoppingCount;
  final int favoritesCount;
  final VoidCallback onShowFavorites;
  final VoidCallback onShowShoppingList;
  final VoidCallback onShowLegal;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xFFF5F7F5),
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: Color(0xFF006C51),
            foregroundColor: Colors.white,
            child: Icon(Icons.shopping_basket_rounded, size: 20),
          ),
          SizedBox(width: 10),
          Flexible(
            child: Text(
              'Tiago Market',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: onShowFavorites,
          tooltip: 'Favoritos',
          icon: Badge(
            isLabelVisible: favoritesCount > 0,
            label: Text('$favoritesCount'),
            child: const Icon(Icons.favorite_border),
          ),
        ),
        IconButton(
          onPressed: onShowShoppingList,
          tooltip: 'Lista de compras',
          icon: Badge(
            isLabelVisible: shoppingCount > 0,
            label: Text('$shoppingCount'),
            child: const Icon(Icons.shopping_cart_outlined),
          ),
        ),
        IconButton(
          onPressed: onShowLegal,
          tooltip: 'Aviso legal',
          icon: const Icon(Icons.info_outline),
        ),
        if (authEnabled) const AuthAccountButton(),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _SearchHero extends StatelessWidget {
  const _SearchHero();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Compara antes\nde comprar.',
          style: TextStyle(
            fontSize: 36,
            height: 1.05,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.4,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Compara alimentos, bebidas, hogar, limpieza, electrónica y más productos publicados por tiendas reales.',
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SearchInputRow extends StatelessWidget {
  const _SearchInputRow({
    required this.controller,
    required this.onShowFilters,
  });

  final local.SearchController controller;
  final VoidCallback onShowFilters;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SearchBar(
            controller: controller.queryController,
            hintText: 'Busca leche, arroz, huevo...',
            leading: const Icon(Icons.search_rounded),
            trailing: [
              IconButton(
                onPressed:
                    controller.loading ? null : () => controller.search(),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ],
            onSubmitted: (_) => controller.search(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          onPressed: onShowFilters,
          tooltip: 'Filtros',
          icon: Badge(
            isLabelVisible: controller.freshOnly,
            child: const Icon(Icons.tune_rounded),
          ),
        ),
      ],
    );
  }
}

class _QuickSearchChips extends StatelessWidget {
  const _QuickSearchChips({
    required this.loading,
    required this.onSelected,
  });

  final bool loading;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final query in ['coca', 'leche', 'arroz', 'huevo'])
          ActionChip(
            label: Text(query),
            onPressed: loading ? null : () => onSelected(query),
          ),
      ],
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selectedCategory,
    required this.onSelected,
  });

  final List<ProductCategory> categories;
  final String? selectedCategory;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('Todo'),
              selected: selectedCategory == null,
              onSelected: (_) => onSelected(null),
            ),
          ),
          for (final category in categories)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${category.name} (${category.count})'),
                selected: selectedCategory == category.name,
                onSelected: (_) => onSelected(category.name),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchHistorySection extends StatelessWidget {
  const _SearchHistorySection({required this.controller});

  final local.SearchController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Búsquedas recientes',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const Spacer(),
            TextButton(
              onPressed: controller.clearSearchHistory,
              child: const Text('Borrar'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final query in controller.searchHistory)
              ActionChip(
                label: Text(query),
                onPressed: () => controller.search(quickQuery: query),
              ),
          ],
        ),
      ],
    );
  }
}

class _LocationControls extends StatelessWidget {
  const _LocationControls({required this.controller});

  final local.SearchController controller;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.tonalIcon(
          onPressed:
              controller.locating ? null : () => controller.useLocation(),
          icon: controller.locating
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location_rounded),
          label: Text(
            controller.hasLocation ? 'Ubicación activa' : 'Usar mi ubicación',
          ),
        ),
        if (controller.hasLocation)
          ActionChip(
            avatar: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Quitar ubicación'),
            onPressed: controller.clearLocation,
          ),
        DropdownButton<double>(
          value: controller.radiusKm,
          items: [2, 5, 10, 20]
              .map(
                (radius) => DropdownMenuItem(
                  value: radius.toDouble(),
                  child: Text('$radius km'),
                ),
              )
              .toList(),
          onChanged: controller.hasLocation
              ? (value) {
                  if (value == null) return;
                  controller.setRadiusKm(value);
                  controller.searchWithLocationFallback();
                }
              : null,
        ),
      ],
    );
  }
}

class _LocationHint extends StatelessWidget {
  const _LocationHint({required this.controller});

  final local.SearchController controller;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Buscando dentro de ${controller.radiusKm.toStringAsFixed(0)} km. '
      'Tu ubicación se usa solo para esta consulta. '
      '${controller.nearbyBranches} sucursales verificadas cerca.',
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _FavoritesSection extends StatelessWidget {
  const _FavoritesSection({required this.controller});

  final local.SearchController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Favoritos guardados',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (context) => FavoritesSheet(
                    items: controller.favorites,
                    onRemove: controller.removeFavorite,
                    onAdd: controller.addFavoriteToShoppingList,
                  ),
                );
              },
              child: const Text('Ver todo'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: controller.favorites.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final favorite = controller.favorites[index];
              return ActionChip(
                label: Text(favorite.productName),
                onPressed: () => controller.search(
                  quickQuery: favorite.productName,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NoticeSection extends StatelessWidget {
  const _NoticeSection({required this.controller});

  final local.SearchController controller;

  @override
  Widget build(BuildContext context) {
    final notices = <Widget>[];
    if (controller.usingDemo) {
      notices.add(const NoticeCard(
        icon: Icons.science_outlined,
        text:
            'Vista demo. Al desplegar la API, esta pantalla mostrará datos en vivo.',
      ));
    }
    if (controller.error != null) {
      notices.add(
        NoticeCard(icon: Icons.info_outline, text: controller.error!),
      );
    }
    if (controller.showingOnlineFallback) {
      notices.add(const NoticeCard(
        icon: Icons.storefront_outlined,
        text: 'Todavía no hay precios verificados por sucursal en esta zona.',
      ));
      notices.add(const NoticeCard(
        icon: Icons.public_rounded,
        text: 'Precios online, no verificados para una sucursal cercana.',
      ));
    }
    if (controller.usingCache) {
      notices.add(const NoticeCard(
        icon: Icons.offline_bolt_outlined,
        text: 'Sin conexión estable. Mostrando la última consulta guardada.',
      ));
    }

    if (notices.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final notice in notices) ...[
          notice,
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ResultsHeader extends StatelessWidget {
  const _ResultsHeader({
    required this.groupsCount,
    required this.pricesCount,
  });

  final int groupsCount;
  final int pricesCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Mejores precios',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const Spacer(),
        Text(
          '$groupsCount productos · $pricesCount precios',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.controller,
    required this.groups,
  });

  final local.SearchController controller;
  final List<ProductComparisonGroup> groups;

  @override
  Widget build(BuildContext context) {
    if (controller.loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (controller.results.isEmpty) {
      return Center(
        child: Text(controller.emptyMessage),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups) ...[
          ProductComparisonCard(
            group: group,
            onAdd: () => controller.addToShoppingList(group),
            favorite: controller.isFavorite(group),
            onToggleFavorite: () => controller.toggleFavorite(group),
            recommendationMode: controller.sortMode,
          ),
          const SizedBox(height: 12),
        ],
        if (controller.loadingMore)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (!controller.loading &&
            controller.hasMore &&
            !controller.usingDemo)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text('Desliza para mostrar más productos'),
            ),
          ),
      ],
    );
  }
}
