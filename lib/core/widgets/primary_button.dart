import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/vivrant_colors.dart';
import '../theme/vivrant_motion.dart';

/// Full-width inverse primary action (matches web PrimaryButton).
class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final c = VivrantColors.of(context);
    final spinnerColor = c.onAccent;
    final enabled = !widget.loading && widget.onPressed != null;
    return Listener(
      onPointerDown: enabled ? (_) => _setPressed(true) : null,
      onPointerUp: enabled ? (_) => _setPressed(false) : null,
      onPointerCancel: enabled ? (_) => _setPressed(false) : null,
      child: AnimatedScale(
        scale: _pressed && enabled ? 0.98 : 1,
        duration: VivrantMotion.fast,
        curve: Curves.easeOutCubic,
        child: SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: c.ink.withValues(alpha: c.dark ? 0.28 : 0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: enabled
                  ? () {
                      HapticFeedback.lightImpact();
                      widget.onPressed!();
                    }
                  : null,
              child: AnimatedSwitcher(
                duration: VivrantMotion.fast,
                child: widget.loading
                    ? SizedBox(
                        key: const ValueKey('loading'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: spinnerColor,
                        ),
                      )
                    : widget.icon == null
                        ? Text(widget.label, key: ValueKey(widget.label))
                        : Row(
                            key: ValueKey(widget.label),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(widget.icon, size: 18),
                              const SizedBox(width: 8),
                              Text(widget.label),
                            ],
                          ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
