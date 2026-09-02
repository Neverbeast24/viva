class QuickMeal {
  const QuickMeal({
    required this.name,
    required this.mealType,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.hint,
  });

  final String name;
  final String mealType;
  final int calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final String hint;
}

const quickMeals = <QuickMeal>[
  QuickMeal(
    name: 'Eggs & toast',
    mealType: 'breakfast',
    calories: 350,
    proteinG: 18,
    carbsG: 30,
    fatG: 16,
    hint: '2 eggs + 1–2 toast',
  ),
  QuickMeal(
    name: 'Garlic rice & egg',
    mealType: 'breakfast',
    calories: 420,
    proteinG: 16,
    carbsG: 52,
    fatG: 14,
    hint: '1 plate + fried egg',
  ),
  QuickMeal(
    name: 'Oatmeal & fruit',
    mealType: 'breakfast',
    calories: 320,
    proteinG: 10,
    carbsG: 55,
    fatG: 6,
    hint: '1 bowl',
  ),
  QuickMeal(
    name: 'Chicken rice bowl',
    mealType: 'lunch',
    calories: 550,
    proteinG: 35,
    carbsG: 55,
    fatG: 15,
    hint: 'palm protein + fist rice',
  ),
  QuickMeal(
    name: 'Chicken adobo & rice',
    mealType: 'lunch',
    calories: 580,
    proteinG: 38,
    carbsG: 52,
    fatG: 18,
    hint: '1 cup rice + 2 pieces',
  ),
  QuickMeal(
    name: 'Salad with protein',
    mealType: 'lunch',
    calories: 380,
    proteinG: 30,
    carbsG: 18,
    fatG: 18,
    hint: 'big bowl + chicken/tofu',
  ),
  QuickMeal(
    name: 'Fish & veggies',
    mealType: 'dinner',
    calories: 420,
    proteinG: 32,
    carbsG: 20,
    fatG: 18,
    hint: 'palm fish + veggies',
  ),
  QuickMeal(
    name: 'Sinigang & rice',
    mealType: 'dinner',
    calories: 480,
    proteinG: 28,
    carbsG: 50,
    fatG: 12,
    hint: '1 bowl + 1 cup rice',
  ),
  QuickMeal(
    name: 'Protein snack',
    mealType: 'snack',
    calories: 200,
    proteinG: 15,
    carbsG: 12,
    fatG: 8,
    hint: 'yogurt, shake, or nuts',
  ),
  QuickMeal(
    name: 'Banana & peanut butter',
    mealType: 'snack',
    calories: 240,
    proteinG: 8,
    carbsG: 28,
    fatG: 12,
    hint: '1 banana + 1 tbsp',
  ),
];

String suggestedMealType([DateTime? date]) {
  final hour = (date ?? DateTime.now()).hour;
  if (hour < 10) return 'breakfast';
  if (hour < 15) return 'lunch';
  if (hour < 21) return 'dinner';
  return 'snack';
}

List<QuickMeal> mealsForType(String type, {int limit = 3}) {
  final matched = quickMeals.where((meal) => meal.mealType == type).toList();
  if (matched.length >= limit) return matched.take(limit).toList();
  return [
    ...matched,
    ...quickMeals.where((meal) => meal.mealType != type),
  ].take(limit).toList();
}

List<QuickMeal> nextMealSuggestions(Iterable<String> loggedTypes, {DateTime? date, int limit = 3}) {
  final done = loggedTypes.map((type) => type.trim().toLowerCase()).where((type) => type.isNotEmpty).toSet();
  final preferred = suggestedMealType(date);
  final type = done.contains(preferred) ? (preferred == 'snack' ? 'dinner' : 'snack') : preferred;
  return mealsForType(type, limit: limit);
}
