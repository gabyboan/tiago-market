import 'package:flutter/material.dart';

class ComparisonFilters extends StatelessWidget {
  const ComparisonFilters({
    required this.sortMode,
    required this.freshOnly,
    required this.locationEnabled,
    required this.onSortChanged,
    required this.onFreshOnlyChanged,
    super.key,
  });

  final String sortMode;
  final bool freshOnly;
  final bool locationEnabled;
  final ValueChanged<String> onSortChanged;
  final ValueChanged<bool> onFreshOnlyChanged;

  @override
  Widget build(BuildContext context) {
    final effectiveSortMode =
        sortMode == 'distance' && !locationEnabled ? 'price_asc' : sortMode;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownMenu<String>(
          initialSelection: effectiveSortMode,
          label: const Text('Ordenar'),
          width: 210,
          dropdownMenuEntries: [
            const DropdownMenuEntry(
              value: 'price_asc',
              label: 'Menor precio',
              leadingIcon: Icon(Icons.south_rounded),
            ),
            const DropdownMenuEntry(
              value: 'price_desc',
              label: 'Mayor precio',
              leadingIcon: Icon(Icons.north_rounded),
            ),
            const DropdownMenuEntry(
              value: 'stores_desc',
              label: 'Más tiendas (cargadas)',
              leadingIcon: Icon(Icons.storefront_rounded),
            ),
            const DropdownMenuEntry(
              value: 'fresh_desc',
              label: 'Mas reciente',
              leadingIcon: Icon(Icons.update_rounded),
            ),
            if (locationEnabled)
              const DropdownMenuEntry(
                value: 'distance',
                label: 'Mas cerca',
                leadingIcon: Icon(Icons.near_me_rounded),
              ),
          ],
          onSelected: (value) {
            if (value != null) onSortChanged(value);
          },
        ),
        FilterChip(
          avatar: const Icon(Icons.bolt_rounded, size: 18),
          label: const Text('Solo recientes'),
          selected: freshOnly,
          onSelected: onFreshOnlyChanged,
        ),
      ],
    );
  }
}
