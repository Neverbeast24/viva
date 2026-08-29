import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/humanize.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/providers/module_cache.dart';

class ChallengesScreen extends ConsumerStatefulWidget {
  const ChallengesScreen({super.key});

  @override
  ConsumerState<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends ConsumerState<ChallengesScreen>
    with SelectableIdsMixin {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  List<Habit> _habits = [];
  bool _loading = true;
  bool _syncing = false;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    final cached = ref
        .read(moduleCacheProvider)
        .read<List<Map<String, dynamic>>>(ModuleCacheKeys.challenges);
    if (cached != null) {
      _items = List<Map<String, dynamic>>.from(cached);
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _setItems(List<Map<String, dynamic>> items) {
    ref.read(moduleCacheProvider).write(ModuleCacheKeys.challenges, items);
    setState(() {
      _items = items;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _load() async {
    final showSpinner =
        ref.read(moduleCacheProvider).shouldShowSpinner(ModuleCacheKeys.challenges);
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(vivrantApiProvider);
      final items = await api.listChallenges();
      List<Habit> habits = const [];
      try {
        habits = await api.listHabits();
      } catch (_) {}
      if (!mounted) return;
      _habits = habits;
      _setItems(items);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _syncProgress() async {
    setState(() => _syncing = true);
    try {
      final res = await ref.read(vivrantApiProvider).refreshChallenges();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      final updated = res['updated'];
      context.showSuccess(
        updated == null
            ? 'Challenge progress synced'
            : 'Synced · $updated updated',
      );
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _create() async {
    final title = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New challenge'),
        content: TextField(
          controller: title,
          decoration: const InputDecoration(labelText: 'Title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    final text = title.text.trim();
    title.dispose();
    if (ok == true && text.isNotEmpty && mounted) {
      try {
        final challenge = await ref.read(vivrantApiProvider).createChallenge({
          'title': text,
          'target_value': 7,
          'metric': 'habits',
        });
        if (!mounted) return;
        _setItems([challenge, ..._items]);
        context.showSuccess('Challenge created');
      } catch (e) {
        if (!mounted) return;
        context.showError(apiErrorMessage(e));
      }
    }
  }

  Future<void> _delete(int id, {bool confirm = true}) async {
    if (confirm) {
      final ok = await confirmDelete(context, label: 'this challenge');
      if (!ok || !mounted) return;
    }
    final prev = _items.map((e) => Map<String, dynamic>.from(e)).toList();
    _setItems(
      _items.where((item) => (item['id'] as num?)?.toInt() != id).toList(),
    );
    try {
      await ref.read(vivrantApiProvider).deleteChallenge(id);
      if (!mounted) return;
      context.showSuccess('Challenge removed');
    } catch (e) {
      if (!mounted) return;
      _setItems(prev);
      context.showError(apiErrorMessage(e));
    }
  }

  List<String> get _statuses {
    final values = _items
        .map((c) => c['status']?.toString() ?? 'active')
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.text.trim().toLowerCase();
    return _items.where((c) {
      final status = c['status']?.toString() ?? 'active';
      if (_filter != 'all' && status != _filter) return false;
      if (q.isEmpty) return true;
      return (c['title']?.toString().toLowerCase() ?? '').contains(q) ||
          status.toLowerCase().contains(q);
    }).toList();
  }

  double _progressPct(Map<String, dynamic> c) {
    final current = (c['current_value'] as num?)?.toDouble() ?? 0;
    final target = (c['target_value'] as num?)?.toDouble() ?? 0;
    if (target <= 0) return 0;
    return (current / target).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Challenges'),
        actions: [
          ...selectAppBarActions(
            visibleIds: _items
                .map((c) => (c['id'] as num?)?.toInt())
                .whereType<int>(),
            onArchive: () => confirmAndArchiveSelected(
              request: (ids) => ref.read(vivrantApiProvider).archiveItems(
                    entity: 'challenges',
                    ids: ids,
                  ),
              onRemoved: (ids) {
                setState(() {
                  _items = _items
                      .where(
                        (c) => !ids.contains((c['id'] as num?)?.toInt()),
                      )
                      .toList();
                });
              },
            ),
          ),
          IconButton(
            onPressed: _syncing ? null : _syncProgress,
            tooltip: 'Sync progress',
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
          IconButton(onPressed: _create, icon: const Icon(Icons.add)),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: VivrantLayout.pagePadding,
          children: [
            const PageHeader(
              eyebrow: 'Habits',
              title: 'Active',
              highlight: 'challenges',
            ),
            OutlinedButton.icon(
              onPressed: _syncing ? null : _syncProgress,
              icon: const Icon(Icons.sync),
              label: Text(_syncing ? 'Syncing…' : 'Sync progress'),
            ),
            if (_habits.isNotEmpty) ...[
              const SizedBox(height: 16),
              VivrantPanel(
                title: 'Today’s habits',
                child: Column(
                  children: [
                    for (final habit in _habits)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ListRow(
                          title: habit.title,
                          leading: Checkbox(
                            value: habit.doneToday,
                            onChanged: (v) async {
                              final done = v ?? false;
                              try {
                                await ref
                                    .read(vivrantApiProvider)
                                    .toggleHabit(habit.id, done);
                                if (!mounted) return;
                                setState(() {
                                  _habits = [
                                    for (final h in _habits)
                                      if (h.id == habit.id)
                                        h.copyWith(doneToday: done)
                                      else
                                        h,
                                  ];
                                });
                              } catch (e) {
                                if (!context.mounted) return;
                                context.showError(apiErrorMessage(e));
                              }
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              EmptyState(
                message: _error!,
                action: OutlinedButton(
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              )
            else if (_items.isEmpty)
              EmptyState(
                message: 'No challenges yet.',
                action: ElevatedButton(
                  onPressed: _create,
                  child: const Text('Create challenge'),
                ),
              )
            else ...[
              VivrantSearchField(
                controller: _query,
                hintText: 'Search challenges…',
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
                  ..._statuses.map(
                    (s) => VivrantFilterOption(
                      value: s,
                      label: humanizeLabel(s),
                      count: _items
                          .where(
                            (c) => (c['status']?.toString() ?? 'active') == s,
                          )
                          .length,
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
                      'No challenges match these filters. Try All or another search.',
                )
              else
                ...filtered.map((c) {
                  final id = (c['id'] as num?)?.toInt();
                  final current = (c['current_value'] as num?)?.toDouble() ?? 0;
                  final target = (c['target_value'] as num?)?.toDouble();
                  final pct = _progressPct(c);
                  final done = c['completed'] == true;
                  final title = c['title']?.toString() ?? 'Challenge';
                  final card = Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: VivrantPanel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (selecting && id != null)
                                Checkbox(
                                  value: selectedIds.contains(id),
                                  onChanged: (_) => toggleSelected(id),
                                ),
                              Expanded(
                                child: Text(
                                  '$title${done ? ' · Done' : ''}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (id != null)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _delete(id),
                                ),
                            ],
                          ),
                          Text(
                            [
                              if (c['metric'] != null) c['metric'].toString(),
                              if (c['duration_days'] != null)
                                '${c['duration_days']} days',
                              c['status']?.toString() ?? 'active',
                            ].join(' · '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (target != null && target > 0) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: pct,
                                minHeight: 8,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${current.toStringAsFixed(0)} / ${target.toStringAsFixed(0)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                  if (id == null) return card;
                  return wrapArchiveable(
                    id: id,
                    label: title,
                    archive: () => _delete(id, confirm: false),
                    child: card,
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }
}
