import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/humanize.dart';
import '../../../../core/utils/share_export.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/constants/enums.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/providers/module_cache.dart';

class SpendingHistoryScreen extends ConsumerStatefulWidget {
  const SpendingHistoryScreen({super.key});

  @override
  ConsumerState<SpendingHistoryScreen> createState() =>
      _SpendingHistoryScreenState();
}

class _SpendingHistoryScreenState extends ConsumerState<SpendingHistoryScreen>
    with SelectableIdsMixin {
  final _query = TextEditingController();
  Map<String, dynamic>? _overview;
  List<Expense> _expenses = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    final cached = ref
        .read(moduleCacheProvider)
        .read<Map<String, dynamic>>(ModuleCacheKeys.spending);
    if (cached != null) {
      _overview = cached['overview'] as Map<String, dynamic>?;
      final expenses = cached['expenses'];
      if (expenses is List<Expense>) {
        _expenses = List<Expense>.from(expenses);
      }
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _cache() {
    ref.read(moduleCacheProvider).write(ModuleCacheKeys.spending, {
      'overview': _overview,
      'expenses': _expenses,
    });
  }

  Future<void> _load() async {
    final showSpinner = ref.read(moduleCacheProvider).shouldShowSpinner(ModuleCacheKeys.spending);
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(vivrantApiProvider);
      final results = await Future.wait([
        api.spendingOverview(),
        api.listExpenses(),
      ]);
      if (!mounted) return;
      final overview = results[0] as Map<String, dynamic>;
      final expenses = results[1] as List<Expense>;
      ref.read(moduleCacheProvider).write(ModuleCacheKeys.spending, {
        'overview': overview,
        'expenses': expenses,
      });
      setState(() {
        _overview = overview;
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

  List<String> get _categories {
    final cats = _expenses.map((e) => e.category).where((c) => c.isNotEmpty).toSet().toList()
      ..sort();
    return cats;
  }

  List<Expense> get _filtered {
    final q = _query.text.trim().toLowerCase();
    return _expenses.where((e) {
      if (_filter != 'all' && e.category != _filter) return false;
      if (q.isEmpty) return true;
      return e.title.toLowerCase().contains(q) ||
          e.category.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final spent = (_overview?['spent'] as num?)?.toDouble() ??
        _expenses.fold<double>(0, (s, e) => s + e.amount);
    final budget = (_overview?['budget'] as num?)?.toDouble();
    final filtered = _filtered;
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Expense history'),
        actions: [
          if (_expenses.isNotEmpty)
            ShareExportButton(doc: expensesDoc(_expenses)),
          ...selectAppBarActions(
            visibleIds: _expenses.map((e) => e.id),
            onArchive: () => confirmAndArchiveSelected(
              request: (ids) => ref.read(vivrantApiProvider).archiveItems(
                    entity: 'expenses',
                    ids: ids,
                  ),
              onRemoved: (ids) {
                setState(() {
                  _expenses =
                      _expenses.where((e) => !ids.contains(e.id)).toList();
                });
                _cache();
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
              title: 'Expense',
              highlight: 'history',
            ),
            StatCard(
              label: 'Spent',
              value: '₱${spent.toStringAsFixed(0)}',
              caption: budget != null
                  ? 'of ₱${budget.toStringAsFixed(0)} budget'
                  : 'this month',
              icon: Icons.account_balance_wallet_outlined,
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
            else if (_expenses.isEmpty)
              EmptyState(
                message: 'No expenses yet.',
                action: ElevatedButton(
                  onPressed: () => context.push('/spending/log'),
                  child: const Text('Log expense'),
                ),
              )
            else ...[
              VivrantSearchField(
                controller: _query,
                hintText: 'Search expenses…',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              VivrantFilterChips<String>(
                options: [
                  VivrantFilterOption(
                    value: 'all',
                    label: 'All',
                    count: _expenses.length,
                  ),
                  ..._categories.map(
                    (c) => VivrantFilterOption(
                      value: c,
                      label: humanizeLabel(c),
                      count: _expenses.where((e) => e.category == c).length,
                    ),
                  ),
                ],
                selected: _filter,
                onSelected: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                const EmptyState(
                  message:
                      'No expenses match these filters. Try All or another search.',
                )
              else
                ...filtered.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: selecting
                        ? ListRow(
                            selected: selectedIds.contains(e.id),
                            leading: selectLeading(selectedIds.contains(e.id)),
                            title: e.title,
                            subtitle:
                                '${e.category} · ₱${e.amount.toStringAsFixed(0)}',
                            onTap: () => toggleSelected(e.id),
                          )
                        : SwipeToRemove(
                            itemKey: ValueKey(e.id),
                            action: 'Archive',
                            confirmDismiss: (_) =>
                                confirmDelete(context, label: e.title),
                            onRemove: () async {
                              try {
                                await ref
                                    .read(vivrantApiProvider)
                                    .deleteExpense(e.id);
                                if (!mounted) return;
                                setState(() {
                                  _expenses = _expenses
                                      .where((x) => x.id != e.id)
                                      .toList();
                                });
                                _cache();
                                context.showSuccess('Expense archived');
                              } catch (err) {
                                if (!mounted) return;
                                context.showError(apiErrorMessage(err));
                              }
                            },
                            child: VivrantPanel(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${e.category} · ₱${e.amount.toStringAsFixed(0)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              final draft = await showFieldEditorSheet(
                                context,
                                title: 'Edit expense',
                                fields: {
                                  'Title': e.title,
                                  'Category': e.category,
                                  'Amount': e.amount.toStringAsFixed(0),
                                  'Date': e.spentAt.toIso8601String().substring(0, 10),
                                },
                              );
                              if (draft == null || !mounted) return;
                              try {
                                final updated = await ref.read(vivrantApiProvider).updateExpense(e.id, {
                                  'title': draft['Title'] ?? e.title,
                                  'category': normalizeExpenseCategory(draft['Category'] ?? e.category),
                                  'amount': double.tryParse(draft['Amount'] ?? '') ?? e.amount,
                                  'spent_at': draft['Date'] ?? e.spentAt.toIso8601String().substring(0, 10),
                                });
                                if (!mounted) return;
                                setState(() {
                                  _expenses = [for (final item in _expenses) item.id == e.id ? updated : item];
                                });
                                _cache();
                                context.showSuccess('Expense updated');
                              } catch (err) {
                                if (!mounted) return;
                                context.showError(apiErrorMessage(err));
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (!(await confirmDelete(context, label: e.title))) return;
                              final prev = List<Expense>.from(_expenses);
                              setState(() {
                                _expenses =
                                    _expenses.where((x) => x.id != e.id).toList();
                              });
                              _cache();
                              try {
                                await ref
                                    .read(vivrantApiProvider)
                                    .deleteExpense(e.id);
                                if (!mounted) return;
                                context.showSuccess('Expense removed');
                              } catch (err) {
                                if (!mounted) return;
                                setState(() => _expenses = prev);
                                _cache();
                                context.showError(apiErrorMessage(err));
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                          ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
