import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/vivrant_colors.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/models/gym_exercise.dart';
import '../../data/gym_labels.dart';
import 'exercise_demo_sheet.dart';

class MachineDetection {
  const MachineDetection({
    required this.found,
    required this.machine,
    required this.confidence,
    required this.why,
    required this.howToUse,
    required this.sets,
    required this.muscleGroup,
    required this.notes,
    required this.alternatives,
    this.demoSlug,
  });

  final bool found;
  final String machine;
  final String? demoSlug;
  final int confidence;
  final String why;
  final String howToUse;
  final String sets;
  final String muscleGroup;
  final String notes;
  final List<MachineDetectionAlternative> alternatives;

  factory MachineDetection.fromJson(Map<String, dynamic> json) {
    return MachineDetection(
      found: json['found'] == true,
      machine: json['machine']?.toString() ?? 'Gym machine',
      demoSlug: json['demo_slug']?.toString(),
      confidence: (json['confidence'] as num?)?.round() ?? 0,
      why: json['why']?.toString() ?? '',
      howToUse: json['how_to_use']?.toString() ?? '',
      sets: json['sets']?.toString() ?? '',
      muscleGroup: json['muscle_group']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      alternatives: [
        for (final row in (json['alternatives'] as List? ?? const []))
          if (row is Map)
            MachineDetectionAlternative.fromJson(Map<String, dynamic>.from(row)),
      ],
    );
  }

  MachineDetection copyWith({
    bool? found,
    String? machine,
    String? demoSlug,
    String? why,
    String? muscleGroup,
  }) {
    return MachineDetection(
      found: found ?? this.found,
      machine: machine ?? this.machine,
      demoSlug: demoSlug ?? this.demoSlug,
      confidence: confidence,
      why: why ?? this.why,
      howToUse: howToUse,
      sets: sets,
      muscleGroup: muscleGroup ?? this.muscleGroup,
      notes: notes,
      alternatives: alternatives,
    );
  }
}

class MachineDetectionAlternative {
  const MachineDetectionAlternative({
    required this.machine,
    required this.why,
    this.demoSlug,
  });

  final String machine;
  final String? demoSlug;
  final String why;

  factory MachineDetectionAlternative.fromJson(Map<String, dynamic> json) {
    return MachineDetectionAlternative(
      machine: json['machine']?.toString() ?? 'Machine',
      demoSlug: json['demo_slug']?.toString(),
      why: json['why']?.toString() ?? '',
    );
  }
}

Future<void> runMachinePhotoDetect({
  required BuildContext context,
  required WidgetRef ref,
  required List<GymExercise> exercises,
  List<Map<String, dynamic>> plans = const [],
  void Function(GymExercise exercise, String sets)? onAddToSession,
  void Function(String slug)? onMarkedKnown,
  void Function(Map<String, dynamic> plan)? onPlanUpdated,
}) async {
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

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  Map<String, dynamic> res;
  try {
    res = await ref.read(vivrantApiProvider).identifyMachineFromPhoto(photo.path);
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      context.showError(apiErrorMessage(e));
    }
    return;
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();

  final raw = res['detection'];
  if (raw is! Map) {
    context.showError('Could not identify that machine.');
    return;
  }
  var detection = MachineDetection.fromJson(Map<String, dynamic>.from(raw));
  if (detection.found) {
    context.showSuccess('Looks like ${detection.machine}.');
  } else {
    context.showInfo(detection.why.isEmpty
        ? 'Could not match that photo to a catalog machine.'
        : detection.why);
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return _MachineDetectSheet(
        initial: detection,
        exercises: exercises,
        plans: plans,
        onAddToSession: onAddToSession,
        onMarkedKnown: onMarkedKnown,
        onPlanUpdated: onPlanUpdated,
      );
    },
  );
}

class _MachineDetectSheet extends ConsumerStatefulWidget {
  const _MachineDetectSheet({
    required this.initial,
    required this.exercises,
    required this.plans,
    this.onAddToSession,
    this.onMarkedKnown,
    this.onPlanUpdated,
  });

  final MachineDetection initial;
  final List<GymExercise> exercises;
  final List<Map<String, dynamic>> plans;
  final void Function(GymExercise exercise, String sets)? onAddToSession;
  final void Function(String slug)? onMarkedKnown;
  final void Function(Map<String, dynamic> plan)? onPlanUpdated;

  @override
  ConsumerState<_MachineDetectSheet> createState() => _MachineDetectSheetState();
}

class _MachineDetectSheetState extends ConsumerState<_MachineDetectSheet> {
  late MachineDetection _detection = widget.initial;
  bool _saving = false;

  GymExercise? _match(String? slug, [String? name]) {
    if (slug != null && slug.isNotEmpty) {
      for (final item in widget.exercises) {
        if (item.slug == slug) return item;
      }
    }
    if (name == null || name.trim().isEmpty) return null;
    return findExerciseMatch(name, widget.exercises);
  }

  Map<String, dynamic>? get _plan => widget.plans.isEmpty ? null : widget.plans.first;

  Future<void> _markKnown(String slug) async {
    final prefs = await SharedPreferences.getInstance();
    final current = sanitizeKnownMachineSlugs(
      prefs.getStringList('vivrant.gym.knownMachines') ?? const [],
    );
    if (!current.contains(slug) && current.length < maxKnownMachineSlugs) {
      await prefs.setStringList('vivrant.gym.knownMachines', [...current, slug]);
    }
    widget.onMarkedKnown?.call(slug);
    if (!mounted) return;
    context.showSuccess('Saved as a machine you know — next program can use it.');
  }

  Future<void> _addToDay(int dayIndex) async {
    final plan = _plan;
    if (plan == null) {
      context.showError('Save a program first, then add this machine to a day.');
      return;
    }
    final match = _match(_detection.demoSlug, _detection.machine);
    final name = match?.name ?? _detection.machine;
    final days = [
      for (final day in (plan['days'] as List? ?? const []))
        if (day is Map) Map<String, dynamic>.from(day),
    ];
    if (dayIndex < 0 || dayIndex >= days.length) return;
    final before = (days[dayIndex]['exercises'] as List?)?.length ?? 0;
    final rest = suggestGymMoveRest(
      name,
      equipment: match?.equipment,
      catalog: widget.exercises,
    );
    final next = appendNamedExerciseToPlanDays(days, dayIndex, {
      'name': name,
      'sets': _detection.sets.isEmpty ? '3 x 10' : _detection.sets,
      'rest': rest,
      if (match?.cues != null && match!.cues!.isNotEmpty) 'notes': match.cues,
    });
    final after = (next[dayIndex]['exercises'] as List?)?.length ?? 0;
    if (after == before) {
      context.showError(before >= 6 ? 'That day already has 6 moves.' : 'That move is already on this day.');
      return;
    }
    final id = (plan['id'] as num?)?.toInt();
    if (id == null) return;
    setState(() => _saving = true);
    try {
      final updated = await ref.read(vivrantApiProvider).updateGymPlan(id, {
        'title': plan['title'],
        'summary': plan['summary'],
        'focus': plan['focus'],
        'level': plan['level'],
        'days': next,
        'recommendations': plan['recommendations'],
        'training_days': trainingDaysFromSavedDays(
          next,
          (plan['training_days'] as List?)
              ?.map((item) => (item as num).toInt())
              .toList(),
        ),
      });
      widget.onPlanUpdated?.call(updated);
      if (!mounted) return;
      context.showSuccess('Added $name to ${days[dayIndex]['day'] ?? 'this day'}.');
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addToToday() async {
    final plan = _plan;
    if (plan == null) {
      context.showError('Save a program first, then add this machine to a day.');
      return;
    }
    final days = [
      for (final day in (plan['days'] as List? ?? const []))
        if (day is Map) Map<String, dynamic>.from(day),
    ];
    final today = pickTodaysPlanDay(days, DateTime.now(), planTrainingDaysList(plan));
    final index = today == null ? -1 : days.indexWhere((day) => day['day'] == today['day']);
    if (index < 0) {
      context.showError('Today is a rest day — pick another program day.');
      return;
    }
    await _addToDay(index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = VivrantColors.of(context);
    final match = _match(_detection.demoSlug, _detection.machine);
    final days = [
      for (final day in (_plan?['days'] as List? ?? const []))
        if (day is Map) Map<String, dynamic>.from(day),
    ];

    return SafeArea(
      child: Padding(
        padding: VivrantLayout.sheetPadding,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _detection.found ? _detection.machine : 'Not a catalog machine',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                _detection.found
                    ? '${_detection.confidence}% match'
                    : 'Try a clearer photo of the whole machine.',
                style: theme.textTheme.labelMedium?.copyWith(color: c.accent),
              ),
              if (_detection.muscleGroup.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    humanizeLabel(_detection.muscleGroup),
                    if (_detection.sets.isNotEmpty) _detection.sets,
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_detection.why.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(_detection.why, style: theme.textTheme.bodySmall),
              ],
              if (_detection.howToUse.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(_detection.howToUse, style: theme.textTheme.bodySmall),
              ],
              if (_detection.found) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (match != null && match.hasDemo)
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          showExerciseDemoSheet(context, match);
                        },
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('Watch demo'),
                      ),
                    if (_detection.demoSlug != null && _detection.demoSlug!.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _markKnown(_detection.demoSlug!),
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('I use this'),
                      ),
                    if (widget.onAddToSession != null && match != null)
                      FilledButton.icon(
                        onPressed: _saving
                            ? null
                            : () {
                                widget.onAddToSession!(
                                  match,
                                  _detection.sets.isEmpty ? '3 x 10' : _detection.sets,
                                );
                                Navigator.pop(context);
                              },
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add to this workout'),
                      ),
                    if (_plan != null) ...[
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _addToToday,
                        icon: const Icon(Icons.today_rounded),
                        label: const Text('Add to today'),
                      ),
                      if (days.isNotEmpty)
                        PopupMenuButton<int>(
                          enabled: !_saving,
                          onSelected: _addToDay,
                          itemBuilder: (ctx) => [
                            for (var i = 0; i < days.length; i++)
                              PopupMenuItem(
                                value: i,
                                child: Text(days[i]['day']?.toString() ?? 'Day ${i + 1}'),
                              ),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Text('Add to a day…'),
                          ),
                        ),
                    ],
                  ],
                ),
              ],
              if (_detection.alternatives.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'If that’s not it',
                  style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final item in _detection.alternatives)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.machine, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: item.why.isEmpty ? null : Text(item.why),
                    onTap: () {
                      final alt = _match(item.demoSlug, item.machine);
                      setState(() {
                        _detection = _detection.copyWith(
                          found: true,
                          machine: alt?.name ?? item.machine,
                          demoSlug: alt?.slug ?? item.demoSlug,
                          why: item.why,
                          muscleGroup: alt?.muscleGroup ?? _detection.muscleGroup,
                        );
                      });
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
