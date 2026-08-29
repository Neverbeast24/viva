import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/vivrant_colors.dart';
import '../theme/vivrant_motion.dart';
import 'icon_well.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.title,
    this.action,
    this.icon = Icons.spa_outlined,
  });

  final String message;
  final String? title;
  final Widget? action;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = VivrantColors.of(context);
    Widget mark = IconWell(icon: icon, size: 56, iconSize: 26);
    if (!VivrantMotion.reduce(context)) {
      mark = mark
          .animate()
          .fadeIn(duration: 360.ms)
          .scale(
            begin: const Offset(0.86, 0.86),
            end: const Offset(1, 1),
            duration: 480.ms,
            curve: VivrantMotion.spring,
          );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 40, 28, 40),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Theme.of(context).cardTheme.color?.withValues(alpha: 0.55),
        border: Border.all(
          color: c.ink.withValues(alpha: 0.10),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          mark,
          const SizedBox(height: 18),
          if (title != null) ...[
            Text(
              title!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
          ),
          if (action != null) ...[
            const SizedBox(height: 18),
            action!,
          ],
        ],
      ),
    );
  }
}
