import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/list_order.dart';
import '../../../../core/utils/share_export.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/providers/module_cache.dart';

class GroceriesScreen extends ConsumerStatefulWidget {
  const GroceriesScreen({super.key});

  @override
  ConsumerState<GroceriesScreen> createState() => _GroceriesScreenState();
}

class _GroceriesScreenState extends ConsumerState<GroceriesScreen>
    with SelectableIdsMixin {
  final _query = TextEditingController();
  final _quickName = TextEditingController();
  final _sheetName = TextEditingController();
  final _sheetQty = TextEditingController();
  List<GroceryItem> _items = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';
  EasyEntryMode _mode = EasyEntryMode.list;
  String _sheetCategory = 'other';
  bool _bulkBusy = false;

  @override
  void initState() {
    super.initState();
    final cached = ref
        .read(moduleCacheProvider)
        .read<List<GroceryItem>>(ModuleCacheKeys.groceries);
    if (cached != null) {
      _items = List<GroceryItem>.from(cached);
      _loading = false;
    }
    _load();
    loadEasyEntryMode('groceries').then((mode) {
      if (mounted) setState(() => _mode = mode);
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _quickName.dispose();
    _sheetName.dispose();
    _sheetQty.dispose();
    super.dispose();
  }

  void _setMode(EasyEntryMode mode) {
    setState(() => _mode = mode);
    saveEasyEntryMode('groceries', mode);
  }

  void _setItems(List<GroceryItem> items) {
    ref.read(moduleCacheProvider).write(ModuleCacheKeys.groceries, items);
    setState(() {
      _items = items;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _load() async {
    final showSpinner = ref
        .read(moduleCacheProvider)
        .shouldShowSpinner(ModuleCacheKeys.groceries);
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(vivrantApiProvider);
      final items = await api.listGroceries();
      List<int> order = const [];
      try {
        order = parseModuleListOrder(await api.getPreferences(), 'groceries');
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

  Future<void> _quickAdd(String name, {String? quantity, String? category}) async {
    final itemName = name.trim();
    if (itemName.isEmpty) return;
    try {
      final item = await ref.read(vivrantApiProvider).addGrocery({
        'name': itemName,
        if (quantity != null && quantity.trim().isNotEmpty)
          'quantity': quantity.trim(),
        if (category != null && category.isNotEmpty) 'category': category,
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
      final added = await ref.read(vivrantApiProvider).addGroceryBulk(text);
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
    await _quickAdd(
      name,
      quantity: _sheetQty.text,
      category: _sheetCategory,
    );
    _sheetName.clear();
    _sheetQty.clear();
    setState(() => _sheetCategory = 'other');
  }

  Future<void> _editGrocery(GroceryItem item) async {
    final draft = await showFieldEditorSheet(
      context,
      title: 'Edit item',
      fields: {
        'Name': item.name,
        'Quantity': item.quantity ?? '',
        'Category': item.category,
        'Price': item.estimatedPrice?.toStringAsFixed(0) ?? '',
      },
    );
    if (draft == null || !mounted) return;
    try {
      const cats = {
        'produce',
        'protein',
        'dairy',
        'grains',
        'pantry',
        'snacks',
        'drinks',
        'household',
        'other',
      };
      final category = (draft['Category'] ?? item.category).toLowerCase();
      final updated = await ref.read(vivrantApiProvider).updateGrocery(item.id, {
        'name': draft['Name'] ?? item.name,
        'quantity': draft['Quantity'],
        'category': cats.contains(category) ? category : item.category,
        if ((draft['Price'] ?? '').isNotEmpty)
          'estimated_price': double.tryParse(draft['Price']!),
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
    const cats = [
      'produce',
      'protein',
      'dairy',
      'grains',
      'pantry',
      'snacks',
      'drinks',
      'household',
      'other',
    ];
    final rows = _filtered;
    return ExcelTable(
      highlightLastRow: true,
      headers: [
        if (selecting) '',
        'Buy',
        'Item',
        'Qty',
        'Cat',
        '₱',
        '',
      ],
      rows: [
        for (final item in rows)
          [
            if (selecting)
              Checkbox(
                value: selectedIds.contains(item.id),
                onChanged: (_) => toggleSelected(item.id),
              ),
            Checkbox(
              value: item.isChecked,
              onChanged: (v) => _toggle(item, v ?? false),
            ),
            InkWell(
              onTap: () => _editGrocery(item),
              child: Text(
                item.name,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  decoration:
                      item.isChecked ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            Text(item.quantity ?? '—'),
            Text(item.category),
            Text(
              item.estimatedPrice == null
                  ? '—'
                  : '₱${item.estimatedPrice!.round()}',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _delete(item),
            ),
          ],
        [
          if (selecting) const SizedBox.shrink(),
          const SizedBox.shrink(),
          ExcelCellField(
            controller: _sheetName,
            hint: 'New item',
            width: 140,
            onSubmitted: (_) => _addSheetRow(),
          ),
          ExcelCellField(
            controller: _sheetQty,
            hint: 'qty',
            width: 72,
            onSubmitted: (_) => _addSheetRow(),
          ),
          ExcelDropdown<String>(
            value: cats.contains(_sheetCategory) ? _sheetCategory : 'other',
            items: [
              for (final c in cats)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _sheetCategory = v ?? 'other'),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _addSheetRow,
          ),
          const SizedBox.shrink(),
        ],
      ],
    );
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final qty = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: qty,
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final itemName = name.text.trim();
    final itemQty = qty.text.trim();
    name.dispose();
    qty.dispose();
    if (ok == true && itemName.isNotEmpty && mounted) {
      try {
        final api = ref.read(vivrantApiProvider);
        Map<String, dynamic>? estimate;
        try {
          estimate = await api.estimateGroceryCostAi(
            name: itemName,
            quantity: itemQty.isEmpty ? null : itemQty,
          );
        } catch (_) {
          estimate = null;
        }
        final item = await api.addGrocery({
          'name': itemName,
          if (itemQty.isNotEmpty) 'quantity': itemQty,
          if (estimate?['category'] != null) 'category': estimate!['category'],
          if (estimate?['estimated_price'] != null)
            'estimated_price': estimate!['estimated_price'],
        });
        if (!mounted) return;
        _setItems([..._items, item]);
        final tip = estimate?['store_tip']?.toString();
        context.showSuccess(
          tip != null && tip.isNotEmpty
              ? 'Item added · $tip'
              : 'Item added',
        );
      } catch (e) {
        if (!mounted) return;
        context.showError(apiErrorMessage(e));
      }
    }
  }

  Future<void> _toggle(GroceryItem item, bool checked) async {
    final prev = List<GroceryItem>.from(_items);
    _setItems([
      for (final i in _items)
        if (i.id == item.id) i.copyWith(isChecked: checked) else i,
    ]);
    try {
      await ref.read(vivrantApiProvider).toggleGrocery(item.id, checked);
      if (!mounted) return;
      context.showSuccess(checked ? 'Item checked' : 'Item unchecked');
    } catch (e) {
      if (!mounted) return;
      _setItems(prev);
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _delete(GroceryItem item, {bool confirm = true}) async {
    if (confirm) {
      final ok = await confirmDelete(context, label: item.name);
      if (!ok || !mounted) return;
    }
    final prev = List<GroceryItem>.from(_items);
    _setItems(_items.where((i) => i.id != item.id).toList());
    try {
      await ref.read(vivrantApiProvider).deleteGrocery(item.id);
      if (!mounted) return;
      context.showSuccess('Item removed');
    } catch (e) {
      if (!mounted) return;
      _setItems(prev);
      context.showError(apiErrorMessage(e));
    }
  }

  List<GroceryItem> get _filtered {
    final q = _query.text.trim().toLowerCase();
    return _items.where((item) {
      if (_filter == 'open' && item.isChecked) return false;
      if (_filter == 'done' && !item.isChecked) return false;
      if (q.isEmpty) return true;
      return item.name.toLowerCase().contains(q) ||
          (item.quantity?.toLowerCase().contains(q) ?? false) ||
          item.category.toLowerCase().contains(q);
    }).toList();
  }

  bool get _canReorder => _filter == 'all' && _query.text.trim().isEmpty;

  void _reorder(int from, int to) {
    final next = moveItem(_items, from, to);
    _setItems(next);
    unawaited(
      ref.read(vivrantApiProvider).saveListOrder(
        'groceries',
        next.map((item) => item.id).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checked = _items.where((i) => i.isChecked).length;
    final filtered = _filtered;
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Groceries'),
        actions: [
          if (_items.isNotEmpty) ShareExportButton(doc: groceryListDoc(_items)),
          ...selectAppBarActions(
            visibleIds: _items.map((i) => i.id),
            onArchive: () => confirmAndArchiveSelected(
              request: (ids) => ref.read(vivrantApiProvider).archiveItems(
                    entity: 'grocery_items',
                    ids: ids,
                  ),
              onRemoved: (ids) {
                _setItems(_items.where((i) => !ids.contains(i.id)).toList());
              },
            ),
          ),
          IconButton(onPressed: _add, icon: const Icon(Icons.add)),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: VivrantLayout.pagePadding,
          children: [
            const PageHeader(
              eyebrow: 'Shopping',
              title: 'Grocery',
              highlight: 'list',
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
                  hintText: 'e.g. eggs',
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
                onSubmit: _pasteList,
              ),
              const SizedBox(height: 16),
            ],
            StatCard(
              label: 'Checked',
              value: '$checked / ${_items.length}',
              caption: 'items',
              icon: Icons.shopping_basket_outlined,
            ),
            const SectionGap(),
            ModuleTile(
              icon: Icons.tune_rounded,
              label: 'List tools',
              caption: 'Low stock, restock, and smart plan',
              onTap: () => context.push('/groceries/tools'),
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
                message: 'List is empty.',
                action: ElevatedButton(
                  onPressed: _add,
                  child: const Text('Add item'),
                ),
              )
            else ...[
              VivrantSearchField(
                controller: _query,
                hintText: 'Search groceries…',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              VivrantFilterChips<String>(
                options: [
                  VivrantFilterOption(
                    value: 'all',
                    label: 'All',
                    count: _items.length,
                  ),
                  VivrantFilterOption(
                    value: 'open',
                    label: 'To buy',
                    count: _items.where((i) => !i.isChecked).length,
                  ),
                  VivrantFilterOption(
                    value: 'done',
                    label: 'Checked',
                    count: checked,
                  ),
                ],
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
                        child: Row(
                          children: [
                            Checkbox(
                              value: selecting
                                  ? selectedIds.contains(item.id)
                                  : item.isChecked,
                              onChanged: selecting
                                  ? (_) => toggleSelected(item.id)
                                  : (v) => _toggle(item, v ?? false),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      decoration: item.isChecked
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                  if (item.quantity != null)
                                    Text(
                                      item.quantity!,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _editGrocery(item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(item),
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
