import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/vivrant_colors.dart';
import '../theme/vivrant_motion.dart';

class VivrantFilterOption<T> {
  const VivrantFilterOption({
    required this.value,
    required this.label,
    this.count,
  });

  final T value;
  final String label;
  final int? count;
}

/// Horizontal filter chip row used across list panels.
class VivrantFilterChips<T> extends StatelessWidget {
  const VivrantFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<VivrantFilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            _Chip(
              label: options[i].count == null
                  ? options[i].label
                  : '${options[i].label} (${options[i].count})',
              selected: selected == options[i].value,
              onTap: () {
                HapticFeedback.selectionClick();
                onSelected(options[i].value);
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = VivrantColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: VivrantMotion.base,
          curve: VivrantMotion.enter,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? c.inverse : c.panel,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : c.ink.withValues(alpha: 0.1),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: c.ink.withValues(alpha: c.dark ? 0.28 : 0.14),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: AnimatedDefaultTextStyle(
            duration: VivrantMotion.fast,
            curve: VivrantMotion.enter,
            style: TextStyle(
              color: selected ? c.inverseFg : c.ink,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              height: 1.1,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}
