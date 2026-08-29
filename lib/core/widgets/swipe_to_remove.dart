import 'package:flutter/material.dart';

/// Horizontal swipe to remove a row. Use with optional [confirmDismiss].
class SwipeToRemove extends StatelessWidget {
  const SwipeToRemove({
    super.key,
    required this.itemKey,
    required this.onRemove,
    required this.child,
    this.confirmDismiss,
    this.action = 'Remove',
  });

  final Key itemKey;
  final VoidCallback onRemove;
  final Widget child;
  final ConfirmDismissCallback? confirmDismiss;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: itemKey,
      direction: DismissDirection.horizontal,
      confirmDismiss: confirmDismiss,
      onDismissed: (_) => onRemove(),
      background: _rail(Alignment.centerLeft),
      secondaryBackground: _rail(Alignment.centerRight),
      child: child,
    );
  }

  Widget _rail(Alignment alignment) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFB42318),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        action,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
      ),
    );
  }
}
