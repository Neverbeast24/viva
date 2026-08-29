import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/vivrant_colors.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/humanize.dart';
import '../../../../core/utils/list_order.dart';
import '../../../../core/utils/share_export.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/constants/enums.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/providers/module_cache.dart';

class PantryScreen extends ConsumerStatefulWidget {
  const PantryScreen({super.key});

  @override
  ConsumerState<PantryScreen> createState() => _PantryScreenState();
}

class _PantryScreenState extends ConsumerState<PantryScreen>
    with SelectableIdsMixin {
  final _query = TextEditingController();
  final _quickName = TextEditingController();
  final _sheetName = TextEditingController();
  List<PantryItem> _items = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';
  EasyEntryMode _mode = EasyEntryMode.list;
  String _sheetCategory = 'other';
  bool _bulkBusy = false;

  @override
  void initState() {
    super.initState();
    loadEasyEntryMode('pantry-items').then((mode) {
      if (mounted) setState(() => _mode = mode);
    });
    final cached =
        ref.read(moduleCacheProvider).read<List<PantryItem>>(ModuleCacheKeys.pantry);
    if (cached != null) {
      _items = List<PantryItem>.from(cached);
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _quickName.dispose();
    _sheetName.dispose();
    super.dispose();
  }

  void _setMode(EasyEntryMode mode) {
    setState(() => _mode = mode);
    saveEasyEntryMode('pantry-items', mode);
  }

  void _setItems(List<PantryItem> items) {
    ref.read(moduleCacheProvider).write(ModuleCacheKeys.pantry, items);
    setState(() {
      _items = items;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _load() async {
    final showSpinner =
        ref.read(moduleCacheProvider).shouldShowSpinner(ModuleCacheKeys.pantry);
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(vivrantApiProvider);
      final items = await api.listPantry();
      List<int> order = const [];
      try {
        order = parseModuleListOrder(await api.getPreferences(), 'pantry');
      } catch (_) {}
      if (!mounted) return;
      _setItems(applyIdOrder(items, order, (item) => item.id));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _quickAdd(String name) async {
    final itemName = name.trim();
    if (itemName.isEmpty) return;
    try {
      final item = await ref.read(vivrantApiProvider).addPantry({
        'name': itemName,
        'category': 'other',
        'stock_level': 50,
      });
      if (!mounted) return;
      _setItems([..._items, item]);
      context.showSuccess('Item added');
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _pasteList(String text) async {
    setState(() => _bulkBusy = true);
    try {
      final added = await ref.read(vivrantApiProvider).addPantryBulk(text);
      if (!mounted) return;
      _setItems([..._items, ...added]);
      context.showSuccess(
        'Added ${added.length} item${added.length == 1 ? '' : 's'}',
      );
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
      rethrow;
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Future<void> _addSheetRow() async {
    final name = _sheetName.text.trim();
    if (name.isEmpty) return;
    try {
      final item = await ref.read(vivrantApiProvider).addPantry({
        'name': name,
        'category': _sheetCategory,
        'stock_level': 50,
      });
      if (!mounted) return;
      _setItems([..._items, item]);
      _sheetName.clear();
      setState(() => _sheetCategory = 'other');
      context.showSuccess('Item added');
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _editPantry(PantryItem item) async {
    final draft = await showFieldEditorSheet(
      context,
      title: 'Edit pantry item',
      fields: {
        'Name': item.name,
        'Category': item.category,
        'Stock': item.stockLevel.toString(),
      },
    );
    if (draft == null || !mounted) return;
    try {
      final stock = int.tryParse(draft['Stock'] ?? '') ?? item.stockLevel;
      final updated = await ref.read(vivrantApiProvider).updatePantry(item.id, {
        'name': draft['Name'] ?? item.name,
        'category': draft['Category'] ?? item.category,
        'stock_level': stock.clamp(0, 100),
      });
      if (!mounted) return;
      _setItems([for (final row in _items) row.id == item.id ? updated : row]);
      context.showSuccess('Item updated');
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Widget _buildSheet() {
    return ExcelTable(
      highlightLastRow: true,
      headers: [
        if (selecting) '',
        'Item',
        'Category',
        'Stock',
        '',
      ],
      rows: [
        for (final item in _filtered)
          [
            if (selecting)
              Checkbox(
                value: selectedIds.contains(item.id),
                onChanged: (_) => toggleSelected(item.id),
              ),
            InkWell(
              onTap: () => _editPantry(item),
              child: Text(
                item.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(item.category),
            Text('${item.stockLevel}%'),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _delete(item),
            ),
          ],
        [
          if (selecting) const SizedBox.shrink(),
          ExcelCellField(
            controller: _sheetName,
            hint: 'New item',
            width: 140,
            onSubmitted: (_) => _addSheetRow(),
          ),
          ExcelDropdown<String>(
            value: pantryCategories.contains(_sheetCategory)
                ? _sheetCategory
                : 'other',
            items: [
              for (final c in pantryCategories)
                DropdownMenuItem(value: c, child: Text(labelForOption(c))),
            ],
            onChanged: (v) => setState(() => _sheetCategory = v ?? 'other'),
          ),
          const Text('50%'),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 18),
            onPressed: _addSheetRow,
          ),
        ],
      ],
    );
  }

  void _patchStock(int id, int stockLevel) {
    _setItems([
      for (final item in _items)
        if (item.id == id) item.copyWith(stockLevel: stockLevel) else item,
    ]);
  }

  Future<void> _commitStock(PantryItem item, int stockLevel) async {
    final prev = item.stockLevel;
    _patchStock(item.id, stockLevel);
    try {
      await ref.read(vivrantApiProvider).updatePantryStock(item.id, stockLevel);
      if (!mounted) return;
      context.showSuccess('Stock updated');
    } catch (e) {
      if (!mounted) return;
      _patchStock(item.id, prev);
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _delete(PantryItem item, {bool confirm = true}) async {
    if (confirm) {
      final ok = await confirmDelete(context, label: item.name);
      if (!ok || !mounted) return;
    }
    final prev = List<PantryItem>.from(_items);
    _setItems(_items.where((i) => i.id != item.id).toList());
    try {
      await ref.read(vivrantApiProvider).deletePantry(item.id);
      if (!mounted) return;
      context.showSuccess('Item removed');
    } catch (e) {
      if (!mounted) return;
      _setItems(prev);
      context.showError(apiErrorMessage(e));
    }
  }

  List<String> get _categories {
    final cats = _items.map((i) => i.category).where((c) => c.isNotEmpty).toSet().toList()
      ..sort();
    return cats;
  }

  List<VivrantFilterOption<String>> get _filterOptions => [
        VivrantFilterOption(
          value: 'all',
          label: 'All',
          count: _items.length,
        ),
        VivrantFilterOption(
          value: 'low',
          label: 'Low stock',
          count: _items.where((i) => i.isLowStock).length,
        ),
        ..._categories.map(
          (c) => VivrantFilterOption(
            value: 'cat:$c',
            label: humanizeLabel(c),
            count: _items.where((i) => i.category == c).length,
          ),
        ),
      ];

  List<PantryItem> get _filtered {
    final q = _query.text.trim().toLowerCase();
    return _items.where((item) {
      if (_filter == 'low' && !item.isLowStock) return false;
      if (_filter.startsWith('cat:') &&
          item.category != _filter.substring(4)) {
        return false;
      }
      if (q.isEmpty) return true;
      return item.name.toLowerCase().contains(q) ||
          item.category.toLowerCase().contains(q);
    }).toList();
  }

  bool get _canReorder => _filter == 'all' && _query.text.trim().isEmpty;

  void _reorder(int from, int to) {
    final next = moveItem(_items, from, to);
    _setItems(next);
    unawaited(
      ref.read(vivrantApiProvider).saveListOrder(
        'pantry',
        next.map((item) => item.id).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final low = _items.where((i) => i.isLowStock).length;
    final filtered = _filtered;
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Pantry'),
        actions: [
          if (_items.isNotEmpty) ShareExportButton(doc: pantryDoc(_items)),
          ...selectAppBarActions(
            visibleIds: _items.map((i) => i.id),
            onArchive: () => confirmAndArchiveSelected(
              request: (ids) => ref.read(vivrantApiProvider).archiveItems(
                    entity: 'pantry_items',
                    ids: ids,
                  ),
              onRemoved: (ids) {
                setState(() {
                  _items = _items.where((i) => !ids.contains(i.id)).toList();
                });
              },
            ),
          ),
          IconButton(
            tooltip: 'Add pantry item',
            onPressed: () => context.push('/pantry/add'),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: VivrantLayout.pagePadding,
          children: [
            const PageHeader(
              eyebrow: 'Kitchen',
              title: 'Pantry',
              highlight: 'stock',
            ),
            EasyEntryToggle(
              value: _mode,
              onChanged: _setMode,
            ),
            const SizedBox(height: 12),
            if (_mode == EasyEntryMode.list || _mode == EasyEntryMode.sheet) ...[
              TextField(
                controller: _quickName,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Add with just a name',
                  hintText: 'e.g. brown rice',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () async {
                      await _quickAdd(_quickName.text);
                      _quickName.clear();
                    },
                  ),
                ),
                onSubmitted: (value) async {
                  await _quickAdd(value);
                  _quickName.clear();
                },
              ),
              const SizedBox(height: 12),
            ],
            if (_mode == EasyEntryMode.paste) ...[
              QuickListPaste(
                pending: _bulkBusy,
                placeholder: 'brown rice\neggs\nmilk',
                onSubmit: _pasteList,
              ),
              const SizedBox(height: 16),
            ],
            StatCard(
              label: 'Low stock',
              value: '$low',
              caption: 'of ${_items.length} items',
              icon: Icons.kitchen_outlined,
            ),
            const SectionGap(),
            ModuleTile(
              icon: Icons.shopping_cart_outlined,
              label: 'Add low stock to groceries',
              caption: low == 0 ? 'Nothing is low' : '$low items to restock',
              onTap: () async {
                try {
                  await ref.read(vivrantApiProvider).addLowStockToGrocery();
                  if (!context.mounted) return;
                  context.showSuccess('Low stock added to groceries');
                  await _load();
                } catch (e) {
                  if (!context.mounted) return;
                  context.showError(apiErrorMessage(e));
                }
              },
            ),
            const SectionGap(),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              EmptyState(
                message: _error!,
                action: OutlinedButton(
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              )
            else if (_mode == EasyEntryMode.sheet)
              _buildSheet()
            else if (_items.isEmpty)
              EmptyState(
                message: 'Pantry is empty.',
                action: ElevatedButton(
                  onPressed: () => context.push('/pantry/add'),
                  child: const Text('Add item'),
                ),
              )
            else ...[
              VivrantSearchField(
                controller: _query,
                hintText: 'Search pantry…',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              VivrantFilterChips<String>(
                options: _filterOptions,
                selected: _filter,
                onSelected: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                const EmptyState(
                  message:
                      'No items match these filters. Try All or another search.',
                )
              else ...[
                if (_canReorder && !selecting)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Long-press, then drag to reorder.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                NestedReorderableColumn(
                  enabled: _canReorder && !selecting,
                  itemCount: filtered.length,
                  keyOf: (i) => filtered[i].id,
                  onReorder: _reorder,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return wrapArchiveable(
                      id: item.id,
                      label: item.name,
                      archive: () => _delete(item, confirm: false),
                      child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: VivrantPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (selecting)
                                  Checkbox(
                                    value: selectedIds.contains(item.id),
                                    onChanged: (_) => toggleSelected(item.id),
                                  ),
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (item.isLowStock)
                                  Text(
                                    'LOW',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: VivrantColors.of(context).accent,
                                        ),
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _editPantry(item),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _delete(item),
                                ),
                              ],
                            ),
                            Text(
                              '${item.category} · ${item.stockLevel}%',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Slider(
                              value: item.stockLevel.toDouble().clamp(0, 100),
                              min: 0,
                              max: 100,
                              divisions: 20,
                              label: '${item.stockLevel}%',
                              onChanged: (v) => _patchStock(item.id, v.round()),
                              onChangeEnd: (v) => _commitStock(item, v.round()),
                            ),
                          ],
                        ),
                      ),
                    ),
                    );
                  },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
