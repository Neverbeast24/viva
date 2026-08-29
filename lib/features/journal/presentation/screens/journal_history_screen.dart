import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/utils/context_extensions.dart';
import '../../../../core/utils/share_export.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../data/vivrant_api.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/providers/module_cache.dart';

class JournalHistoryScreen extends ConsumerStatefulWidget {
  const JournalHistoryScreen({super.key});

  @override
  ConsumerState<JournalHistoryScreen> createState() =>
      _JournalHistoryScreenState();
}

class _JournalHistoryScreenState extends ConsumerState<JournalHistoryScreen>
    with SelectableIdsMixin {
  final _query = TextEditingController();
  List<JournalEntry> _entries = [];
  bool _loading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    final cached = ref
        .read(moduleCacheProvider)
        .read<List<JournalEntry>>(ModuleCacheKeys.journal);
    if (cached != null) {
      _entries = List<JournalEntry>.from(cached);
      _loading = false;
    }
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _setEntries(List<JournalEntry> entries) {
    ref.read(moduleCacheProvider).write(ModuleCacheKeys.journal, entries);
    setState(() {
      _entries = entries;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _load() async {
    final showSpinner =
        ref.read(moduleCacheProvider).shouldShowSpinner(ModuleCacheKeys.journal);
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final entries = await ref.read(vivrantApiProvider).listJournal();
      if (!mounted) return;
      _setEntries(entries);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = apiErrorMessage(e);
        _loading = false;
      });
    }
  }

  List<JournalEntry> get _filtered {
    final q = _query.text.trim().toLowerCase();
    return _entries.where((e) {
      switch (_filter) {
        case 'good':
          if (e.mood == null || e.mood! < 4) return false;
        case 'ok':
          if (e.mood != 3) return false;
        case 'low':
          if (e.mood == null || e.mood! > 2) return false;
        case 'unrated':
          if (e.mood != null) return false;
      }
      if (q.isEmpty) return true;
      return (e.title?.toLowerCase().contains(q) ?? false) ||
          e.body.toLowerCase().contains(q) ||
          e.entryDate.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return GradientScaffold(
      appBar: AppBar(
        title: const Text('Past notes'),
        actions: [
          if (_entries.isNotEmpty)
            ShareExportButton(doc: journalEntriesDoc(_entries)),
          ...selectAppBarActions(
            visibleIds: _entries.map((e) => e.id),
            onArchive: () => confirmAndArchiveSelected(
              request: (ids) => ref.read(vivrantApiProvider).archiveItems(
                    entity: 'journal_entries',
                    ids: ids,
                  ),
              onRemoved: (ids) {
                setState(() {
                  _entries =
                      _entries.where((e) => !ids.contains(e.id)).toList();
                });
              },
            ),
          ),
          IconButton(
            tooltip: 'New entry',
            onPressed: () => context.push('/journal/new').then((_) {
              if (mounted) _load();
            }),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: VivrantLayout.pagePadding,
          children: [
            const PageHeader(
              eyebrow: 'Journal',
              title: 'Past',
              highlight: 'notes',
            ),
            if (_loading)
              const Center(child: CircularProgressIndicator())
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
                message: 'No journal entries yet.',
                action: ElevatedButton(
                  onPressed: () => context.push('/journal/new').then((_) {
                    if (mounted) _load();
                  }),
                  child: const Text('Write a note'),
                ),
              )
            else ...[
              VivrantSearchField(
                controller: _query,
                hintText: 'Search journal…',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 14),
              VivrantFilterChips<String>(
                options: [
                  VivrantFilterOption(
                    value: 'all',
                    label: 'All',
                    count: _entries.length,
                  ),
                  const VivrantFilterOption(value: 'good', label: 'Good'),
                  const VivrantFilterOption(value: 'ok', label: 'OK'),
                  const VivrantFilterOption(value: 'low', label: 'Low'),
                  const VivrantFilterOption(value: 'unrated', label: 'Unrated'),
                ],
                selected: _filter,
                onSelected: (v) => setState(() => _filter = v),
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                const EmptyState(
                  message:
                      'No notes match these filters. Try All or another search.',
                )
              else
                ...filtered.map(
                  (e) {
                    final label = (e.title?.trim().isNotEmpty == true)
                        ? e.title!.trim()
                        : 'this note';
                    return wrapArchiveable(
                      id: e.id,
                      label: label,
                      archive: () async {
                        final prev = List<JournalEntry>.from(_entries);
                        _setEntries(
                          _entries.where((x) => x.id != e.id).toList(),
                        );
                        try {
                          await ref.read(vivrantApiProvider).deleteJournal(e.id);
                          if (!mounted) return;
                          context.showSuccess('Entry removed');
                        } catch (err) {
                          if (!mounted) return;
                          _setEntries(prev);
                          context.showError(apiErrorMessage(err));
                        }
                      },
                      child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: VivrantPanel(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (selecting)
                            Checkbox(
                              value: selectedIds.contains(e.id),
                              onChanged: (_) => toggleSelected(e.id),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.title?.isNotEmpty == true
                                      ? e.title!
                                      : e.entryDate,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  e.body,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              final draft = await showFieldEditorSheet(
                                context,
                                title: 'Edit note',
                                fields: {
                                  'Title': e.title ?? '',
                                  'Body': e.body,
                                },
                              );
                              if (draft == null || !mounted) return;
                              try {
                                final updated = await ref
                                    .read(vivrantApiProvider)
                                    .updateJournal(e.id, {
                                  'title': (draft['Title'] ?? '').isEmpty
                                      ? 'Journal'
                                      : draft['Title'],
                                  'body': draft['Body'] ?? e.body,
                                  'entry_date': e.entryDate,
                                  if (e.mood != null) 'mood': e.mood,
                                });
                                if (!mounted) return;
                                _setEntries([
                                  for (final item in _entries)
                                    item.id == e.id ? updated : item,
                                ]);
                                context.showSuccess('Entry updated');
                              } catch (err) {
                                if (!mounted) return;
                                context.showError(apiErrorMessage(err));
                              }
                            },
                          ),
                          IconButton(
                            tooltip: 'Share or export',
                            icon: const Icon(Icons.ios_share_rounded),
                            onPressed: () => showShareExportSheet(
                              context,
                              journalNoteDoc(e),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (!(await confirmDelete(
                                    context,
                                    label: (e.title?.trim().isNotEmpty == true)
                                        ? e.title!.trim()
                                        : 'this note',
                                  ))) {
                                return;
                              }
                              final prev = List<JournalEntry>.from(_entries);
                              _setEntries(
                                _entries.where((x) => x.id != e.id).toList(),
                              );
                              try {
                                await ref
                                    .read(vivrantApiProvider)
                                    .deleteJournal(e.id);
                                if (!mounted) return;
                                context.showSuccess('Entry removed');
                              } catch (err) {
                                if (!mounted) return;
                                _setEntries(prev);
                                context.showError(apiErrorMessage(err));
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}
