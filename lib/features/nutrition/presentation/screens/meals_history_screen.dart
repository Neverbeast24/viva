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
import '../widgets/macro_chips.dart';
import '../widgets/meal_list_tile.dart';

class MealsHistoryScreen extends ConsumerStatefulWidget {
  const MealsHistoryScreen({super.key});

  @override
  ConsumerState<MealsHistoryScreen> createState() => _MealsHistoryScreenState();
}

class _MealsHistoryScreenState extends ConsumerState<MealsHistoryScreen>
    with SelectableIdsMixin {
  final _query = TextEditingController();
  List<NutritionLog> _meals = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    final cached = ref
        .read(moduleCacheProvider)
        .read<List<NutritionLog>>(ModuleCacheKeys.nutrition);
    if (cached != null) {
      _meals = List<NutritionLog>.from(cached);
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final showSpinner = ref
        .read(moduleCacheProvider)
        .shouldShowSpinner(ModuleCacheKeys.nutrition);
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final meals = await ref.read(vivrantApiProvider).listMeals();
      if (!mounted) return;
      ref.read(moduleCacheProvider).write(ModuleCacheKeys.nutrition, meals);
      setState(() {
        _meals = meals;
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
    final types =
        _meals
            .map((m) => m.mealType)
            .where((t) => t.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final filtered = _meals.where((m) {
      if (_filter != 'all' && m.mealType != _filter) return false;
      final q = _query.text.trim().toLowerCase();
      if (q.isEmpty) return true;
      return m.mealName.toLowerCase().contains(q) ||
          m.mealType.toLowerCase().contains(q);
    }).toList();

    String titleCase(String value) {
      if (value.isEmpty) return value;
      return value
          .split(RegExp(r'[_\s]+'))
          .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
    }

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Meal history'),
        actions: [
          if (_meals.isNotEmpty) ShareExportButton(doc: mealsDoc(_meals)),
          ...selectAppBarActions(
            visibleIds: _meals.map((m) => m.id),
            onArchive: () => confirmAndArchiveSelected(
              request: (ids) => ref.read(vivrantApiProvider).archiveItems(
                    entity: 'nutrition_logs',
                    ids: ids,
                  ),
              onRemoved: (ids) {
                setState(() {
                  _meals = _meals.where((m) => !ids.contains(m.id)).toList();
                });
                ref
                    .read(moduleCacheProvider)
                    .write(ModuleCacheKeys.nutrition, _meals);
              },
            ),
          ),
          IconButton(
            tooltip: 'Log meal',
            onPressed: () => context.push('/nutrition/log'),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: VivrantLayout.pagePadding,
          children: [
            const PageHeader(
              eyebrow: 'Nutrition',
              title: 'Meal',
              highlight: 'history',
            ),
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
            else if (_meals.isEmpty)
              EmptyState(
                message: 'No meals yet. Log your first meal.',
                action: ElevatedButton(
                  onPressed: () => context.push('/nutrition/log'),
                  child: const Text('Log meal'),
                ),
              )
            else ...[
              VivrantSearchField(
                controller: _query,
                hintText: 'Search meals…',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              VivrantFilterChips<String>(
                options: [
                  VivrantFilterOption(
                    value: 'all',
                    label: 'All',
                    count: _meals.length,
                  ),
                  ...types.map(
                    (t) => VivrantFilterOption(
                      value: t,
                      label: titleCase(t),
                      count: _meals.where((m) => m.mealType == t).length,
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
                      'No meals match these filters. Try All or another search.',
                )
              else
                ...filtered.map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(
                      bottom: VivrantLayout.itemGap,
                    ),
                    child: selecting
                        ? ListRow(
                            selected: selectedIds.contains(m.id),
                            leading: selectLeading(selectedIds.contains(m.id)),
                            title: m.mealName,
                            subtitle:
                                '${m.mealType} · ${m.calories?.toStringAsFixed(0) ?? '—'} kcal',
                            onTap: () => toggleSelected(m.id),
                          )
                        : SwipeToRemove(
                            itemKey: ValueKey(m.id),
                            action: 'Archive',
                            confirmDismiss: (_) =>
                                confirmDelete(context, label: m.mealName),
                            onRemove: () async {
                              try {
                                await ref
                                    .read(vivrantApiProvider)
                                    .deleteMeal(m.id);
                                if (!mounted) return;
                                setState(() {
                                  _meals = _meals
                                      .where((x) => x.id != m.id)
                                      .toList();
                                });
                                ref
                                    .read(moduleCacheProvider)
                                    .write(ModuleCacheKeys.nutrition, _meals);
                                context.showSuccess('Meal removed');
                              } catch (e) {
                                if (!mounted) return;
                                context.showError(apiErrorMessage(e));
                              }
                            },
                            child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MealListTile(
                          meal: m,
                          onEdit: () async {
                            final draft = await showFieldEditorSheet(
                              context,
                              title: 'Edit meal',
                              fields: {
                                'Name': m.mealName,
                                'Type': m.mealType,
                                'Calories':
                                    '${m.calories?.toStringAsFixed(0) ?? ''}',
                                'Protein': '${m.proteinG ?? ''}',
                                'Carbs': '${m.carbsG ?? ''}',
                                'Fat': '${m.fatG ?? ''}',
                              },
                            );
                            if (draft == null || !mounted) return;
                            try {
                              const mealTypes = {
                                'breakfast',
                                'lunch',
                                'dinner',
                                'snack',
                              };
                              final mealType = (draft['Type'] ?? m.mealType)
                                  .toLowerCase();
                              final updated = await ref
                                  .read(vivrantApiProvider)
                                  .updateMeal(m.id, {
                                    'meal_name': draft['Name'] ?? m.mealName,
                                    'meal_type': mealTypes.contains(mealType)
                                        ? mealType
                                        : m.mealType,
                                    if ((draft['Calories'] ?? '').isNotEmpty)
                                      'calories': int.tryParse(
                                        draft['Calories']!,
                                      ),
                                    if ((draft['Protein'] ?? '').isNotEmpty)
                                      'protein_g': double.tryParse(
                                        draft['Protein']!,
                                      ),
                                    if ((draft['Carbs'] ?? '').isNotEmpty)
                                      'carbs_g': double.tryParse(
                                        draft['Carbs']!,
                                      ),
                                    if ((draft['Fat'] ?? '').isNotEmpty)
                                      'fat_g': double.tryParse(draft['Fat']!),
                                  });
                              if (!mounted) return;
                              setState(() {
                                _meals = [
                                  for (final item in _meals)
                                    item.id == m.id ? updated : item,
                                ];
                              });
                              ref
                                  .read(moduleCacheProvider)
                                  .write(ModuleCacheKeys.nutrition, _meals);
                              context.showSuccess('Meal updated');
                            } catch (e) {
                              if (!mounted) return;
                              context.showError(apiErrorMessage(e));
                            }
                          },
                          onDelete: () async {
                            if (!(await confirmDelete(
                              context,
                              label: m.mealName,
                            )))
                              return;
                            try {
                              await ref
                                  .read(vivrantApiProvider)
                                  .deleteMeal(m.id);
                              if (!mounted) return;
                              setState(() {
                                _meals = _meals
                                    .where((x) => x.id != m.id)
                                    .toList();
                              });
                              ref
                                  .read(moduleCacheProvider)
                                  .write(ModuleCacheKeys.nutrition, _meals);
                              context.showSuccess('Meal removed');
                            } catch (e) {
                              if (!mounted) return;
                              context.showError(apiErrorMessage(e));
                            }
                          },
                        ),
                        if (m.proteinG != null ||
                            m.carbsG != null ||
                            m.fatG != null) ...[
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.only(left: 54),
                            child: MacroChips(
                              proteinG: m.proteinG,
                              carbsG: m.carbsG,
                              fatG: m.fatG,
                            ),
                          ),
                        ],
                      ],
                    ),
                          ),
                  ),
                ),
            ],
            const SectionGap(),
            OutlinedButton.icon(
              onPressed: () => _estimateMeal(),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Estimate meal with AI'),
            ),
            const TileGap(),
            OutlinedButton.icon(
              onPressed: _suggestMealAi,
              icon: const Icon(Icons.restaurant_outlined),
              label: const Text('Suggest meal with AI'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _suggestMealAi() async {
    try {
      final res = await ref.read(vivrantApiProvider).suggestMealAi();
      if (!mounted) return;
      context.showInfo(
        formatAiResponse(
          res,
          keys: const ['suggestion', 'advice', 'tip', 'reason'],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _estimateMeal() async {
    final ctrl = TextEditingController();
    String? photoPath;
    String? photoName;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('AI meal estimate'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: ctrl,
                    decoration: const InputDecoration(
                      hintText: 'Describe your meal (optional with photo)',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final source = await showPhotoSourceSheet(context);
                      if (source == null || !context.mounted) return;
                      final photo = await pickPhoto(
                        context,
                        source: source,
                        maxWidth: 1280,
                        maxHeight: 1280,
                        imageQuality: 85,
                      );
                      if (photo == null || !context.mounted) return;
                      setLocal(() {
                        photoPath = photo.path;
                        photoName = photo.name;
                      });
                    },
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(
                      photoName == null ? 'Add meal photo' : photoName!,
                    ),
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
                  child: const Text('Estimate'),
                ),
              ],
            );
          },
        );
      },
    );

    final description = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || !mounted) return;
    if (description.length < 2 && photoPath == null) {
      context.showError('Describe the meal or attach a photo first.');
      return;
    }

    try {
      final res = await ref
          .read(vivrantApiProvider)
          .estimateMealAi(description, photoPath: photoPath);
      if (!mounted) return;
      final name = res['meal_name']?.toString();
      final summary = res['summary']?.toString() ?? res.toString();
      final macros = [
        if (res['calories'] != null) '${res['calories']} kcal',
        if (res['protein_g'] != null) 'P ${res['protein_g']}g',
        if (res['carbs_g'] != null) 'C ${res['carbs_g']}g',
        if (res['fat_g'] != null) 'F ${res['fat_g']}g',
      ].join(' · ');
      context.showInfo(
        [
          if (name != null && name.isNotEmpty) name,
          if (macros.isNotEmpty) macros,
          summary,
        ].where((s) => s.isNotEmpty).join('\n'),
      );
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }
}
