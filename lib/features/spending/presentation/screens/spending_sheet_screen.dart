import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/share_export.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/models/models.dart';

class SpendingSheetScreen extends ConsumerStatefulWidget {
  const SpendingSheetScreen({super.key});

  @override
  ConsumerState<SpendingSheetScreen> createState() =>
      _SpendingSheetScreenState();
}

class _SpendingSheetScreenState extends ConsumerState<SpendingSheetScreen>
    with SelectableIdsMixin {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  List<Expense> _expenses = [];
  bool _loading = true;
  String? _error;
  bool _bulkBusy = false;
  EasyEntryMode _mode = EasyEntryMode.sheet;
  String _category = 'food';

  static const _categories = [
    'food',
    'fitness',
    'supplements',
    'wellness',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    loadEasyEntryMode('spending-sheet', EasyEntryMode.sheet).then((mode) {
      if (mounted) setState(() => _mode = mode);
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final expenses = await ref.read(vivrantApiProvider).listExpenses();
      if (!mounted) return;
      setState(() {
        _expenses = expenses;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _addRow() async {
    final title = _title.text.trim();
    final amount = double.tryParse(_amount.text);
    if (title.isEmpty || amount == null) return;
    try {
      final expense = await ref.read(vivrantApiProvider).addExpense({
        'title': title,
        'category': _category,
        'amount': amount,
      });
      if (!mounted) return;
      setState(() {
        _expenses = [expense, ..._expenses];
        _title.clear();
        _amount.clear();
      });
      context.showSuccess('Expense added');
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _paste(String text) async {
    setState(() => _bulkBusy = true);
    try {
      final added = await ref.read(vivrantApiProvider).addExpenseBulk(text);
      if (!mounted) return;
      setState(() => _expenses = [...added, ..._expenses]);
      context.showSuccess('Added ${added.length}');
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
      rethrow;
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Spending sheet'),
        actions: [
          if (_expenses.isNotEmpty) ShareExportButton(doc: expensesDoc(_expenses)),
          ...selectAppBarActions(
            visibleIds: _expenses.map((e) => e.id),
            onArchive: () => confirmAndArchiveSelected(
              request: (ids) => ref.read(vivrantApiProvider).archiveItems(
                    entity: 'expenses',
                    ids: ids,
                  ),
              onRemoved: (ids) {
                setState(() {
                  _expenses = _expenses.where((e) => !ids.contains(e.id)).toList();
                });
              },
            ),
          ),
          IconButton(
            onPressed: () => context.push('/spending/log'),
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
              eyebrow: 'Money',
              title: 'Sheet',
              highlight: 'ledger',
            ),
            EasyEntryToggle(
              value: _mode,
              onChanged: (mode) {
                setState(() => _mode = mode);
                saveEasyEntryMode('spending-sheet', mode);
              },
            ),
            const SizedBox(height: 12),
            if (_mode == EasyEntryMode.paste)
              QuickListPaste(
                pending: _bulkBusy,
                placeholder: 'Coffee, 120\nGym, 500, fitness',
                hint: 'Amount is required. Optional category after a comma.',
                onSubmit: _paste,
              )
            else if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              EmptyState(
                message: _error!,
                action: OutlinedButton(onPressed: _load, child: const Text('Retry')),
              )
            else
              ExcelTable(
                highlightLastRow: true,
                headers: [
                  if (selecting) '',
                  'Expense',
                  'Category',
                  '₱',
                  '',
                ],
                rows: [
                  for (final e in _expenses)
                    [
                      if (selecting)
                        Checkbox(
                          value: selectedIds.contains(e.id),
                          onChanged: (_) => toggleSelected(e.id),
                        ),
                      Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(e.category),
                      Text('₱${e.amount.round()}'),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () async {
                          if (!(await confirmDelete(context, label: e.title))) return;
                          try {
                            await ref.read(vivrantApiProvider).deleteExpense(e.id);
                            if (!mounted) return;
                            setState(() {
                              _expenses = _expenses.where((row) => row.id != e.id).toList();
                            });
                          } catch (err) {
                            if (!mounted) return;
                            context.showError(apiErrorMessage(err));
                          }
                        },
                      ),
                    ],
                  [
                    if (selecting) const SizedBox.shrink(),
                    ExcelCellField(
                      controller: _title,
                      hint: 'New expense',
                      width: 140,
                      onSubmitted: (_) => _addRow(),
                    ),
                    ExcelDropdown<String>(
                      value: _category,
                      items: [
                        for (final c in _categories)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) => setState(() => _category = v ?? 'food'),
                    ),
                    ExcelCellField(
                      controller: _amount,
                      hint: '0',
                      width: 72,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.right,
                      onSubmitted: (_) => _addRow(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _addRow,
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}
