import 'package:flutter/material.dart';

import '../theme/vivrant_colors.dart';
import '../theme/vivrant_motion.dart';
import 'icon_well.dart';

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = VivrantColors.of(context);
    final parsed = RegExp(r'^(\d+)(.*)$').firstMatch(value.trim());
    final number = parsed == null ? null : int.tryParse(parsed.group(1)!);
    final suffix = parsed?.group(2) ?? '';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.ink.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: c.accent.withValues(alpha: c.dark ? 0.14 : 0.07),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                IconWell(icon: icon!, size: 36, iconSize: 18),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (number != null && !VivrantMotion.reduce(context))
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: number.toDouble()),
              duration: const Duration(milliseconds: 720),
              curve: VivrantMotion.emphasized,
              builder: (context, animated, _) {
                return Text(
                  '${animated.round()}$suffix',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                        height: 1.05,
                      ),
                );
              },
            )
          else
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                    height: 1.05,
                  ),
            ),
          if (caption != null) ...[
            const SizedBox(height: 8),
            Text(caption!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
