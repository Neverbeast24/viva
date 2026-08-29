import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/vivrant_colors.dart';
import '../../../../core/utils/ai_text.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/share_export.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/providers/module_cache.dart';

class HealthHistoryScreen extends ConsumerStatefulWidget {
  const HealthHistoryScreen({super.key});

  @override
  ConsumerState<HealthHistoryScreen> createState() =>
      _HealthHistoryScreenState();
}

class _HealthHistoryScreenState extends ConsumerState<HealthHistoryScreen>
    with SingleTickerProviderStateMixin, SelectableIdsMixin {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _error;
  late final AnimationController _enter;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..forward();
    final cached = ref
        .read(moduleCacheProvider)
        .read<List<Map<String, dynamic>>>(ModuleCacheKeys.healthHistory);
    if (cached != null) {
      _entries = List<Map<String, dynamic>>.from(cached);
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final showSpinner = ref.read(moduleCacheProvider).shouldShowSpinner(ModuleCacheKeys.healthHistory);
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final entries = await ref.read(vivrantApiProvider).healthHistory();
      if (!mounted) return;
      ref.read(moduleCacheProvider).write(ModuleCacheKeys.healthHistory, entries);
      setState(() {
        _entries = entries;
        _loading = false;
      });
      _enter.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final weight = TextEditingController();
    final height = TextEditingController();
    final bodyFat = TextEditingController();
    final waist = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Add measurement'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: weight,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Weight (kg)',
                  hintText: '68',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: height,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Height (cm)',
                  hintText: '154',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bodyFat,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Body fat % (optional)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: waist,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Waist cm (optional)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'Morning weigh-in…',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final weightKg = double.tryParse(weight.text.trim());
    final heightCm = double.tryParse(height.text.trim());
    final bodyFatPct = double.tryParse(bodyFat.text.trim());
    final waistCm = double.tryParse(waist.text.trim());
    final noteText = note.text.trim();
    weight.dispose();
    height.dispose();
    bodyFat.dispose();
    waist.dispose();
    note.dispose();
    if (ok != true || !mounted) return;
    if (weightKg == null &&
        heightCm == null &&
        bodyFatPct == null &&
        waistCm == null) {
      context.showError('Add weight, height, body fat, or waist.');
      return;
    }
    try {
      await ref.read(vivrantApiProvider).addHealthHistory({
        if (weightKg != null) 'weight_kg': weightKg,
        if (heightCm != null) 'height_cm': heightCm,
        if (bodyFatPct != null) 'body_fat_pct': bodyFatPct,
        if (waistCm != null) 'waist_cm': waistCm,
        if (noteText.isNotEmpty) 'note': noteText,
      });
      if (!mounted) return;
      HapticFeedback.lightImpact();
      context.showSuccess('Health history saved');
      await _load();
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _analyzeAi() async {
    try {
      final res = await ref.read(vivrantApiProvider).analyzeHealthHistoryAi();
      if (!mounted) return;
      context.showInfo(
        formatAiResponse(res, keys: const ['insight', 'advice', 'summary']),
      );
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  double? _bmiFor(Map<String, dynamic> e) {
    final weight = (e['weight_kg'] as num?)?.toDouble();
    final height = (e['height_cm'] as num?)?.toDouble();
    if (weight == null || height == null || height <= 0) return null;
    return weight / ((height / 100) * (height / 100));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = dark ? VivrantColors.darkMuted : VivrantColors.muted;
    final panel = dark ? VivrantColors.darkPanel : Colors.white;
    final ink = dark ? VivrantColors.darkInk : VivrantColors.ink;
    final accent = dark ? VivrantColors.darkAccent : VivrantColors.accent;
    final soft = dark ? VivrantColors.darkAccentSoft : VivrantColors.accentSoft;

    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Health history'),
        actions: [
          if (_entries.isNotEmpty)
            ShareExportButton(doc: healthHistoryDoc(_entries)),
          ...selectAppBarActions(
            visibleIds: _entries
                .map((e) => (e['id'] as num?)?.toInt())
                .whereType<int>(),
            onArchive: () => confirmAndArchiveSelected(
              request: (ids) => ref.read(vivrantApiProvider).archiveItems(
                    entity: 'health_history',
                    ids: ids,
                  ),
              onRemoved: (ids) {
                setState(() {
                  _entries = _entries
                      .where(
                        (e) => !ids.contains((e['id'] as num?)?.toInt()),
                      )
                      .toList();
                });
                ref
                    .read(moduleCacheProvider)
                    .write(ModuleCacheKeys.healthHistory, _entries);
              },
            ),
          ),
          IconButton(
            onPressed: _add,
            tooltip: 'Add entry',
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: VivrantLayout.pagePadding,
          children: [
            FadeTransition(
              opacity: CurvedAnimation(
                parent: _enter,
                curve: const Interval(0, 0.5, curve: Curves.easeOutCubic),
              ),
              child: const PageHeader(
                eyebrow: 'Records',
                title: 'Health',
                highlight: 'history',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _analyzeAi,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Analyze with AI'),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              EmptyState(
                message: _error!,
                action: OutlinedButton(
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              )
            else if (_entries.isEmpty)
              EmptyState(
                message: 'No measurements yet. Log weight or height to track BMI.',
                action: PrimaryButton(
                  label: 'Add entry',
                  onPressed: _add,
                  icon: Icons.note_add_outlined,
                ),
              )
            else
              ...List.generate(_entries.length, (i) {
                final e = _entries[i];
                final start = (0.15 + i * 0.07).clamp(0.0, 0.7);
                final end = (start + 0.35).clamp(0.0, 1.0);
                final weight = e['weight_kg'];
                final height = e['height_cm'];
                final bmi = _bmiFor(e);
                final note = e['note']?.toString();
                final date = e['recorded_at']?.toString() ??
                    e['created_at']?.toString() ??
                    e['date']?.toString();
                final titleParts = <String>[
                  if (date != null && date.isNotEmpty)
                    date.length >= 10 ? date.substring(0, 10) : date,
                  if (weight != null) '$weight kg',
                  if (bmi != null) 'BMI ${bmi.toStringAsFixed(1)}',
                ];
                final subtitleParts = <String>[
                  if (height != null) '$height cm',
                  if (e['body_fat_pct'] != null) '${e['body_fat_pct']}% fat',
                  if (e['waist_cm'] != null) '${e['waist_cm']} cm waist',
                  if (note != null && note.isNotEmpty) note,
                ];
                final title = titleParts.isEmpty
                    ? 'Measurement'
                    : titleParts.join(' · ');
                final subtitle = subtitleParts.join(' · ');

                return FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _enter,
                    curve: Interval(start, end, curve: Curves.easeOutCubic),
                  ),
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.06),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: _enter,
                        curve: Interval(start, end, curve: Curves.easeOutCubic),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: wrapArchiveable(
                        id: (e['id'] as num?)?.toInt() ?? i,
                        label: 'this measurement',
                        archive: () async {
                          final id = (e['id'] as num?)?.toInt();
                          if (id == null) return;
                          try {
                            await ref
                                .read(vivrantApiProvider)
                                .deleteHealthHistory(id);
                            if (!mounted) return;
                            setState(() {
                              _entries = _entries
                                  .where(
                                    (row) => (row['id'] as num?)?.toInt() != id,
                                  )
                                  .toList();
                            });
                            ref.read(moduleCacheProvider).write(
                                  ModuleCacheKeys.healthHistory,
                                  _entries,
                                );
                            context.showSuccess('Measurement archived');
                          } catch (err) {
                            if (!mounted) return;
                            context.showError(apiErrorMessage(err));
                          }
                        },
                        child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: panel.withValues(alpha: dark ? 0.92 : 0.96),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: ink.withValues(alpha: 0.06)),
                          boxShadow: [
                            BoxShadow(
                              color: accent
                                  .withValues(alpha: dark ? 0.07 : 0.04),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (selecting)
                              Checkbox(
                                value: selectedIds.contains(
                                  (e['id'] as num?)?.toInt(),
                                ),
                                onChanged: (_) {
                                  final id = (e['id'] as num?)?.toInt();
                                  if (id != null) toggleSelected(id);
                                },
                              ),
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: soft,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(
                                Icons.monitor_weight_outlined,
                                color: accent,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (subtitle.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      subtitle,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: muted,
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                final id = (e['id'] as num?)?.toInt();
                                if (id == null) return;
                                if (!(await confirmDelete(
                                  context,
                                  label: 'this measurement',
                                ))) {
                                  return;
                                }
                                try {
                                  await ref
                                      .read(vivrantApiProvider)
                                      .deleteHealthHistory(id);
                                  if (!mounted) return;
                                  setState(() {
                                    _entries = _entries
                                        .where(
                                          (row) =>
                                              (row['id'] as num?)?.toInt() !=
                                              id,
                                        )
                                        .toList();
                                  });
                                  ref.read(moduleCacheProvider).write(
                                        ModuleCacheKeys.healthHistory,
                                        _entries,
                                      );
                                  context.showSuccess('Measurement archived');
                                } catch (err) {
                                  if (!mounted) return;
                                  context.showError(apiErrorMessage(err));
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
