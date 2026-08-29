import 'package:flutter/material.dart';

import 'confirm_dialog.dart';
import 'swipe_to_remove.dart';

/// Select mode + bulk archive for module lists.
mixin SelectableIdsMixin<T extends StatefulWidget> on State<T> {
  bool selecting = false;
  final Set<int> selectedIds = <int>{};

  void toggleSelected(int id) {
    setState(() {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
      } else {
        selectedIds.add(id);
      }
    });
  }

  void enterSelect([int? id]) {
    setState(() {
      selecting = true;
      if (id != null) selectedIds.add(id);
    });
  }

  void exitSelect() {
    setState(() {
      selecting = false;
      selectedIds.clear();
    });
  }

  void selectVisible(Iterable<int> ids) {
    setState(() {
      selectedIds
        ..clear()
        ..addAll(ids);
    });
  }

  List<Widget> selectAppBarActions({
    required Iterable<int> visibleIds,
    required VoidCallback onArchive,
    String archiveTooltip = 'Archive',
    IconData archiveIcon = Icons.delete_outline,
  }) {
    if (!selecting) {
      if (visibleIds.isEmpty) return const [];
      return [
        IconButton(
          tooltip: 'Select',
          icon: const Icon(Icons.checklist_outlined),
          onPressed: () => enterSelect(),
        ),
      ];
    }
    return [
      IconButton(
        tooltip: 'Select all',
        icon: const Icon(Icons.select_all),
        onPressed: () => selectVisible(visibleIds),
      ),
      IconButton(
        tooltip: archiveTooltip,
        icon: Icon(archiveIcon),
        onPressed: selectedIds.isEmpty ? null : onArchive,
      ),
      IconButton(
        tooltip: 'Cancel',
        icon: const Icon(Icons.close),
        onPressed: exitSelect,
      ),
    ];
  }

  Future<void> confirmAndArchiveSelected({
    required Future<String> Function(List<int> ids) request,
    required void Function(Set<int> ids) onRemoved,
  }) async {
    final ids = selectedIds.toList();
    if (ids.isEmpty) return;
    if (!mounted) return;
    final ok = await confirmDeleteMany(context, count: ids.length);
    if (!ok || !mounted) return;
    try {
      final message = await request(ids);
      if (!mounted) return;
      onRemoved(ids.toSet());
      exitSelect();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  /// Swipe-to-archive when not in select mode. [archive] should not confirm again.
  Widget wrapArchiveable({
    required int id,
    required String label,
    required Widget child,
    required Future<void> Function() archive,
  }) {
    if (selecting) return child;
    return SwipeToRemove(
      itemKey: ValueKey('swipe-$id'),
      action: 'Archive',
      confirmDismiss: (_) => confirmDelete(context, label: label),
      onRemove: () {
        archive();
      },
      child: child,
    );
  }
}

Widget selectLeading(bool selected) {
  return Icon(selected ? Icons.check_box : Icons.check_box_outline_blank);
}
