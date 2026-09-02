import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/providers/module_cache.dart';
import '../../../../shared/providers/shell_tab_provider.dart';
import '../../data/meal_suggestions.dart';

/// Nutrition tab — destinations only. Meals live on history / log pages.
class NutritionScreen extends ConsumerStatefulWidget {
  const NutritionScreen({super.key});

  @override
  ConsumerState<NutritionScreen> createState() => _NutritionScreenState();
}

class _NutritionScreenState extends ConsumerState<NutritionScreen> {
  static const _tabIndex = 1;

  List<NutritionLog> _meals = [];
  int _pantryCount = 0;
  int _waterMl = 0;
  bool _loading = false;
  bool _activated = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final cached = ref
        .read(moduleCacheProvider)
        .read<List<NutritionLog>>(ModuleCacheKeys.nutrition);
    if (cached != null) {
      _meals = List<NutritionLog>.from(cached);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeActivate());
  }

  void _maybeActivate() {
    if (!mounted || _activated) return;
    if (ref.read(shellTabIndexProvider) != _tabIndex) return;
    _activated = true;
    _load();
  }

  Future<void> _load() async {
    final showSpinner =
        ref.read(moduleCacheProvider).shouldShowSpinner(ModuleCacheKeys.nutrition);
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(vivrantApiProvider);
      final meals = await api.listMeals();
      var pantryCount = 0;
      var waterMl = 0;
      try {
        final pantry = await api.listPantry();
        pantryCount = pantry.where((p) => p.stockLevel > 0).length;
      } catch (_) {}
      try {
        final today = await api.getToday();
        waterMl = (today['water_ml'] as num?)?.toInt() ?? 0;
      } catch (_) {}
      if (!mounted) return;
      ref.read(moduleCacheProvider).write(ModuleCacheKeys.nutrition, meals);
      setState(() {
        _meals = meals;
        _pantryCount = pantryCount;
        _waterMl = waterMl;
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

  Future<void> _quickLog(QuickMeal meal) async {
    try {
      await ref.read(vivrantApiProvider).logMeal({
        'meal_name': meal.name,
        'meal_type': meal.mealType,
        'calories': meal.calories,
        'protein_g': meal.proteinG,
        'carbs_g': meal.carbsG,
        'fat_g': meal.fatG,
      });
      if (!mounted) return;
      context.showSuccess('Logged ${meal.name}');
      _load();
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(shellTabIndexProvider, (_, next) {
      if (next == _tabIndex) _maybeActivate();
    });
    final totalCal = _meals.fold<double>(0, (s, m) => s + (m.calories ?? 0));
    const calorieGoal = 2000;
    final calLeft = (calorieGoal - totalCal).round().clamp(0, calorieGoal);
    final suggestions = nextMealSuggestions(_meals.map((m) => m.mealType));
    final slot = suggestedMealType();

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: VivrantLayout.pagePadding,
          children: [
            const PageHeader(
              eyebrow: 'Nutrition',
              title: 'Meals &',
              highlight: 'macros',
            ),
            if (_error != null)
              EmptyState(
                message: _error!,
                action: OutlinedButton(
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              )
            else
              StatCard(
                label: 'Today',
                value: _loading && _meals.isEmpty
                    ? '—'
                    : totalCal.toStringAsFixed(0),
                caption: '$calLeft kcal left of $calorieGoal',
                icon: Icons.restaurant,
              ),
            const SectionGap(),
            SectionLabel('Suggested $slot'),
            for (final meal in suggestions) ...[
              ModuleTile(
                icon: Icons.restaurant_outlined,
                label: meal.name,
                caption: '${meal.hint} · ~${meal.calories} kcal',
                onTap: () => _quickLog(meal),
              ),
              const TileGap(),
            ],
            ModuleTile(
              icon: Icons.auto_awesome,
              label: 'AI meal idea',
              caption: 'From pantry and today’s logs',
              onTap: () => context.push('/nutrition/history'),
            ),
            const SectionGap(),
            const SectionLabel('Log'),
            ModuleTile(
              icon: Icons.add_circle_outline,
              label: 'Log a meal',
              caption: 'Name, macros, or a photo',
              onTap: () => context.push('/nutrition/log'),
            ),
            const TileGap(),
            ModuleTile(
              icon: Icons.history_rounded,
              label: 'Meal history',
              caption: _meals.isEmpty
                  ? 'Past meals and AI estimates'
                  : '${_meals.length} logged',
              onTap: () => context.push('/nutrition/history'),
            ),
            const SectionGap(),
            const SectionLabel('Related'),
            ModuleTile(
              icon: Icons.kitchen_outlined,
              label: 'Cook from pantry',
              caption: _pantryCount == 0
                  ? 'Open pantry stock'
                  : '$_pantryCount items on the shelf',
              onTap: () => context.push('/pantry'),
            ),
            const TileGap(),
            ModuleTile(
              icon: Icons.water_drop_outlined,
              label: 'Hydration',
              caption: '$_waterMl ml today',
              onTap: () => context.push('/hydration'),
            ),
          ],
        ),
      ),
    );
  }
}
