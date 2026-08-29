import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

/// Confirms a destructive or important action. Returns `true` when confirmed.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'OK',
  String cancelLabel = 'Cancel',
}) async {
  final ok = await showModal<bool>(
    context: context,
    configuration: const FadeScaleTransitionConfiguration(
      barrierDismissible: true,
    ),
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Shared archive confirmation used by every module delete action.
Future<bool> confirmDelete(
  BuildContext context, {
  required String label,
  String? body,
  String confirmLabel = 'Archive',
}) {
  return confirmAction(
    context,
    title: 'Archive $label?',
    body: body ??
        'It will leave this list and move to Archived. You can restore it anytime from Profile → Archived.',
    confirmLabel: confirmLabel,
  );
}

Future<bool> confirmDeleteMany(
  BuildContext context, {
  required int count,
}) {
  final n = count < 0 ? 0 : count;
  return confirmAction(
    context,
    title: 'Archive $n item${n == 1 ? '' : 's'}?',
    body:
        'They will leave this list and move to Archived. You can restore them anytime from Profile → Archived.',
    confirmLabel: 'Archive',
  );
}

Future<bool> confirmRestoreMany(
  BuildContext context, {
  required int count,
}) {
  final n = count < 0 ? 0 : count;
  return confirmAction(
    context,
    title: 'Restore $n item${n == 1 ? '' : 's'}?',
    body: 'They will come back to their original module lists.',
    confirmLabel: 'Restore',
  );
}
