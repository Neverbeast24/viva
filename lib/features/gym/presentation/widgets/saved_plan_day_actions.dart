import 'package:flutter/material.dart';

import '../../../../core/widgets/widgets.dart';
import '../../../../shared/models/gym_exercise.dart';
import '../../data/gym_labels.dart';
import 'gym_move_picker.dart';

class SavedPlanDayActions extends StatelessWidget {
  const SavedPlanDayActions({
    super.key,
    required this.plan,
    required this.day,
    required this.dayIndex,
    required this.onStart,
    required this.onSaveDays,
    this.catalog = const [],
  });

  final Map<String, dynamic> plan;
  final Map<String, dynamic> day;
  final int dayIndex;
  final VoidCallback onStart;
  final Future<void> Function(List<Map<String, dynamic>> days) onSaveDays;
  final List<GymExercise> catalog;

  List<Map<String, dynamic>> get _days => [
        for (final raw in (plan['days'] as List? ?? const []))
          if (raw is Map) Map<String, dynamic>.from(raw),
      ];

  int? get _currentIso => weekdayIsoFromLabel(day['day']?.toString() ?? '');

  Future<void> _modify(BuildContext context) async {
    final edited = await _DayEditorSheet.show(context, day, catalog: catalog);
    if (edited == null) return;
    final days = _days;
    if (dayIndex < 0 || dayIndex >= days.length) return;
    days[dayIndex] = edited;
    await onSaveDays(days);
  }

  Future<void> _add(BuildContext context) async {
    final current = Map<String, dynamic>.from(day);
    final exercises = [
      for (final raw in (current['exercises'] as List? ?? const []))
        if (raw is Map) Map<String, dynamic>.from(raw),
    ];
    if (exercises.length >= 6) return;
    exercises.add(emptyPlanExercise());
    current['exercises'] = exercises;
    final edited = await _DayEditorSheet.show(context, current, catalog: catalog);
    if (edited == null) return;
    final days = _days;
    if (dayIndex < 0 || dayIndex >= days.length) return;
    days[dayIndex] = edited;
    await onSaveDays(days);
  }

  Future<void> _move(int iso) async {
    if (iso == _currentIso) return;
    await onSaveDays(moveSavedPlanDay(_days, dayIndex, iso));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Start this day'),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              onPressed: () => _modify(context),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Modify'),
            ),
            TextButton.icon(
              onPressed: () => _add(context),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add'),
            ),
            DropdownButton<int>(
              hint: const Text('Move to'),
              value: _currentIso,
              items: [
                for (final item in gymWeekdays)
                  DropdownMenuItem(
                    value: item.iso,
                    child: Text(item.full),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                _move(value);
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _DayEditorSheet extends StatefulWidget {
  const _DayEditorSheet({required this.day, required this.catalog});

  final Map<String, dynamic> day;
  final List<GymExercise> catalog;

  static Future<Map<String, dynamic>?> show(
    BuildContext context,
    Map<String, dynamic> day, {
    List<GymExercise> catalog = const [],
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _DayEditorSheet(day: day, catalog: catalog),
    );
  }

  @override
  State<_DayEditorSheet> createState() => _DayEditorSheetState();
}

class _ExerciseDraft {
  _ExerciseDraft(Map<String, dynamic> raw)
      : name = TextEditingController(text: raw['name']?.toString() ?? ''),
        sets = TextEditingController(text: raw['sets']?.toString() ?? '3 x 10'),
        rest = TextEditingController(text: raw['rest']?.toString() ?? '60s');

  final TextEditingController name;
  final TextEditingController sets;
  final TextEditingController rest;

  void dispose() {
    name.dispose();
    sets.dispose();
    rest.dispose();
  }
}

class _DayEditorSheetState extends State<_DayEditorSheet> {
  late final TextEditingController _focus;
  late List<_ExerciseDraft> _exercises;

  @override
  void initState() {
    super.initState();
    _focus = TextEditingController(text: widget.day['focus']?.toString() ?? '');
    _exercises = [
      for (final raw in (widget.day['exercises'] as List? ?? const []))
        if (raw is Map) _ExerciseDraft(Map<String, dynamic>.from(raw)),
    ];
    if (_exercises.isEmpty) _exercises.add(_ExerciseDraft(emptyPlanExercise()));
  }

  @override
  void dispose() {
    _focus.dispose();
    for (final ex in _exercises) {
      ex.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Modify day', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _focus,
            decoration: const InputDecoration(labelText: 'Focus'),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _exercises.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        GymMovePickerField(
                          value: _exercises[i].name.text,
                          onChanged: (name) => _exercises[i].name.text = name,
                          catalog: widget.catalog,
                        ),
                        TextField(
                          controller: _exercises[i].sets,
                          decoration: const InputDecoration(labelText: 'Sets'),
                        ),
                        TextField(
                          controller: _exercises[i].rest,
                          decoration: const InputDecoration(labelText: 'Rest'),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      if (!(await confirmDelete(
                        context,
                        label: _exercises[i].name.text.trim().isEmpty
                            ? 'this move'
                            : _exercises[i].name.text.trim(),
                      ))) {
                        return;
                      }
                      setState(() {
                        _exercises.removeAt(i).dispose();
                      });
                    },
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          if (_exercises.length < 6)
            TextButton.icon(
              onPressed: () {
                setState(() => _exercises.add(_ExerciseDraft(emptyPlanExercise())));
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add a move'),
            ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, {
                ...widget.day,
                'focus': _focus.text.trim().isEmpty ? 'Training' : _focus.text.trim(),
                'exercises': [
                  for (final ex in _exercises)
                    if (ex.name.text.trim().length >= 2)
                      {
                        'name': ex.name.text.trim(),
                        'sets': ex.sets.text.trim().isEmpty ? '3 x 10' : ex.sets.text.trim(),
                        'rest': ex.rest.text.trim().isEmpty ? '60s' : ex.rest.text.trim(),
                      },
                ],
              });
            },
            child: const Text('Save day'),
          ),
        ],
      ),
    );
  }
}
