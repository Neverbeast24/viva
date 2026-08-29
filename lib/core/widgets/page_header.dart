import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/vivrant_colors.dart';
import '../theme/vivrant_layout.dart';
import '../theme/vivrant_motion.dart';
import 'fade_slide_in.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.highlight,
    this.lede,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String? highlight;
  final String? lede;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = VivrantColors.of(context);
    Widget bar = Container(
      width: 36,
      height: 3,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(99),
        gradient: c.brandGradient,
      ),
    );
    if (!VivrantMotion.reduce(context)) {
      bar = bar
          .animate()
          .scaleX(
            begin: 0.2,
            end: 1,
            duration: 520.ms,
            curve: VivrantMotion.enter,
            alignment: Alignment.centerLeft,
          )
          .fadeIn(duration: 280.ms);
    }

    return FadeSlideIn(
      child: Padding(
        padding: const EdgeInsets.only(bottom: VivrantLayout.headerBottom),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    eyebrow.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: c.accent,
                          letterSpacing: 2,
                        ),
                  ),
                  const SizedBox(height: 10),
                  bar,
                  const SizedBox(height: 12),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: c.ink,
                                height: 1.12,
                              ),
                        ),
                        if (highlight != null)
                          TextSpan(
                            text: ' $highlight',
                            style: GoogleFonts.instrumentSerif(
                              fontSize: 30,
                              fontWeight: FontWeight.w400,
                              fontStyle: FontStyle.italic,
                              height: 1.12,
                              color: c.accentDeep,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (lede != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      lede!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: c.muted,
                            fontSize: 15,
                            height: 1.45,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
