import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/vivrant_colors.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/models/gym_exercise.dart';
import '../../../../shared/providers/module_cache.dart';
import '../../data/gym_labels.dart';
import '../widgets/exercise_demo_card.dart';
import '../widgets/exercise_demo_sheet.dart';
import '../widgets/machine_detect_sheet.dart';
import '../widgets/todays_program_moves.dart';

class GymMachinesScreen extends ConsumerStatefulWidget {
  const GymMachinesScreen({super.key});

  @override
  ConsumerState<GymMachinesScreen> createState() => _GymMachinesScreenState();
}

class _GymMachinesScreenState extends ConsumerState<GymMachinesScreen> {
  final _query = TextEditingController();
  /// Fresh field name avoids hot-reload keeping an old `List<Map>` in state.
  List<GymExercise> _exercises = const [];
  List<Map<String, dynamic>> _plans = const [];
  bool _loading = true;
  String? _error;
  String _muscle = 'all';

  @override
  void initState() {
    super.initState();
    final cached = ref
        .read(moduleCacheProvider)
        .read<List<GymExercise>>(ModuleCacheKeys.gymMachines);
    if (cached != null) {
      _exercises = List<GymExercise>.from(cached);
      _loading = false;
    }
    _load();
  }

  @override
  void reassemble() {
    super.reassemble();
    _exercises = const [];
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final showSpinner = ref.read(moduleCacheProvider).shouldShowSpinner(ModuleCacheKeys.gymMachines);
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(vivrantApiProvider);
      final rows = await api.gymExercises();
      List<Map<String, dynamic>> plans = const [];
      try {
        plans = await api.gymPlans();
      } catch (_) {}
      if (!mounted) return;
      final exercises = rows
          .map(GymExercise.fromJson)
          .where((e) => e.isMachine)
          .toList(growable: false);
      ref.read(moduleCacheProvider).write(ModuleCacheKeys.gymMachines, exercises);
      setState(() {
        _exercises = exercises;
        _plans = plans;
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

  List<String> get _muscleOptions {
    final groups = _exercises
        .map((e) => e.muscleGroup)
        .where((g) => g.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return ['all', ...groups];
  }

  List<GymExercise> get _filtered {
    final q = _query.text.trim().toLowerCase();
    return _exercises.where((exercise) {
      if (!matchesMuscleFilter(exercise.muscleGroup, _muscle)) return false;
      if (q.isEmpty) return true;
      return exercise.name.toLowerCase().contains(q) ||
          exercise.muscleGroup.toLowerCase().contains(q) ||
          exercise.equipment.toLowerCase().contains(q) ||
          exercise.difficulty.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _snapMachine() async {
    await runMachinePhotoDetect(
      context: context,
      ref: ref,
      exercises: _exercises,
      plans: _plans,
      onPlanUpdated: (plan) {
        final id = (plan['id'] as num?)?.toInt();
        if (id == null) return;
        setState(() {
          _plans = [
            for (final item in _plans)
              if ((item['id'] as num?)?.toInt() == id) plan else item,
          ];
        });
      },
    );
  }

  Future<void> _suggestMachines() async {
    try {
      final res = await ref.read(vivrantApiProvider).recommendMachinesAi();
      if (!mounted) return;
      final payload = res['recommendation'] is Map
          ? Map<String, dynamic>.from(res['recommendation'] as Map)
          : res;
      final recs = (payload['recommendations'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList()
        ..sort(
          (a, b) => ((a['priority'] as num?)?.toInt() ?? 99)
              .compareTo((b['priority'] as num?)?.toInt() ?? 99),
        );
      if (recs.isEmpty) {
        context.showInfo(payload['summary']?.toString() ?? 'No suggestions yet.');
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (ctx) {
          return SafeArea(
            child: Padding(
              padding: VivrantLayout.sheetPadding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    payload['title']?.toString() ?? 'Suggested machines',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  if ((payload['summary']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      payload['summary'].toString(),
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: recs.length,
                      separatorBuilder: (_, __) => const Divider(height: 20),
                      itemBuilder: (_, index) {
                        final item = recs[index];
                        final slug = item['demo_slug']?.toString();
                        GymExercise? demo;
                        if (slug != null && slug.isNotEmpty) {
                          for (final ex in _exercises) {
                            if (ex.slug == slug) {
                              demo = ex;
                              break;
                            }
                          }
                        }
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: demo != null ? _RecThumb(exercise: demo) : null,
                          title: Text(
                            item['machine']?.toString() ?? 'Machine',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            [
                              if (item['why'] != null) item['why'].toString(),
                              if (item['sets'] != null) 'Sets: ${item['sets']}',
                            ].where((e) => e.isNotEmpty).join('\n'),
                          ),
                          trailing: demo != null && demo.hasDemo
                              ? TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    showExerciseDemoSheet(context, demo!);
                                  },
                                  child: const Text('Demo'),
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return GradientScaffold(
      appBar: AppBar(title: const Text('Machines')),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: VivrantLayout.pagePadding,
          children: [
            const PageHeader(
              eyebrow: 'Equipment',
              title: 'Gym',
              highlight: 'machines',
            ),
            TodaysProgramMoves(
              plans: _plans,
              exercises: _exercises,
              machinesOnly: true,
              onSelect: (exercise) => showExerciseDemoSheet(context, exercise),
            ),
            const SectionGap(),
            Text(
              'Browse machines, snap the one in front of you, or get simple suggestions.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _suggestMachines,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Suggest machines for me'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _snapMachine,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Snap a machine'),
            ),
            const SizedBox(height: 16),
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
            else if (_exercises.isEmpty)
              const EmptyState(
                title: 'No machines yet',
                message: 'Machine demos will show up here when available.',
              )
            else ...[
              VivrantSearchField(
                controller: _query,
                hintText: 'Search machines…',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              VivrantFilterChips<String>(
                options: [
                  for (final muscle in _muscleOptions)
                    VivrantFilterOption(
                      value: muscle,
                      label: muscleFilterLabel(muscle),
                    ),
                ],
                selected: _muscle,
                onSelected: (v) => setState(() => _muscle = v),
              ),
              const SizedBox(height: 18),
              if (filtered.isEmpty)
                const EmptyState(
                  message:
                      'No machines match these filters. Try All or another search.',
                )
              else ...[
                SectionLabel(
                  '${filtered.length} machine${filtered.length == 1 ? '' : 's'}',
                ),
                ...filtered.map(
                  (exercise) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ExerciseDemoCard(
                      exercise: exercise,
                      onTap: () => showExerciseDemoSheet(context, exercise),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _RecThumb extends StatelessWidget {
  const _RecThumb({required this.exercise});

  final GymExercise exercise;

  @override
  Widget build(BuildContext context) {
    final c = VivrantColors.of(context);
    final thumb = exercise.demoThumbnailUrl?.trim();
    final hasThumb = thumb != null && thumb.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 48,
        height: 48,
        child: hasThumb
            ? CachedNetworkImage(
                imageUrl: thumb,
                fit: BoxFit.cover,
                placeholder: (_, __) => ColoredBox(
                  color: c.accentSoft,
                  child: Icon(muscleIcon(exercise.muscleGroup), color: c.accent, size: 20),
                ),
                errorWidget: (_, __, ___) => ColoredBox(
                  color: c.accentSoft,
                  child: Icon(muscleIcon(exercise.muscleGroup), color: c.accent, size: 20),
                ),
              )
            : ColoredBox(
                color: c.accentSoft,
                child: Icon(muscleIcon(exercise.muscleGroup), color: c.accent, size: 20),
              ),
      ),
    );
  }
}
