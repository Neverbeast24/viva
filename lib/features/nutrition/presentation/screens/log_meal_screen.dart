import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/constants/enums.dart';
import '../../../../shared/models/models.dart';
import '../../data/meal_suggestions.dart';

class LogMealScreen extends ConsumerStatefulWidget {
  const LogMealScreen({super.key});

  @override
  ConsumerState<LogMealScreen> createState() => _LogMealScreenState();
}

class _LogMealScreenState extends ConsumerState<LogMealScreen>
    with SelectableIdsMixin {
  final _name = TextEditingController();
  final _cal = TextEditingController();
  final _protein = TextEditingController();
  final _carbs = TextEditingController();
  final _fat = TextEditingController();
  String _type = 'breakfast';
  bool _loading = false;
  EasyEntryMode _mode = EasyEntryMode.list;
  List<PantryItem> _pantry = const [];
  List<NutritionLog> _meals = const [];

  @override
  void initState() {
    super.initState();
    _loadContext();
    loadEasyEntryMode('nutrition-log').then((mode) {
      if (mounted) setState(() => _mode = mode);
    });
  }

  Future<void> _loadContext() async {
    try {
      final api = ref.read(vivrantApiProvider);
      final results = await Future.wait([
        api.listPantry(),
        api.listMeals(),
      ]);
      if (!mounted) return;
      setState(() {
        _pantry = (results[0] as List<PantryItem>)
            .where((p) => p.stockLevel > 0)
            .take(14)
            .toList();
        _meals = results[1] as List<NutritionLog>;
      });
    } catch (_) {}
  }

  void _setMode(EasyEntryMode mode) {
    setState(() => _mode = mode);
    saveEasyEntryMode('nutrition-log', mode);
  }

  @override
  void dispose() {
    _name.dispose();
    _cal.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  void _clearDraft() {
    _name.clear();
    _cal.clear();
    _protein.clear();
    _carbs.clear();
    _fat.clear();
  }

  Future<void> _save({bool popOnSuccess = true}) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      context.showError('Enter a meal name.');
      return;
    }
    setState(() => _loading = true);
    try {
      final calories = double.tryParse(_cal.text.trim());
      final protein = double.tryParse(_protein.text.trim());
      final carbs = double.tryParse(_carbs.text.trim());
      final fat = double.tryParse(_fat.text.trim());
      final meal = await ref.read(vivrantApiProvider).logMeal({
        'meal_name': name,
        'meal_type': _type,
        if (calories != null) 'calories': calories,
        if (protein != null) 'protein_g': protein,
        if (carbs != null) 'carbs_g': carbs,
        if (fat != null) 'fat_g': fat,
      });
      if (!mounted) return;
      setState(() => _meals = [meal, ..._meals]);
      _clearDraft();
      if (popOnSuccess) {
        context.pop();
      } else {
        context.showSuccess('Meal logged');
      }
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pasteMeals(String text) async {
    setState(() => _loading = true);
    try {
      final added = await ref.read(vivrantApiProvider).logMealsBulk(text);
      if (!mounted) return;
      setState(() => _meals = [...added, ..._meals]);
      context.showSuccess(
        'Logged ${added.length} meal${added.length == 1 ? '' : 's'}',
      );
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
      rethrow;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editMeal(NutritionLog meal) async {
    final draft = await showFieldEditorSheet(
      context,
      title: 'Edit meal',
      fields: {
        'Name': meal.mealName,
        'Type': meal.mealType,
        'Calories': meal.calories?.round().toString() ?? '',
        'Protein g': meal.proteinG?.round().toString() ?? '',
        'Carbs g': meal.carbsG?.round().toString() ?? '',
        'Fat g': meal.fatG?.round().toString() ?? '',
      },
    );
    if (draft == null || !mounted) return;
    final type = (draft['Type'] ?? meal.mealType).toLowerCase();
    try {
      final updated = await ref.read(vivrantApiProvider).updateMeal(meal.id, {
        'meal_name': draft['Name'] ?? meal.mealName,
        'meal_type': mealTypes.contains(type) ? type : meal.mealType,
        if ((draft['Calories'] ?? '').isNotEmpty)
          'calories': double.tryParse(draft['Calories']!),
        if ((draft['Protein g'] ?? '').isNotEmpty)
          'protein_g': double.tryParse(draft['Protein g']!),
        if ((draft['Carbs g'] ?? '').isNotEmpty)
          'carbs_g': double.tryParse(draft['Carbs g']!),
        if ((draft['Fat g'] ?? '').isNotEmpty)
          'fat_g': double.tryParse(draft['Fat g']!),
      });
      if (!mounted) return;
      setState(() {
        _meals = [for (final row in _meals) row.id == meal.id ? updated : row];
      });
      context.showSuccess('Meal updated');
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _deleteMeal(NutritionLog meal) async {
    if (!(await confirmDelete(context, label: meal.mealName))) return;
    try {
      await ref.read(vivrantApiProvider).deleteMeal(meal.id);
      if (!mounted) return;
      setState(() => _meals = _meals.where((row) => row.id != meal.id).toList());
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
        'Meal',
        'Type',
        'Cal',
        'P',
        'C',
        'F',
        '',
      ],
      rows: [
        for (final meal in _meals)
          [
            if (selecting)
              Checkbox(
                value: selectedIds.contains(meal.id),
                onChanged: (_) => toggleSelected(meal.id),
              ),
            InkWell(
              onTap: () => _editMeal(meal),
              child: Text(
                meal.mealName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Text(labelForOption(meal.mealType)),
            Text(meal.calories == null ? '—' : '${meal.calories!.round()}'),
            Text(meal.proteinG == null ? '—' : '${meal.proteinG!.round()}'),
            Text(meal.carbsG == null ? '—' : '${meal.carbsG!.round()}'),
            Text(meal.fatG == null ? '—' : '${meal.fatG!.round()}'),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _deleteMeal(meal),
            ),
          ],
        [
          if (selecting) const SizedBox.shrink(),
          ExcelCellField(
            controller: _name,
            hint: 'New meal',
            width: 140,
            onSubmitted: (_) => _save(popOnSuccess: false),
          ),
          ExcelDropdown<String>(
            value: _type,
            items: [
              for (final t in mealTypes)
                DropdownMenuItem(value: t, child: Text(labelForOption(t))),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'snack'),
          ),
          ExcelCellField(
            controller: _cal,
            hint: 'kcal',
            width: 64,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            onSubmitted: (_) => _save(popOnSuccess: false),
          ),
          ExcelCellField(
            controller: _protein,
            hint: 'g',
            width: 48,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            onSubmitted: (_) => _save(popOnSuccess: false),
          ),
          ExcelCellField(
            controller: _carbs,
            hint: 'g',
            width: 48,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            onSubmitted: (_) => _save(popOnSuccess: false),
          ),
          ExcelCellField(
            controller: _fat,
            hint: 'g',
            width: 48,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            onSubmitted: (_) => _save(popOnSuccess: false),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline, size: 18),
            onPressed: _loading ? null : () => _save(popOnSuccess: false),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Log meal'),
        actions: [
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
              },
            ),
          ),
        ],
      ),
      child: ListView(
        padding: VivrantLayout.pagePadding,
        children: [
          if (_meals.isNotEmpty || _pantry.isNotEmpty) ...[
            StatCard(
              label: 'Calories today',
              value:
                  '${_meals.fold<double>(0, (s, m) => s + (m.calories ?? 0)).round()}',
              caption:
                  '${_meals.length} meal${_meals.length == 1 ? '' : 's'} · ${(2000 - _meals.fold<double>(0, (s, m) => s + (m.calories ?? 0)).round()).clamp(0, 2000)} left of 2000',
              icon: Icons.local_fire_department_outlined,
            ),
            const SizedBox(height: 12),
          ],
          if (_pantry.isNotEmpty) ...[
            const SectionLabel('Cook from pantry'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in _pantry)
                  ActionChip(
                    label: Text(item.name),
                    onPressed: () {
                      _name.text = item.name;
                      setState(() {});
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          SectionLabel('Suggested ${suggestedMealType()}'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final meal in nextMealSuggestions(_meals.map((m) => m.mealType)))
                ActionChip(
                  label: Text(meal.name),
                  onPressed: () {
                    _name.text = meal.name;
                    _type = meal.mealType;
                    _cal.text = '${meal.calories}';
                    _protein.text = '${meal.proteinG}';
                    _carbs.text = '${meal.carbsG}';
                    _fat.text = '${meal.fatG}';
                    setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          EasyEntryToggle(
            value: _mode,
            onChanged: _setMode,
          ),
          const SizedBox(height: 16),
          if (_mode == EasyEntryMode.paste)
            QuickListPaste(
              pending: _loading,
              placeholder: 'sinigang, lunch, 450\neggs & toast, breakfast, 350',
              submitLabel: 'Log all',
              onSubmit: _pasteMeals,
            )
          else if (_mode == EasyEntryMode.sheet)
            _buildSheet()
          else ...[
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Meal name'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              items: [
                for (final t in mealTypes)
                  DropdownMenuItem(value: t, child: Text(labelForOption(t))),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'snack'),
              decoration: const InputDecoration(labelText: 'Meal type'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cal,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Calories'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _protein,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Protein g'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _carbs,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Carbs g'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _fat,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Fat g'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: Text(_loading ? 'Saving…' : 'Save meal'),
            ),
          ],
        ],
      ),
    );
  }
}
