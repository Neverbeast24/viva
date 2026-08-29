import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/list_order.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/providers/module_cache.dart';

class RemindersScreen extends ConsumerStatefulWidget {
  const RemindersScreen({super.key});

  @override
  ConsumerState<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends ConsumerState<RemindersScreen>
    with SelectableIdsMixin {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    final cached = ref
        .read(moduleCacheProvider)
        .read<List<Map<String, dynamic>>>(ModuleCacheKeys.reminders);
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
    ref.read(moduleCacheProvider).write(ModuleCacheKeys.reminders, items);
    setState(() {
      _items = items;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _load() async {
    final showSpinner = ref.read(moduleCacheProvider).shouldShowSpinner(ModuleCacheKeys.reminders);
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(vivrantApiProvider);
      final items = await api.listReminders();
      List<int> order = const [];
      try {
        order = parseModuleListOrder(await api.getPreferences(), 'reminders');
      } catch (_) {}
      if (!mounted) return;
      _setItems(applyIdOrder(items, order, (r) => (r['id'] as num).toInt()));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final title = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New reminder'),
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
        final reminder = await ref.read(vivrantApiProvider).createReminder({
          'title': text,
          'body': text,
          'schedule_time': '09:00',
          'days_of_week': const [1, 2, 3, 4, 5, 6, 7],
          'enabled': true,
        });
        if (!mounted) return;
        _setItems([reminder, ..._items]);
        context.showSuccess('Reminder created');
      } catch (e) {
        if (!mounted) return;
        context.showError(apiErrorMessage(e));
      }
    }
  }

  Future<void> _draftAi() async {
    try {
      final res = await ref.read(vivrantApiProvider).draftReminderAi();
      if (!mounted) return;
      final reminder = res['reminder'];
      if (reminder is Map) {
        _setItems([
          Map<String, dynamic>.from(reminder),
          ..._items,
        ]);
      } else {
        await _load();
      }
      if (!mounted) return;
      context.showSuccess('AI reminder drafted');
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _syncTodayLeftovers() async {
    try {
      final res =
          await ref.read(vivrantApiProvider).syncRemindersFromTodayLeftovers();
      if (!mounted) return;
      final reminder = res['reminder'];
      if (reminder is Map) {
        final next = Map<String, dynamic>.from(reminder);
        final id = (next['id'] as num?)?.toInt();
        _setItems([
          next,
          ..._items.where((r) => (r['id'] as num?)?.toInt() != id),
        ]);
      } else {
        await _load();
      }
      if (!mounted) return;
      context.showSuccess(
        res['message']?.toString() ?? 'Evening catch-up scheduled',
      );
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _syncGymPlan() async {
    try {
      final res = await ref.read(vivrantApiProvider).syncRemindersFromGymPlan();
      if (!mounted) return;
      final reminder = res['reminder'];
      if (reminder is Map) {
        final next = Map<String, dynamic>.from(reminder);
        final id = (next['id'] as num?)?.toInt();
        _setItems([
          next,
          ..._items.where((r) => (r['id'] as num?)?.toInt() != id),
        ]);
      } else {
        await _load();
      }
      if (!mounted) return;
      context.showSuccess('Gym plan synced to reminders');
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.text.trim().toLowerCase();
    return _items.where((r) {
      final enabled = r['enabled'] as bool? ?? true;
      if (_filter == 'on' && !enabled) return false;
      if (_filter == 'off' && enabled) return false;
      if (q.isEmpty) return true;
      return (r['title']?.toString().toLowerCase() ?? '').contains(q);
    }).toList();
  }

  bool get _canReorder => _filter == 'all' && _query.text.trim().isEmpty;

  void _reorder(int from, int to) {
    final next = moveItem(_items, from, to);
    _setItems(next);
    unawaited(
      ref.read(vivrantApiProvider).saveListOrder(
        'reminders',
        next.map((r) => (r['id'] as num).toInt()).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final onCount = _items.where((r) => r['enabled'] as bool? ?? true).length;
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Reminders'),
        actions: [
          ...selectAppBarActions(
            visibleIds: _items
                .map((r) => (r['id'] as num?)?.toInt())
                .whereType<int>(),
            onArchive: () => confirmAndArchiveSelected(
              request: (ids) => ref.read(vivrantApiProvider).archiveItems(
                    entity: 'user_reminders',
                    ids: ids,
                  ),
              onRemoved: (ids) {
                setState(() {
                  _items = _items
                      .where(
                        (r) => !ids.contains((r['id'] as num?)?.toInt()),
                      )
                      .toList();
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
              eyebrow: 'Ask for help',
              title: 'Smart',
              highlight: 'reminders',
            ),
            OutlinedButton.icon(
              onPressed: _draftAi,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Draft reminder with AI'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _syncGymPlan,
              icon: const Icon(Icons.fitness_center),
              label: const Text('Sync gym plan'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _syncTodayLeftovers,
              icon: const Icon(Icons.wb_twilight_outlined),
              label: const Text('Nudge leftovers'),
            ),
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
                message: 'No reminders yet.',
                action: ElevatedButton(
                  onPressed: _add,
                  child: const Text('Add reminder'),
                ),
              )
            else ...[
              VivrantSearchField(
                controller: _query,
                hintText: 'Search reminders…',
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
                    value: 'on',
                    label: 'Enabled',
                    count: onCount,
                  ),
                  VivrantFilterOption(
                    value: 'off',
                    label: 'Disabled',
                    count: _items.length - onCount,
                  ),
                ],
                selected: _filter,
                onSelected: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                const EmptyState(
                  message:
                      'No reminders match these filters. Try All or another search.',
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
                  keyOf: (i) => (filtered[i]['id'] as num).toInt(),
                  onReorder: _reorder,
                  itemBuilder: (context, index) {
                  final r = filtered[index];
                  final enabled = r['enabled'] as bool? ?? true;
                  final id = (r['id'] as num).toInt();
                  final title = r['title']?.toString() ?? 'Reminder';
                  return wrapArchiveable(
                    id: id,
                    label: title,
                    archive: () async {
                      final prev =
                          _items.map((e) => Map<String, dynamic>.from(e)).toList();
                      _setItems(
                        _items
                            .where((item) => (item['id'] as num).toInt() != id)
                            .toList(),
                      );
                      try {
                        await ref.read(vivrantApiProvider).deleteReminder(id);
                        if (!mounted) return;
                        context.showSuccess('Reminder removed');
                      } catch (e) {
                        if (!mounted) return;
                        _setItems(prev);
                        context.showError(apiErrorMessage(e));
                      }
                    },
                    child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: VivrantPanel(
                      child: Row(
                        children: [
                          if (selecting)
                            Checkbox(
                              value: selectedIds.contains(id),
                              onChanged: (_) => toggleSelected(id),
                            ),
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Switch(
                            value: enabled,
                            onChanged: (v) async {
                              final prev =
                                  _items.map((e) => Map<String, dynamic>.from(e)).toList();
                              _setItems([
                                for (final item in _items)
                                  if ((item['id'] as num).toInt() == id)
                                    {...item, 'enabled': v}
                                  else
                                    item,
                              ]);
                              try {
                                await ref
                                    .read(vivrantApiProvider)
                                    .toggleReminder(id, v);
                                if (!mounted) return;
                                context.showSuccess(
                                  v ? 'Reminder enabled' : 'Reminder disabled',
                                );
                              } catch (e) {
                                if (!mounted) return;
                                _setItems(prev);
                                context.showError(apiErrorMessage(e));
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              final draft = await showFieldEditorSheet(
                                context,
                                title: 'Edit reminder',
                                fields: {
                                  'Title': r['title']?.toString() ?? '',
                                  'Message': r['body']?.toString() ?? '',
                                  'Time': () {
                                    final time = r['schedule_time']?.toString() ?? '09:00';
                                    return time.length >= 5 ? time.substring(0, 5) : (time.isEmpty ? '09:00' : time);
                                  }(),
                                },
                              );
                              if (draft == null || !mounted) return;
                              try {
                                await ref.read(vivrantApiProvider).updateReminder(id, {
                                  'title': draft['Title'],
                                  'body': draft['Message'],
                                  'schedule_time': draft['Time'],
                                });
                                if (!mounted) return;
                                _setItems([
                                  for (final item in _items)
                                    if ((item['id'] as num).toInt() == id)
                                      {
                                        ...item,
                                        'title': draft['Title'],
                                        'body': draft['Message'],
                                        'schedule_time': draft['Time'],
                                      }
                                    else
                                      item,
                                ]);
                                context.showSuccess('Reminder updated');
                              } catch (e) {
                                if (!mounted) return;
                                context.showError(apiErrorMessage(e));
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (!(await confirmDelete(context, label: title))) return;
                              final prev =
                                  _items.map((e) => Map<String, dynamic>.from(e)).toList();
                              _setItems(
                                _items
                                    .where((item) => (item['id'] as num).toInt() != id)
                                    .toList(),
                              );
                              try {
                                await ref
                                    .read(vivrantApiProvider)
                                    .deleteReminder(id);
                                if (!mounted) return;
                                context.showSuccess('Reminder removed');
                              } catch (e) {
                                if (!mounted) return;
                                _setItems(prev);
                                context.showError(apiErrorMessage(e));
                              }
                            },
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
