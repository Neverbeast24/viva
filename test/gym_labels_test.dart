import 'package:flutter_test/flutter_test.dart';
import 'package:vivrant_mobile/features/gym/data/gym_labels.dart';

void main() {
  group('pickTodaysPlanDay', () {
    test('matches a weekday name on the session label', () {
      final named = [
        {'day': 'Monday · Pull', 'focus': 'Pull', 'exercises': <Map<String, dynamic>>[]},
        {'day': 'Wednesday', 'focus': 'Push', 'exercises': <Map<String, dynamic>>[]},
      ];
      expect(
        pickTodaysPlanDay(named, DateTime(2026, 8, 17, 12))?['focus'],
        'Pull',
      );
      expect(pickTodaysPlanDay(named, DateTime(2026, 8, 18, 12)), isNull);
      expect(
        pickTodaysPlanDay(named, DateTime(2026, 8, 19, 12))?['focus'],
        'Push',
      );
    });

    test('returns null on rest days when sessions are weekday-labeled', () {
      final named = [
        {'day': 'Monday · Pull', 'focus': 'Pull', 'exercises': <Map<String, dynamic>>[]},
        {'day': 'Tuesday · Push', 'focus': 'Push', 'exercises': <Map<String, dynamic>>[]},
        {'day': 'Wednesday · Legs', 'focus': 'Legs', 'exercises': <Map<String, dynamic>>[]},
        {'day': 'Thursday · Upper', 'focus': 'Upper', 'exercises': <Map<String, dynamic>>[]},
        {'day': 'Friday · Lower', 'focus': 'Lower', 'exercises': <Map<String, dynamic>>[]},
        {'day': 'Sunday · Full body', 'focus': 'Full body', 'exercises': <Map<String, dynamic>>[]},
      ];
      expect(pickTodaysPlanDay(named, DateTime(2026, 8, 22, 12)), isNull);
      expect(
        pickTodaysPlanDay(named, DateTime(2026, 8, 23, 12))?['focus'],
        'Full body',
      );
    });

    test('uses Mon/Wed/Fri for unlabeled 3-day plans and rests otherwise', () {
      final days = [
        {
          'day': 'Day 1',
          'focus': 'Pull',
          'exercises': [
            {'name': 'Row', 'sets': '3 x 10'},
          ],
        },
        {
          'day': 'Day 2',
          'focus': 'Push',
          'exercises': [
            {'name': 'Press', 'sets': '3 x 10'},
          ],
        },
        {
          'day': 'Day 3',
          'focus': 'Legs',
          'exercises': [
            {'name': 'Squat', 'sets': '3 x 8'},
          ],
        },
      ];
      expect(pickTodaysPlanDay(days, DateTime(2026, 8, 17, 12))?['focus'], 'Pull');
      expect(pickTodaysPlanDay(days, DateTime(2026, 8, 18, 12)), isNull);
      expect(pickTodaysPlanDay(days, DateTime(2026, 8, 19, 12))?['focus'], 'Push');
    });

    test('maps a 6-day unlabeled plan onto Mon–Fri + Sunday', () {
      final six = [
        {'day': 'Day 1', 'focus': 'Pull', 'exercises': <Map<String, dynamic>>[]},
        {'day': 'Day 2', 'focus': 'Push', 'exercises': <Map<String, dynamic>>[]},
        {'day': 'Day 3', 'focus': 'Legs', 'exercises': <Map<String, dynamic>>[]},
        {'day': 'Day 4', 'focus': 'Upper', 'exercises': <Map<String, dynamic>>[]},
        {'day': 'Day 5', 'focus': 'Lower', 'exercises': <Map<String, dynamic>>[]},
        {'day': 'Day 6', 'focus': 'Full', 'exercises': <Map<String, dynamic>>[]},
      ];
      expect(pickTodaysPlanDay(six, DateTime(2026, 8, 22, 12)), isNull);
      expect(pickTodaysPlanDay(six, DateTime(2026, 8, 23, 12))?['focus'], 'Full');
    });
  });

  group('sanitizeGymPlanLevel', () {
    test('defaults unknown values to beginner', () {
      expect(sanitizeGymPlanLevel(null), 'beginner');
      expect(sanitizeGymPlanLevel('expert'), 'beginner');
      expect(sanitizeGymPlanLevel('ADVANCED'), 'advanced');
      expect(sanitizeGymPlanLevel('intermediate'), 'intermediate');
    });
  });

  group('parseRestSeconds', () {
    test('reads seconds, minutes, and zero rest', () {
      expect(parseRestSeconds('90s'), 90);
      expect(parseRestSeconds('2 min'), 120);
      expect(parseRestSeconds('60-90s'), 60);
      expect(parseRestSeconds('0s'), 0);
      expect(parseRestSeconds('none'), 0);
    });
  });

  group('parseSetCount', () {
    test('reads the leading set count', () {
      expect(parseSetCount('4 x 10-12'), 4);
      expect(parseSetCount('3x10'), 3);
      expect(parseSetCount('1 set of 35-40 mins'), 1);
      expect(parseSetCount('12 minutes steady'), 1);
    });
  });

  group('gymSessionFocusFromPlan', () {
    test('maps day labels onto session focus values', () {
      expect(gymSessionFocusFromPlan('Pull'), 'upper');
      expect(gymSessionFocusFromPlan('Leg day'), 'lower');
      expect(gymSessionFocusFromPlan('strength'), 'strength');
      expect(gymSessionFocusFromPlan('HIIT'), 'endurance');
    });
  });

  group('program builder helpers', () {
    test('lists remaining weekdays after a kept day', () {
      expect(
        remainingTrainingDays(
          [1, 3, 5],
          {
            'kept_days': {
              '1': {'day': 'Monday · Pull', 'focus': 'Pull'},
            },
          },
        ),
        [3, 5],
      );
    });

    test('picks a saved day by weekday even when it is not today', () {
      final named = [
        {'day': 'Monday · Pull', 'focus': 'Pull', 'exercises': <Map<String, dynamic>>[]},
        {'day': 'Wednesday · Push', 'focus': 'Push', 'exercises': <Map<String, dynamic>>[]},
      ];
      expect(findPlanDayByLabel(named, 'Wednesday · Push')?['focus'], 'Push');
      expect(findPlanDayByLabel(named, 'monday')?['focus'], 'Pull');
    });

    test('picks Day 2 labels without treating them as Tuesday', () {
      final numbered = [
        {'day': 'Day 1: Upper Body Push & Core', 'focus': 'Push', 'exercises': <Map<String, dynamic>>[]},
        {'day': 'Day 2: Lower Body Quads & Calves', 'focus': 'Legs', 'exercises': <Map<String, dynamic>>[]},
      ];
      expect(findPlanDayByLabel(numbered, 'Day 2: Lower Body Quads & Calves')?['focus'], 'Legs');
      expect(
        resolveSessionPlanDay(numbered, label: 'Day 2: Lower Body Quads & Calves')?['focus'],
        'Legs',
      );
    });

    test('counts remaining rest from an end timestamp', () {
      final now = DateTime.fromMillisecondsSinceEpoch(1_000_000);
      final ends = restEndsAtFromSeconds(90, now);
      expect(restRemainingSeconds(ends, now), 90);
      expect(restRemainingSeconds(ends, now.add(const Duration(seconds: 30))), 60);
      expect(restRemainingSeconds(ends, now.add(const Duration(seconds: 120))), 0);
    });
  });

  group('custom move formatting', () {
    test('title-cases typed moves and strips stray commas', () {
      expect(formatGymMoveName('multi press'), 'Multi Press');
      expect(formatGymMoveName(', tricep rope,'), 'Tricep Rope');
      expect(formatGymMoveName('leg curl (extension)'), 'Leg Curl (Extension)');
    });

    test('splits comma lists when adding custom moves', () {
      expect(
        sanitizeCustomExercises([', tricep rope,', 'hip thrust, landmine press']),
        ['Tricep Rope', 'Hip Thrust', 'Landmine Press'],
      );
    });
  });

  group('mergePlanDaysIntoDraft', () {
    test('fills empty weekdays from a saved program', () {
      final draft = {
        'training_days': [1, 3, 5],
        'kept_days': {
          '1': {'day': 'Monday · Pull', 'focus': 'pull', 'exercises': <Map<String, dynamic>>[]},
        },
      };
      final next = mergePlanDaysIntoDraft(draft, [
        {'day': 'Monday · Push', 'focus': 'push', 'exercises': <Map<String, dynamic>>[]},
        {'day': 'Wednesday · Legs', 'focus': 'legs', 'exercises': <Map<String, dynamic>>[]},
      ]);
      expect((next['kept_days'] as Map)['1']['focus'], 'pull');
      expect((next['kept_days'] as Map)['3']['focus'], 'legs');
    });
  });

  group('moveSavedPlanDay', () {
    test('moves a workout onto an empty weekday', () {
      final next = moveSavedPlanDay(
        [
          {
            'day': 'Monday · Pull',
            'focus': 'Pull',
            'exercises': [
              {'name': 'Row', 'sets': '3 x 10', 'rest': '60s'},
            ],
          },
        ],
        0,
        3,
      );
      expect(next, hasLength(1));
      expect(next.first['day'], contains('Wednesday'));
      expect((next.first['exercises'] as List).first['name'], 'Row');
    });

    test('swaps two weekday sessions', () {
      final next = moveSavedPlanDay(
        [
          {
            'day': 'Monday · Pull',
            'focus': 'Pull',
            'exercises': [
              {'name': 'Row'},
            ],
          },
          {
            'day': 'Wednesday · Push',
            'focus': 'Push',
            'exercises': [
              {'name': 'Press'},
            ],
          },
        ],
        0,
        3,
      );
      expect(
        next.firstWhere((day) => day['day'].toString().contains('Wednesday'))['focus'],
        'Pull',
      );
      expect(
        next.firstWhere((day) => day['day'].toString().contains('Monday'))['focus'],
        'Push',
      );
    });
  });

  group('moveKeptDayOnDraft', () {
    test('swaps kept workouts between weekdays', () {
      final draft = {
        'kept_days': {
          '1': {'day': 'Monday · Push', 'focus': 'push', 'exercises': <Map<String, dynamic>>[]},
          '3': {'day': 'Wednesday · Pull', 'focus': 'pull', 'exercises': <Map<String, dynamic>>[]},
        },
      };
      final next = moveKeptDayOnDraft(draft, 1, 3);
      expect((next['kept_days'] as Map)['1']['focus'], 'pull');
      expect((next['kept_days'] as Map)['3']['focus'], 'push');
    });
  });

  group('reorderPreviewExercisesOnDraft', () {
    test('moves a preview exercise', () {
      final draft = {
        'preview_days': [
          {
            'day': 'Monday',
            'focus': 'push',
            'exercises': [
              {'name': 'Press'},
              {'name': 'Fly'},
            ],
          },
        ],
      };
      final next = reorderPreviewExercisesOnDraft(draft, 0, 0, 1);
      final names = ((next['preview_days'] as List).first['exercises'] as List)
          .map((ex) => (ex as Map)['name'])
          .toList();
      expect(names, ['Fly', 'Press']);
    });
  });
}
