import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/vivrant_colors.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/share_export.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/models/gym_exercise.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/module_cache.dart';
import '../../../../shared/providers/persistent_store.dart';
import '../../data/gym_labels.dart';
import '../widgets/exercise_demo_sheet.dart';
import '../widgets/saved_plan_day_actions.dart';
import '../widgets/saved_plan_editor_sheet.dart';

class GymPlansScreen extends ConsumerStatefulWidget {
  const GymPlansScreen({
    super.key,
    this.view = GymPlansView.builder,
  });

  final GymPlansView view;

  @override
  ConsumerState<GymPlansScreen> createState() => _GymPlansScreenState();
}

enum GymPlansView { builder, saved }

class _GymPlansScreenState extends ConsumerState<GymPlansScreen>
    with SelectableIdsMixin {
  static const _prefsDaysKey = 'vivrant.gym.plan.days';
  static const _prefsTrainingDaysKey = 'vivrant.gym.plan.trainingDays';
  static const _prefsSessionKey = 'vivrant.gym.plan.session';
  static const _prefsLevelKey = 'vivrant.gym.plan.level';
  static const _prefsKnownKey = 'vivrant.gym.knownMachines';
  static const _prefsCustomKey = 'vivrant.gym.knownCustom';
  static const _prefsAvoidKey = 'vivrant.gym.avoidTargets';

  final _query = TextEditingController();
  final _knownQuery = TextEditingController();
  final _customCtrl = TextEditingController();
  final _sessionCtrl = TextEditingController(text: '45');

  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _programHistory = [];
  Map<String, dynamic>? _draft;
  List<GymExercise> _exercises = const [];
  final Set<String> _knownSlugs = {};
  final List<String> _customExercises = [];
  final Set<String> _avoidTargets = {};
  final Set<int> _expanded = {};
  List<int> _trainingDays = defaultTrainingDaysFromCount(3);
  String _level = 'beginner';

  bool _loading = true;
  bool _generating = false;
  bool _showCustomize = false;
  String? _error;
  String _filter = 'all';
  String _knownMuscle = 'all';

  @override
  void initState() {
    super.initState();
    final cached = ref
        .read(moduleCacheProvider)
        .read<List<Map<String, dynamic>>>(ModuleCacheKeys.gymPlans);
    if (cached != null) {
      _plans = List<Map<String, dynamic>>.from(cached);
      _loading = false;
    }
    _restorePrefs();
    _restoreDraft();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _knownQuery.dispose();
    _customCtrl.dispose();
    _sessionCtrl.dispose();
    super.dispose();
  }

  Future<void> _restorePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final days = int.tryParse(prefs.getString(_prefsDaysKey) ?? '') ?? 3;
    final savedDays = prefs.getStringList(_prefsTrainingDaysKey);
    final trainingDays = sanitizeTrainingDays(
      (savedDays ?? const <String>[]).map((item) => int.tryParse(item) ?? 0),
      fallbackCount: days.clamp(2, 6).toInt(),
    );
    final session = int.tryParse(prefs.getString(_prefsSessionKey) ?? '') ?? 45;
    final level = sanitizeGymPlanLevel(prefs.getString(_prefsLevelKey));
    setState(() {
      _trainingDays = trainingDays;
      _sessionCtrl.text = session.clamp(15, 120).toString();
      _level = level;
      _knownSlugs
        ..clear()
        ..addAll(sanitizeKnownMachineSlugs(prefs.getStringList(_prefsKnownKey) ?? const []));
      _customExercises
        ..clear()
        ..addAll(sanitizeCustomExercises(prefs.getStringList(_prefsCustomKey) ?? const []));
      _avoidTargets
        ..clear()
        ..addAll(sanitizeAvoidTargets(prefs.getStringList(_prefsAvoidKey) ?? const []));
    });
  }

  Future<void> _restoreDraft() async {
    final local = await PersistentStore.instance.readJson(gymProgramDraftKey);
    if (!mounted) return;
    if (local != null) setState(() => _draft = local);
  }

  Future<void> _persistDraft(Map<String, dynamic>? draft) async {
    setState(() => _draft = draft);
    await PersistentStore.instance.writeJson(gymProgramDraftKey, draft);
  }

  Future<void> _persistPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final known = sanitizeKnownMachineSlugs(_knownSlugs);
    final customs = sanitizeCustomExercises(_customExercises);
    final avoids = sanitizeAvoidTargets(_avoidTargets);
    if (!mounted) return;
    if (known.length != _knownSlugs.length ||
        customs.length != _customExercises.length ||
        avoids.length != _avoidTargets.length) {
      setState(() {
        _knownSlugs
          ..clear()
          ..addAll(known);
        _customExercises
          ..clear()
          ..addAll(customs);
        _avoidTargets
          ..clear()
          ..addAll(avoids);
      });
    }
    await prefs.setString(_prefsDaysKey, _daysPerWeek.toString());
    await prefs.setStringList(
      _prefsTrainingDaysKey,
      _trainingDays.map((day) => day.toString()).toList(),
    );
    await prefs.setString(_prefsSessionKey, _sessionMinutes.toString());
    await prefs.setString(_prefsLevelKey, _level);
    await prefs.setStringList(_prefsKnownKey, known);
    await prefs.setStringList(_prefsCustomKey, customs);
    await prefs.setStringList(_prefsAvoidKey, avoids);
  }

  Future<void> _load() async {
    final showSpinner =
        ref.read(moduleCacheProvider).shouldShowSpinner(ModuleCacheKeys.gymPlans);
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(vivrantApiProvider);
      final plans = await api.gymPlans();
      final exerciseRows = await api.gymExercises();
      var history = <Map<String, dynamic>>[];
      try {
        history = await api.listActivity(entity: 'gym_plans');
      } catch (_) {}
      Map<String, dynamic>? draft;
      var remoteDraftOk = false;
      try {
        draft = await api.gymProgramDraft();
        remoteDraftOk = true;
      } catch (_) {
        draft = _draft;
      }
      if (!mounted) return;
      final exercises = exerciseRows.map(GymExercise.fromJson).toList(growable: false);
      ref.read(moduleCacheProvider).write(ModuleCacheKeys.gymPlans, plans);
      await PersistentStore.instance.writeJson('vivrant.gym.plans.snap', plans);
      if (remoteDraftOk) {
        await _persistDraft(draft);
      }
      setState(() {
        _plans = plans;
        _programHistory = history;
        _exercises = exercises;
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

  int get _daysPerWeek => _trainingDays.length;

  int get _sessionMinutes {
    final n = int.tryParse(_sessionCtrl.text.trim()) ?? 45;
    return n.clamp(15, 120);
  }

  Future<void> _createAi() async {
    setState(() => _generating = true);
    try {
      await _persistPrefs();
      final result = await ref.read(vivrantApiProvider).createAiGymPlan(
            daysPerWeek: _daysPerWeek,
            trainingDays: _trainingDays,
            sessionMinutes: _sessionMinutes,
            level: _level,
            knownMachineSlugs: _knownSlugs.toList(),
            knownCustomExercises: List<String>.from(_customExercises),
            avoidTargets: _avoidTargets.toList(),
          );
      if (!mounted) return;
      final draft = result['draft'] is Map
          ? Map<String, dynamic>.from(result['draft'] as Map)
          : null;
      if (draft != null) await _persistDraft(draft);
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: 'Workouts ready — keep the days you like',
        tone: SnackTone.success,
      );
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _keepDay(int iso) async {
    try {
      final result = await ref.read(vivrantApiProvider).gymProgramDraftAction(
            action: 'keep',
            iso: iso,
          );
      final draft = result['draft'] is Map
          ? Map<String, dynamic>.from(result['draft'] as Map)
          : null;
      if (draft != null) await _persistDraft(draft);
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _dropDay(int iso) async {
    try {
      final result = await ref.read(vivrantApiProvider).gymProgramDraftAction(
            action: 'drop',
            iso: iso,
          );
      final draft = result['draft'] is Map
          ? Map<String, dynamic>.from(result['draft'] as Map)
          : null;
      if (draft != null) await _persistDraft(draft);
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _savePlanDays(Map<String, dynamic> plan, List<Map<String, dynamic>> days) async {
    final id = (plan['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      final updated = await ref.read(vivrantApiProvider).updateGymPlan(id, {
        'title': plan['title'],
        'summary': plan['summary'],
        'focus': plan['focus'],
        'level': plan['level'],
        'days': days,
        'recommendations': plan['recommendations'],
        'training_days': trainingDaysFromSavedDays(
          days,
          (plan['training_days'] as List?)
              ?.map((item) => (item as num).toInt())
              .toList(),
        ),
      });
      if (!mounted) return;
      setState(() {
        _plans = [
          for (final item in _plans)
            if ((item['id'] as num?)?.toInt() == id) updated else item,
        ];
      });
      ref.read(moduleCacheProvider).write(ModuleCacheKeys.gymPlans, _plans);
      context.showSuccess('Program updated');
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _moveKeptDay(int fromIso, int toIso) async {
    final current = _draft;
    if (current == null) return;
    final updated = moveKeptDayOnDraft(current, fromIso, toIso);
    setState(() => _draft = updated);
    try {
      final saved = await ref.read(vivrantApiProvider).saveGymProgramDraft(updated);
      await _persistDraft(saved.isNotEmpty ? saved : updated);
    } catch (e) {
      if (!mounted) return;
      await _persistDraft(current);
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _reorderPreviewExercises(int dayIndex, int from, int to) async {
    final current = _draft;
    if (current == null) return;
    final updated = reorderPreviewExercisesOnDraft(current, dayIndex, from, to);
    setState(() => _draft = updated);
    try {
      final saved = await ref.read(vivrantApiProvider).saveGymProgramDraft(updated);
      await _persistDraft(saved.isNotEmpty ? saved : updated);
    } catch (e) {
      if (!mounted) return;
      await _persistDraft(current);
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _mergeIntoDraft(Map<String, dynamic> plan) async {
    final days = [
      for (final raw in (plan['days'] as List? ?? const []))
        if (raw is Map) Map<String, dynamic>.from(raw),
    ];
    if (days.isEmpty) return;
    final current = _draft;
    final updated = current == null
        ? draftFromSavedPlan(plan, trainingDays: _trainingDays)
        : mergePlanDaysIntoDraft(current, days);
    setState(() {
      _draft = updated;
      _trainingDays = sanitizeTrainingDays(
        (updated['training_days'] as List? ?? _trainingDays).map((item) => (item as num).toInt()),
      );
    });
    try {
      final saved = await ref.read(vivrantApiProvider).saveGymProgramDraft(updated);
      await _persistDraft(saved.isNotEmpty ? saved : updated);
      if (!mounted) return;
      context.showSuccess('Added ${plan['title'] ?? 'program'} days to this week');
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _customizeDraft() async {
    final current = _draft;
    if (current == null) return;
    final isos = keptIsoList(current);
    final kept = keptDaysMap(current);
    final days = [
      for (final iso in isos)
        if (kept['$iso'] is Map) Map<String, dynamic>.from(kept['$iso'] as Map),
    ];
    if (days.isEmpty) return;
    final result = await SavedPlanEditorSheet.show(
      context,
      {
        ...current,
        'title': current['title'] ?? 'Program',
        'days': days,
      },
      catalog: _exercises,
      bodyWeightKg: ref.read(authProvider).profile?.weightKg,
    );
    if (result == null || !mounted) return;
    final nextKept = <String, dynamic>{};
    for (final raw in (result['days'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final day = Map<String, dynamic>.from(raw);
      final iso = weekdayIsoFromLabel(day['day']?.toString() ?? '') ?? (nextKept.length + 1);
      nextKept['$iso'] = day;
    }
    final updated = {
      ...current,
      'title': result['title'] ?? current['title'],
      'summary': result['summary'] ?? current['summary'],
      'kept_days': nextKept,
    };
    try {
      final saved = await ref.read(vivrantApiProvider).saveGymProgramDraft(updated);
      await _persistDraft(saved.isNotEmpty ? saved : updated);
      if (!mounted) return;
      context.showSuccess('Draft customized');
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _saveDraftProgram() async {
    try {
      await ref.read(vivrantApiProvider).commitGymProgramDraft();
      if (!mounted) return;
      await _persistDraft(null);
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: 'Program saved from the days you kept',
        tone: SnackTone.success,
        actionLabel: 'Start today',
        onAction: () => context.push('/gym/sessions'),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _discardDraft() async {
    final ok = await confirmAction(
      context,
      title: 'Clear this draft?',
      body: 'Unsaved generated days will be discarded.',
      confirmLabel: 'Clear',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(vivrantApiProvider).discardGymProgramDraft();
      if (!mounted) return;
      await _persistDraft(null);
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  void _toggleTrainingDay(int iso) {
    final selected = _trainingDays.contains(iso);
    if (selected) {
      if (_trainingDays.length <= 2) return;
      setState(() => _trainingDays = _trainingDays.where((day) => day != iso).toList());
    } else {
      if (_trainingDays.length >= 6) return;
      setState(() {
        _trainingDays = [..._trainingDays, iso]..sort();
      });
    }
    _persistPrefs();
  }

  void _addCustom() {
    final cleaned = sanitizeCustomExercises([..._customExercises, _customCtrl.text]);
    if (cleaned.isEmpty) return;
    setState(() {
      _customExercises
        ..clear()
        ..addAll(cleaned);
      _customCtrl.clear();
    });
    _persistPrefs();
  }

  void _toggleKnown(String slug) {
    final cleaned = sanitizeKnownMachineSlugs([slug]);
    if (cleaned.isEmpty) return;
    final key = cleaned.first;
    setState(() {
      if (_knownSlugs.contains(key)) {
        _knownSlugs.remove(key);
      } else if (_knownSlugs.length < maxKnownMachineSlugs) {
        _knownSlugs.add(key);
      }
    });
    _persistPrefs();
  }

  void _clearKnown() {
    setState(() {
      _knownSlugs.clear();
      _customExercises.clear();
    });
    _persistPrefs();
  }

  void _toggleSelectAllKnownInView() {
    final visible = _visibleKnownExercises.map((e) => e.slug).toList(growable: false);
    if (visible.isEmpty) return;
    final allSelected = visible.every(_knownSlugs.contains);
    setState(() {
      if (allSelected) {
        _knownSlugs.removeAll(visible);
      } else {
        for (final slug in visible) {
          if (_knownSlugs.length >= maxKnownMachineSlugs) break;
          _knownSlugs.add(slug);
        }
      }
    });
    _persistPrefs();
  }

  bool _matchesKnownSearch(GymExercise exercise, String q) {
    if (q.isEmpty) return true;
    return exercise.name.toLowerCase().contains(q) ||
        exercise.muscleGroup.toLowerCase().contains(q) ||
        exercise.equipment.toLowerCase().contains(q);
  }

  List<GymExercise> _filterKnownList(List<GymExercise> source) {
    final q = _knownQuery.text.trim().toLowerCase();
    return source
        .where(
          (exercise) =>
              matchesMuscleFilter(exercise.muscleGroup, _knownMuscle) &&
              _matchesKnownSearch(exercise, q),
        )
        .toList(growable: false);
  }

  List<String> get _focuses {
    final values = _plans
        .map((p) => p['focus']?.toString() ?? '')
        .where((f) => f.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _query.text.trim().toLowerCase();
    return _plans.where((p) {
      final focus = p['focus']?.toString() ?? '';
      if (_filter != 'all' && focus != _filter) return false;
      if (q.isEmpty) return true;
      final title = p['title']?.toString().toLowerCase() ?? '';
      return title.contains(q) || focus.toLowerCase().contains(q);
    }).toList();
  }

  List<GymExercise> get _machines =>
      _exercises.where((e) => e.isMachine).toList(growable: false);

  List<GymExercise> get _freeWeights =>
      _exercises.where((e) => !e.isMachine).toList(growable: false);

  List<GymExercise> get _filteredMachines => _filterKnownList(_machines);

  List<GymExercise> get _filteredFreeWeights => _filterKnownList(_freeWeights);

  List<GymExercise> get _visibleKnownExercises =>
      [..._filteredMachines, ..._filteredFreeWeights];

  bool get _allVisibleKnownSelected {
    final visible = _visibleKnownExercises;
    return visible.isNotEmpty && visible.every((e) => _knownSlugs.contains(e.slug));
  }

  Future<void> _removePlan(int id, {bool confirm = true, String? title}) async {
    if (confirm) {
      if (!(await confirmDelete(context, label: title ?? 'this program'))) return;
    }
    try {
      await ref.read(vivrantApiProvider).deleteGymPlan(id);
      if (!mounted) return;
      setState(() {
        _plans = _plans.where((item) => (item['id'] as num).toInt() != id).toList();
        _expanded.remove(id);
      });
      ref.read(moduleCacheProvider).write(ModuleCacheKeys.gymPlans, _plans);
      context.showSuccess('Program removed');
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final theme = Theme.of(context);
    final isBuilder = widget.view == GymPlansView.builder;
    final isSaved = widget.view == GymPlansView.saved;
    return GradientScaffold(
      appBar: AppBar(
        title: Text(isSaved ? 'Saved programs' : 'Create program'),
        actions: [
          if (isSaved && _plans.isNotEmpty)
            ShareExportButton(doc: gymPlansDoc(_plans)),
          if (isSaved)
            ...selectAppBarActions(
              visibleIds: filtered
                  .map((p) => (p['id'] as num?)?.toInt())
                  .whereType<int>(),
              onArchive: () => confirmAndArchiveSelected(
                request: (ids) => ref.read(vivrantApiProvider).archiveItems(
                      entity: 'gym_plans',
                      ids: ids,
                    ),
                onRemoved: (ids) {
                  setState(() {
                    _plans = _plans
                        .where((item) => !ids.contains((item['id'] as num).toInt()))
                        .toList();
                    _expanded.removeAll(ids);
                  });
                  ref.read(moduleCacheProvider).write(ModuleCacheKeys.gymPlans, _plans);
                },
              ),
            ),
          if (isBuilder)
            IconButton(
              onPressed: _generating ? null : _createAi,
              icon: _generating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
            ),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: VivrantLayout.pagePadding,
          children: [
            if (isBuilder) ...[
            const PageHeader(
              eyebrow: 'Gym',
              title: 'Create',
              highlight: 'program',
            ),
            Text(
              'Pick the weekdays you train. Generate workouts, keep the days you like, generate again for the rest, then save — nothing hits your program list until you keep it.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            VivrantPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How often do you train?',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pick weekdays, minutes, and experience, then create a program. Extra options are optional.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Training days',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$_daysPerWeek days/week${formatRestDaysLabel(_trainingDays).isEmpty ? '' : ' · ${formatRestDaysLabel(_trainingDays)}'}. Pick 2–6.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in gymWeekdays)
                        FilterChip(
                          label: Text(item.short),
                          selected: _trainingDays.contains(item.iso),
                          onSelected: (_) => _toggleTrainingDay(item.iso),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Minutes per workout',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final mins in [
                        ...sessionMinutePresets,
                        if (!sessionMinutePresets.contains(_sessionMinutes)) _sessionMinutes,
                      ])
                        ChoiceChip(
                          label: Text('$mins min'),
                          selected: _sessionMinutes == mins,
                          onSelected: (_) {
                            _sessionCtrl.text = mins.toString();
                            _persistPrefs();
                            setState(() {});
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Experience',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Working loads use your body weight and this level.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final item in gymPlanLevels)
                        ChoiceChip(
                          label: Text(humanizeLabel(item)),
                          selected: _level == item,
                          onSelected: (_) {
                            setState(() => _level = item);
                            _persistPrefs();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _generating ? null : _createAi,
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(
                        _generating ? 'Generating workouts…' : 'Generate workouts',
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _showCustomize = !_showCustomize),
                    icon: Icon(
                      _showCustomize
                          ? Icons.expand_less
                          : Icons.tune_rounded,
                    ),
                    label: Text(
                      _showCustomize
                          ? 'Hide optional settings'
                          : 'Customize (optional)',
                    ),
                  ),
                  if (_showCustomize) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Skip these areas',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final target in gymAvoidTargets)
                          FilterChip(
                            label: Text(humanizeLabel(target)),
                            selected: _avoidTargets.contains(target),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _avoidTargets.add(target);
                                } else {
                                  _avoidTargets.remove(target);
                                }
                              });
                              _persistPrefs();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Moves you already know',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Optional: mark exercises you know. If you pick any, your program uses only those (plus anything you type) and will not add extras like a leg press.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(
                          label: Text(
                            '${_knownSlugs.length + _customExercises.length} selected',
                          ),
                        ),
                        if (_visibleKnownExercises.isNotEmpty)
                          TextButton(
                            onPressed: _toggleSelectAllKnownInView,
                            child: Text(
                              _allVisibleKnownSelected
                                  ? 'Clear these'
                                  : 'Select these (${_visibleKnownExercises.length})',
                            ),
                          ),
                        if (_knownSlugs.isNotEmpty ||
                            _customExercises.isNotEmpty)
                          TextButton(
                            onPressed: _clearKnown,
                            child: const Text('Clear all'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    VivrantSearchField(
                      controller: _knownQuery,
                      hintText: 'Search exercises…',
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    VivrantFilterChips<String>(
                      options: [
                        for (final muscle in gymMuscleFilters)
                          VivrantFilterOption(
                            value: muscle,
                            label: muscleFilterLabel(muscle),
                          ),
                      ],
                      selected: _knownMuscle,
                      onSelected: (v) => setState(() => _knownMuscle = v),
                    ),
                    const SizedBox(height: 10),
                    _ExerciseChecklist(
                      title: 'Machines (${_filteredMachines.length})',
                      exercises: _filteredMachines,
                      emptyMessage: _machines.isEmpty
                          ? 'No machines listed yet.'
                          : 'No machines match this search.',
                      selected: _knownSlugs,
                      onToggle: _toggleKnown,
                      onDemo: (ex) => showExerciseDemoSheet(context, ex),
                    ),
                    const SizedBox(height: 10),
                    _ExerciseChecklist(
                      title:
                          'Free weights & bodyweight (${_filteredFreeWeights.length})',
                      exercises: _filteredFreeWeights,
                      emptyMessage: _freeWeights.isEmpty
                          ? 'No free-weight moves listed yet.'
                          : 'No free-weight moves match this search.',
                      selected: _knownSlugs,
                      onToggle: _toggleKnown,
                      onDemo: (ex) => showExerciseDemoSheet(context, ex),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Other moves',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customCtrl,
                            decoration: const InputDecoration(
                              hintText: 'e.g. Hip thrust…',
                            ),
                            onSubmitted: (_) => _addCustom(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _addCustom,
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    if (_customExercises.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final name in _customExercises)
                            InputChip(
                              label: Text(name),
                              onDeleted: () {
                                setState(() => _customExercises.remove(name));
                                _persistPrefs();
                              },
                            ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_draft != null)
              _ProgramDraftPanel(
                draft: _draft!,
                generating: _generating,
                onKeep: _keepDay,
                onDrop: _dropDay,
                onMoveKept: _moveKeptDay,
                onReorderPreview: _reorderPreviewExercises,
                onGenerate: _createAi,
                onSave: _saveDraftProgram,
                onDiscard: _discardDraft,
                onCustomize: _customizeDraft,
                onShare: () => showShareExportSheet(context, gymProgramDraftDoc(_draft!)),
              ),
            if (_draft != null) const SizedBox(height: 18),
            ],
            if (isSaved) ...[
            const PageHeader(
              eyebrow: 'Gym',
              title: 'Saved',
              highlight: 'programs',
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              EmptyState(
                message: _error!,
                action: OutlinedButton(
                  onPressed: _load,
                  child: const Text('Try again'),
                ),
              )
            else if (_plans.isEmpty)
              EmptyState(
                title: 'No program yet',
                message:
                    'Create a week of workouts, keep the days you like, then save.',
                action: ElevatedButton(
                  onPressed: () => context.push('/gym/plans/build'),
                  child: const Text('Create a program'),
                ),
              )
            else ...[
              VivrantSearchField(
                controller: _query,
                hintText: 'Search programs…',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              VivrantFilterChips<String>(
                options: [
                  VivrantFilterOption(
                    value: 'all',
                    label: 'All',
                    count: _plans.length,
                  ),
                  ..._focuses.map(
                    (f) => VivrantFilterOption(
                      value: f,
                      label: humanizeLabel(f),
                      count: _plans
                          .where((p) => p['focus']?.toString() == f)
                          .length,
                    ),
                  ),
                ],
                selected: _filter,
                onSelected: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                const EmptyState(
                  message:
                      'No programs match these filters. Try All or another search.',
                )
              else
                ...filtered.map((p) {
                  final id = (p['id'] as num).toInt();
                  final title = (p['title'] as String?)?.trim().isNotEmpty == true
                      ? p['title'] as String
                      : 'this program';
                  final card = _PlanCard(
                      plan: p,
                      exercises: _knownSlugs.isEmpty && _customExercises.isEmpty
                          ? _exercises
                          : _exercises
                              .where((e) => _knownSlugs.contains(e.slug))
                              .toList(growable: false),
                      catalog: _exercises,
                      bodyWeightKg: ref.watch(authProvider).profile?.weightKg,
                      expanded: _expanded.contains((p['id'] as num?)?.toInt()),
                      onToggleExpand: () {
                        final id = (p['id'] as num?)?.toInt();
                        if (id == null) return;
                        setState(() {
                          if (_expanded.contains(id)) {
                            _expanded.remove(id);
                          } else {
                            _expanded.add(id);
                          }
                        });
                      },
                      onUseInDraft: () => _mergeIntoDraft(p),
                      onSaveDays: (days) => _savePlanDays(p, days),
                      onShare: () => showShareExportSheet(context, gymPlanDoc(p)),
                      onEdit: () async {
                        final id = (p['id'] as num?)?.toInt();
                        if (id == null) return;
                        final draft = await SavedPlanEditorSheet.show(
                          context,
                          p,
                          catalog: _exercises,
                          bodyWeightKg: ref.read(authProvider).profile?.weightKg,
                        );
                        if (draft == null || !mounted) return;
                        try {
                          final updated = await ref.read(vivrantApiProvider).updateGymPlan(id, draft);
                          if (!mounted) return;
                          setState(() {
                            _plans = [
                              for (final item in _plans)
                                if ((item['id'] as num?)?.toInt() == id) updated else item,
                            ];
                          });
                          ref.read(moduleCacheProvider).write(ModuleCacheKeys.gymPlans, _plans);
                          context.showSuccess('Program updated');
                        } catch (e) {
                          if (!mounted) return;
                          context.showError(apiErrorMessage(e));
                        }
                      },
                      onDelete: () => _removePlan(id, title: title),
                    );
                  if (selecting) {
                    return GestureDetector(
                      onTap: () => toggleSelected(id),
                      child: Stack(
                        children: [
                          IgnorePointer(child: card),
                          Positioned(
                            left: 12,
                            top: 18,
                            child: selectLeading(selectedIds.contains(id)),
                          ),
                        ],
                      ),
                    );
                  }
                  return wrapArchiveable(
                    id: id,
                    label: title,
                    archive: () => _removePlan(id, confirm: false, title: title),
                    child: card,
                  );
                }),
            ],
              if (!_loading && _error == null && _programHistory.isNotEmpty) ...[
                const SizedBox(height: 18),
                const SectionLabel('Program history'),
                const SizedBox(height: 8),
                for (final item in _programHistory.take(12)) ...[
                  VivrantPanel(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        (item['title'] as String?)?.trim().isNotEmpty == true
                            ? item['title'] as String
                            : 'Gym program',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        [
                          item['detail'] as String?,
                          item['created_at'] as String?,
                        ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' · '),
                      ),
                      onTap: () => context.push('/profile/activity'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _ProgramDraftPanel extends StatelessWidget {
  const _ProgramDraftPanel({
    required this.draft,
    required this.generating,
    required this.onKeep,
    required this.onDrop,
    required this.onMoveKept,
    required this.onReorderPreview,
    required this.onGenerate,
    required this.onSave,
    required this.onDiscard,
    required this.onCustomize,
    required this.onShare,
  });

  final Map<String, dynamic> draft;
  final bool generating;
  final ValueChanged<int> onKeep;
  final ValueChanged<int> onDrop;
  final void Function(int fromIso, int toIso) onMoveKept;
  final void Function(int dayIndex, int from, int to) onReorderPreview;
  final VoidCallback onGenerate;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final VoidCallback onCustomize;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trainingDays = (draft['training_days'] as List? ?? const [])
        .whereType<num>()
        .map((n) => n.round())
        .where((n) => n >= 1 && n <= 7)
        .toList();
    final kept = keptDaysMap(draft);
    final remaining = remainingTrainingDays(trainingDays, draft);
    final keptCount = keptIsoList(draft).length;
    final preview = (draft['preview_days'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final remainingLabel = remaining
        .map((iso) => gymWeekdays.firstWhere((item) => item.iso == iso).short)
        .join(', ');

    return VivrantPanel(
      title: 'Build your week',
      trailing: IconButton(
        tooltip: 'Share or export draft',
        onPressed: onShare,
        icon: const Icon(Icons.ios_share_rounded),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keep the days you like, then long-press a kept day and drop it on another weekday. Customize to drag moves. Nothing is saved to your program list until you tap Save program.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Text(
            remaining.isEmpty
                ? '$keptCount/${trainingDays.length} days kept · ready to save'
                : '$keptCount/${trainingDays.length} days kept · still need $remainingLabel',
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final iso in trainingDays)
                Builder(
                  builder: (context) {
                    final weekday = gymWeekdays.firstWhere((item) => item.iso == iso);
                    final keptDay = kept['$iso'] is Map
                        ? Map<String, dynamic>.from(kept['$iso'] as Map)
                        : null;
                    final chip = InputChip(
                      selected: keptDay != null,
                      label: Text(
                        keptDay == null
                            ? weekday.short
                            : '${weekday.short} · ${humanizeLabel(keptDay['focus']?.toString() ?? '')}',
                      ),
                      onDeleted: keptDay == null ? null : () => onDrop(iso),
                      onPressed: keptDay == null ? null : () => onDrop(iso),
                    );
                    return DragTarget<int>(
                      onWillAcceptWithDetails: (details) => details.data != iso,
                      onAcceptWithDetails: (details) => onMoveKept(details.data, iso),
                      builder: (context, candidate, rejected) {
                        final highlighted = candidate.isNotEmpty;
                        final child = AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          padding: highlighted ? const EdgeInsets.all(2) : EdgeInsets.zero,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: highlighted
                                ? Border.all(color: Theme.of(context).colorScheme.primary)
                                : null,
                          ),
                          child: chip,
                        );
                        if (keptDay == null) return child;
                        return LongPressDraggable<int>(
                          data: iso,
                          feedback: Material(
                            color: Colors.transparent,
                            child: InputChip(
                              selected: true,
                              label: Text(
                                '${weekday.short} · ${humanizeLabel(keptDay['focus']?.toString() ?? '')}',
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(opacity: 0.35, child: child),
                          child: child,
                        );
                      },
                    );
                  },
                ),
            ],
          ),
          if (keptCount > 0) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onCustomize,
              icon: const Icon(Icons.drag_indicator),
              label: const Text('Customize kept days'),
            ),
          ],
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Latest generated workouts',
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              'Long-press a move, then drag to reorder.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (var dayIndex = 0; dayIndex < preview.length; dayIndex++)
              Builder(
                builder: (context) {
                  final day = preview[dayIndex];
                  final exercises = [
                    for (final raw in (day['exercises'] as List? ?? const []))
                      if (raw is Map) Map<String, dynamic>.from(raw),
                  ];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${day['day'] ?? 'Day'} · ${humanizeLabel(day['focus']?.toString() ?? '')}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        NestedReorderableColumn(
                          itemCount: exercises.length,
                          keyOf: (i) => '$dayIndex-$i-${exercises[i]['name']}',
                          onReorder: (from, to) => onReorderPreview(dayIndex, from, to),
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              formatGymExerciseLine(exercises[index]),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () {
                              final iso = weekdayIsoFromLabel(day['day']?.toString() ?? '');
                              if (iso != null) onKeep(iso);
                            },
                            icon: const Icon(Icons.check_rounded, size: 16),
                            label: Text(
                              kept['${weekdayIsoFromLabel(day['day']?.toString() ?? '')}'] != null
                                  ? 'Replace kept day'
                                  : 'Keep this day',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: generating ? null : onGenerate,
              icon: const Icon(Icons.auto_awesome),
              label: Text(
                generating
                    ? 'Generating…'
                    : remaining.isEmpty
                        ? 'Generate new options'
                        : 'Generate remaining days',
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: keptCount == 0 ? null : onSave,
              child: Text(
                'Save program · $keptCount day${keptCount == 1 ? '' : 's'}',
              ),
            ),
          ),
          TextButton(
            onPressed: onDiscard,
            child: const Text('Clear draft'),
          ),
        ],
      ),
    );
  }
}

class _ExerciseChecklist extends StatelessWidget {
  const _ExerciseChecklist({
    required this.title,
    required this.exercises,
    required this.emptyMessage,
    required this.selected,
    required this.onToggle,
    required this.onDemo,
  });

  final String title;
  final List<GymExercise> exercises;
  final String emptyMessage;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final ValueChanged<GymExercise> onDemo;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 6),
        if (exercises.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              emptyMessage,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: exercises.length,
              itemBuilder: (context, index) {
                final ex = exercises[index];
                final checked = selected.contains(ex.slug);
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: checked,
                  onChanged: (_) => onToggle(ex.slug),
                  title: Row(
                    children: [
                      _KnownExerciseThumb(exercise: ex),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ex.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '${humanizeLabel(ex.muscleGroup)} · ${humanizeLabel(ex.equipment)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  secondary: ex.hasDemo
                      ? IconButton(
                          tooltip: 'Demo',
                          onPressed: () => onDemo(ex),
                          icon: const Icon(Icons.play_circle_outline),
                        )
                      : null,
                );
              },
            ),
          ),
      ],
    );
  }
}

class _KnownExerciseThumb extends StatelessWidget {
  const _KnownExerciseThumb({
    required this.exercise,
    this.size = 40,
  });

  final GymExercise exercise;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = VivrantColors.of(context);
    final thumb = exercise.demoThumbnailUrl?.trim();
    final hasThumb = thumb != null && thumb.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: hasThumb
            ? CachedNetworkImage(
                imageUrl: thumb,
                fit: BoxFit.cover,
                placeholder: (_, __) => ColoredBox(
                  color: c.accentSoft,
                  child: Icon(muscleIcon(exercise.muscleGroup), color: c.accent, size: 18),
                ),
                errorWidget: (_, __, ___) => ColoredBox(
                  color: c.accentSoft,
                  child: Icon(muscleIcon(exercise.muscleGroup), color: c.accent, size: 18),
                ),
              )
            : ColoredBox(
                color: c.accentSoft,
                child: Icon(muscleIcon(exercise.muscleGroup), color: c.accent, size: 18),
              ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.exercises,
    required this.catalog,
    this.bodyWeightKg,
    required this.expanded,
    required this.onToggleExpand,
    required this.onShare,
    required this.onEdit,
    required this.onDelete,
    required this.onUseInDraft,
    required this.onSaveDays,
  });

  final Map<String, dynamic> plan;
  final List<GymExercise> exercises;
  final List<GymExercise> catalog;
  final double? bodyWeightKg;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onShare;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onUseInDraft;
  final Future<void> Function(List<Map<String, dynamic>> days) onSaveDays;

  void _openSession(BuildContext context, {String? day}) {
    final planId = (plan['id'] as num?)?.toInt();
    final uri = Uri(
      path: '/gym/sessions',
      queryParameters: {
        if (planId != null) 'plan': '$planId',
        if (day != null && day.isNotEmpty) 'day': day,
      },
    );
    context.push(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final daysPerWeek = plan['days_per_week'] ?? (plan['days'] is List ? (plan['days'] as List).length : null);
    final summary = plan['summary']?.toString();
    final recs = programRecommendations(plan);
    final days = enrichPlanDays(
      (plan['days'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      exercises,
    );
    final scheduleDays = (plan['training_days'] as List?)
            ?.map((item) => (item as num).toInt())
            .toList() ??
        resolveTrainingDays(days: days, daysPerWeek: (daysPerWeek as num?)?.toInt());
    final schedule = formatTrainingDaysLabel(scheduleDays);
    final today = pickTodaysPlanDay(days, null, scheduleDays);
    final todayFirst = (today?['exercises'] as List?)
        ?.whereType<Map>()
        .map((e) => e['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .firstOrNull;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: VivrantPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan['title']?.toString() ?? 'Program',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '${humanizeLabel(plan['focus']?.toString() ?? 'program')} · ${plan['level'] ?? '—'} · ${schedule.isNotEmpty ? schedule : '${daysPerWeek ?? '—'} days/wk'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          today == null
                              ? 'Rest day · recovery'
                              : [
                                  'Today',
                                  today['day']?.toString() ?? '',
                                  humanizeLabel(today['focus']?.toString() ?? ''),
                                  if (todayFirst != null) todayFirst,
                                ].where((part) => part.isNotEmpty).join(' · '),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: today == null
                                    ? null
                                    : Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: expanded ? 'Hide days' : 'Show days',
                  onPressed: onToggleExpand,
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                ),
                IconButton(
                  tooltip: 'Share or export',
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: onShare,
                ),
                IconButton(
                  tooltip: 'Edit program',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onEdit,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openSession(context, day: today?['day']?.toString()),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(today == null ? 'Start a saved day' : "Start today's workout"),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: onUseInDraft,
                icon: const Icon(Icons.merge_type_rounded),
                label: const Text('Add days to this week'),
              ),
            ),
            if (days.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final day in days)
                    ActionChip(
                      avatar: const Icon(Icons.play_arrow_rounded, size: 16),
                      label: Text(day['day']?.toString() ?? 'Day'),
                      onPressed: () => _openSession(context, day: day['day']?.toString()),
                    ),
                ],
              ),
            ],
            if (summary != null && summary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(summary, style: Theme.of(context).textTheme.bodySmall),
            ],
            if (recs.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Coach notes',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 6),
              for (final rec in recs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          rec,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (days.any(
              (day) =>
                  dayAlternatives(day).isNotEmpty || dayAdditionals(day).isNotEmpty,
            )) ...[
              const SizedBox(height: 10),
              Text(
                'Suggestions to add',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'If a machine is busy or you have extra minutes, use these swaps and extras.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final day in days)
                if (dayAlternatives(day).isNotEmpty || dayAdditionals(day).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${day['day'] ?? 'Day'}: ${[
                        ...dayAlternatives(day).map(
                          (swap) => '${swap['use']} instead of ${swap['instead_of']}',
                        ),
                        ...dayAdditionals(day).map(
                          (addon) => addon['sets'] != null && addon['sets']!.isNotEmpty
                              ? 'add ${addon['name']} (${addon['sets']})'
                              : 'add ${addon['name']}',
                        ),
                      ].join(' · ')}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
            ],
            if (expanded && days.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final day in days) ...[
                Text(
                  '${day['day'] ?? 'Day'} · ${humanizeLabel(day['focus']?.toString() ?? '')}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                for (final raw in (day['exercises'] as List? ?? const []))
                  Builder(
                    builder: (context) {
                      final ex = Map<String, dynamic>.from(raw as Map);
                      final details = gymMoveDetails(ex['name']?.toString() ?? 'Movement');
                      final notes = ex['notes']?.toString() ?? '';
                      final linked = findExerciseMatch(details.displayName, exercises) ??
                          findRelatedExerciseMatch(details.displayName, exercises);
                      final cue = notes.isNotEmpty
                          ? notes
                          : (linked?.cues?.trim().isNotEmpty == true
                              ? linked!.cues!
                              : details.cues);
                      final sets = [
                        if ((ex['sets']?.toString() ?? '').isNotEmpty) ex['sets'],
                        if ((ex['weight']?.toString() ?? '').trim().isNotEmpty) ex['weight'],
                        if ((ex['rest']?.toString() ?? '').isNotEmpty) 'rest ${ex['rest']}',
                      ].join(' · ');
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (linked != null)
                              _KnownExerciseThumb(exercise: linked, size: 32)
                            else
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: ColoredBox(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                                    child: Icon(
                                      muscleIcon(details.muscleGroup),
                                      size: 16,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    details.displayName,
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  Text(
                                    '${humanizeLabel(linked?.muscleGroup ?? details.muscleGroup)} · ${humanizeLabel(linked?.equipment ?? details.equipment)}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  if (sets.isNotEmpty)
                                    Text(sets, style: Theme.of(context).textTheme.bodySmall),
                                  Text(
                                    cue,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          fontSize: 11,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            if (linked != null && linked.hasDemo)
                              TextButton(
                                onPressed: () => showExerciseDemoSheet(context, linked),
                                child: const Text('Demo'),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                SavedPlanDayActions(
                  plan: plan,
                  day: day,
                  dayIndex: days.indexOf(day),
                  catalog: catalog,
                  bodyWeightKg: bodyWeightKg,
                  onStart: () => _openSession(context, day: day['day']?.toString()),
                  onSaveDays: onSaveDays,
                ),
                if (dayAlternatives(day).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Alternatives',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  for (final swap in dayAlternatives(day))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.swap_horiz_rounded,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${swap['use']} instead of ${swap['instead_of']}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (dayAdditionals(day).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Add to this workout',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  for (final addon in dayAdditionals(day))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.add_circle_outline_rounded,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              addon['sets'] != null && addon['sets']!.isNotEmpty
                                  ? '${addon['name']} · ${addon['sets']}'
                                  : addon['name'] ?? '',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                const SizedBox(height: 10),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
