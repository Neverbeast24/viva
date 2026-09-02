import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/vivrant_colors.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/persistent_store.dart';
import '../../../../shared/models/gym_exercise.dart';
import '../../data/gym_labels.dart';
import '../../data/gym_rest_alert.dart';
import 'gym_move_picker.dart';
import 'machine_detect_sheet.dart';

class ProgramSessionPanel extends ConsumerStatefulWidget {
  const ProgramSessionPanel({
    super.key,
    required this.plans,
    this.onLogged,
    this.initialPlanId,
    this.initialDayLabel,
    this.allowDayPick = true,
  });

  final List<Map<String, dynamic>> plans;
  final VoidCallback? onLogged;
  final int? initialPlanId;
  final String? initialDayLabel;
  final bool allowDayPick;

  @override
  ConsumerState<ProgramSessionPanel> createState() => _ProgramSessionPanelState();
}

class _RunnerItem {
  _RunnerItem({
    required this.key,
    required this.name,
    required this.originalName,
    required this.setsLabel,
    required this.rest,
    required this.restSeconds,
    required this.setCount,
    required this.kind,
    this.weight,
    this.notes,
    this.swap,
  });

  final String key;
  final String name;
  final String originalName;
  final String setsLabel;
  final String rest;
  final int restSeconds;
  final int setCount;
  final String kind;
  final String? weight;
  final String? notes;
  final String? swap;
}

class _MoveMeta {
  const _MoveMeta({required this.setsLabel, required this.rest, required this.restSeconds});

  final String setsLabel;
  final String rest;
  final int restSeconds;
}

class _ProgramSessionPanelState extends ConsumerState<ProgramSessionPanel>
    with WidgetsBindingObserver {
  int? _planId;
  String _dayLabel = '';
  Map<String, List<bool>> _checks = {};
  Map<String, String> _names = {};
  Map<String, String> _weights = {};
  DateTime? _startedAt;
  bool _saving = false;
  bool _restored = false;
  List<_RunnerItem> _extras = [];
  List<GymExercise> _catalog = const [];
  List<Map<String, dynamic>> _sessions = const [];
  bool _catchUpDismissed = false;
  final List<String> _removedKeys = [];
  final Map<String, _MoveMeta> _meta = {};

  Timer? _ticker;
  Timer? _syncTimer;
  int? _restEndsAtMs;
  int _restTotal = 0;
  String? _restLabel;
  String _restKind = 'rest';
  bool _alarmArmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _planId = widget.initialPlanId ??
        (widget.plans.isEmpty ? null : (widget.plans.first['id'] as num?)?.toInt());
    _dayLabel = widget.initialDayLabel ?? '';
    _resetFromPlan();
    _restoreSession();
    _loadCatalog();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      final rows = await ref.read(vivrantApiProvider).gymSessions();
      if (!mounted) return;
      setState(() {
        _sessions = [
          for (final row in rows)
            {
              'title': row.title,
              'logged_at': row.loggedAt?.toIso8601String(),
            },
        ];
      });
    } catch (_) {
      // Catch-up banner is optional when sessions fail to load.
    }
  }

  Future<void> _loadCatalog() async {
    try {
      final rows = await ref.read(vivrantApiProvider).gymExercises();
      final catalog = [
        for (final row in rows) GymExercise.fromJson(row),
      ];
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _fillMissingWeights();
      });
    } catch (_) {
      // Picker still accepts typed names without the catalog.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _catchUpRest();
      setState(() {});
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _persistSession();
    }
  }

  @override
  void didUpdateWidget(covariant ProgramSessionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final plansArrived = oldWidget.plans.isEmpty && widget.plans.isNotEmpty;
    final planHintChanged =
        widget.initialPlanId != null && widget.initialPlanId != oldWidget.initialPlanId;
    final dayHintChanged =
        (widget.initialDayLabel ?? '') != (oldWidget.initialDayLabel ?? '') &&
            (widget.initialDayLabel ?? '').isNotEmpty;
    if (!plansArrived && !planHintChanged && !dayHintChanged && _planId != null) return;
    if (widget.plans.isEmpty) return;
    _planId = widget.initialPlanId ?? _planId ?? (widget.plans.first['id'] as num?)?.toInt();
    if ((widget.initialDayLabel ?? '').isNotEmpty) {
      _dayLabel = widget.initialDayLabel!;
    }
    _resetFromPlan();
    _restoreSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }

  Map<String, dynamic>? get _plan {
    if (widget.plans.isEmpty) return null;
    for (final plan in widget.plans) {
      if ((plan['id'] as num?)?.toInt() == _planId) return plan;
    }
    return widget.plans.first;
  }

  Map<String, dynamic>? get _calendarToday {
    final plan = _plan;
    if (plan == null) return null;
    final days = (plan['days'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return pickTodaysPlanDay(days, null, planTrainingDaysList(plan));
  }

  Map<String, dynamic>? get _sessionDay {
    final plan = _plan;
    if (plan == null) return null;
    final days = (plan['days'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return resolveSessionPlanDay(
      days,
      label: widget.allowDayPick ? _dayLabel : null,
      trainingDays: planTrainingDaysList(plan),
    );
  }

  MissedProgramDay? get _missedDay {
    final plan = _plan;
    if (plan == null) return null;
    final days = (plan['days'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final missed = findMissedProgramDays(
      days,
      _sessions,
      trainingDays: planTrainingDaysList(plan),
    );
    return missed.isEmpty ? null : missed.first;
  }

  List<_RunnerItem> get _items {
    final day = _sessionDay;
    final base = [
      if (day != null) ..._buildItems(day),
      ..._extras,
    ].where((item) => !_removedKeys.contains(item.key)).toList();
    return [
      for (final item in base)
        _withMeta(item),
    ];
  }

  _RunnerItem _withMeta(_RunnerItem item) {
    final over = _meta[item.key];
    final row = _checks[item.key];
    final setCount = [
      over != null ? parseSetCount(over.setsLabel) : item.setCount,
      row?.length ?? 0,
      1,
    ].reduce((a, b) => a > b ? a : b);
    if (over == null && setCount == item.setCount) return item;
    return _RunnerItem(
      key: item.key,
      name: item.name,
      originalName: item.originalName,
      setsLabel: over?.setsLabel ?? item.setsLabel,
      rest: over?.rest ?? item.rest,
      restSeconds: over?.restSeconds ?? item.restSeconds,
      setCount: setCount,
      kind: item.kind,
      weight: item.weight,
      notes: item.notes,
      swap: item.swap,
    );
  }

  List<_RunnerItem> _buildItems(Map<String, dynamic> day) {
    final alternatives = dayAlternatives(day);
    final exercises = (day['exercises'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final mains = <_RunnerItem>[
      for (var i = 0; i < exercises.length; i++)
        _RunnerItem(
          key: 'main-$i',
          name: displayGymMoveName(exercises[i]['name']?.toString()),
          originalName: displayGymMoveName(exercises[i]['name']?.toString()),
          setsLabel: exercises[i]['sets']?.toString() ?? '3 x 10',
          rest: exercises[i]['rest']?.toString() ?? '60s',
          restSeconds: parseRestSeconds(exercises[i]['rest']?.toString() ?? '60s'),
          setCount: parseSetCount(exercises[i]['sets']?.toString() ?? '3 x 10'),
          kind: 'main',
          weight: (exercises[i]['weight']?.toString() ?? '').trim().isEmpty
              ? null
              : exercises[i]['weight'].toString(),
          notes: (exercises[i]['notes']?.toString() ?? '').trim().isEmpty
              ? gymMoveDetails(displayGymMoveName(exercises[i]['name']?.toString())).cues
              : exercises[i]['notes'].toString(),
          swap: alternatives
              .where(
                (alt) =>
                    (alt['instead_of'] ?? '').toLowerCase() ==
                    (exercises[i]['name']?.toString() ?? '').toLowerCase(),
              )
              .map((alt) => alt['use'])
              .firstOrNull,
        ),
    ];
    final addons = dayAdditionals(day);
    return [
      ...mains,
      for (var i = 0; i < addons.length; i++)
        _RunnerItem(
          key: 'addon-$i',
          name: displayGymMoveName(addons[i]['name']),
          originalName: displayGymMoveName(addons[i]['name']),
          setsLabel: addons[i]['sets'] ?? '2 x 12',
          rest: '45s',
          restSeconds: 45,
          setCount: parseSetCount(addons[i]['sets'] ?? '2 x 12'),
          kind: 'addon',
        ),
    ];
  }

  double? get _bodyWeightKg => ref.read(authProvider).profile?.weightKg;

  String _sessionWeightFor(_RunnerItem item, {String? name, String? saved}) {
    return resolveSessionMoveWeight(
      name ?? _names[item.key] ?? item.name,
      programmedWeight: item.weight,
      savedWeight: saved ?? _weights[item.key],
      level: _plan?['level']?.toString(),
      bodyWeightKg: _bodyWeightKg,
      catalog: _catalog,
    );
  }

  void _fillMissingWeights() {
    for (final item in _items) {
      if ((_weights[item.key] ?? '').trim().isNotEmpty) continue;
      final next = _sessionWeightFor(item, saved: '');
      if (next.isNotEmpty) _weights[item.key] = next;
    }
  }

  void _resetFromPlan() {
    _extras = [];
    _removedKeys.clear();
    _meta.clear();
    final items = _items;
    _checks = {
      for (final item in items) item.key: List<bool>.filled(item.setCount, false),
    };
    _names = {for (final item in items) item.key: item.name};
    _weights = {
      for (final item in items) item.key: _sessionWeightFor(item, saved: ''),
    };
  }

  int get _restLeft => restRemainingSeconds(_restEndsAtMs);

  bool get _hasProgress {
    if (_startedAt != null) return true;
    return _checks.values.any((row) => row.any((on) => on));
  }

  Map<String, dynamic> _sessionPayload() {
    final plan = _plan;
    final today = _sessionDay;
    return {
      'plan_id': (plan?['id'] as num?)?.toInt() ?? _planId ?? 0,
      'day_label': today?['day']?.toString() ?? '',
      'session_date': todaySessionDate(),
      'checks': _checks,
      'names': _names,
      'weights': _weights,
      'extras': [
        for (final item in _extras)
          {
            'key': item.key,
            'name': _names[item.key] ?? item.name,
            'setsLabel': _meta[item.key]?.setsLabel ?? item.setsLabel,
            'rest': _meta[item.key]?.rest ?? item.rest,
            'setCount': item.setCount,
            'restSeconds': _meta[item.key]?.restSeconds ?? item.restSeconds,
          },
      ],
      'removed_keys': List<String>.from(_removedKeys),
      'started_at': _startedAt?.millisecondsSinceEpoch,
      'rest_ends_at': _restEndsAtMs,
      'rest_label': _restLabel,
      'rest_total': _restTotal,
      'rest_alerted': false,
      'rest_kind': _restKind,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _persistSession() async {
    if (_plan == null || _sessionDay == null) return;
    final payload = _sessionPayload();
    await PersistentStore.instance.writeJson(gymLiveSessionKey, payload);
    if (!_hasProgress && _restEndsAtMs == null && _extras.isEmpty && _removedKeys.isEmpty) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 700), () async {
      try {
        await ref.read(vivrantApiProvider).saveGymLiveSession(payload);
      } catch (_) {}
    });
  }

  Future<void> _clearPersistedSession() async {
    await PersistentStore.instance.writeJson(gymLiveSessionKey, null);
    try {
      await ref.read(vivrantApiProvider).clearGymLiveSession();
    } catch (_) {}
  }

  bool _matchesSession(Map<String, dynamic>? saved) {
    if (saved == null) return false;
    final plan = _plan;
    final today = _sessionDay;
    if (plan == null || today == null) return false;
    final planId = (saved['plan_id'] as num?)?.toInt();
    return planId == (plan['id'] as num?)?.toInt() &&
        saved['day_label']?.toString() == today['day']?.toString() &&
        saved['session_date']?.toString() == todaySessionDate();
  }

  void _applySaved(Map<String, dynamic> saved) {
    final extrasRaw = saved['extras'];
    _extras = [
      if (extrasRaw is List)
        for (final raw in extrasRaw)
          if (raw is Map)
            _RunnerItem(
              key: raw['key']?.toString() ?? 'extra-${DateTime.now().millisecondsSinceEpoch}',
              name: raw['name']?.toString() ?? 'Extra move',
              originalName: raw['name']?.toString() ?? 'Extra move',
              setsLabel: raw['setsLabel']?.toString() ?? raw['sets_label']?.toString() ?? '3 x 10',
              rest: raw['rest']?.toString() ?? '60s',
              restSeconds: (raw['restSeconds'] as num?)?.toInt() ??
                  (raw['rest_seconds'] as num?)?.toInt() ??
                  parseRestSeconds(raw['rest']?.toString() ?? '60s'),
              setCount: (raw['setCount'] as num?)?.toInt() ??
                  (raw['set_count'] as num?)?.toInt() ??
                  parseSetCount(raw['setsLabel']?.toString() ?? '3 x 10'),
              kind: 'addon',
            ),
    ];
    if (_extras.isEmpty && saved['checks'] is Map) {
      final checksMap = saved['checks'] as Map;
      final namesMap = saved['names'] is Map ? saved['names'] as Map : const {};
      _extras = [
        for (final entry in checksMap.entries)
          if (entry.key.toString().startsWith('extra-'))
            _RunnerItem(
              key: entry.key.toString(),
              name: namesMap[entry.key]?.toString() ?? 'Extra move',
              originalName: namesMap[entry.key]?.toString() ?? 'Extra move',
              setsLabel: '3 x 10',
              rest: '60s',
              restSeconds: 60,
              setCount: entry.value is List ? (entry.value as List).length.clamp(1, 10) : 3,
              kind: 'addon',
            ),
      ];
    }
    _removedKeys
      ..clear()
      ..addAll([
        if (saved['removed_keys'] is List)
          for (final key in saved['removed_keys'] as List) key.toString(),
      ]);
    _meta.clear();
    for (final item in _extras) {
      _meta[item.key] = _MoveMeta(
        setsLabel: item.setsLabel,
        rest: item.rest,
        restSeconds: item.restSeconds,
      );
    }
    final items = _items;
    _checks = {
      for (final item in items)
        item.key: List<bool>.generate(item.setCount, (i) {
          final row = saved['checks'] is Map ? (saved['checks'] as Map)[item.key] : null;
          if (row is List && i < row.length) return row[i] == true;
          return false;
        }),
    };
    for (final item in items) {
      final row = saved['checks'] is Map ? (saved['checks'] as Map)[item.key] : null;
      if (row is List && row.length > (_checks[item.key]?.length ?? 0)) {
        _checks[item.key] = [
          for (var i = 0; i < row.length; i++) row[i] == true,
        ];
      }
    }
    final names = saved['names'];
    if (names is Map) {
      for (final item in items) {
        final value = names[item.key]?.toString();
        if (value != null && value.isNotEmpty) _names[item.key] = value;
      }
    }
    final weights = saved['weights'];
    if (weights is Map) {
      for (final item in items) {
        final value = weights[item.key]?.toString();
        if (value != null && value.isNotEmpty) _weights[item.key] = value;
      }
    }
    for (final item in items) {
      if ((_weights[item.key] ?? '').trim().isEmpty) {
        _weights[item.key] = _sessionWeightFor(item);
      }
    }
    final started = saved['started_at'];
    if (started is num && started > 0) {
      _startedAt = DateTime.fromMillisecondsSinceEpoch(started.round());
    } else if (started is String) {
      _startedAt = DateTime.tryParse(started);
    }
    final restEnds = saved['rest_ends_at'];
    if (restEnds is num && restEnds > 0) {
      _restEndsAtMs = restEnds.round();
    } else if (restEnds is String) {
      _restEndsAtMs = DateTime.tryParse(restEnds)?.millisecondsSinceEpoch;
    }
    _restLabel = saved['rest_label']?.toString();
    _restTotal = (saved['rest_total'] as num?)?.toInt() ?? _restLeft;
    _restKind = saved['rest_kind']?.toString() == 'work' ? 'work' : 'rest';
    _restored = _hasProgress;
    _catchUpRest();
  }

  Future<void> _restoreSession() async {
    final local = await PersistentStore.instance.readJson(gymLiveSessionKey);
    Map<String, dynamic>? remote;
    try {
      remote = await ref.read(vivrantApiProvider).gymLiveSession();
    } catch (_) {}
    if (!mounted) return;
    final localOk = _matchesSession(local) ? local : null;
    final remoteOk = _matchesSession(remote) ? remote : null;
    Map<String, dynamic>? chosen = remoteOk ?? localOk;
    if (localOk != null && remoteOk != null) {
      final localAt = DateTime.tryParse(localOk['updated_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      final remoteAt = DateTime.tryParse(remoteOk['updated_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0);
      chosen = remoteAt.isAfter(localAt) ? remoteOk : localOk;
    }
    if (chosen == null) return;
    setState(() => _applySaved(chosen!));
    if (_restEndsAtMs != null && _restLeft > 0) _resumeTicker();
  }

  void _catchUpRest() {
    if (_restEndsAtMs == null) return;
    if (_restLeft > 0) return;
    final label = _restLabel;
    final kind = _restKind;
    _ticker?.cancel();
    _restEndsAtMs = null;
    _restLabel = null;
    _restTotal = 0;
    _alarmArmed = false;
    GymRestAlert.fire();
    if (label != null && mounted) {
      context.showSuccess(kind == 'work' ? 'Time’s up — nice work' : 'Rest done — next set');
    }
  }

  void _resumeTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_restEndsAtMs != null && _restLeft <= 0) {
        timer.cancel();
        if (_alarmArmed) return;
        _alarmArmed = true;
        _catchUpRest();
        setState(() {});
        return;
      }
      if (_restEndsAtMs == null && _startedAt == null) {
        timer.cancel();
        return;
      }
      setState(() {});
    });
  }

  int get _doneCount =>
      _checks.values.fold<int>(0, (sum, row) => sum + row.where((on) => on).length);

  int get _totalCount =>
      _items.fold<int>(0, (sum, item) => sum + item.setCount);

  int get _elapsedMinutes {
    final start = _startedAt;
    if (start == null) return 45;
    final mins = DateTime.now().difference(start).inMinutes;
    return mins.clamp(5, 180);
  }

  void _startRest(int seconds, String label, {String kind = 'rest'}) {
    if (seconds <= 0) return;
    _ticker?.cancel();
    _alarmArmed = false;
    unawaited(GymRestAlert.unlock());
    setState(() {
      _restEndsAtMs = restEndsAtFromSeconds(seconds);
      _restTotal = seconds;
      _restLabel = label;
      _restKind = kind;
    });
    _resumeTicker();
    _persistSession();
  }

  void _skipRest() {
    _ticker?.cancel();
    _alarmArmed = true;
    setState(() {
      _restEndsAtMs = null;
      _restLabel = null;
      _restTotal = 0;
    });
    if (_startedAt != null) _resumeTicker();
    _persistSession();
  }

  void _beginSet(_RunnerItem item) {
    unawaited(GymRestAlert.unlock());
    GymRestAlert.tick();
    _startedAt ??= DateTime.now();
    _resumeTicker();
    final displayName = _names[item.key] ?? item.name;
    final timed = parseTimedMinutes(_meta[item.key]?.setsLabel ?? item.setsLabel);
    if (timed != null && isCardioGymMove(displayName)) {
      _startRest(timed * 60, displayName, kind: 'work');
      return;
    }
    final stillOpen = _items.any((row) {
      final rowChecks = _checks[row.key] ?? const <bool>[];
      return rowChecks.any((on) => !on);
    });
    if (item.restSeconds > 0 && stillOpen) {
      _startRest(item.restSeconds, displayName);
    } else {
      _persistSession();
    }
  }

  void _toggleSet(_RunnerItem item, int index) {
    final current = List<bool>.from(_checks[item.key] ?? List<bool>.filled(item.setCount, false));
    current[index] = !current[index];
    setState(() {
      _checks[item.key] = current;
      if (current[index]) _startedAt ??= DateTime.now();
    });
    if (!current[index]) {
      _persistSession();
      return;
    }
    _beginSet(item);
  }

  void _toggleExercise(_RunnerItem item) {
    final current = _checks[item.key] ?? List<bool>.filled(item.setCount, false);
    final allOn = current.isNotEmpty && current.every((on) => on);
    setState(() {
      _checks[item.key] = List<bool>.filled(item.setCount, !allOn);
      if (!allOn) _startedAt ??= DateTime.now();
    });
    if (allOn) {
      _persistSession();
      return;
    }
    _beginSet(item);
  }

  void _applyMoveName(_RunnerItem item, String name) {
    final previous = _names[item.key] ?? item.name;
    final next = nextGymMovePrescription(
      name,
      currentSets: _meta[item.key]?.setsLabel ?? item.setsLabel,
      currentRest: _meta[item.key]?.rest ?? item.rest,
      currentWeight: _weights[item.key],
      previousName: previous,
      level: _plan?['level']?.toString(),
      bodyWeightKg: _bodyWeightKg,
      catalog: _catalog,
    );
    final restSeconds = parseRestSeconds(next.rest);
    final setCount = parseSetCount(next.sets);
    setState(() {
      _names[item.key] = name;
      _weights[item.key] = next.weight;
      _meta[item.key] = _MoveMeta(setsLabel: next.sets, rest: next.rest, restSeconds: restSeconds);
      final row = _checks[item.key] ?? const <bool>[];
      _checks[item.key] = List<bool>.generate(setCount, (i) => i < row.length && row[i]);
      if (item.key.startsWith('extra-')) {
        _extras = [
          for (final row in _extras)
            if (row.key == item.key)
              _RunnerItem(
                key: row.key,
                name: name,
                originalName: name,
                setsLabel: next.sets,
                rest: next.rest,
                restSeconds: restSeconds,
                setCount: setCount,
                kind: row.kind,
              )
            else
              row,
        ];
      }
    });
    _persistSession();
  }

  void _swap(_RunnerItem item) {
    final swap = item.swap;
    if (swap == null) return;
    final current = _names[item.key] ?? item.name;
    final next = current == item.originalName ? swap : item.originalName;
    _applyMoveName(item, next);
  }

  void _addExtra() {
    final key = 'extra-${DateTime.now().millisecondsSinceEpoch}';
    final item = _RunnerItem(
      key: key,
      name: 'Extra move',
      originalName: 'Extra move',
      setsLabel: '3 x 10',
      rest: '60s',
      restSeconds: 60,
      setCount: 3,
      kind: 'addon',
    );
    setState(() {
      _extras = [..._extras, item];
      _checks[key] = List<bool>.filled(3, false);
      _names[key] = 'Extra move';
      _weights[key] = '';
      _meta[key] = const _MoveMeta(setsLabel: '3 x 10', rest: '60s', restSeconds: 60);
    });
    _persistSession();
  }

  Future<void> _snapMachine() async {
    await runMachinePhotoDetect(
      context: context,
      ref: ref,
      exercises: _catalog,
      plans: widget.plans,
      onAddToSession: _addDetectedExtra,
    );
  }

  void _addDetectedExtra(GymExercise exercise, String sets) {
    final key = 'extra-${DateTime.now().millisecondsSinceEpoch}';
    final rest = suggestGymMoveRest(exercise.name, equipment: exercise.equipment, catalog: _catalog);
    final restSeconds = parseRestSeconds(rest);
    final setCount = parseSetCount(sets).clamp(1, 10).toInt();
    final item = _RunnerItem(
      key: key,
      name: exercise.name,
      originalName: exercise.name,
      setsLabel: sets.isEmpty ? '3 x 10' : sets,
      rest: rest,
      restSeconds: restSeconds,
      setCount: setCount,
      kind: 'addon',
    );
    setState(() {
      _extras = [..._extras, item];
      _checks[key] = List<bool>.filled(setCount, false);
      _names[key] = exercise.name;
      _weights[key] = '';
      _meta[key] = _MoveMeta(setsLabel: item.setsLabel, rest: rest, restSeconds: restSeconds);
    });
    _persistSession();
    if (mounted) context.showSuccess('Added ${exercise.name} to this workout.');
  }

  void _removeMove(_RunnerItem item) {
    setState(() {
      _checks.remove(item.key);
      _names.remove(item.key);
      _weights.remove(item.key);
      _meta.remove(item.key);
      if (item.key.startsWith('extra-')) {
        _extras = _extras.where((row) => row.key != item.key).toList();
      } else if (!_removedKeys.contains(item.key)) {
        _removedKeys.add(item.key);
      }
    });
    _persistSession();
  }

  String _repsFromSets(String sets) {
    final match = RegExp(r'[x×]\s*(\d+(?:\s*[-–]\s*\d+)?)', caseSensitive: false).firstMatch(sets);
    return match?.group(1)?.replaceAll(RegExp(r'\s+'), '') ?? '10';
  }

  void _nudgeMinutes(_RunnerItem item, int delta) {
    final current = parseTimedMinutes(_meta[item.key]?.setsLabel ?? item.setsLabel) ?? 10;
    final next = (current + delta).clamp(5, 90);
    final setsLabel = '$next mins';
    setState(() {
      _meta[item.key] = _MoveMeta(setsLabel: setsLabel, rest: '0s', restSeconds: 0);
      _checks[item.key] = _checks[item.key]?.isNotEmpty == true ? _checks[item.key]! : [false];
      if (item.key.startsWith('extra-')) {
        _extras = [
          for (final row in _extras)
            if (row.key == item.key)
              _RunnerItem(
                key: row.key,
                name: row.name,
                originalName: row.originalName,
                setsLabel: setsLabel,
                rest: '0s',
                restSeconds: 0,
                setCount: 1,
                kind: row.kind,
              )
            else
              row,
        ];
      }
    });
    _persistSession();
  }

  void _addSet(_RunnerItem item) {
    if (parseTimedMinutes(_meta[item.key]?.setsLabel ?? item.setsLabel) != null) {
      _nudgeMinutes(item, 5);
      return;
    }
    final current = List<bool>.from(_checks[item.key] ?? List<bool>.filled(item.setCount, false));
    if (current.length >= 10) return;
    current.add(false);
    final setsLabel = '${current.length} x ${_repsFromSets(_meta[item.key]?.setsLabel ?? item.setsLabel)}';
    final rest = _meta[item.key]?.rest ?? item.rest;
    setState(() {
      _checks[item.key] = current;
      _meta[item.key] = _MoveMeta(setsLabel: setsLabel, rest: rest, restSeconds: parseRestSeconds(rest));
      if (item.key.startsWith('extra-')) {
        _extras = [
          for (final row in _extras)
            if (row.key == item.key)
              _RunnerItem(
                key: row.key,
                name: row.name,
                originalName: row.originalName,
                setsLabel: setsLabel,
                rest: rest,
                restSeconds: parseRestSeconds(rest),
                setCount: current.length,
                kind: row.kind,
              )
            else
              row,
        ];
      }
    });
    _persistSession();
  }

  void _removeSet(_RunnerItem item) {
    if (parseTimedMinutes(_meta[item.key]?.setsLabel ?? item.setsLabel) != null) {
      _nudgeMinutes(item, -5);
      return;
    }
    final current = List<bool>.from(_checks[item.key] ?? List<bool>.filled(item.setCount, false));
    if (current.length <= 1) return;
    current.removeLast();
    final setsLabel = '${current.length} x ${_repsFromSets(_meta[item.key]?.setsLabel ?? item.setsLabel)}';
    final rest = _meta[item.key]?.rest ?? item.rest;
    setState(() {
      _checks[item.key] = current;
      _meta[item.key] = _MoveMeta(setsLabel: setsLabel, rest: rest, restSeconds: parseRestSeconds(rest));
      if (item.key.startsWith('extra-')) {
        _extras = [
          for (final row in _extras)
            if (row.key == item.key)
              _RunnerItem(
                key: row.key,
                name: row.name,
                originalName: row.originalName,
                setsLabel: setsLabel,
                rest: rest,
                restSeconds: parseRestSeconds(rest),
                setCount: current.length,
                kind: row.kind,
              )
            else
              row,
        ];
      }
    });
    _persistSession();
  }

  Future<void> _persistMove(int toIso, {String? fromLabel}) async {
    final plan = _plan;
    final today = _sessionDay;
    final fromDay = fromLabel ?? today?['day']?.toString();
    if (plan == null || fromDay == null) return;
    final id = (plan['id'] as num?)?.toInt();
    if (id == null) return;
    final days = [
      for (final raw in (plan['days'] as List? ?? const []))
        if (raw is Map) Map<String, dynamic>.from(raw),
    ];
    final fromIndex = days.indexWhere(
      (day) => day['day']?.toString() == fromDay,
    );
    if (fromIndex < 0) return;
    final next = moveSavedPlanDay(days, fromIndex, toIso);
    setState(() => _saving = true);
    try {
      await ref.read(vivrantApiProvider).updateGymPlan(id, {
        'title': plan['title'],
        'summary': plan['summary'],
        'focus': plan['focus'],
        'level': plan['level'],
        'days': next,
        'recommendations': plan['recommendations'],
        'training_days': trainingDaysFromSavedDays(
          next,
          (plan['training_days'] as List?)?.map((item) => (item as num).toInt()).toList(),
        ),
      });
      if (!mounted) return;
      final moved = next.firstWhere(
        (day) => weekdayIsoFromLabel(day['day']?.toString() ?? '') == toIso,
        orElse: () => next[fromIndex],
      );
      setState(() {
        _saving = false;
        _dayLabel = moved['day']?.toString() ?? _dayLabel;
        _resetFromPlan();
      });
      context.showSuccess('Moved that workout to a new weekday.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _save() async {
    final plan = _plan;
    final today = _sessionDay;
    if (plan == null || today == null) return;
    final logged = <Map<String, dynamic>>[];
    for (final item in _items) {
      final row = _checks[item.key] ?? const <bool>[];
      final completed = row.where((on) => on).length;
      if (completed == 0) continue;
      logged.add({
        'name': _names[item.key] ?? item.name,
        'sets': _meta[item.key]?.setsLabel ?? item.setsLabel,
        'rest': _meta[item.key]?.rest ?? item.rest,
        if ((_weights[item.key] ?? item.weight ?? '').trim().isNotEmpty)
          'weight': (_weights[item.key] ?? item.weight)!.trim(),
        'done': completed >= item.setCount,
        'completed_sets': completed,
      });
    }
    if (logged.isEmpty) {
      context.showError('Check off at least one set, then save.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(vivrantApiProvider).logGymSession({
        'title': '${today['day'] ?? 'Today'}: ${humanizeLabel(today['focus']?.toString() ?? 'workout')}',
        'focus': gymSessionFocusFromPlan(today['focus']?.toString() ?? 'full_body'),
        'duration_minutes': _elapsedMinutes,
        'notes': 'From program: ${plan['title'] ?? 'gym'}',
        'exercises': logged,
      });
      if (!mounted) return;
      _ticker?.cancel();
      setState(() {
        _saving = false;
        _startedAt = null;
        _restLabel = null;
        _restEndsAtMs = null;
        _restTotal = 0;
        _restored = false;
        _resetFromPlan();
      });
      await _clearPersistedSession();
      if (!mounted) return;
      context.showSuccess('Workout saved from your program');
      widget.onLogged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showError(apiErrorMessage(e));
    }
  }

  bool get _catchingUp {
    final missed = _missedDay;
    final session = _sessionDay;
    final calendar = _calendarToday;
    return missed != null &&
        session != null &&
        missed.day == session['day']?.toString() &&
        calendar?['day']?.toString() != session['day']?.toString();
  }

  bool get _showCatchUp {
    final missed = _missedDay;
    final session = _sessionDay;
    return widget.allowDayPick &&
        missed != null &&
        !_catchUpDismissed &&
        (session == null || missed.day != session['day']?.toString());
  }

  Widget _catchUpBanner(BuildContext context) {
    final missed = _missedDay;
    if (missed == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Skipped ${missed.weekdayName} · ${humanizeLabel(missed.focus)}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Use that workout today without changing your weekly plan.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: () {
                setState(() {
                  _dayLabel = missed.day;
                  _resetFromPlan();
                });
                _restoreSession();
              },
              child: Text('Use ${missed.weekdayName} today'),
            ),
            OutlinedButton(
              onPressed: _saving
                  ? null
                  : () => _persistMove(DateTime.now().weekday, fromLabel: missed.day),
              child: Text('Move ${missed.weekdayName} here'),
            ),
            TextButton(
              onPressed: () => setState(() => _catchUpDismissed = true),
              child: const Text("Keep today's"),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = VivrantColors.of(context);
    if (widget.plans.isEmpty) {
      return VivrantPanel(
        title: "Today's program",
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create a weekly program first — then today’s exercises show up here with checkboxes and a rest timer.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => context.push('/gym/plans'),
              child: const Text('Create a program'),
            ),
          ],
        ),
      );
    }

    final plan = _plan;
    final today = _sessionDay;
    if (plan == null || today == null) {
      final days = (plan?['days'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      return VivrantPanel(
        title: widget.allowDayPick ? 'Saved program day' : "Today's program",
        child: days.isNotEmpty && widget.allowDayPick
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rest day on the calendar — pick a saved day to train anyway.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_showCatchUp) ...[
                    const SizedBox(height: 12),
                    _catchUpBanner(context),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: null,
                    decoration: const InputDecoration(labelText: 'Start a saved day'),
                    items: [
                      for (final day in days)
                        DropdownMenuItem(
                          value: day['day']?.toString(),
                          child: Text(
                            '${day['day'] ?? 'Day'} · ${humanizeLabel(day['focus']?.toString() ?? '')}',
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _dayLabel = value;
                        _resetFromPlan();
                      });
                      _restoreSession();
                    },
                  ),
                ],
              )
            : const Text('Rest day — no session on your schedule today.'),
      );
    }

    final items = _items;
    return VivrantPanel(
      title: "Today's program",
      trailing: Text(
        '$_doneCount/$_totalCount sets',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: c.accent,
          fontSize: 12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Check off each set. Rest starts from the program — skip anytime. Use − Set for fewer rounds. Swipe a move to remove it. Leave and come back: your sets and rest timer stay.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_catchingUp && _missedDay != null) ...[
            const SizedBox(height: 8),
            Text(
              'Catching up on ${_missedDay!.weekdayName} · ${humanizeLabel(_missedDay!.focus)} — weekly plan stays as-is.',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: c.accent,
                fontSize: 12,
              ),
            ),
          ],
          if (_showCatchUp) ...[
            const SizedBox(height: 8),
            _catchUpBanner(context),
          ],
          if (_restored) ...[
            const SizedBox(height: 8),
            Text(
              'Restored your in-progress workout.',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: c.accent,
                fontSize: 12,
              ),
            ),
          ],
          if (widget.plans.length > 1) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey(_planId),
              initialValue: (plan['id'] as num?)?.toInt(),
              decoration: const InputDecoration(labelText: 'Program'),
              items: [
                for (final item in widget.plans)
                  DropdownMenuItem(
                    value: (item['id'] as num?)?.toInt(),
                    child: Text(item['title']?.toString() ?? 'Program'),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _planId = value;
                  _dayLabel = '';
                  _resetFromPlan();
                });
                _restoreSession();
              },
            ),
          ],
          if (widget.allowDayPick && ((plan['days'] as List?)?.length ?? 0) > 1) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('${_planId}_$_dayLabel'),
              initialValue: today['day']?.toString(),
              decoration: const InputDecoration(labelText: 'Day'),
              items: [
                for (final raw in (plan['days'] as List? ?? const []))
                  if (raw is Map)
                    DropdownMenuItem(
                      value: raw['day']?.toString(),
                      child: Text(
                        '${raw['day'] ?? 'Day'} · ${humanizeLabel(raw['focus']?.toString() ?? '')}${_calendarToday?['day']?.toString() == raw['day']?.toString() ? ' · today' : ''}',
                      ),
                    ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _dayLabel = value;
                  _resetFromPlan();
                });
                _restoreSession();
              },
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: ValueKey('move_${_planId}_$_dayLabel'),
            initialValue: weekdayIsoFromLabel(today['day']?.toString() ?? ''),
            decoration: const InputDecoration(labelText: 'Move this workout to'),
            items: [
              for (final item in gymWeekdays)
                DropdownMenuItem(
                  value: item.iso,
                  child: Text(
                    '${item.full}${weekdayIsoFromLabel(today['day']?.toString() ?? '') == item.iso ? ' · current' : ''}',
                  ),
                ),
            ],
            onChanged: _saving
                ? null
                : (value) {
                    if (value == null) return;
                    _persistMove(value);
                  },
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.accentSoft.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${today['day'] ?? 'Today'} · ${humanizeLabel(today['focus']?.toString() ?? '')}${_calendarToday?['day']?.toString() == today['day']?.toString() ? ' · today' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: c.accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  plan['title']?.toString() ?? 'Program',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          if (_restLabel != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: BoxDecoration(
                color: c.solid,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ' ${_restKind == 'work' ? 'WORK' : 'REST'} · $_restLabel',
                          style: TextStyle(
                            color: c.solidFg.withValues(alpha: 0.7),
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          formatRestClock(_restLeft),
                          style: TextStyle(
                            color: c.solidFg,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_restTotal > 0)
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        value: _restLeft / _restTotal,
                        color: c.accent,
                        backgroundColor: c.solidFg.withValues(alpha: 0.24),
                        strokeWidth: 3,
                      ),
                    ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _skipRest,
                    style: TextButton.styleFrom(foregroundColor: c.solidFg),
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          for (final item in items) ...[
            Dismissible(
              key: ValueKey(item.key),
              direction: DismissDirection.horizontal,
              onDismissed: (_) => _removeMove(item),
              background: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFB42318),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Remove',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
              secondaryBackground: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFB42318),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Remove',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
              child: _ExerciseCard(
              item: item,
              name: displayGymMoveName(_names[item.key] ?? item.name),
              weight: _weights[item.key] ?? item.weight ?? '',
              checks: _checks[item.key] ?? const [],
              catalog: _catalog,
              onNameChanged: (name) => _applyMoveName(item, name),
              onWeightChanged: (value) {
                setState(() => _weights[item.key] = value);
                _persistSession();
              },
              onToggleExercise: () => _toggleExercise(item),
              onToggleSet: (index) => _toggleSet(item, index),
              onAddSet: () => _addSet(item),
              onRemoveSet: () => _removeSet(item),
              onNudgeMinutes: (delta) => _nudgeMinutes(item, delta),
              onSwap: item.swap == null ? null : () => _swap(item),
            ),
            ),
            const SizedBox(height: 10),
          ],
          TextButton.icon(
            onPressed: _addExtra,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add a move'),
          ),
          TextButton.icon(
            onPressed: _snapMachine,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Snap a machine'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _saving || _doneCount == 0 ? null : _save,
            child: Text(
              _saving ? 'Saving…' : 'Save workout · $_elapsedMinutes min',
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.item,
    required this.name,
    required this.weight,
    required this.checks,
    required this.catalog,
    required this.onNameChanged,
    required this.onWeightChanged,
    required this.onToggleExercise,
    required this.onToggleSet,
    required this.onAddSet,
    required this.onRemoveSet,
    required this.onNudgeMinutes,
    this.onSwap,
  });

  final _RunnerItem item;
  final String name;
  final String weight;
  final List<bool> checks;
  final List<GymExercise> catalog;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onWeightChanged;
  final VoidCallback onToggleExercise;
  final ValueChanged<int> onToggleSet;
  final VoidCallback onAddSet;
  final VoidCallback onRemoveSet;
  final ValueChanged<int> onNudgeMinutes;
  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context) {
    final c = VivrantColors.of(context);
    final complete = checks.isNotEmpty && checks.every((on) => on);
    final timed = parseTimedMinutes(item.setsLabel);
    final cardio = isCardioGymMove(name);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: complete ? c.accentSoft.withValues(alpha: 0.55) : c.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: complete ? c.accent.withValues(alpha: 0.35) : c.ink.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: complete,
                onChanged: (_) => onToggleExercise(),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GymMovePickerField(
                        value: name == 'Extra move' ? '' : name,
                        onChanged: onNameChanged,
                        catalog: catalog,
                      ),
                      const SizedBox(height: 6),
                      _SessionWeightField(
                        value: weight,
                        onChanged: onWeightChanged,
                        label: cardio ? 'Pace' : 'Weight',
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          item.setsLabel,
                          if (item.restSeconds > 0) 'rest ${item.rest}',
                          if (item.kind == 'addon') 'extra',
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (item.notes != null)
            Padding(
              padding: const EdgeInsets.only(left: 48, bottom: 6),
              child: Text(item.notes!, style: Theme.of(context).textTheme.bodySmall),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (timed != null) ...[
                  FilterChip(
                    label: Text(checks.isNotEmpty && checks.first ? '$timed min done' : 'Start $timed min'),
                    selected: checks.isNotEmpty && checks.first,
                    onSelected: (_) => onToggleSet(0),
                  ),
                  ActionChip(label: const Text('−5'), onPressed: () => onNudgeMinutes(-5)),
                  ActionChip(label: const Text('+5'), onPressed: () => onNudgeMinutes(5)),
                ] else ...[
                  for (var i = 0; i < checks.length; i++)
                    FilterChip(
                      label: Text('Set ${i + 1}'),
                      selected: checks[i],
                      onSelected: (_) => onToggleSet(i),
                    ),
                  ActionChip(
                    label: const Text('− Set'),
                    onPressed: checks.length <= 1 ? null : onRemoveSet,
                  ),
                  ActionChip(label: const Text('+ Set'), onPressed: onAddSet),
                ],
              ],
            ),
          ),
          if (onSwap != null)
            TextButton.icon(
              onPressed: onSwap,
              icon: const Icon(Icons.swap_horiz_rounded, size: 16),
              label: Text(
                name == item.originalName
                    ? 'Swap for ${item.swap}'
                    : 'Back to ${item.originalName}',
              ),
            ),
        ],
      ),
    );
  }
}

class _SessionWeightField extends StatefulWidget {
  const _SessionWeightField({
    required this.value,
    required this.onChanged,
    this.label = 'Weight',
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  State<_SessionWeightField> createState() => _SessionWeightFieldState();
}

class _SessionWeightFieldState extends State<_SessionWeightField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _SessionWeightField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(labelText: widget.label, isDense: true),
      onChanged: widget.onChanged,
    );
  }
}
