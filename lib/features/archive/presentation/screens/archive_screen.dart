import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';

/// Same labels as viva-server `ARCHIVE_LABELS`.
const archiveLabels = {
  'nutrition_logs': 'Meal',
  'workout_logs': 'Workout',
  'expenses': 'Expense',
  'pantry_items': 'Pantry item',
  'grocery_items': 'Grocery item',
  'health_goals': 'Goal',
  'health_history': 'Health history',
  'gym_sessions': 'Gym session',
  'gym_plans': 'Gym program',
  'habits': 'Habit',
  'challenges': 'Challenge',
  'journal_entries': 'Journal note',
  'user_reminders': 'Reminder',
};

class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen>
    with SelectableIdsMixin {
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await ref.read(vivrantApiProvider).listArchived();
      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _restore(Map<String, dynamic> item, {bool confirm = true}) async {
    final id = (item['id'] as num?)?.toInt();
    if (id == null) return;
    final title = (item['title'] as String?)?.trim().isNotEmpty == true
        ? item['title'] as String
        : 'this item';
    if (confirm) {
      final ok = await confirmAction(
        context,
        title: 'Restore $title?',
        body: 'It will come back to its original module list.',
        confirmLabel: 'Restore',
      );
      if (!ok || !mounted) return;
    }
    try {
      final message = await ref.read(vivrantApiProvider).restoreArchived(id);
      if (!mounted) return;
      setState(() => _items = _items.where((row) => row['id'] != id).toList());
      context.showSuccess(message);
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final origin = shareOriginFor(context);
    try {
      final dump = await ref.read(vivrantApiProvider).exportBackup();
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/vivrant-backup-${DateTime.now().toIso8601String().sliceDate}.json',
      );
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(dump));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/json', name: file.uri.pathSegments.last)],
          text: 'VIVRΛNT backup',
          sharePositionOrigin: origin,
        ),
      );
      if (!mounted) return;
      context.showSuccess('Backup ready. Keep this file somewhere safe.');
    } catch (e) {
      if (!mounted) return;
      context.showError(apiErrorMessage(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> get _grouped {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final item in _items) {
      final entity = (item['entity'] as String?) ?? 'other';
      map.putIfAbsent(entity, () => []).add(item);
    }
    return map.entries.toList();
  }

  String _labelFor(String entity) =>
      archiveLabels[entity] ?? entity.replaceAll('_', ' ');

  String _archivedWhen(Map<String, dynamic> item) {
    final deletedAt = item['deleted_at'] as String?;
    final when = deletedAt == null
        ? null
        : DateTime.tryParse(deletedAt)?.toLocal().toString().split('.').first;
    return when == null ? 'Archived' : 'Archived $when';
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Archived'),
        actions: [
          ...selectAppBarActions(
            visibleIds: _items
                .map((item) => (item['id'] as num?)?.toInt())
                .whereType<int>(),
            archiveTooltip: 'Restore',
            archiveIcon: Icons.settings_backup_restore,
            onArchive: () async {
              final ids = selectedIds.toList();
              if (ids.isEmpty) return;
              if (!await confirmRestoreMany(context, count: ids.length)) {
                return;
              }
              try {
                final message =
                    await ref.read(vivrantApiProvider).restoreArchivedBulk(ids);
                if (!mounted) return;
                setState(() {
                  _items = _items
                      .where(
                        (row) => !ids.contains((row['id'] as num?)?.toInt()),
                      )
                      .toList();
                });
                exitSelect();
                context.showSuccess(message);
              } catch (e) {
                if (!mounted) return;
                context.showError(apiErrorMessage(e));
              }
            },
          ),
          IconButton(
            tooltip: 'Download backup',
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_outlined),
          ),
        ],
      ),
      child: AsyncBody(
        loading: _loading,
        error: _error,
        onRetry: _load,
        child: _items.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: EmptyState(
                  title: 'Nothing archived',
                  message:
                      'Deleted meals, habits, and plans land here so you can restore them.',
                ),
              )
            : ListView(
                padding: VivrantLayout.pagePadding,
                children: [
                  Text(
                    'Deleted items stay hidden from every module and from Gemini. Restore them here, or download a JSON backup.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  for (final entry in grouped) ...[
                    SectionLabel(
                      '${_labelFor(entry.key)} · ${entry.value.length}',
                    ),
                    const SizedBox(height: 8),
                    for (final item in entry.value) ...[
                      Builder(
                        builder: (context) {
                          final id = (item['id'] as num?)?.toInt();
                          final title =
                              (item['title'] as String?)?.trim().isNotEmpty ==
                                      true
                                  ? item['title'] as String
                                  : 'Archived item';
                          final selected =
                              id != null && selectedIds.contains(id);
                          final card = VivrantPanel(
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: selecting && id != null
                                  ? selectLeading(selected)
                                  : null,
                              title: Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(_archivedWhen(item)),
                              selected: selected,
                              onTap: selecting && id != null
                                  ? () => toggleSelected(id)
                                  : null,
                              trailing: selecting
                                  ? null
                                  : TextButton(
                                      onPressed: () => _restore(item),
                                      child: const Text('Restore'),
                                    ),
                            ),
                          );
                          if (selecting || id == null) return card;
                          return SwipeToRemove(
                            itemKey: ValueKey('restore-$id'),
                            action: 'Restore',
                            confirmDismiss: (_) => confirmAction(
                              context,
                              title: 'Restore $title?',
                              body:
                                  'It will come back to its original module list.',
                              confirmLabel: 'Restore',
                            ),
                            onRemove: () => _restore(item, confirm: false),
                            child: card,
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 8),
                  ],
                ],
              ),
      ),
    );
  }
}

extension on String {
  String get sliceDate => length >= 10 ? substring(0, 10) : this;
}
