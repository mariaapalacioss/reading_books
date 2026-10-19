import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import 'repaso_models.dart';

class RepasoSessionMcqCard extends StatelessWidget {
  const RepasoSessionMcqCard({
    super.key,
    required this.card,
    required this.selectedIndex,
    required this.revealed,
    required this.onSelect,
  });

  final RepasoFlashcard card;
  final int? selectedIndex;
  final bool revealed;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final practice = card.practice!;
    final options = practice.options;
    final correct = practice.correctIndex ?? 0;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF111827)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTokens.cyan.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Opción múltiple',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppTokens.cyan,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            card.question,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          ...List.generate(options.length, (i) {
            Color? fill;
            Color border = Theme.of(context).dividerColor;
            if (revealed && i == correct) {
              fill = const Color(0xFF22C55E).withValues(alpha: 0.15);
              border = const Color(0xFF22C55E);
            } else if (revealed && selectedIndex == i && i != correct) {
              fill = AppTokens.danger.withValues(alpha: 0.12);
              border = AppTokens.danger;
            } else if (selectedIndex == i) {
              fill = AppTokens.purple.withValues(alpha: 0.1);
              border = AppTokens.purple;
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: fill ?? Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: revealed ? null : () => onSelect(i),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: border),
                    ),
                    child: Text(
                      options[i],
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
          if (revealed) ...[
            const SizedBox(height: 8),
            Text(
              'Respuesta: ${card.answer}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: muted,
                height: 1.35,
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Elige una opción para ver la respuesta correcta.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: muted),
              ),
            ),
        ],
      ),
    );
  }
}
