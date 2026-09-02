import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/vivrant_colors.dart';
import '../../../../core/utils/bmi.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../../../shared/providers/module_cache.dart';
import '../widgets/quick_actions_row.dart';

class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final cached = ref
        .read(moduleCacheProvider)
        .read<Map<String, dynamic>>(ModuleCacheKeys.today);
    if (cached != null) {
      _data = cached;
      _loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    final showSpinner = _data == null;
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(vivrantApiProvider).getToday();
      if (!mounted) return;
      ref.read(moduleCacheProvider).write(ModuleCacheKeys.today, data);
      setState(() {
        _data = data;
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

  Future<void> _quickCheckin() async {
    final energy = await _pickScore('Energy (1–5)');
    if (energy == null || !mounted) return;
    final mood = await _pickScore('Mood (1–5)');
    if (mood == null || !mounted) return;
    try {
      await ref.read(vivrantApiProvider).saveCheckin(
            DailyCheckin(energy: energy, mood: mood),
          );
      if (!mounted) return;
      context.showSuccess('Check-in saved');
      _load();
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Future<int?> _pickScore(String title) async {
    int? selected;
    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: VivrantLayout.sheetPadding,
            child: StatefulBuilder(
              builder: (context, setSheet) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 20),
                    ScorePicker(
                      value: selected,
                      onChanged: (n) {
                        setSheet(() => selected = n);
                        Navigator.pop(context, n);
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = VivrantColors.of(context);
    final profile = ref.watch(authProvider).profile;
    final checkin = _data?['checkin'] as Map?;
    final calories = (_data?['calories'] as num?)?.toInt() ?? 0;
    final steps = (_data?['steps'] as num?)?.toInt() ??
        (checkin?['steps'] as num?)?.toInt() ??
        0;
    final water = (_data?['water_ml'] as num?)?.toInt() ??
        (checkin?['water_ml'] as num?)?.toInt() ??
        0;
    final bmiRaw = _data?['bmi'];
    final bmi = bmiRaw is Map
        ? Map<String, dynamic>.from(bmiRaw)
        : summarizeBmi(profile?.heightCm, profile?.weightKg);
    final program = _data?['program'];
    final missed = program is Map ? program['missed'] : null;
    final missedDay = missed is Map ? missed['day']?.toString() : null;
    final missedName = missed is Map
        ? (missed['weekdayName'] ?? missed['weekday_name'] ?? missed['day'])?.toString()
        : null;
    final missedFocus = missed is Map ? missed['focus']?.toString() : null;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        color: c.accent,
        child: ListView(
          padding: VivrantLayout.pagePadding,
          children: [
            Row(
              children: [
                const Expanded(child: VivrantBrand()),
                IconButton(
                  tooltip: 'Notifications',
                  onPressed: () => context.push('/notifications'),
                  icon: const Icon(Icons.notifications_outlined),
                ),
                IconButton(
                  tooltip: 'Profile',
                  onPressed: () => context.push('/profile'),
                  icon: CircleAvatar(
                    radius: 16,
                    backgroundColor: c.accentSoft,
                    backgroundImage: profile?.avatarUrl != null
                        ? CachedNetworkImageProvider(profile!.avatarUrl!)
                        : null,
                    child: profile?.avatarUrl == null
                        ? Text(
                            (profile?.displayName.isNotEmpty == true
                                    ? profile!.displayName[0]
                                    : 'V')
                                .toUpperCase(),
                            style: TextStyle(
                              color: c.accent,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            PageHeader(
              eyebrow: 'Today',
              title: 'Hello,',
              highlight: profile?.displayName.split(' ').first ?? 'friend',
            ),
            if (_loading)
              const SkeletonFeed()
            else if (_error != null)
              EmptyState(
                icon: Icons.cloud_off_outlined,
                message: _error!,
                action: OutlinedButton(
                  onPressed: _load,
                  child: const Text('Retry'),
                ),
              )
            else
              ...staggerAppear([
                VivrantPanel(
                  title: 'At a glance',
                  child: Text(
                    [
                      '$calories kcal · $steps steps · $water ml water',
                      if (bmi != null)
                        'BMI ${(bmi['bmi'] as num).toString()} · ${bmi['band_label'] ?? bmi['bandLabel'] ?? ''}'
                            .trim(),
                    ].where((line) => line.isNotEmpty).join('\n'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (bmi == null) ...[
                  const TileGap(),
                  ModuleTile(
                    icon: Icons.monitor_weight_outlined,
                    label: 'Add height & weight',
                    caption: 'See BMI on Today and personalize plans',
                    onTap: () => context.push('/profile/health'),
                  ),
                ] else ...[
                  const TileGap(),
                  ModuleTile(
                    icon: Icons.monitor_weight_outlined,
                    label: 'BMI ${(bmi['bmi'] as num).toString()}',
                    caption: '${bmi['band_label'] ?? bmi['bandLabel'] ?? 'Screening measure'} · tap to update',
                    onTap: () => context.push('/profile/health'),
                  ),
                ],
                if (missedDay != null && missedDay.isNotEmpty) ...[
                  const TileGap(),
                  ModuleTile(
                    icon: Icons.fitness_center,
                    label: 'Skipped ${missedName ?? missedDay}',
                    caption: missedFocus == null || missedFocus.isEmpty
                        ? 'Use that workout today — weekly plan stays as-is'
                        : '$missedFocus · train it today without changing the week',
                    onTap: () => context.push(
                      '/gym/sessions?day=${Uri.encodeQueryComponent(missedDay)}',
                    ),
                  ),
                ],
                const TileGap(),
                VivrantPanel(
                  title: 'Quick check-in',
                  trailing: TextButton(
                    onPressed: _quickCheckin,
                    child: const Text('Log'),
                  ),
                  child: Text(
                    checkin == null
                        ? 'How is your energy and mood today?'
                        : 'Energy ${checkin['energy'] ?? '—'} · Mood ${checkin['mood'] ?? '—'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SectionGap(),
                QuickActionsRow(
                  programCaption: _programCaption(_data?['program']),
                  mealsToday: (_data?['meals_today'] as num?)?.toInt() ?? 0,
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

String? _programCaption(Object? raw) {
  if (raw is! Map) return null;
  final plan = Map<String, dynamic>.from(raw);
  final title = plan['title']?.toString().trim();
  if (title == null || title.isEmpty) return null;
  final count = (plan['planCount'] as num?)?.toInt() ?? 1;
  if (count > 1) return '$title · $count saved';
  return title;
}
