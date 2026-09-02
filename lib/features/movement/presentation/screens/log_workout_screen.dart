import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/constants/enums.dart';
import '../../../../shared/providers/module_cache.dart';
import '../../../gym/presentation/widgets/program_session_panel.dart';

class LogWorkoutScreen extends ConsumerStatefulWidget {
  const LogWorkoutScreen({super.key, this.initialPlanId, this.initialDayLabel});

  final int? initialPlanId;
  final String? initialDayLabel;

  @override
  ConsumerState<LogWorkoutScreen> createState() => _LogWorkoutScreenState();
}

class _LogWorkoutScreenState extends ConsumerState<LogWorkoutScreen> {
  final _title = TextEditingController();
  final _minutes = TextEditingController();
  final _calories = TextEditingController();
  String _type = 'walk';
  bool _loading = false;
  List<Map<String, dynamic>> _plans = [];

  @override
  void initState() {
    super.initState();
    final cached = ref
        .read(moduleCacheProvider)
        .read<List<Map<String, dynamic>>>(ModuleCacheKeys.gymPlans);
    if (cached != null) {
      _plans = List<Map<String, dynamic>>.from(cached);
    }
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    try {
      final plans = await ref.read(vivrantApiProvider).gymPlans();
      if (!mounted) return;
      ref.read(moduleCacheProvider).write(ModuleCacheKeys.gymPlans, plans);
      setState(() => _plans = plans);
    } catch (_) {
      // Keep walk/run logging even if programs fail to load.
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _minutes.dispose();
    _calories.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    try {
      await ref.read(vivrantApiProvider).logWorkout({
        'title': _title.text.trim(),
        'activity_type': _type,
        if (_minutes.text.isNotEmpty)
          'duration_minutes': int.tryParse(_minutes.text),
        if (_calories.text.isNotEmpty)
          'calories_burned': double.tryParse(_calories.text),
      });
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: AppBar(title: const Text('Log workout')),
      child: ListView(
        padding: VivrantLayout.pagePadding,
        children: [
          ProgramSessionPanel(
            plans: _plans,
            initialPlanId: widget.initialPlanId,
            initialDayLabel: widget.initialDayLabel,
            onLogged: () {
              if (mounted) context.pop();
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Or log a walk, run, or yoga',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            items: [
              for (final t in activityTypes)
                DropdownMenuItem(value: t, child: Text(labelForOption(t))),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'other'),
            decoration: const InputDecoration(labelText: 'Activity type'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _minutes,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Duration (minutes)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _calories,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Calories burned'),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loading ? null : _save,
            child: Text(_loading ? 'Saving…' : 'Save workout'),
          ),
        ],
      ),
    );
  }
}
