import 'package:flutter_test/flutter_test.dart';
import 'package:vivrant_mobile/core/utils/bmi.dart';
import 'package:vivrant_mobile/features/nutrition/data/meal_suggestions.dart';

void main() {
  group('summarizeBmi', () {
    test('rounds BMI and labels the band', () {
      final summary = summarizeBmi(170, 68);
      expect(summary?['bmi'], 23.5);
      expect(summary?['band_label'], 'Normal');
    });

    test('returns null when height or weight is missing', () {
      expect(summarizeBmi(null, 68), isNull);
      expect(summarizeBmi(170, null), isNull);
    });
  });

  group('nextMealSuggestions', () {
    test('suggests lunch around noon', () {
      final meals = nextMealSuggestions(const [], date: DateTime(2026, 8, 18, 12));
      expect(meals, isNotEmpty);
      expect(meals.every((meal) => meal.mealType == 'lunch'), isTrue);
    });
  });
}
