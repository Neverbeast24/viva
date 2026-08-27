import 'package:flutter/material.dart';

import '../../../../core/widgets/widgets.dart';
import '../../../../shared/models/gym_exercise.dart';
import '../../data/gym_labels.dart';
import 'gym_move_picker.dart';

class SavedPlanEditorSheet extends StatefulWidget {
  const SavedPlanEditorSheet({
    super.key,
    required this.plan,
    this.catalog = const [],
    this.bodyWeightKg,
  });

  final Map<String, dynamic> plan;
  final List<GymExercise> catalog;
  final double? bodyWeightKg;

  static Future<Map<String, dynamic>?> show(
    BuildContext context,
    Map<String, dynamic> plan, {
    List<GymExercise> catalog = const [],
    double? bodyWeightKg,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SavedPlanEditorSheet(
        plan: plan,
        catalog: catalog,
        bodyWeightKg: bodyWeightKg,
      ),
    );
  }

  @override
  State<SavedPlanEditorSheet> createState() => _SavedPlanEditorSheetState();
}

class _SavedPlanEditorSheetState extends State<SavedPlanEditorSheet> {
  late final TextEditingController _title;
  late final TextEditingController _summary;
  late List<_DayDraft> _days;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.plan['title']?.toString() ?? '');
    _summary = TextEditingController(text: widget.plan['summary']?.toString() ?? '');
    _days = [
      for (final raw in (widget.plan['days'] as List? ?? const []))
        if (raw is Map)
          _DayDraft.fromMap(Map<String, dynamic>.from(raw)),
    ];
  }

  @override
  void dispose() {
    _title.dispose();
    _summary.dispose();
    for (final day in _days) {
      day.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit program', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Program name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _summary,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Summary'),
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 4),
            Text(
              'Long-press a day or move, then drag to reorder.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ReorderableListView.builder(
                itemCount: _days.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final day = _days.removeAt(oldIndex);
                    _days.insert(newIndex, day);
                  });
                },
                itemBuilder: (context, dayIndex) {
                  final day = _days[dayIndex];
                  return Padding(
                    key: ValueKey(day),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            TextField(
                              controller: day.label,
                              decoration: const InputDecoration(labelText: 'Day'),
                            ),
                            TextField(
                              controller: day.focus,
                              decoration: const InputDecoration(labelText: 'Focus'),
                            ),
                            const SizedBox(height: 8),
                            ReorderableListView(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              onReorder: (oldIndex, newIndex) {
                                setState(() {
                                  if (newIndex > oldIndex) newIndex -= 1;
                                  final ex = day.exercises.removeAt(oldIndex);
                                  day.exercises.insert(newIndex, ex);
                                });
                              },
                              children: [
                                for (var i = 0; i < day.exercises.length; i++)
                                  Padding(
                                    key: ValueKey(day.exercises[i]),
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            children: [
                                              GymMovePickerField(
                                                value: day.exercises[i].name.text,
                                                onChanged: (name) {
                                                  final previous = day.exercises[i].name.text;
                                                  day.exercises[i].name.text = name;
                                                  final next = nextGymMovePrescription(
                                                    name,
                                                    currentSets: day.exercises[i].sets.text,
                                                    currentRest: day.exercises[i].rest.text,
                                                    currentWeight: day.exercises[i].weight.text,
                                                    previousName: previous,
                                                    level: widget.plan['level']?.toString(),
                                                    bodyWeightKg: widget.bodyWeightKg,
                                                    catalog: widget.catalog,
                                                  );
                                                  day.exercises[i].sets.text = next.sets;
                                                  day.exercises[i].rest.text = next.rest;
                                                  day.exercises[i].weight.text = next.weight;
                                                },
                                                catalog: widget.catalog,
                                              ),
                                              TextField(
                                                controller: day.exercises[i].sets,
                                                decoration: const InputDecoration(labelText: 'Sets or mins'),
                                              ),
                                              TextField(
                                                controller: day.exercises[i].weight,
                                                decoration: const InputDecoration(labelText: 'Weight'),
                                              ),
                                              TextField(
                                                controller: day.exercises[i].rest,
                                                decoration: const InputDecoration(labelText: 'Rest'),
                                              ),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          onPressed: () async {
                                            if (!(await confirmDelete(
                                              context,
                                              label: day.exercises[i].name.text.trim().isEmpty
                                                  ? 'this move'
                                                  : day.exercises[i].name.text.trim(),
                                            ))) {
                                              return;
                                            }
                                            setState(() => day.exercises.removeAt(i));
                                          },
                                          icon: const Icon(Icons.delete_outline),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            if (day.exercises.length < 6)
                              TextButton.icon(
                                onPressed: () => setState(() => day.exercises.add(_ExerciseDraft.empty())),
                                icon: const Icon(Icons.add),
                                label: const Text('Add a move'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            FilledButton(
              onPressed: () {
                final days = [
                  for (final day in _days)
                    {
                      'day': day.label.text.trim().isEmpty ? 'Day' : day.label.text.trim(),
                      'focus': day.focus.text.trim().isEmpty ? 'Training' : day.focus.text.trim(),
                      'exercises': [
                        for (final ex in day.exercises)
                          if (ex.name.text.trim().length >= 2)
                            {
                              'name': ex.name.text.trim(),
                              'sets': ex.sets.text.trim().isEmpty ? '3 x 10' : ex.sets.text.trim(),
                              'rest': ex.rest.text.trim().isEmpty ? '60s' : ex.rest.text.trim(),
                              if (ex.weight.text.trim().isNotEmpty) 'weight': ex.weight.text.trim(),
                              if (ex.notes.text.trim().isNotEmpty) 'notes': ex.notes.text.trim(),
                            },
                      ],
                      if (day.alternatives.isNotEmpty) 'alternatives': day.alternatives,
                      if (day.additionals.isNotEmpty) 'additionals': day.additionals,
                    },
                ];
                final trainingDays = [
                  for (final day in days)
                    if (weekdayIsoFromLabel(day['day']?.toString() ?? '') != null)
                      weekdayIsoFromLabel(day['day']!.toString())!,
                ];
                Navigator.pop(context, {
                  'title': _title.text.trim(),
                  'summary': _summary.text.trim(),
                  'focus': widget.plan['focus'],
                  'level': widget.plan['level'],
                  'days': days,
                  'recommendations': widget.plan['recommendations'],
                  'training_days': trainingDays.isNotEmpty
                      ? trainingDays
                      : widget.plan['training_days'],
                });
              },
              child: const Text('Save program'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayDraft {
  _DayDraft({
    required this.label,
    required this.focus,
    required this.exercises,
    required this.alternatives,
    required this.additionals,
  });

  factory _DayDraft.fromMap(Map<String, dynamic> day) {
    return _DayDraft(
      label: TextEditingController(text: day['day']?.toString() ?? 'Day'),
      focus: TextEditingController(text: day['focus']?.toString() ?? ''),
      exercises: [
        for (final raw in (day['exercises'] as List? ?? const []))
          if (raw is Map) _ExerciseDraft.fromMap(Map<String, dynamic>.from(raw)),
      ],
      alternatives: [
        for (final raw in (day['alternatives'] as List? ?? const []))
          if (raw is Map) Map<String, dynamic>.from(raw),
      ],
      additionals: [
        for (final raw in (day['additionals'] as List? ?? const []))
          if (raw is Map) Map<String, dynamic>.from(raw),
      ],
    );
  }

  final TextEditingController label;
  final TextEditingController focus;
  final List<_ExerciseDraft> exercises;
  final List<Map<String, dynamic>> alternatives;
  final List<Map<String, dynamic>> additionals;

  void dispose() {
    label.dispose();
    focus.dispose();
    for (final ex in exercises) {
      ex.dispose();
    }
  }
}

class _ExerciseDraft {
  _ExerciseDraft({
    required this.name,
    required this.sets,
    required this.rest,
    required this.weight,
    required this.notes,
  });

  factory _ExerciseDraft.empty() => _ExerciseDraft(
        name: TextEditingController(),
        sets: TextEditingController(text: '3 x 10'),
        rest: TextEditingController(text: '60s'),
        weight: TextEditingController(),
        notes: TextEditingController(),
      );

  factory _ExerciseDraft.fromMap(Map<String, dynamic> ex) => _ExerciseDraft(
        name: TextEditingController(text: ex['name']?.toString() ?? ''),
        sets: TextEditingController(text: ex['sets']?.toString() ?? '3 x 10'),
        rest: TextEditingController(text: ex['rest']?.toString() ?? '60s'),
        weight: TextEditingController(text: ex['weight']?.toString() ?? ''),
        notes: TextEditingController(text: ex['notes']?.toString() ?? ''),
      );

  final TextEditingController name;
  final TextEditingController sets;
  final TextEditingController rest;
  final TextEditingController weight;
  final TextEditingController notes;

  void dispose() {
    name.dispose();
    sets.dispose();
    rest.dispose();
    weight.dispose();
    notes.dispose();
  }
}
