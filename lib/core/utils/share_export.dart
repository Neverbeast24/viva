import 'dart:convert';

import '../../shared/models/models.dart';
import '../../features/gym/data/gym_labels.dart';

/// Builds shareable text / CSV / JSON documents for lists and gym programs.
///
/// Gym-specific formatters import `gym_labels.dart` because they need the same
/// muscle / equipment vocabulary as the gym UI. Generic CSV helpers stay here.

class ShareExportDoc {
  const ShareExportDoc({
    required this.title,
    required this.filename,
    required this.text,
    required this.csv,
    required this.json,
  });

  final String title;
  final String filename;
  final String text;
  final String csv;
  final String json;
}

String csvEscape(Object? value) {
  final raw = value?.toString() ?? '';
  if (RegExp(r'["\n\r,]').hasMatch(raw)) {
    return '"${raw.replaceAll('"', '""')}"';
  }
  return raw;
}

String toCsv(List<List<Object?>> rows) =>
    rows.map((row) => row.map(csvEscape).join(',')).join('\n');

String filenameSlug(String title) {
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) return 'vivrant-export';
  return slug.length > 60 ? slug.substring(0, 60) : slug;
}

String _jsonEncode(Object? value) {
  return '${const JsonEncoder.withIndent('  ').convert(value)}\n';
}

String _heading(String title, List<String> lines) {
  return '${['VIVRΛNT', title, '', ...lines].join('\n').trimRight()}\n';
}

ShareExportDoc gymPlanDoc(Map<String, dynamic> plan) {
  final title = plan['title']?.toString() ?? 'Training program';
  final focus = humanizeLabel(plan['focus']?.toString() ?? '');
  final level = plan['level']?.toString() ?? '';
  final daysPerWeek = plan['days_per_week'] ??
      ((plan['days'] is List) ? (plan['days'] as List).length : '');
  const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final trainingDays = (plan['training_days'] as List? ?? const [])
      .whereType<num>()
      .map((n) => n.round())
      .where((n) => n >= 1 && n <= 7)
      .toSet()
      .toList()
    ..sort();
  final schedule = trainingDays.isEmpty
      ? '$daysPerWeek days/week'
      : trainingDays.map((n) => weekdayShort[n - 1]).join(', ');
  final summary = plan['summary']?.toString();
  final recs = (plan['recommendations'] as List? ?? const [])
      .map((e) => e.toString().trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final days = (plan['days'] as List? ?? const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  if (recs.isEmpty && days.isNotEmpty) {
    recs.addAll(
      (days.first['recommendations'] as List? ?? const [])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty),
    );
  }

  final lines = <String>[
    title,
    '$focus · $level · $schedule',
    if (summary != null && summary.isNotEmpty) '',
    if (summary != null && summary.isNotEmpty) summary,
    if (recs.isNotEmpty) '',
    if (recs.isNotEmpty) 'Coach notes',
    ...recs.map((rec) => '• $rec'),
    '',
  ];
  final csvRows = <List<Object?>>[
    ['Day', 'Focus', 'Exercise', 'Sets', 'Weight', 'Rest', 'Notes'],
  ];
  for (final day in days) {
    final dayLabel = day['day']?.toString() ?? 'Day';
    final dayFocus = humanizeLabel(day['focus']?.toString() ?? '');
    lines.add('$dayLabel — $dayFocus');
    final exercises = (day['exercises'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e));
    for (final ex in exercises) {
      final name = displayGymMoveName(ex['name']?.toString());
      final sets = ex['sets']?.toString() ?? '';
      final weight = ex['weight']?.toString() ?? '';
      final rest = ex['rest']?.toString() ?? '';
      final notes = ex['notes']?.toString() ?? '';
      final extras = [
        sets,
        if (weight.isNotEmpty) weight,
        'rest $rest',
        if (notes.isNotEmpty) notes,
      ].join(' · ');
      lines.add('• $name · $extras');
      csvRows.add([dayLabel, dayFocus, name, sets, weight, rest, notes]);
    }
    final alts = day['alternatives'];
    if (alts is List) {
      for (final item in alts.whereType<Map>()) {
        final row = Map<String, dynamic>.from(item);
        final insteadOf = (row['instead_of'] ?? '').toString();
        final use = (row['use'] ?? '').toString();
        if (insteadOf.isEmpty && use.isEmpty) continue;
        lines.add('  Alternative: $use instead of $insteadOf');
      }
    }
    final adds = day['additionals'];
    if (adds is List) {
      for (final item in adds.whereType<Map>()) {
        final row = Map<String, dynamic>.from(item);
        final name = (row['name'] ?? '').toString();
        final sets = (row['sets'] ?? '').toString();
        if (name.isEmpty) continue;
        lines.add('  Add-on: $name${sets.isNotEmpty ? ' · $sets' : ''}');
      }
    }
    lines.add('');
  }

  return ShareExportDoc(
    title: title,
    filename: filenameSlug(title),
    text: _heading(title, lines),
    csv: toCsv(csvRows),
    json: _jsonEncode({
      'title': title,
      'focus': plan['focus'],
      'level': plan['level'],
      'days_per_week': daysPerWeek,
      'training_days': trainingDays,
      'summary': summary,
      'recommendations': recs,
      'days': days,
    }),
  );
}

ShareExportDoc gymProgramDraftDoc(Map<String, dynamic> draft) {
  final keptRaw = draft['kept_days'];
  final kept = keptRaw is Map
      ? keptRaw.map((key, value) => MapEntry(key.toString(), value))
      : <String, dynamic>{};
  final trainingDays = (draft['training_days'] as List? ?? const [])
      .whereType<num>()
      .map((n) => n.round())
      .where((n) => n >= 1 && n <= 7)
      .toList()
    ..sort();
  final keptIsos = kept.keys.map((k) => int.tryParse(k) ?? 0).where((n) => n >= 1 && n <= 7).toList()
    ..sort();
  const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final remaining = trainingDays.where((iso) => !keptIsos.contains(iso)).toList();
  final remainingLabel = remaining.map((iso) => weekdayShort[iso - 1]).join(', ');
  final keptDays = [
    for (final iso in keptIsos)
      if (kept['$iso'] is Map) Map<String, dynamic>.from(kept['$iso'] as Map),
  ];
  final keptPlan = {
    ...draft,
    'title': '${draft['title'] ?? 'Training program'} — days you kept',
    'days': keptDays,
    'training_days': keptIsos,
    'days_per_week': keptIsos.length,
  };
  final keptDoc = gymPlanDoc(keptPlan);
  final preview = (draft['preview_days'] as List? ?? const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e));
  final previewLines = <String>[
    remaining.isEmpty ? 'All training days kept.' : 'Still to pick: $remainingLabel',
    '',
    keptDoc.text.trimRight(),
    '',
    'Latest generated options',
    '',
  ];
  for (final day in preview) {
    previewLines.add('${day['day'] ?? 'Day'} — ${humanizeLabel(day['focus']?.toString() ?? '')}');
    final exercises = (day['exercises'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e));
    for (final ex in exercises) {
      previewLines.add('• ${ex['name'] ?? 'Movement'} · ${ex['sets'] ?? ''} · rest ${ex['rest'] ?? ''}');
    }
    previewLines.add('');
  }
  return ShareExportDoc(
    title: '${draft['title'] ?? 'Training program'} (in progress)',
    filename: filenameSlug('${draft['title'] ?? 'program'}-draft'),
    text: _heading('${draft['title'] ?? 'Training program'} (in progress)', previewLines),
    csv: keptDoc.csv,
    json: _jsonEncode({
      'title': draft['title'],
      'focus': draft['focus'],
      'level': draft['level'],
      'training_days': trainingDays,
      'kept_days': kept,
      'preview_days': draft['preview_days'],
      'remaining_days': remaining,
    }),
  );
}

ShareExportDoc gymPlansDoc(List<Map<String, dynamic>> plans) {
  if (plans.length == 1) return gymPlanDoc(plans.first);
  final parts = plans.map((p) => gymPlanDoc(p).text.trimRight()).join('\n\n---\n\n');
  final csvRows = <List<Object?>>[
    ['Program', 'Day', 'Focus', 'Exercise', 'Sets', 'Weight', 'Rest', 'Notes'],
  ];
  for (final plan in plans) {
    final title = plan['title']?.toString() ?? 'Program';
    final days = (plan['days'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e));
    for (final day in days) {
      final exercises = (day['exercises'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e));
      for (final ex in exercises) {
        csvRows.add([
          title,
          day['day'],
          humanizeLabel(day['focus']?.toString() ?? ''),
          displayGymMoveName(ex['name']?.toString()),
          ex['sets'],
          ex['weight'] ?? '',
          ex['rest'],
          ex['notes'] ?? '',
        ]);
      }
    }
  }
  return ShareExportDoc(
    title: 'Saved training programs',
    filename: 'vivrant-training-programs',
    text: _heading('Saved training programs', [parts]),
    csv: toCsv(csvRows),
    json: _jsonEncode(plans),
  );
}

ShareExportDoc gymSessionsDoc(List<GymSession> sessions) {
  final lines = <String>[];
  for (final session in sessions) {
    lines.add(
      '${session.title} · ${humanizeLabel(session.focus ?? '')} · ${session.durationMinutes ?? 0} min · ${session.caloriesBurned ?? 0} kcal',
    );
    if (session.loggedAt != null) {
      lines.add('Logged ${session.loggedAt!.toIso8601String().substring(0, 10)}');
    }
    for (final ex in session.exercises) {
      final name = displayGymMoveName(ex['name']?.toString());
      final sets = ex['sets']?.toString();
      lines.add('  • $name${sets != null && sets.isNotEmpty ? ' · $sets' : ''}');
    }
    if (session.notes != null && session.notes!.isNotEmpty) {
      lines.add('Notes: ${session.notes}');
    }
    lines.add('');
  }
  return ShareExportDoc(
    title: 'Gym workouts',
    filename: 'vivrant-gym-workouts',
    text: _heading('Gym workouts', lines),
    csv: toCsv([
      ['Title', 'Focus', 'Minutes', 'Calories', 'Exercises', 'Notes', 'Logged'],
      ...sessions.map(
        (s) => [
          s.title,
          s.focus ?? '',
          s.durationMinutes ?? '',
          s.caloriesBurned ?? '',
          s.exercises
              .map((e) => '${e['name'] ?? ''}${e['sets'] != null ? ' (${e['sets']})' : ''}')
              .join('; '),
          s.notes ?? '',
          s.loggedAt?.toIso8601String().substring(0, 10) ?? '',
        ],
      ),
    ]),
    json: _jsonEncode(
      sessions
          .map(
            (s) => {
              'title': s.title,
              'focus': s.focus,
              'duration_minutes': s.durationMinutes,
              'calories_burned': s.caloriesBurned,
              'exercises': s.exercises,
              'notes': s.notes,
              'logged_at': s.loggedAt?.toIso8601String(),
            },
          )
          .toList(),
    ),
  );
}

ShareExportDoc groceryListDoc(List<GroceryItem> items) {
  final lines = items.map((item) {
    final qty = item.quantity != null && item.quantity!.isNotEmpty
        ? ' (${item.quantity})'
        : '';
    final price = item.estimatedPrice != null
        ? ' · ₱${item.estimatedPrice!.toStringAsFixed(0)}'
        : '';
    final done = item.isChecked ? '[x]' : '[ ]';
    return '$done ${item.name}$qty$price';
  }).toList();
  return ShareExportDoc(
    title: 'Shopping list',
    filename: 'vivrant-shopping-list',
    text: _heading('Shopping list', lines),
    csv: toCsv([
      ['Name', 'Quantity', 'Category', 'Checked', 'Estimated price'],
      ...items.map(
        (item) => [
          item.name,
          item.quantity ?? '',
          item.category,
          item.isChecked ? 'yes' : 'no',
          item.estimatedPrice ?? '',
        ],
      ),
    ]),
    json: _jsonEncode(
      items
          .map(
            (item) => {
              'name': item.name,
              'quantity': item.quantity,
              'category': item.category,
              'is_checked': item.isChecked,
              'estimated_price': item.estimatedPrice,
            },
          )
          .toList(),
    ),
  );
}

ShareExportDoc groceryPlanDoc(Map<String, dynamic> plan) {
  final title = plan['title']?.toString().trim().isNotEmpty == true
      ? plan['title'].toString()
      : 'Grocery plan';
  final summary = plan['summary']?.toString() ?? '';
  final budgetNote = plan['budget_note']?.toString() ?? '';
  final estimatedTotal = plan['estimated_total'];
  final meals = (plan['meals'] as List? ?? const [])
      .map((e) => e.toString().trim())
      .where((e) => e.isNotEmpty)
      .toList();
  final items = (plan['items'] as List? ?? const [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  final totalText = estimatedTotal == null
      ? ''
      : 'Estimated total: ₱${(estimatedTotal is num) ? estimatedTotal.round() : estimatedTotal}';
  final lines = [
    summary,
    if (budgetNote.isNotEmpty) 'Budget: $budgetNote',
    if (totalText.isNotEmpty) totalText,
    '',
    if (meals.isNotEmpty) ...['Meals', ...meals.map((meal) => '• $meal'), ''],
    'Items',
    ...items.map((item) {
      final qty = item['quantity']?.toString().trim();
      final qtyText = qty != null && qty.isNotEmpty ? ' ($qty)' : '';
      final price = item['estimated_price'];
      final priceText = price == null
          ? ''
          : ' · ₱${price is num ? price.round() : price}';
      return '• ${item['name'] ?? 'Item'}$qtyText$priceText';
    }),
  ];
  return ShareExportDoc(
    title: title,
    filename: filenameSlug(title),
    text: _heading(title, lines),
    csv: toCsv([
      ['Name', 'Quantity', 'Category', 'Estimated price'],
      ...items.map(
        (item) => [
          item['name'] ?? '',
          item['quantity'] ?? '',
          item['category'] ?? '',
          item['estimated_price'] ?? '',
        ],
      ),
    ]),
    json: _jsonEncode(plan),
  );
}

ShareExportDoc mealsDoc(List<NutritionLog> meals) {
  final lines = meals
      .map(
        (m) =>
            '${m.loggedAt.toIso8601String().substring(0, 10)} · ${m.mealType} · ${m.mealName} · ~${m.calories ?? 0} kcal',
      )
      .toList();
  return ShareExportDoc(
    title: 'Meal log',
    filename: 'vivrant-meals',
    text: _heading('Meal log', lines),
    csv: toCsv([
      ['Date', 'Type', 'Meal', 'Calories', 'Protein g', 'Carbs g', 'Fat g'],
      ...meals.map(
        (m) => [
          m.loggedAt.toIso8601String().substring(0, 10),
          m.mealType,
          m.mealName,
          m.calories ?? '',
          m.proteinG ?? '',
          m.carbsG ?? '',
          m.fatG ?? '',
        ],
      ),
    ]),
    json: _jsonEncode(
      meals
          .map(
            (m) => {
              'meal_name': m.mealName,
              'meal_type': m.mealType,
              'calories': m.calories,
              'protein_g': m.proteinG,
              'carbs_g': m.carbsG,
              'fat_g': m.fatG,
              'logged_at': m.loggedAt.toIso8601String(),
            },
          )
          .toList(),
    ),
  );
}

ShareExportDoc expensesDoc(List<Expense> expenses) {
  final total = expenses.fold<double>(0, (s, e) => s + e.amount);
  final lines = [
    ...expenses.map(
      (e) =>
          '${e.spentAt.toIso8601String().substring(0, 10)} · ${e.title} · ${humanizeLabel(e.category)} · ₱${e.amount.toStringAsFixed(0)}',
    ),
    '',
    'Total: ₱${total.toStringAsFixed(0)}',
  ];
  return ShareExportDoc(
    title: 'Health spending',
    filename: 'vivrant-expenses',
    text: _heading('Health spending', lines),
    csv: toCsv([
      ['Date', 'Title', 'Category', 'Amount'],
      ...expenses.map(
        (e) => [
          e.spentAt.toIso8601String().substring(0, 10),
          e.title,
          e.category,
          e.amount,
        ],
      ),
    ]),
    json: _jsonEncode(
      expenses
          .map(
            (e) => {
              'title': e.title,
              'category': e.category,
              'amount': e.amount,
              'spent_at': e.spentAt.toIso8601String(),
            },
          )
          .toList(),
    ),
  );
}

ShareExportDoc journalEntriesDoc(List<JournalEntry> entries) {
  final lines = entries
      .map(
        (e) => [
          e.title?.isNotEmpty == true ? e.title! : 'Journal note',
          e.entryDate,
          if (e.mood != null) 'Mood: ${e.mood}/5',
          '',
          e.body,
          '',
          '---',
          '',
        ].join('\n'),
      )
      .toList();
  return ShareExportDoc(
    title: 'Journal notes',
    filename: 'vivrant-journal',
    text: _heading('Journal notes', lines),
    csv: toCsv([
      ['Date', 'Title', 'Mood', 'Body'],
      ...entries.map((e) => [e.entryDate, e.title ?? '', e.mood ?? '', e.body]),
    ]),
    json: _jsonEncode(
      entries
          .map(
            (e) => {
              'title': e.title,
              'entry_date': e.entryDate,
              'mood': e.mood,
              'body': e.body,
            },
          )
          .toList(),
    ),
  );
}

ShareExportDoc journalNoteDoc(JournalEntry entry) => journalEntriesDoc([entry]);

ShareExportDoc reportsDoc(Map<String, dynamic> data, {String? story}) {
  final calories = data['calories'] ?? 0;
  final protein = data['protein_g'] ?? 0;
  final meals = data['meals'] ?? 0;
  final workouts = data['workouts'] ?? 0;
  final workoutMinutes = data['workout_minutes'] ?? 0;
  final steps = data['steps'] ?? 0;
  final water = data['water_ml'] ?? 0;
  final spend = data['spend'] ?? 0;
  final checkins = data['checkins'] ?? 0;
  final lines = [
    'Calories: $calories',
    'Protein: ${protein}g',
    'Meals: $meals',
    'Workouts: $workouts · $workoutMinutes min',
    'Steps: $steps',
    'Water: $water ml',
    'Health spend: ₱$spend',
    'Check-ins: $checkins',
    if (story != null && story.isNotEmpty) ...['', 'Weekly summary', story],
  ];
  return ShareExportDoc(
    title: 'Weekly summary',
    filename: 'vivrant-weekly-summary',
    text: _heading('Weekly summary', lines),
    csv: toCsv([
      ['Metric', 'Value'],
      ['Calories', calories],
      ['Protein g', protein],
      ['Meals', meals],
      ['Workouts', workouts],
      ['Workout minutes', workoutMinutes],
      ['Steps', steps],
      ['Water ml', water],
      ['Health spend', spend],
      ['Check-ins', checkins],
      if (story != null) ['Story', story],
    ]),
    json: _jsonEncode({...data, if (story != null) 'story': story}),
  );
}

ShareExportDoc pantryDoc(List<PantryItem> items) {
  final lines = items
      .map((i) => '${i.name} · ${humanizeLabel(i.category)} · stock ${i.stockLevel}%')
      .toList();
  return ShareExportDoc(
    title: 'Pantry inventory',
    filename: 'vivrant-pantry',
    text: _heading('Pantry inventory', lines),
    csv: toCsv([
      ['Name', 'Category', 'Stock %'],
      ...items.map((i) => [i.name, i.category, i.stockLevel]),
    ]),
    json: _jsonEncode(
      items
          .map(
            (i) => {
              'name': i.name,
              'category': i.category,
              'stock_level': i.stockLevel,
            },
          )
          .toList(),
    ),
  );
}

ShareExportDoc goalsDoc(List<HealthGoal> goals) {
  final lines = goals.map((g) {
    final unit = g.unit != null && g.unit!.isNotEmpty ? ' ${g.unit}' : '';
    final target = g.targetValue != null ? ' → ${g.targetValue}$unit' : '';
    return '${g.title} · ${g.status} · ${g.currentValue ?? 0}$unit$target';
  }).toList();
  return ShareExportDoc(
    title: 'Health goals',
    filename: 'vivrant-goals',
    text: _heading('Health goals', lines),
    csv: toCsv([
      ['Title', 'Category', 'Current', 'Target', 'Unit', 'Date', 'Status'],
      ...goals.map(
        (g) => [
          g.title,
          g.category,
          g.currentValue ?? '',
          g.targetValue ?? '',
          g.unit ?? '',
          g.targetDate ?? '',
          g.status,
        ],
      ),
    ]),
    json: _jsonEncode(
      goals
          .map(
            (g) => {
              'title': g.title,
              'category': g.category,
              'current_value': g.currentValue,
              'target_value': g.targetValue,
              'unit': g.unit,
              'target_date': g.targetDate,
              'status': g.status,
            },
          )
          .toList(),
    ),
  );
}

ShareExportDoc movementWorkoutsDoc(List<WorkoutLog> workouts) {
  final lines = workouts
      .map(
        (w) =>
            '${w.title} · ${humanizeLabel(w.activityType)} · ${w.durationMinutes ?? 0} min · ${w.caloriesBurned ?? 0} kcal',
      )
      .toList();
  return ShareExportDoc(
    title: 'Activity log',
    filename: 'vivrant-activity',
    text: _heading('Activity log', lines),
    csv: toCsv([
      ['Title', 'Type', 'Minutes', 'Calories', 'Logged'],
      ...workouts.map(
        (w) => [
          w.title,
          w.activityType,
          w.durationMinutes ?? '',
          w.caloriesBurned ?? '',
          w.loggedAt.toIso8601String().substring(0, 10),
        ],
      ),
    ]),
    json: _jsonEncode(
      workouts
          .map(
            (w) => {
              'title': w.title,
              'activity_type': w.activityType,
              'duration_minutes': w.durationMinutes,
              'calories_burned': w.caloriesBurned,
              'logged_at': w.loggedAt.toIso8601String(),
            },
          )
          .toList(),
    ),
  );
}

ShareExportDoc healthHistoryDoc(List<Map<String, dynamic>> entries) {
  final lines = entries.map((e) {
    final date = (e['recorded_at'] ?? e['date'] ?? '').toString();
    final weight = e['weight_kg'];
    final note = e['note'];
    return [
      date.length >= 10 ? date.substring(0, 10) : date,
      if (weight != null) '$weight kg',
      if (note != null && note.toString().isNotEmpty) note.toString(),
    ].join(' · ');
  }).toList();
  return ShareExportDoc(
    title: 'Health history',
    filename: 'vivrant-health-history',
    text: _heading('Health history', lines),
    csv: toCsv([
      ['Date', 'Weight kg', 'Height cm', 'Body fat %', 'Waist cm', 'Note'],
      ...entries.map(
        (e) => [
          e['recorded_at'] ?? e['date'] ?? '',
          e['weight_kg'] ?? '',
          e['height_cm'] ?? '',
          e['body_fat_pct'] ?? '',
          e['waist_cm'] ?? '',
          e['note'] ?? '',
        ],
      ),
    ]),
    json: _jsonEncode(entries),
  );
}
