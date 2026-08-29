import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/vivrant_colors.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/list_order.dart';
import '../../../../core/utils/share_export.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/providers/module_cache.dart';

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen>
    with SingleTickerProviderStateMixin, SelectableIdsMixin {
  List<HealthGoal> _goals = [];
  Map<String, dynamic> _today = const {};
  bool _loading = true;
  String? _error;
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..forward();
    final cached =
        ref.read(moduleCacheProvider).read<List<HealthGoal>>(ModuleCacheKeys.goals);
    if (cached != null) {
      _goals = List<HealthGoal>.from(cached);
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  void _setGoals(List<HealthGoal> goals) {
    ref.read(moduleCacheProvider).write(ModuleCacheKeys.goals, goals);
    setState(() {
      _goals = goals;
      _loading = false;
      _error = null;
    });
  }

  void _reorder(int from, int to) {
    final next = moveItem(_goals, from, to);
    _setGoals(next);
    unawaited(
      ref.read(vivrantApiProvider).saveListOrder(
        'goals',
        next.map((g) => g.id).toList(),
      ),
    );
  }

  Future<void> _load() async {
    final showSpinner = ref.read(moduleCacheProvider).shouldShowSpinner(ModuleCacheKeys.goals);
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(vivrantApiProvider);
      final results = await Future.wait([
        api.listGoals(),
        api.getToday(),
      ]);
      List<int> order = const [];
      try {
        order = parseModuleListOrder(await api.getPreferences(), 'goals');
      } catch (_) {}
      if (!mounted) return;
      _today = results[1] as Map<String, dynamic>;
      _setGoals(applyIdOrder(results[0] as List<HealthGoal>, order, (g) => g.id));
      _enter.forward(from: 0);
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
        title: const Text('New goal'),
        content: TextField(
          controller: title,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Title',
            hintText: 'e.g. Walk 8k steps',
          ),
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
    final text = title.text.trim();
    title.dispose();
    if (ok == true && text.isNotEmpty && mounted) {
      try {
        final goal = await ref.read(vivrantApiProvider).addGoal({
          'title': text,
          'category': 'other',
        });
        if (!mounted) return;
        HapticFeedback.lightImpact();
        _setGoals([goal, ..._goals]);
        context.showSuccess('Goal added');
      } catch (e) {
        if (!mounted) return;
        context.showError(apiErrorMessage(e));
      }
    }
  }

  Future<void> _suggestAi() async {
    try {
      final suggestions = await ref.read(vivrantApiProvider).suggestGoalsAi();
      if (!mounted) return;
      if (suggestions.isEmpty) {
        context.showInfo('No goal ideas right now. Try again after logging more.');
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
                  'AI goal ideas',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('Tailored to your BMI, pace, and recent logs'),
              ),
              ...suggestions.map((g) {
                final title = g['title']?.toString() ?? 'Goal';
                final why = g['why']?.toString();
                final category = g['category']?.toString() ?? 'other';
                final unit = g['unit']?.toString();
                final target = g['target_value'];
                final subtitle = [
                  category,
                  if (target != null) '$target${unit != null ? ' $unit' : ''}',
                  if (why != null && why.isNotEmpty) why,
                ].join(' · ');
                return ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: Text(title),
                  subtitle: Text(subtitle),
                  onTap: () => Navigator.pop(sheetCtx, g),
                );
              }),
            ],
          ),
        ),
      );
      if (chosen == null || !mounted) return;
      final goal = await ref.read(vivrantApiProvider).acceptSuggestedGoal({
        'title': chosen['title'],
        'category': chosen['category'] ?? 'other',
        'target_value': chosen['target_value'],
        'unit': chosen['unit'],
      });
      if (!mounted) return;
      HapticFeedback.lightImpact();
      _setGoals([goal, ..._goals]);
      context.showSuccess('Goal added from AI');
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _refreshProgress() async {
    try {
      final res = await ref.read(vivrantApiProvider).refreshGoalProgress();
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      final updated = res['updated'];
      context.showSuccess(
        updated == null
            ? 'Goal progress synced'
            : 'Synced · $updated goals updated',
      );
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Color _statusColor(String status, bool dark) {
    switch (status) {
      case 'completed':
        return dark ? VivrantColors.darkCyan : VivrantColors.cyan;
      case 'active':
        return dark ? VivrantColors.darkAccent : VivrantColors.accent;
      default:
        return dark ? VivrantColors.darkMuted : VivrantColors.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = dark ? VivrantColors.darkMuted : VivrantColors.muted;
    final panel = dark ? VivrantColors.darkPanel : Colors.white;
    final ink = dark ? VivrantColors.darkInk : VivrantColors.ink;
    final accent = dark ? VivrantColors.darkAccent : VivrantColors.accent;

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Goals'),
        actions: [
          if (_goals.isNotEmpty) ShareExportButton(doc: goalsDoc(_goals)),
          ...selectAppBarActions(
            visibleIds: _goals.map((g) => g.id),
            onArchive: () => confirmAndArchiveSelected(
              request: (ids) => ref.read(vivrantApiProvider).archiveItems(
                    entity: 'health_goals',
                    ids: ids,
                  ),
              onRemoved: (ids) {
                setState(() {
                  _goals = _goals.where((g) => !ids.contains(g.id)).toList();
                });
              },
            ),
          ),
          IconButton(
            onPressed: _add,
            tooltip: 'Add goal',
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: VivrantLayout.pagePadding,
          children: [
            FadeTransition(
              opacity: CurvedAnimation(
                parent: _enter,
                curve: const Interval(0, 0.5, curve: Curves.easeOutCubic),
              ),
              child: const PageHeader(
                eyebrow: 'Goals',
                title: 'Health',
                highlight: 'targets',
              ),
            ),
            if (_today.isNotEmpty) ...[
              const SizedBox(height: 12),
              Builder(builder: (context) {
                final checkin = _today['checkin'] is Map
                    ? Map<String, dynamic>.from(_today['checkin'] as Map)
                    : const <String, dynamic>{};
                final waterMl = (_today['water_ml'] as num?)?.toInt() ??
                    (checkin['water_ml'] as num?)?.toInt() ??
                    0;
                final calories = (_today['calories'] as num?)?.toInt() ?? 0;
                final workouts = (_today['workouts_today'] as num?)?.toInt() ?? 0;
                final sleepMin = (checkin['sleep_minutes'] as num?)?.toInt();
                final items = [
                  ('Water', '${(waterMl / 1000).toStringAsFixed(1)}L'),
                  ('Calories', '$calories'),
                  ('Workouts', '$workouts'),
                  (
                    'Sleep',
                    sleepMin == null
                        ? '—'
                        : '${(sleepMin / 60).toStringAsFixed(1)}h'
                  ),
                ];
                return Row(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: panel,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              Text(
                                items[i].$1.toUpperCase(),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: muted,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                items[i].$2,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (i < items.length - 1) const SizedBox(width: 8),
                    ],
                  ],
                );
              }),
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _suggestAi,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Suggest goals with AI'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _refreshProgress,
              icon: const Icon(Icons.sync),
              label: const Text('Sync from logs'),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 48),
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
            else if (_goals.isEmpty)
              EmptyState(
                message: 'No goals yet. Set one to stay on track.',
                action: PrimaryButton(
                  label: 'Add goal',
                  onPressed: _add,
                  icon: Icons.flag_outlined,
                ),
              )
            else ...[
              if (!selecting)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Long-press, then drag to reorder.',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              NestedReorderableColumn(
                enabled: !selecting,
                itemCount: _goals.length,
                keyOf: (i) => _goals[i].id,
                onReorder: _reorder,
                itemBuilder: (context, i) {
                final g = _goals[i];
                final start = (0.15 + i * 0.08).clamp(0.0, 0.7);
                final end = (start + 0.35).clamp(0.0, 1.0);
                final statusColor = _statusColor(g.status, dark);

                return FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _enter,
                    curve: Interval(start, end, curve: Curves.easeOutCubic),
                  ),
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.06),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: _enter,
                        curve: Interval(start, end, curve: Curves.easeOutCubic),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: wrapArchiveable(
                        id: g.id,
                        label: g.title,
                        archive: () async {
                          final prev = List<HealthGoal>.from(_goals);
                          _setGoals(_goals.where((x) => x.id != g.id).toList());
                          try {
                            await ref.read(vivrantApiProvider).deleteGoal(g.id);
                            if (!mounted) return;
                            HapticFeedback.selectionClick();
                            context.showSuccess('Goal deleted');
                          } catch (e) {
                            if (!mounted) return;
                            _setGoals(prev);
                            context.showError(apiErrorMessage(e));
                          }
                        },
                        child: Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                        decoration: BoxDecoration(
                          color: panel.withValues(alpha: dark ? 0.92 : 0.96),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: ink.withValues(alpha: 0.06)),
                          boxShadow: [
                            BoxShadow(
                              color: accent
                                  .withValues(alpha: dark ? 0.07 : 0.04),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            if (selecting)
                              Checkbox(
                                value: selectedIds.contains(g.id),
                                onChanged: (_) => toggleSelected(g.id),
                              ),
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(
                                g.status == 'completed'
                                    ? Icons.check_circle_outline_rounded
                                    : Icons.flag_outlined,
                                color: statusColor,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    g.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              statusColor.withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          g.status,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: statusColor,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          [
                                            g.category,
                                            if (g.targetValue != null)
                                              '${g.currentValue?.toStringAsFixed(0) ?? '0'} / ${g.targetValue!.toStringAsFixed(0)}${g.unit != null ? ' ${g.unit}' : ''}',
                                          ].join(' · '),
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            color: muted,
                                            fontSize: 12.5,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: Icon(
                                Icons.more_horiz_rounded,
                                color: muted,
                              ),
                              onSelected: (v) async {
                                final prev = List<HealthGoal>.from(_goals);
                                try {
                                  if (v == 'edit') {
                                    final draft = await showFieldEditorSheet(
                                      context,
                                      title: 'Edit goal',
                                      fields: {
                                        'Title': g.title,
                                        'Category': g.category,
                                        'Target': '${g.targetValue ?? ''}',
                                        'Unit': g.unit ?? '',
                                        'Date': g.targetDate ?? '',
                                      },
                                    );
                                    if (draft == null || !mounted) return;
                                    final updated = await ref.read(vivrantApiProvider).updateGoal(g.id, {
                                      'title': draft['Title'] ?? g.title,
                                      'category': draft['Category'] ?? g.category,
                                      if ((draft['Target'] ?? '').isNotEmpty)
                                        'target_value': double.tryParse(draft['Target']!),
                                      'unit': draft['Unit'],
                                      if ((draft['Date'] ?? '').isNotEmpty) 'target_date': draft['Date'],
                                    });
                                    if (!mounted) return;
                                    _setGoals([
                                      for (final item in _goals) item.id == g.id ? updated : item,
                                    ]);
                                    context.showSuccess('Goal updated');
                                    return;
                                  }
                                  if (v == 'delete') {
                                    if (!(await confirmDelete(context, label: g.title))) return;
                                    if (!mounted) return;
                                    _setGoals(
                                      _goals.where((x) => x.id != g.id).toList(),
                                    );
                                    await ref
                                        .read(vivrantApiProvider)
                                        .deleteGoal(g.id);
                                    if (!mounted) return;
                                    HapticFeedback.selectionClick();
                                    context.showSuccess('Goal deleted');
                                  } else {
                                    _setGoals([
                                      for (final item in _goals)
                                        if (item.id == g.id)
                                          item.copyWith(status: v)
                                        else
                                          item,
                                    ]);
                                    await ref
                                        .read(vivrantApiProvider)
                                        .updateGoalStatus(g.id, v);
                                    if (!mounted) return;
                                    HapticFeedback.selectionClick();
                                    context.showSuccess(
                                      v == 'completed'
                                          ? 'Goal completed'
                                          : 'Goal marked active',
                                    );
                                  }
                                } catch (e) {
                                  if (!mounted) return;
                                  _setGoals(prev);
                                  context.showError(apiErrorMessage(e));
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Edit'),
                                ),
                                PopupMenuItem(
                                  value: 'active',
                                  child: Text('Mark active'),
                                ),
                                PopupMenuItem(
                                  value: 'completed',
                                  child: Text('Mark completed'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      ),
                    ),
                  ),
                );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
