import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/utils/ai_text.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/share_export.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/providers/module_cache.dart';
import '../../../../shared/providers/shell_tab_provider.dart';

class MovementScreen extends ConsumerStatefulWidget {
  const MovementScreen({super.key});

  @override
  ConsumerState<MovementScreen> createState() => _MovementScreenState();
}

class _MovementScreenState extends ConsumerState<MovementScreen>
    with SelectableIdsMixin {
  static const _tabIndex = 2;

  final _query = TextEditingController();
  List<WorkoutLog> _items = [];
  bool _loading = false;
  bool _activated = false;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    final cached = ref
        .read(moduleCacheProvider)
        .read<List<WorkoutLog>>(ModuleCacheKeys.movement);
    if (cached != null) {
      _items = List<WorkoutLog>.from(cached);
      _loading = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Load when this is the Training tab, or when pushed as /move/activity.
      if (ref.read(shellTabIndexProvider) == _tabIndex ||
          GoRouter.of(context).canPop()) {
        _activated = true;
        _load();
      } else {
        _maybeActivate();
      }
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _maybeActivate() {
    if (!mounted || _activated) return;
    if (ref.read(shellTabIndexProvider) != _tabIndex) return;
    _activated = true;
    _load();
  }

  Future<void> _load() async {
    final showSpinner = ref.read(moduleCacheProvider).shouldShowSpinner(ModuleCacheKeys.movement);
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(vivrantApiProvider);
      final items = await api.listWorkouts();
      if (!mounted) return;
      ref.read(moduleCacheProvider).write(ModuleCacheKeys.movement, items);
      setState(() {
        _items = items;
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

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(shellTabIndexProvider, (_, next) {
      if (next == _tabIndex) _maybeActivate();
    });
    final minutes = _items.fold<int>(0, (s, w) => s + (w.durationMinutes ?? 0));
    final types = _items
        .map((w) => w.activityType)
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final filtered = _items.where((w) {
      if (_filter != 'all' && w.activityType != _filter) return false;
      final q = _query.text.trim().toLowerCase();
      if (q.isEmpty) return true;
      return w.title.toLowerCase().contains(q) ||
          w.activityType.toLowerCase().contains(q);
    }).toList();

    String titleCase(String value) {
      if (value.isEmpty) return value;
      return value
          .split(RegExp(r'[_\s]+'))
          .map((w) =>
              w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: VivrantLayout.pagePadding,
          children: [
            PageHeader(
              eyebrow: 'Training',
              title: 'Daily',
              highlight: 'activity',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (GoRouter.of(context).canPop())
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  if (_items.isNotEmpty)
                    ShareExportButton(doc: movementWorkoutsDoc(_items)),
                  ...selectAppBarActions(
                    visibleIds: _items.map((w) => w.id),
                    onArchive: () => confirmAndArchiveSelected(
                      request: (ids) => ref.read(vivrantApiProvider).archiveItems(
                            entity: 'workout_logs',
                            ids: ids,
                          ),
                      onRemoved: (ids) {
                        setState(() {
                          _items = _items.where((w) => !ids.contains(w.id)).toList();
                        });
                        ref
                            .read(moduleCacheProvider)
                            .write(ModuleCacheKeys.movement, _items);
                      },
                    ),
                  ),
                  IconButton(
                    onPressed: () => context.push('/move/log'),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
            StatCard(
              label: 'Today',
              value: '$minutes min',
              caption: '${_items.length} sessions',
              icon: Icons.directions_run,
            ),
            const SizedBox(height: 16),
            if (!_activated || _loading)
              const Center(child: CircularProgressIndicator())
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
                message: 'No workouts yet.',
                action: ElevatedButton(
                  onPressed: () => context.push('/move/log'),
                  child: const Text('Log workout'),
                ),
              )
            else ...[
              VivrantSearchField(
                controller: _query,
                hintText: 'Search workouts…',
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
                  ...types.map(
                    (t) => VivrantFilterOption(
                      value: t,
                      label: titleCase(t),
                      count: _items.where((w) => w.activityType == t).length,
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
                      'No workouts match these filters. Try All or another search.',
                )
              else
                ...filtered.map(
                  (w) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: selecting
                        ? ListRow(
                            selected: selectedIds.contains(w.id),
                            leading: selectLeading(selectedIds.contains(w.id)),
                            title: w.title,
                            subtitle:
                                '${w.activityType} · ${w.durationMinutes ?? '—'} min',
                            onTap: () => toggleSelected(w.id),
                          )
                        : SwipeToRemove(
                            itemKey: ValueKey(w.id),
                            action: 'Archive',
                            confirmDismiss: (_) =>
                                confirmDelete(context, label: w.title),
                            onRemove: () async {
                              try {
                                await ref
                                    .read(vivrantApiProvider)
                                    .deleteWorkout(w.id);
                                if (!mounted) return;
                                setState(() {
                                  _items = _items
                                      .where((x) => x.id != w.id)
                                      .toList();
                                });
                                ref
                                    .read(moduleCacheProvider)
                                    .write(ModuleCacheKeys.movement, _items);
                                context.showSuccess('Workout removed');
                              } catch (e) {
                                if (!mounted) return;
                                context.showError(apiErrorMessage(e));
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
                                  w.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${w.activityType} · ${w.durationMinutes ?? '—'} min',
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
                                title: 'Edit workout',
                                fields: {
                                  'Title': w.title,
                                  'Type': w.activityType,
                                  'Minutes': '${w.durationMinutes ?? ''}',
                                  'Calories': '${w.caloriesBurned?.toStringAsFixed(0) ?? ''}',
                                },
                              );
                              if (draft == null || !mounted) return;
                              try {
                                const types = {'walk', 'run', 'strength', 'cycle', 'yoga', 'other'};
                                final type = (draft['Type'] ?? w.activityType).toLowerCase();
                                final updated = await ref.read(vivrantApiProvider).updateWorkout(w.id, {
                                  'title': draft['Title'] ?? w.title,
                                  'activity_type': types.contains(type) ? type : w.activityType,
                                  'duration_minutes': int.tryParse(draft['Minutes'] ?? '') ?? w.durationMinutes ?? 1,
                                  if ((draft['Calories'] ?? '').isNotEmpty)
                                    'calories_burned': int.tryParse(draft['Calories']!),
                                });
                                if (!mounted) return;
                                setState(() {
                                  _items = [for (final item in _items) item.id == w.id ? updated : item];
                                });
                                ref.read(moduleCacheProvider).write(ModuleCacheKeys.movement, _items);
                                context.showSuccess('Workout updated');
                              } catch (e) {
                                if (!mounted) return;
                                context.showError(apiErrorMessage(e));
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (!(await confirmDelete(context, label: w.title))) return;
                              try {
                                await ref
                                    .read(vivrantApiProvider)
                                    .deleteWorkout(w.id);
                                if (!mounted) return;
                                setState(() {
                                  _items = _items
                                      .where((x) => x.id != w.id)
                                      .toList();
                                });
                                ref
                                    .read(moduleCacheProvider)
                                    .write(ModuleCacheKeys.movement, _items);
                                context.showSuccess('Workout removed');
                              } catch (e) {
                                if (!mounted) return;
                                context.showError(apiErrorMessage(e));
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
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  final res =
                      await ref.read(vivrantApiProvider).suggestWorkoutAi();
                  if (!mounted) return;
                  context.showInfo(
                    formatAiResponse(
                      res,
                      keys: const ['suggestion', 'advice', 'tip'],
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  context.showError(apiErrorMessage(e));
                }
              },
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Suggest workout with AI'),
            ),
          ],
        ),
      ),
    );
  }
}
