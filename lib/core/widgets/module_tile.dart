import 'package:flutter/material.dart';

import '../theme/vivrant_colors.dart';
import '../theme/vivrant_layout.dart';
import '../theme/vivrant_motion.dart';
import 'icon_well.dart';

/// Navigation tile for the More menu and module grids.
class ModuleTile extends StatefulWidget {
  const ModuleTile({
    super.key,
    required this.icon,
    required this.label,
    required this.caption,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String caption;
  final VoidCallback onTap;

  @override
  State<ModuleTile> createState() => _ModuleTileState();
}

class _ModuleTileState extends State<ModuleTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = VivrantColors.of(context);
    return AnimatedScale(
      scale: _pressed ? 0.975 : 1,
      duration: VivrantMotion.fast,
      curve: Curves.easeOutCubic,
      child: Material(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: widget.onTap,
          onHighlightChanged: (value) => setState(() => _pressed = value),
          child: AnimatedContainer(
            duration: VivrantMotion.base,
            curve: VivrantMotion.enter,
            constraints: const BoxConstraints(minHeight: VivrantLayout.minTap),
            padding: VivrantLayout.rowPadding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: c.ink.withValues(alpha: _pressed ? 0.14 : 0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: c.accent.withValues(alpha: c.dark ? 0.12 : 0.06),
                  blurRadius: _pressed ? 8 : 20,
                  offset: Offset(0, _pressed ? 2 : 8),
                ),
              ],
            ),
            child: Row(
              children: [
                IconWell(icon: widget.icon),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          height: 1.25,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.caption,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: c.ink.withValues(alpha: 0.62),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                            ),
                      ),
                    ],
                  ),
                ),
                AnimatedSlide(
                  duration: VivrantMotion.fast,
                  curve: VivrantMotion.enter,
                  offset: _pressed ? const Offset(0.18, 0) : Offset.zero,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c.surfaceSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: c.ink.withValues(alpha: 0.42),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
