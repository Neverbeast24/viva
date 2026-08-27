/// Gym catalog constants, muscle filters, and equipment labels.
///
/// Mirrors viva-server gym helpers. Keep this file UI-free so screens,
/// export formatters, and plan editors can share the same vocabulary.
library;

import 'package:flutter/material.dart';

import '../../../core/utils/humanize.dart';
import '../../../shared/models/gym_exercise.dart';

export '../../../core/utils/humanize.dart' show humanizeLabel;

/// Mirrors web `GYM_PLAN_LEVELS` for AI gym plan prefs.
const gymPlanLevels = <String>['beginner', 'intermediate', 'advanced'];

String sanitizeGymPlanLevel(String? input) {
  final value = (input ?? '').trim().toLowerCase();
  if (value == 'intermediate' || value == 'advanced') return value;
  return 'beginner';
}

/// Mirrors web `GYM_AVOID_TARGETS` for AI gym plan prefs.
const gymAvoidTargets = <String>[
  'core',
  'arms',
  'forearms',
  'shoulders',
  'chest',
  'back',
  'traps',
  'legs',
  'glutes',
  'hamstrings',
  'calves',
  'inner_thighs',
  'lower_back',
  'cardio',
  'mobility',
];

/// Mirrors web `muscleFilters` for gym catalog filtering.
const gymMuscleFilters = <String>[
  'all',
  'legs',
  'inner_thighs',
  'calves',
  'glutes',
  'hamstrings',
  'chest',
  'back',
  'shoulders',
  'traps',
  'arms',
  'forearms',
  'core',
  'lower_back',
  'full_body',
  'cardio',
  'mobility',
];

/// Short beginner-friendly muscle chips; remaining filters stay behind "More".
const gymMuscleFiltersPrimary = <String>[
  'all',
  'legs',
  'glutes',
  'chest',
  'back',
  'shoulders',
  'arms',
  'core',
  'cardio',
];

/// Mirrors web `MAX_KNOWN_MACHINE_SLUGS`.
const maxKnownMachineSlugs = 250;

String muscleFilterLabel(String value) {
  switch (value) {
    case 'all':
      return 'All muscles';
    case 'lower_back':
      return 'Lower back';
    case 'full_body':
      return 'Full body';
    case 'inner_thighs':
      return 'Inner thighs';
    default:
      return humanizeLabel(value);
  }
}

/// Mirrors web `clampGymPlanPrefs` sanitize rules for known catalog slugs.
List<String> sanitizeKnownMachineSlugs(Iterable<String> input) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in input) {
    final slug = raw.trim().toLowerCase();
    if (slug.isEmpty || slug.length > 80 || seen.contains(slug)) continue;
    seen.add(slug);
    out.add(slug);
    if (out.length >= maxKnownMachineSlugs) break;
  }
  return out;
}

/// Mirrors web sanitize for free-text custom exercises (max 20, ≤80 chars).
List<String> sanitizeCustomExercises(Iterable<String> input) {
  final seen = <String>{};
  final out = <String>[];
  for (final raw in input) {
    final parts = raw.contains(',') ? splitCustomGymMoves(raw) : [formatGymMoveName(raw)];
    for (final name in parts) {
      if (name.length < 2) continue;
      final key = name.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      out.add(name);
      if (out.length >= 20) return out;
    }
  }
  return out;
}

String formatGymMoveName(String raw) {
  var cleaned = raw
      .replaceAll(RegExp(r'[,;|/]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  cleaned = cleaned.replaceFirst(RegExp(r'^[^A-Za-z0-9(]+'), '');
  cleaned = cleaned.replaceFirst(RegExp(r'[^A-Za-z0-9)]+$'), '');
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.length < 2) return cleaned;
  if (cleaned.length > 80) cleaned = cleaned.substring(0, 80);
  return cleaned.replaceAllMapped(RegExp(r"[A-Za-z][A-Za-z0-9']*"), (match) {
    final word = match.group(0)!;
    return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
  });
}

String displayGymMoveName(String? raw) {
  final formatted = formatGymMoveName(raw ?? '');
  if (formatted.length >= 2) return formatted;
  final fallback = (raw ?? '').trim();
  return fallback.isEmpty ? 'Movement' : fallback;
}

List<String> splitCustomGymMoves(String raw) {
  return raw
      .split(',')
      .map(formatGymMoveName)
      .where((name) => name.length >= 2)
      .toList();
}

class GymMoveDetails {
  const GymMoveDetails({
    required this.displayName,
    required this.muscleGroup,
    required this.equipment,
    required this.cues,
  });

  final String displayName;
  final String muscleGroup;
  final String equipment;
  final String cues;
}

String inferCustomMuscleGroup(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'\b(sit\s*-?ups?|crunch|plank|ab\b|core|glider)\b').hasMatch(n)) return 'core';
  if (RegExp(r'\b(treadmill|bike|cardio|run|jog|elliptical)\b').hasMatch(n)) return 'cardio';
  if (RegExp(r'\b(tricep|bicep|arm|pushdown|rope)\b').hasMatch(n) && !RegExp(r'\bleg\b').hasMatch(n)) {
    return 'arms';
  }
  if (RegExp(r'\b(shoulder|delt|overhead press)\b').hasMatch(n)) return 'shoulders';
  if (RegExp(r'\b(chest|bench|pec|fly)\b').hasMatch(n)) return 'chest';
  if (RegExp(r'\bpress\b').hasMatch(n) && !RegExp(r'\b(leg|calf)\b').hasMatch(n)) return 'chest';
  if (RegExp(r'\b(lat|pulldown|row)\b').hasMatch(n) || RegExp(r'\bback\b').hasMatch(n)) return 'back';
  if (RegExp(r'\b(glute|hip thrust|kickback)\b').hasMatch(n)) return 'glutes';
  if (RegExp(r'\b(hamstring|rdl|deadlift|leg curl)\b').hasMatch(n)) return 'hamstrings';
  if (RegExp(r'\b(calf)\b').hasMatch(n)) return 'calves';
  if (RegExp(r'\b(inner thigh|adductor|abductor)\b').hasMatch(n)) return 'inner_thighs';
  if (RegExp(r'\b(leg|squat|lunge|thigh)\b').hasMatch(n)) return 'legs';
  return 'full_body';
}

String inferCustomEquipment(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'\b(cable|rope|pushdown|pulldown|face pull)\b').hasMatch(n)) return 'cable';
  if (RegExp(r'\b(dumbbell|barbell|kettlebell|landmine)\b').hasMatch(n)) return 'free_weight';
  if (RegExp(r'\b(plank|sit\s*-?ups?|crunch|push\s*-?ups?)\b').hasMatch(n)) return 'bodyweight';
  if (RegExp(r'\b(machine|press|curl|extension|pec|deck|fly)\b').hasMatch(n)) return 'machine';
  return 'free_weight';
}

String customGymMoveCue(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'\bpress\b').hasMatch(n)) {
    return 'Brace your core, keep a controlled path, and stop just short of lockout.';
  }
  if (RegExp(r'\b(tricep|pushdown|rope|extension)\b').hasMatch(n) && !RegExp(r'\bleg\b').hasMatch(n)) {
    return 'Keep elbows pinned and finish with a full squeeze.';
  }
  if (RegExp(r'\bcurl\b').hasMatch(n)) {
    return 'Move through a full range and squeeze at the top without swinging.';
  }
  if (RegExp(r'\b(row|pulldown)\b').hasMatch(n)) {
    return 'Pull with your back, keep the chest open, and control the return.';
  }
  if (RegExp(r'\b(hip thrust|glute)\b').hasMatch(n)) {
    return 'Tuck the chin, drive through the heels, and squeeze at the top.';
  }
  if (RegExp(r'\b(squat|lunge|leg)\b').hasMatch(n)) {
    return 'Brace your core, track knees over toes, and push through a full range.';
  }
  switch (inferCustomMuscleGroup(name)) {
    case 'chest':
      return 'Keep your chest high and control both the press and the return.';
    case 'back':
      return 'Lead with the elbows and keep the shoulders packed.';
    case 'arms':
      return 'Lock the upper arms in place and squeeze at the end of the rep.';
    case 'shoulders':
      return 'Brace your core and lift without shrugging.';
    case 'core':
      return 'Keep the ribs down and breathe through a tight midline.';
    case 'cardio':
      return 'Stay smooth and keep an easy, repeatable pace.';
    default:
      return 'Use a full range of motion and keep the weight under control.';
  }
}

GymMoveDetails gymMoveDetails(String name) {
  final displayName = formatGymMoveName(name);
  final label = displayName.isEmpty ? 'Movement' : displayName;
  return GymMoveDetails(
    displayName: label,
    muscleGroup: inferCustomMuscleGroup(label),
    equipment: inferCustomEquipment(label),
    cues: customGymMoveCue(label),
  );
}

String _normalizeGymMoveName(String name) {
  return name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .replaceAll(RegExp(r'\b(machines?|trainers?|exercises?|the)\b'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

const _skipMoveTokens = {
  'the',
  'a',
  'an',
  'and',
  'or',
  'of',
  'to',
  'with',
  'machine',
  'trainer',
  'exercise',
  'exercises',
};

List<String> _significantMoveTokens(String name) {
  return _normalizeGymMoveName(name)
      .split(' ')
      .where((token) => token.length >= 4 && !_skipMoveTokens.contains(token))
      .toList();
}

GymExercise? findRelatedExerciseMatch(String name, List<GymExercise> exercises) {
  final exact = findExerciseMatch(name, exercises);
  if (exact != null) return exact;
  final tokens = _significantMoveTokens(name);
  if (tokens.isEmpty) return null;
  final muscle = inferCustomMuscleGroup(name);
  GymExercise? best;
  var bestScore = 0;
  for (final item in exercises) {
    final overlap = _significantMoveTokens(item.name).where(tokens.contains).length;
    if (overlap == 0) continue;
    if (item.muscleGroup.isNotEmpty && item.muscleGroup != muscle) continue;
    final score = overlap + (item.muscleGroup == muscle ? 2 : 0);
    if (score > bestScore) {
      best = item;
      bestScore = score;
    }
  }
  return best;
}

List<GymExercise> filterGymMoveCatalog(
  String query,
  List<GymExercise> items, {
  int limit = 40,
}) {
  final q = query.trim().toLowerCase();
  final ranked = <({GymExercise item, int score})>[];
  for (final item in items) {
    final name = item.name.toLowerCase();
    final muscle = item.muscleGroup.toLowerCase();
    final gear = item.equipment.toLowerCase();
    var score = 0;
    if (q.isEmpty) {
      score = 1;
    } else if (name == q) {
      score = 100;
    } else if (name.startsWith(q)) {
      score = 80;
    } else if (name.contains(q)) {
      score = 60;
    } else if (muscle.contains(q) || gear.contains(q)) {
      score = 30;
    }
    if (score > 0) ranked.add((item: item, score: score));
  }
  ranked.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return a.item.name.toLowerCase().compareTo(b.item.name.toLowerCase());
  });
  return [
    for (final row in ranked.take(limit < 1 ? 1 : limit)) row.item,
  ];
}

const _gymLoadBands = <String, List<List<double>>>{
  'beginner': [
    [0.15, 0.35],
    [0.40, 0.70],
  ],
  'intermediate': [
    [0.25, 0.45],
    [0.60, 1.00],
  ],
  'advanced': [
    [0.35, 0.55],
    [0.80, 1.40],
  ],
};

String _gymLoadLevel(String? level) {
  final raw = (level ?? '').toLowerCase();
  if (raw == 'advanced') return 'advanced';
  if (raw == 'intermediate') return 'intermediate';
  return 'beginner';
}

double _gymLoadBodyKg(double? bodyWeightKg) {
  final kg = bodyWeightKg ?? 70;
  if (kg >= 30 && kg <= 400) return kg;
  return 70;
}

int _roundGymKg(num n) => (n / 2).round().clamp(1, 500) * 2;

String _formatGymKgWindow(double bodyKg, double loPct, double hiPct) {
  final mid = bodyKg * ((loPct + hiPct) / 2);
  final lo = _roundGymKg(mid - 2);
  final hiRaw = _roundGymKg(mid + 2);
  final hi = hiRaw < lo + 2 ? lo + 2 : hiRaw;
  return '$lo–$hi kg';
}

bool isCardioGymMove(String name, [String? equipment]) {
  final gear = (equipment ?? '').toLowerCase();
  if (gear == 'cardio_machine' || gear == 'cardio') return true;
  return RegExp(
    r'\b(treadmill|elliptical|bike|cycle|row(?:er|ing)?|climber|stair|ski(?:\s|-)?erg|assault bike|intervals?|incline walk)\b',
  ).hasMatch(name.toLowerCase());
}

bool _isBodyweightGymMove(String name, String? equipment) {
  final n = name.toLowerCase();
  final gear = (equipment ?? '').toLowerCase();
  if (RegExp(r'\b(dumbbell|barbell|kettlebell|machine|cable|smith|landmine)\b').hasMatch(n)) {
    return false;
  }
  if (gear == 'bodyweight') return true;
  return RegExp(
    r'\b(bodyweight|air squat|push-?ups?|plank|sit-?ups?|crunch|jumping jack|mountain climber|burpee)\b',
  ).hasMatch(n);
}

bool _isIsolationGymMove(String name) {
  return RegExp(
    r'\b(extension|curl|flye?s?|raise|kickback|pushdown|pullover|abduct|adduct|calf|shrug|pec deck|lateral|concentration|preacher)\b',
  ).hasMatch(name.toLowerCase());
}

/// Working load for a program move: cardio / bodyweight labels, or a kg window from level + body weight.
String suggestGymMoveWeight(
  String name, {
  String? level,
  double? bodyWeightKg,
  String? equipment,
  List<GymExercise> catalog = const [],
}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty || RegExp(r'^extra move$', caseSensitive: false).hasMatch(trimmed)) {
    return '';
  }
  final match = findExerciseMatch(trimmed, catalog);
  final gear = (equipment != null && equipment.isNotEmpty)
      ? equipment
      : (match?.equipment ?? inferCustomEquipment(trimmed));
  if (isCardioGymMove(trimmed, gear)) return 'easy pace';
  if (_isBodyweightGymMove(trimmed, gear)) return 'bodyweight';
  final band = _gymLoadBands[_gymLoadLevel(level)]!;
  final pct = _isIsolationGymMove(trimmed) ? band[0] : band[1];
  return _formatGymKgWindow(_gymLoadBodyKg(bodyWeightKg), pct[0], pct[1]);
}

/// Keep a typed load; otherwise follow the programmed/suggested weight for the selected move.
String nextGymMoveWeight(
  String name, {
  String? currentWeight,
  String? previousName,
  String? level,
  double? bodyWeightKg,
  String? equipment,
  List<GymExercise> catalog = const [],
}) {
  final suggested = suggestGymMoveWeight(
    name,
    level: level,
    bodyWeightKg: bodyWeightKg,
    equipment: equipment,
    catalog: catalog,
  );
  final current = (currentWeight ?? '').trim();
  if (current.isEmpty) return suggested;
  final previousSuggested = (previousName ?? '').trim().isEmpty
      ? ''
      : suggestGymMoveWeight(
          previousName!,
          level: level,
          bodyWeightKg: bodyWeightKg,
          equipment: equipment,
          catalog: catalog,
        );
  if (current == previousSuggested) return suggested;
  return current;
}

String suggestGymMoveSets(
  String name, {
  String? equipment,
  List<GymExercise> catalog = const [],
}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty || RegExp(r'^extra move$', caseSensitive: false).hasMatch(trimmed)) {
    return '3 x 10';
  }
  final match = findExerciseMatch(trimmed, catalog);
  final gear = (equipment != null && equipment.isNotEmpty) ? equipment : match?.equipment;
  if (!isCardioGymMove(trimmed, gear)) return '3 x 10';
  final secs = match?.durationSeconds ?? 0;
  final mins = secs >= 60 ? (secs / 60).round() : 10;
  return '${mins.clamp(5, 60)} mins';
}

String suggestGymMoveRest(
  String name, {
  String? equipment,
  List<GymExercise> catalog = const [],
}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty || RegExp(r'^extra move$', caseSensitive: false).hasMatch(trimmed)) {
    return '60s';
  }
  final match = findExerciseMatch(trimmed, catalog);
  final gear = (equipment != null && equipment.isNotEmpty) ? equipment : match?.equipment;
  return isCardioGymMove(trimmed, gear) ? '0s' : '60s';
}

({String sets, String rest, String weight}) nextGymMovePrescription(
  String name, {
  String? currentSets,
  String? currentRest,
  String? currentWeight,
  String? previousName,
  String? level,
  double? bodyWeightKg,
  String? equipment,
  List<GymExercise> catalog = const [],
}) {
  final nextCardio = isCardioGymMove(name, equipment);
  final prevCardio = (previousName ?? '').trim().isEmpty
      ? !nextCardio
      : isCardioGymMove(previousName!, equipment);
  final weight = nextCardio != prevCardio
      ? suggestGymMoveWeight(
          name,
          level: level,
          bodyWeightKg: bodyWeightKg,
          equipment: equipment,
          catalog: catalog,
        )
      : nextGymMoveWeight(
          name,
          currentWeight: currentWeight,
          previousName: previousName,
          level: level,
          bodyWeightKg: bodyWeightKg,
          equipment: equipment,
          catalog: catalog,
        );
  final prevSets = (previousName ?? '').trim().isEmpty
      ? ''
      : suggestGymMoveSets(previousName!, equipment: equipment, catalog: catalog);
  final prevRest = (previousName ?? '').trim().isEmpty
      ? ''
      : suggestGymMoveRest(previousName!, equipment: equipment, catalog: catalog);
  final setsNow = (currentSets ?? '').trim();
  final restNow = (currentRest ?? '').trim();
  final sets = setsNow.isEmpty ||
          setsNow == prevSets ||
          setsNow == '3 x 10' ||
          nextCardio != prevCardio
      ? suggestGymMoveSets(name, equipment: equipment, catalog: catalog)
      : setsNow;
  final rest = restNow.isEmpty ||
          restNow == prevRest ||
          restNow == '60s' ||
          restNow == '45s' ||
          nextCardio != prevCardio
      ? suggestGymMoveRest(name, equipment: equipment, catalog: catalog)
      : restNow;
  return (sets: sets, rest: rest, weight: weight);
}

String resolveSessionMoveWeight(
  String name, {
  String? programmedWeight,
  String? savedWeight,
  String? level,
  double? bodyWeightKg,
  List<GymExercise> catalog = const [],
}) {
  final saved = (savedWeight ?? '').trim();
  if (saved.isNotEmpty) return saved;
  final programmed = (programmedWeight ?? '').trim();
  if (programmed.isNotEmpty) return programmed;
  return suggestGymMoveWeight(
    name,
    level: level,
    bodyWeightKg: bodyWeightKg,
    catalog: catalog,
  );
}

/// Mirrors web sanitize for avoid targets (allowlist only).
List<String> sanitizeAvoidTargets(Iterable<String> input) {
  final allow = gymAvoidTargets.toSet();
  final seen = <String>{};
  final out = <String>[];
  for (final raw in input) {
    final target = raw.trim().toLowerCase().replaceAll(' ', '_');
    if (!allow.contains(target) || seen.contains(target)) continue;
    seen.add(target);
    out.add(target);
  }
  return out;
}

const legsMuscleGroups = {'legs', 'hamstrings', 'calves', 'inner_thighs'};

bool matchesMuscleFilter(String muscleGroup, String filter) {
  if (filter == 'all') return true;
  if (filter == 'legs') return legsMuscleGroups.contains(muscleGroup);
  return muscleGroup == filter;
}

/// Match an AI/plan exercise name to a catalog demo (exact, then loose contains).
GymExercise? findExerciseMatch(String name, List<GymExercise> exercises) {
  final needle = name.toLowerCase().trim();
  if (needle.isEmpty) return null;
  for (final item in exercises) {
    if (item.name.toLowerCase() == needle) return item;
  }
  for (final item in exercises) {
    final catalog = item.name.toLowerCase();
    if (needle.contains(catalog) || catalog.contains(needle)) return item;
  }
  final stripped = needle
      .replaceAll(RegExp(r'\b(machine|trainer|bike|climber)\b'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (stripped.isEmpty || stripped == needle) return null;
  for (final item in exercises) {
    final catalog = item.name.toLowerCase();
    final catalogStripped = catalog
        .replaceAll(RegExp(r'\b(machine|trainer)\b'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (catalog.contains(stripped) || stripped.contains(catalogStripped)) {
      return item;
    }
  }
  return null;
}

List<String> programRecommendations(Map<String, dynamic> plan) {
  final top = plan['recommendations'];
  if (top is List) {
    return top
        .map((e) => e.toString().trim())
        .where((e) => e.length >= 2)
        .take(8)
        .toList();
  }
  final days = plan['days'];
  if (days is List && days.isNotEmpty && days.first is Map) {
    final recs = Map<String, dynamic>.from(days.first as Map)['recommendations'];
    if (recs is List) {
      return recs
          .map((e) => e.toString().trim())
          .where((e) => e.length >= 2)
          .take(8)
          .toList();
    }
  }
  return const [];
}

String formatGymExerciseLine(Map<String, dynamic> ex) {
  final name = formatGymMoveName(ex['name']?.toString() ?? 'Movement');
  final sets = ex['sets']?.toString() ?? '';
  final rest = ex['rest']?.toString() ?? '';
  final weight = ex['weight']?.toString().trim() ?? '';
  final parts = <String>[
    name.isEmpty ? 'Movement' : name,
    if (sets.isNotEmpty) sets,
    if (weight.isNotEmpty) weight,
    if (rest.isNotEmpty) 'rest $rest',
  ];
  return parts.join(' · ');
}

List<Map<String, String>> dayAlternatives(Map<String, dynamic> day) {
  final raw = day['alternatives'];
  if (raw is! List) return const [];
  final out = <Map<String, String>>[];
  final seen = <String>{};
  for (final item in raw) {
    var insteadOf = '';
    var use = '';
    if (item is String) {
      final text = item.trim();
      final instead = RegExp(r'^(.+?)\s+instead of\s+(.+)$', caseSensitive: false)
          .firstMatch(text);
      final arrow = RegExp(r'^(.+?)\s*(?:→|->)\s*(.+)$').firstMatch(text);
      if (instead != null) {
        use = instead.group(1)!.trim();
        insteadOf = instead.group(2)!.trim();
      } else if (arrow != null) {
        insteadOf = arrow.group(1)!.trim();
        use = arrow.group(2)!.trim();
      }
    } else if (item is Map) {
      final row = Map<String, dynamic>.from(item);
      insteadOf = (row['instead_of'] ?? row['from'] ?? '').toString().trim();
      use = (row['use'] ?? row['to'] ?? row['name'] ?? '').toString().trim();
    }
    if (insteadOf.length < 2 || use.length < 2) continue;
    final key = '${insteadOf.toLowerCase()}=>${use.toLowerCase()}';
    if (seen.contains(key)) continue;
    seen.add(key);
    out.add({'instead_of': insteadOf, 'use': use});
    if (out.length >= 4) break;
  }
  return out;
}

List<Map<String, String>> dayAdditionals(Map<String, dynamic> day) {
  final raw = day['additionals'];
  if (raw is! List) return const [];
  final out = <Map<String, String>>[];
  final seen = <String>{};
  for (final item in raw) {
    var name = '';
    var sets = '';
    if (item is String) {
      name = item.trim();
    } else if (item is Map) {
      final row = Map<String, dynamic>.from(item);
      name = (row['name'] ?? row['use'] ?? '').toString().trim();
      sets = (row['sets'] ?? '').toString().trim();
    }
    if (name.length < 2) continue;
    final key = name.toLowerCase();
    if (seen.contains(key)) continue;
    seen.add(key);
    out.add({
      'name': name,
      if (sets.isNotEmpty) 'sets': sets,
    });
    if (out.length >= 4) break;
  }
  return out;
}

const _addonComplement = <String, List<String>>{
  'back': ['shoulders', 'arms', 'core'],
  'chest': ['arms', 'shoulders', 'core'],
  'shoulders': ['arms', 'core'],
  'traps': ['back', 'shoulders'],
  'arms': ['shoulders', 'core'],
  'forearms': ['arms'],
  'legs': ['calves', 'hamstrings', 'core', 'inner_thighs'],
  'hamstrings': ['calves', 'core', 'legs'],
  'inner_thighs': ['calves', 'core', 'legs'],
  'glutes': ['hamstrings', 'core'],
  'calves': ['core', 'legs'],
  'core': ['cardio'],
  'cardio': ['core', 'mobility'],
  'lower_back': ['core', 'hamstrings'],
  'full_body': ['core', 'cardio'],
  'mobility': ['core'],
};

String _addonSets(GymExercise item) {
  if (item.equipment == 'cardio_machine' || item.muscleGroup == 'cardio') {
    return '8–12 mins easy';
  }
  if (item.muscleGroup == 'core' || item.muscleGroup == 'mobility') {
    return '2 x 12-15';
  }
  return '2–3 x 12-15';
}

List<Map<String, dynamic>> enrichPlanDays(
  List<Map<String, dynamic>> days,
  List<GymExercise> catalog,
) {
  if (days.isEmpty) return days;
  final presented = [
    for (final day in days) _presentPlanDay(Map<String, dynamic>.from(day), catalog),
  ];
  if (catalog.isEmpty) return presented;
  return [
    for (final day in presented) _enrichPlanDay(Map<String, dynamic>.from(day), catalog),
  ];
}

Map<String, dynamic> _presentPlanDay(
  Map<String, dynamic> day,
  List<GymExercise> catalog,
) {
  final exercises = (day['exercises'] as List? ?? const [])
      .whereType<Map>()
      .map((raw) {
        final ex = Map<String, dynamic>.from(raw);
        final name = formatGymMoveName(ex['name']?.toString() ?? '');
        if (name.isNotEmpty) ex['name'] = name;
        final notes = ex['notes']?.toString().trim() ?? '';
        final match = findExerciseMatch(name, catalog);
        if (notes.isEmpty && match == null && name.isNotEmpty) {
          ex['notes'] = gymMoveDetails(name).cues;
        }
        return ex;
      })
      .toList();
  final alternatives = [
    for (final swap in dayAlternatives(day))
      {
        'instead_of': formatGymMoveName(swap['instead_of'] ?? ''),
        'use': formatGymMoveName(swap['use'] ?? ''),
      },
  ];
  final additionals = [
    for (final addon in dayAdditionals(day))
      {
        ...addon,
        'name': formatGymMoveName(addon['name'] ?? ''),
      },
  ];
  return {
    ...day,
    'exercises': exercises,
    if (alternatives.isNotEmpty) 'alternatives': alternatives,
    if (additionals.isNotEmpty) 'additionals': additionals,
  };
}

Map<String, dynamic> _enrichPlanDay(
  Map<String, dynamic> day,
  List<GymExercise> catalog,
) {
  final used = <String>{};
  for (final raw in (day['exercises'] as List? ?? const [])) {
    if (raw is Map) {
      final name = (raw['name'] ?? '').toString().toLowerCase();
      if (name.isNotEmpty) used.add(name);
    }
  }
  final alternatives = dayAlternatives(day);
  final additionals = dayAdditionals(day);
  for (final swap in alternatives) {
    used.add((swap['use'] ?? '').toLowerCase());
  }
  for (final addon in additionals) {
    used.add((addon['name'] ?? '').toLowerCase());
  }

  final exercises = (day['exercises'] as List? ?? const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  for (final ex in exercises) {
    if (alternatives.length >= 3) break;
    final name = ex['name']?.toString() ?? '';
    final match = findExerciseMatch(name, catalog);
    if (match == null) continue;
    final pool = catalog.where((item) {
      final key = item.name.toLowerCase();
      return item.muscleGroup == match.muscleGroup &&
          key != match.name.toLowerCase() &&
          !used.contains(key);
    }).toList();
    final swapped = pool.where((item) => item.equipment != match.equipment).toList();
    final pick = swapped.isNotEmpty ? swapped.first : (pool.isNotEmpty ? pool.first : null);
    if (pick == null) continue;
    used.add(pick.name.toLowerCase());
    alternatives.add({'instead_of': name, 'use': pick.name});
  }

  final dayMuscles = <String>[];
  for (final ex in exercises) {
    final match = findExerciseMatch(ex['name']?.toString() ?? '', catalog);
    if (match != null && !dayMuscles.contains(match.muscleGroup)) {
      dayMuscles.add(match.muscleGroup);
    }
  }
  final targets = <String>[];
  for (final muscle in dayMuscles) {
    for (final next in _addonComplement[muscle] ?? const <String>[]) {
      if (!targets.contains(next)) targets.add(next);
    }
  }
  for (final muscle in targets) {
    if (additionals.length >= 2) break;
    GymExercise? pick;
    for (final item in catalog) {
      if (item.muscleGroup == muscle && !used.contains(item.name.toLowerCase())) {
        pick = item;
        break;
      }
    }
    if (pick == null) continue;
    used.add(pick.name.toLowerCase());
    additionals.add({'name': pick.name, 'sets': _addonSets(pick)});
  }

  return {
    ...day,
    if (alternatives.isNotEmpty) 'alternatives': alternatives,
    if (additionals.isNotEmpty) 'additionals': additionals,
  };
}

IconData muscleIcon(String muscleGroup) {
  switch (muscleGroup) {
    case 'core':
      return Icons.accessibility_new_rounded;
    case 'cardio':
      return Icons.directions_run_rounded;
    case 'mobility':
      return Icons.self_improvement_rounded;
    case 'shoulders':
    case 'traps':
      return Icons.sports_gymnastics_rounded;
    case 'back':
    case 'lower_back':
      return Icons.airline_seat_recline_normal_rounded;
    case 'chest':
      return Icons.fitness_center_rounded;
    case 'arms':
    case 'forearms':
      return Icons.back_hand_outlined;
    case 'legs':
    case 'hamstrings':
    case 'calves':
    case 'inner_thighs':
    case 'glutes':
      return Icons.directions_walk_rounded;
    case 'full_body':
      return Icons.person_outline_rounded;
    default:
      return Icons.fitness_center_rounded;
  }
}

/// ISO weekdays: 1=Mon … 7=Sun. Mirrors viva-server `GYM_WEEKDAYS`.
const gymWeekdays = <({int iso, String short, String full})>[
  (iso: 1, short: 'Mon', full: 'Monday'),
  (iso: 2, short: 'Tue', full: 'Tuesday'),
  (iso: 3, short: 'Wed', full: 'Wednesday'),
  (iso: 4, short: 'Thu', full: 'Thursday'),
  (iso: 5, short: 'Fri', full: 'Friday'),
  (iso: 6, short: 'Sat', full: 'Saturday'),
  (iso: 7, short: 'Sun', full: 'Sunday'),
];

const sessionMinutePresets = <int>[30, 45, 60, 75, 90];

List<int> defaultTrainingDaysFromCount(int daysPerWeek) {
  final n = daysPerWeek.clamp(2, 6).toInt();
  if (n >= 6) return const [1, 2, 3, 4, 5, 7];
  if (n == 5) return const [1, 2, 3, 4, 5];
  if (n == 4) return const [1, 2, 4, 5];
  if (n == 3) return const [1, 3, 5];
  return const [2, 5];
}

List<int> sanitizeTrainingDays(Iterable<int> input, {int fallbackCount = 3}) {
  final seen = <int>{};
  final out = <int>[];
  for (final raw in input) {
    if (raw < 1 || raw > 7 || seen.contains(raw)) continue;
    seen.add(raw);
    out.add(raw);
    if (out.length >= 6) break;
  }
  out.sort();
  return out.length >= 2 ? out : defaultTrainingDaysFromCount(fallbackCount);
}

String formatRestDaysLabel(List<int> trainingDays) {
  final selected = trainingDays.toSet();
  final rest = gymWeekdays
      .where((item) => !selected.contains(item.iso))
      .map((item) => item.short)
      .toList();
  if (rest.isEmpty) return '';
  if (rest.length == 1) return 'Rest ${rest.first}';
  if (rest.length == 2) return 'Rest ${rest[0]} & ${rest[1]}';
  return 'Rest ${rest.sublist(0, rest.length - 1).join(', ')} & ${rest.last}';
}

String formatTrainingDaysLabel(List<int> days) {
  final sorted = sanitizeTrainingDays(days, fallbackCount: days.length);
  if (sorted.isEmpty) return '';
  if (sorted.length == 7) return 'Every day';
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final parts = <String>[];
  var start = sorted.first;
  var prev = sorted.first;
  void flush() {
    if (start == prev) {
      parts.add(names[start - 1]);
    } else if (prev - start == 1) {
      parts.add('${names[start - 1]}, ${names[prev - 1]}');
    } else {
      parts.add('${names[start - 1]}–${names[prev - 1]}');
    }
  }

  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i] == prev + 1) {
      prev = sorted[i];
      continue;
    }
    flush();
    start = prev = sorted[i];
  }
  flush();
  return parts.join(', ');
}

String? nextTrainingDayHint(List<int> trainingDays, [DateTime? date]) {
  final schedule = sanitizeTrainingDays(trainingDays, fallbackCount: trainingDays.length);
  if (schedule.isEmpty) return null;
  final now = date ?? DateTime.now();
  final todayIso = now.weekday;
  for (var offset = 1; offset <= 7; offset++) {
    final iso = ((todayIso - 1 + offset) % 7) + 1;
    if (!schedule.contains(iso)) continue;
    final name = gymWeekdays.firstWhere((item) => item.iso == iso).full;
    if (offset == 1) return 'Tomorrow';
    return name;
  }
  return null;
}

List<int> resolveTrainingDays({
  Iterable<int>? trainingDays,
  List<Map<String, dynamic>> days = const [],
  int? daysPerWeek,
}) {
  if (trainingDays != null) {
    final out = <int>[];
    for (final n in trainingDays) {
      if (n < 1 || n > 7 || out.contains(n)) continue;
      out.add(n);
    }
    out.sort();
    if (out.length >= 2) return out.take(6).toList();
  }
  final labeled = <int>[];
  for (final day in days) {
    final iso = weekdayIsoFromLabel(day['day']?.toString() ?? '');
    if (iso == null || labeled.contains(iso)) continue;
    labeled.add(iso);
  }
  labeled.sort();
  if (labeled.isNotEmpty) return labeled.take(6).toList();
  return defaultTrainingDaysFromCount(daysPerWeek ?? (days.isEmpty ? 3 : days.length));
}

int? weekdayIsoFromLabel(String label) {
  final raw = label.toLowerCase();
  if (raw.isEmpty) return null;
  final tokens = raw.split(RegExp(r'[\s,/:.-]+')).where((part) => part.isNotEmpty);
  for (final item in gymWeekdays) {
    if (raw.contains(item.full.toLowerCase()) || tokens.contains(item.short.toLowerCase())) {
      return item.iso;
    }
  }
  return null;
}

/// Pick the session that should show on Today.
/// Named weekdays and saved training_days are a calendar; rest days return null.
/// Mirrors viva-server `pickTodaysPlanDay`.
Map<String, dynamic>? pickTodaysPlanDay(
  List<Map<String, dynamic>> days, [
  DateTime? date,
  List<int>? trainingDays,
]) {
  if (days.isEmpty) return null;
  final now = date ?? DateTime.now();
  final iso = now.weekday; // DateTime: 1=Mon … 7=Sun
  final named = days.map((day) => weekdayIsoFromLabel(day['day']?.toString() ?? '')).toList();
  if (named.any((value) => value != null)) {
    final index = named.indexOf(iso);
    return index >= 0 ? days[index] : null;
  }
  final schedule = resolveTrainingDays(
    trainingDays: trainingDays,
    days: days,
    daysPerWeek: days.length,
  );
  final index = schedule.indexOf(iso);
  if (index < 0) return null;
  return index < days.length ? days[index] : null;
}

Map<String, dynamic>? findPlanDayByLabel(List<Map<String, dynamic>> days, String? label) {
  if (days.isEmpty || label == null) return null;
  final needle = label.trim().toLowerCase();
  if (needle.isEmpty) return null;
  for (final day in days) {
    if ((day['day']?.toString() ?? '').trim().toLowerCase() == needle) return day;
  }
  final iso = weekdayIsoFromLabel(needle);
  if (iso == null) return null;
  for (final day in days) {
    if (weekdayIsoFromLabel(day['day']?.toString() ?? '') == iso) return day;
  }
  return null;
}

Map<String, dynamic>? resolveSessionPlanDay(
  List<Map<String, dynamic>> days, {
  String? label,
  DateTime? date,
  List<int>? trainingDays,
}) {
  final labeled = findPlanDayByLabel(days, label);
  if (labeled != null) return labeled;
  return pickTodaysPlanDay(days, date, trainingDays);
}

List<int>? planTrainingDaysList(Map<String, dynamic>? plan) {
  final raw = plan?['training_days'];
  if (raw is! List) return null;
  return [
    for (final item in raw)
      if (item is num) item.round() else int.tryParse(item.toString()) ?? 0,
  ].where((n) => n >= 1 && n <= 7).toList();
}

int parseRestSeconds(String rest) {
  final raw = rest
      .toLowerCase()
      .replaceAll(RegExp(r'[–—]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (raw.isEmpty || raw == '-' || raw == 'none' || raw == 'no rest') return 0;
  if (RegExp(r'^0+(?:\s*(?:s|sec|secs|seconds|m|min|mins|minutes))?$').hasMatch(raw)) {
    return 0;
  }
  int clamp(num value) => value.round().clamp(0, 600);
  final match = RegExp(
    r'^(\d+(?:\.\d+)?)(?:\s*-\s*\d+(?:\.\d+)?)?\s*(m|min|mins|minutes|s|sec|secs|seconds)?\b',
  ).firstMatch(raw);
  if (match == null) return 60;
  final n = double.parse(match.group(1)!);
  final unit = match.group(2) ?? '';
  if (unit.startsWith('m')) return clamp(n * 60);
  return clamp(n);
}

int parseSetCount(String sets) {
  final raw = sets
      .toLowerCase()
      .replaceAll(RegExp(r'[–—]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (parseTimedMinutes(raw) != null &&
      !RegExp(r'(\d+)\s*[x×]').hasMatch(raw) &&
      !RegExp(r'(\d+)\s*sets?\b').hasMatch(raw)) {
    return 1;
  }
  final x = RegExp(r'(\d+)\s*[x×]').firstMatch(raw);
  if (x != null) return int.parse(x.group(1)!).clamp(1, 10);
  final word = RegExp(r'(\d+)\s*sets?\b').firstMatch(raw);
  if (word != null) return int.parse(word.group(1)!).clamp(1, 10);
  return 1;
}

int? parseTimedMinutes(String sets) {
  final raw = sets
      .toLowerCase()
      .replaceAll(RegExp(r'[–—]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (raw.isEmpty) return null;
  if (RegExp(r'(\d+)\s*[x×]').hasMatch(raw) && !RegExp(r'\b(m|min|mins|minutes)\b').hasMatch(raw)) {
    return null;
  }
  final match = RegExp(
    r'(\d+(?:\.\d+)?)(?:\s*-\s*\d+(?:\.\d+)?)?\s*(?:m|min|mins|minutes)\b',
  ).firstMatch(raw);
  if (match == null) return null;
  final n = double.tryParse(match.group(1)!);
  if (n == null || n <= 0) return null;
  return n.round().clamp(1, 180);
}

const gymSessionFocuses = <String>[
  'full_body',
  'strength',
  'fat_loss',
  'mobility',
  'endurance',
  'upper',
  'lower',
  'core',
];

String gymSessionFocusFromPlan(String focus) {
  final raw = focus
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final compact = raw.replaceAll(' ', '_');
  if (gymSessionFocuses.contains(compact)) return compact;
  if (RegExp(r'\b(upper|push|pull|chest|back|shoulder|arm)\b').hasMatch(raw)) {
    return 'upper';
  }
  if (RegExp(r'\b(lower|leg|glute|hamstring|calf|squat)\b').hasMatch(raw)) {
    return 'lower';
  }
  if (RegExp(r'\b(core|ab)\b').hasMatch(raw)) return 'core';
  if (RegExp(r'\b(cardio|endurance|hiit|run|bike)\b').hasMatch(raw)) {
    return 'endurance';
  }
  if (RegExp(r'\b(mobilit|stretch|yoga)\b').hasMatch(raw)) return 'mobility';
  if (RegExp(r'\b(fat|cut|loss)\b').hasMatch(raw)) return 'fat_loss';
  if (RegExp(r'\b(strength|hypertrophy|power)\b').hasMatch(raw)) return 'strength';
  return 'full_body';
}

String formatRestClock(int totalSeconds) {
  final s = totalSeconds.clamp(0, 10800);
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}

const gymProgramDraftKey = 'vivrant.gym.programDraft.v1';
const gymLiveSessionKey = 'vivrant.gym.liveSession.v2';

Map<String, dynamic> keptDaysMap(Map<String, dynamic>? draft) {
  final raw = draft?['kept_days'];
  if (raw is! Map) return {};
  return raw.map((key, value) => MapEntry(key.toString(), value));
}

List<int> keptIsoList(Map<String, dynamic>? draft) {
  final out = <int>[];
  for (final key in keptDaysMap(draft).keys) {
    final iso = int.tryParse(key) ?? 0;
    if (iso >= 1 && iso <= 7 && !out.contains(iso)) out.add(iso);
  }
  out.sort();
  return out;
}

List<int> remainingTrainingDays(List<int> trainingDays, Map<String, dynamic>? draft) {
  final kept = keptIsoList(draft).toSet();
  return trainingDays.where((iso) => !kept.contains(iso)).toList();
}

Map<String, dynamic> stampDayWeekday(Map<String, dynamic> day, int iso) {
  final weekday = gymWeekdays.firstWhere(
    (item) => item.iso == iso,
    orElse: () => (iso: iso, short: 'Day', full: 'Day $iso'),
  );
  final focus = humanizeLabel(day['focus']?.toString() ?? '');
  final label = '${weekday.full} · ${focus.isEmpty ? 'Training' : focus}';
  return {
    ...day,
    'day': label.length > 40 ? label.substring(0, 40) : label,
  };
}

Map<String, dynamic> emptyPlanExercise() => {
      'name': '',
      'sets': '3 x 10',
      'rest': '60s',
    };

List<Map<String, dynamic>> clonePlanDays(List<Map<String, dynamic>> days) {
  return [
    for (final day in days)
      {
        ...day,
        'exercises': [
          for (final ex in (day['exercises'] as List? ?? const []))
            if (ex is Map) Map<String, dynamic>.from(ex),
        ],
      },
  ];
}

/// Move a saved program day onto another weekday, swapping if that slot is taken.
List<Map<String, dynamic>> moveSavedPlanDay(
  List<Map<String, dynamic>> days,
  int fromIndex,
  int toIso,
) {
  if (fromIndex < 0 || fromIndex >= days.length || toIso < 1 || toIso > 7) {
    return days;
  }
  final next = clonePlanDays(days);
  final fromIso = weekdayIsoFromLabel(next[fromIndex]['day']?.toString() ?? '');
  if (fromIso == toIso) return next;
  final toIndex = next.indexWhere(
    (day) => weekdayIsoFromLabel(day['day']?.toString() ?? '') == toIso,
  );
  next[fromIndex] = stampDayWeekday(next[fromIndex], toIso);
  if (toIndex >= 0 && toIndex != fromIndex && fromIso != null) {
    next[toIndex] = stampDayWeekday(next[toIndex], fromIso);
  }
  next.sort((a, b) {
    final ia = weekdayIsoFromLabel(a['day']?.toString() ?? '') ?? 99;
    final ib = weekdayIsoFromLabel(b['day']?.toString() ?? '') ?? 99;
    return ia.compareTo(ib);
  });
  return next;
}

List<int> trainingDaysFromSavedDays(
  List<Map<String, dynamic>> days, [
  List<int>? fallback,
]) {
  final labeled = <int>[];
  for (final day in days) {
    final iso = weekdayIsoFromLabel(day['day']?.toString() ?? '');
    if (iso != null && !labeled.contains(iso)) labeled.add(iso);
  }
  if (labeled.isNotEmpty) {
    return sanitizeTrainingDays(labeled, fallbackCount: labeled.length);
  }
  return sanitizeTrainingDays(
    fallback ?? const [],
    fallbackCount: days.isEmpty ? 3 : days.length,
  );
}

/// Swap or move a kept workout onto another weekday slot.
Map<String, dynamic> moveKeptDayOnDraft(
  Map<String, dynamic> draft,
  int fromIso,
  int toIso,
) {
  if (fromIso == toIso) return draft;
  final kept = Map<String, dynamic>.from(keptDaysMap(draft));
  final fromDay = kept['$fromIso'];
  if (fromDay is! Map) return draft;
  final toDay = kept['$toIso'];
  kept['$toIso'] = stampDayWeekday(Map<String, dynamic>.from(fromDay), toIso);
  if (toDay is Map) {
    kept['$fromIso'] = stampDayWeekday(Map<String, dynamic>.from(toDay), fromIso);
  } else {
    kept.remove('$fromIso');
  }
  return {...draft, 'kept_days': kept};
}

Map<String, dynamic> _clonePlanDay(Map<String, dynamic> day) {
  return Map<String, dynamic>.from(day);
}

/// Start a draft week from a saved program.
Map<String, dynamic> draftFromSavedPlan(
  Map<String, dynamic> plan, {
  List<int>? trainingDays,
}) {
  final days = [
    for (final raw in (plan['days'] as List? ?? const []))
      if (raw is Map) Map<String, dynamic>.from(raw),
  ];
  final labeled = [
    for (final day in days)
      if (weekdayIsoFromLabel(day['day']?.toString() ?? '') != null)
        weekdayIsoFromLabel(day['day']!.toString())!,
  ];
  final schedule = sanitizeTrainingDays(
    (plan['training_days'] as List?)?.map((item) => (item as num).toInt()) ?? labeled,
    fallbackCount: days.isEmpty ? 3 : days.length,
  );
  final kept = <String, dynamic>{};
  for (var i = 0; i < days.length; i++) {
    final iso = weekdayIsoFromLabel(days[i]['day']?.toString() ?? '') ??
        (i < schedule.length ? schedule[i] : null);
    if (iso == null) continue;
    kept['$iso'] = stampDayWeekday(_clonePlanDay(days[i]), iso);
  }
  return {
    ...plan,
    'preview_days': <Map<String, dynamic>>[],
    'kept_days': kept,
    'training_days': trainingDays?.isNotEmpty == true ? trainingDays : schedule,
  };
}

/// Copy saved-program days onto a draft. `fill` skips occupied weekdays.
Map<String, dynamic> mergePlanDaysIntoDraft(
  Map<String, dynamic> draft,
  List<Map<String, dynamic>> days, {
  bool overwrite = false,
}) {
  final next = Map<String, dynamic>.from(keptDaysMap(draft));
  var training = [
    for (final raw in (draft['training_days'] as List? ?? const []))
      if (raw is num) raw.toInt(),
  ];
  if (training.isEmpty) training = sanitizeTrainingDays(const []);

  int? firstEmpty() {
    for (final slot in training) {
      if (next['$slot'] == null) return slot;
    }
    return null;
  }

  for (final raw in days) {
    final day = Map<String, dynamic>.from(raw);
    var iso = weekdayIsoFromLabel(day['day']?.toString() ?? '') ?? firstEmpty();
    if (iso == null) continue;
    if (!training.contains(iso)) {
      if (training.length >= 6) {
        iso = firstEmpty();
        if (iso == null) continue;
      } else {
        training = [...training, iso]..sort();
      }
    }
    if (!overwrite && next['$iso'] != null) continue;
    next['$iso'] = stampDayWeekday(day, iso);
  }

  return {
    ...draft,
    'kept_days': next,
    'training_days': training,
  };
}

/// Reorder moves inside a generated preview day.
Map<String, dynamic> reorderPreviewExercisesOnDraft(
  Map<String, dynamic> draft,
  int dayIndex,
  int from,
  int to,
) {
  final preview = [
    for (final raw in (draft['preview_days'] as List? ?? const []))
      if (raw is Map) Map<String, dynamic>.from(raw),
  ];
  if (dayIndex < 0 || dayIndex >= preview.length) return draft;
  final exercises = [
    for (final raw in (preview[dayIndex]['exercises'] as List? ?? const []))
      if (raw is Map) Map<String, dynamic>.from(raw),
  ];
  if (from < 0 || to < 0 || from >= exercises.length || to >= exercises.length || from == to) {
    return draft;
  }
  final moved = exercises.removeAt(from);
  exercises.insert(to, moved);
  preview[dayIndex] = {...preview[dayIndex], 'exercises': exercises};
  return {...draft, 'preview_days': preview};
}

int restRemainingSeconds(int? restEndsAtMs, [DateTime? now]) {
  if (restEndsAtMs == null || restEndsAtMs <= 0) return 0;
  final left = restEndsAtMs - (now ?? DateTime.now()).millisecondsSinceEpoch;
  if (left <= 0) return 0;
  return ((left + 999) / 1000).floor();
}

int restEndsAtFromSeconds(int remaining, [DateTime? now]) {
  return (now ?? DateTime.now()).millisecondsSinceEpoch + remaining.clamp(0, 10800) * 1000;
}

String todaySessionDate([DateTime? date]) {
  final now = date ?? DateTime.now();
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '${now.year}-$m-$d';
}

Color difficultyColor(String difficulty, {Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  switch (difficulty.toLowerCase()) {
    case 'beginner':
      return Color(dark ? 0xFF3DB896 : 0xFF0E7C66);
    case 'intermediate':
      return Color(dark ? 0xFFFDB022 : 0xFFB45309);
    case 'advanced':
      return Color(dark ? 0xFFF97066 : 0xFFB42318);
    default:
      return Color(dark ? 0xFFC5D4CB : 0xFF4A5C54);
  }
}
