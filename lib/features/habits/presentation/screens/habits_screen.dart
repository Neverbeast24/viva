import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/list_order.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/providers/module_cache.dart';

class HabitsScreen extends ConsumerStatefulWidget {
  const HabitsScreen({super.key});

  @override
  ConsumerState<HabitsScreen> createState() => _HabitsScreenState();
}

class _HabitsScreenState extends ConsumerState<HabitsScreen>
    with SelectableIdsMixin {
  final _query = TextEditingController();
  List<Habit> _habits = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    final cached = ref
        .read(moduleCacheProvider)
        .read<List<Habit>>(ModuleCacheKeys.habits);
    if (cached != null) {
      _habits = List<Habit>.from(cached);
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _setHabits(List<Habit> habits) {
    ref.read(moduleCacheProvider).write(ModuleCacheKeys.habits, habits);
    setState(() {
      _habits = habits;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _load() async {
    final showSpinner = ref
        .read(moduleCacheProvider)
        .shouldShowSpinner(ModuleCacheKeys.habits);
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(vivrantApiProvider);
      final habits = await api.listHabits();
      List<int> order = const [];
      try {
        order = parseModuleListOrder(await api.getPreferences(), 'habits');
      } catch (_) {}
      if (!mounted) return;
      _setHabits(applyIdOrder(habits, order, (h) => h.id));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    var title = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New habit'),
        content: TextField(
          decoration: const InputDecoration(hintText: 'Habit title'),
          autofocus: true,
          textInputAction: TextInputAction.done,
          onChanged: (value) => title = value,
          onSubmitted: (_) => Navigator.pop(c, true),
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
    title = title.trim();
    if (ok == true && title.isNotEmpty && mounted) {
      try {
        final habit = await ref.read(vivrantApiProvider).addHabit(title);
        if (!mounted) return;
        _setHabits([..._habits, habit]);
        context.showSuccess('Habit added');
      } catch (e) {
        if (!mounted) return;
        context.showError(apiErrorMessage(e));
      }
    }
  }

  Future<void> _toggle(Habit h, bool done) async {
    final prev = List<Habit>.from(_habits);
    _setHabits([
      for (final item in _habits)
        if (item.id == h.id) item.copyWith(doneToday: done) else item,
    ]);
    try {
      await ref.read(vivrantApiProvider).toggleHabit(h.id, done);
      if (!mounted) return;
      context.showSuccess(done ? 'Habit checked' : 'Habit unchecked');
    } catch (e) {
      if (!mounted) return;
      _setHabits(prev);
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _delete(Habit h, {bool confirm = true}) async {
    if (confirm) {
      final ok = await confirmDelete(context, label: h.title);
      if (!ok || !mounted) return;
    }
    final prev = List<Habit>.from(_habits);
    _setHabits(_habits.where((item) => item.id != h.id).toList());
    try {
      await ref.read(vivrantApiProvider).deleteHabit(h.id);
      if (!mounted) return;
      context.showSuccess('Habit removed');
    } catch (e) {
      if (!mounted) return;
      _setHabits(prev);
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _suggestAi() async {
    try {
      final habits = await ref.read(vivrantApiProvider).suggestHabitsAi();
      if (!mounted) return;
      if (habits.isEmpty) {
        context.showInfo('No habit ideas right now. Try again after logging more.');
        return;
      }
      final chosen = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        showDragHandle: true,
        builder: (sheetCtx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'AI habit ideas',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('Personalized from your BMI and recent logs'),
              ),
              ...habits.map((h) {
                final title = h['title']?.toString() ?? 'Habit';
                final reason = h['reason']?.toString();
                return ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: Text(title),
                  subtitle: reason == null || reason.isEmpty ? null : Text(reason),
                  onTap: () => Navigator.pop(sheetCtx, h),
                );
              }),
            ],
          ),
        ),
      );
      if (chosen == null || !mounted) return;
      final title = chosen['title']?.toString().trim() ?? '';
      if (title.isEmpty) return;
      final habit = await ref.read(vivrantApiProvider).addHabit(title);
      if (!mounted) return;
      _setHabits([..._habits, habit]);
      context.showSuccess('Habit added');
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  List<Habit> get _filtered {
    final q = _query.text.trim().toLowerCase();
    return _habits.where((h) {
      if (_filter == 'done' && !h.doneToday) return false;
      if (_filter == 'todo' && h.doneToday) return false;
      if (q.isEmpty) return true;
      return h.title.toLowerCase().contains(q);
    }).toList();
  }

  bool get _canReorder => _filter == 'all' && _query.text.trim().isEmpty;

  void _reorder(int from, int to) {
    final next = moveItem(_habits, from, to);
    _setHabits(next);
    unawaited(
      ref.read(vivrantApiProvider).saveListOrder(
        'habits',
        next.map((h) => h.id).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final done = _habits.where((h) => h.doneToday).length;
    final filtered = _filtered;
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Habits'),
        actions: [
          ...selectAppBarActions(
            visibleIds: _habits.map((h) => h.id),
            onArchive: () => confirmAndArchiveSelected(
              request: (ids) => ref.read(vivrantApiProvider).archiveItems(
                    entity: 'habits',
                    ids: ids,
                  ),
              onRemoved: (ids) {
                setState(() {
                  _habits = _habits.where((h) => !ids.contains(h.id)).toList();
                });
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
              eyebrow: 'Consistency',
              title: 'Daily',
              highlight: 'habits',
            ),
            StatCard(
              label: 'Today',
              value: '$done / ${_habits.length}',
              caption: 'completed',
              icon: Icons.local_fire_department_outlined,
            ),
            const SectionGap(),
            ModuleTile(
              icon: Icons.emoji_events_outlined,
              label: 'Challenges',
              caption: 'Weekly streaks and extras',
              onTap: () => context.push('/habits/challenges'),
            ),
            const TileGap(),
            ModuleTile(
              icon: Icons.auto_awesome,
              label: 'AI habit ideas',
              caption: 'Suggestions from recent logs',
              onTap: _suggestAi,
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
            else if (_habits.isEmpty)
              EmptyState(
                message: 'No habits yet. Add your first.',
                action: ElevatedButton(
                  onPressed: _add,
                  child: const Text('Add habit'),
                ),
              )
            else ...[
              VivrantSearchField(
                controller: _query,
                hintText: 'Search habits…',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              VivrantFilterChips<String>(
                options: [
                  VivrantFilterOption(
                    value: 'all',
                    label: 'All',
                    count: _habits.length,
                  ),
                  VivrantFilterOption(
                    value: 'done',
                    label: 'Done',
                    count: done,
                  ),
                  VivrantFilterOption(
                    value: 'todo',
                    label: 'To do',
                    count: _habits.length - done,
                  ),
                ],
                selected: _filter,
                onSelected: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                const EmptyState(
                  message:
                      'No habits match these filters. Try All or another search.',
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
                    final h = filtered[index];
                    return wrapArchiveable(
                      id: h.id,
                      label: h.title,
                      archive: () => _delete(h, confirm: false),
                      child: Padding(
                      padding: const EdgeInsets.only(bottom: VivrantLayout.itemGap),
                      child: VivrantPanel(
                        child: Row(
                          children: [
                            Checkbox(
                              value: selecting
                                  ? selectedIds.contains(h.id)
                                  : h.doneToday,
                              onChanged: selecting
                                  ? (_) => toggleSelected(h.id)
                                  : (v) => _toggle(h, v ?? false),
                            ),
                            Expanded(
                              child: Text(
                                h.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  decoration: h.doneToday
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Edit habit',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () async {
                                final draft = await showFieldEditorSheet(
                                  context,
                                  title: 'Edit habit',
                                  fields: {'Title': h.title},
                                );
                                if (draft == null || !mounted) return;
                                try {
                                  final updated = await ref.read(vivrantApiProvider).updateHabit(h.id, {
                                    'title': draft['Title'] ?? h.title,
                                  });
                                  if (!mounted) return;
                                  setState(() {
                                    _habits = [
                                      for (final item in _habits)
                                        item.id == h.id ? updated.copyWith(doneToday: h.doneToday) : item,
                                    ];
                                  });
                                  ref.read(moduleCacheProvider).write(ModuleCacheKeys.habits, _habits);
                                  context.showSuccess('Habit updated');
                                } catch (e) {
                                  if (!mounted) return;
                                  context.showError(apiErrorMessage(e));
                                }
                              },
                            ),
                            IconButton(
                              tooltip: 'Delete habit',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(h),
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
