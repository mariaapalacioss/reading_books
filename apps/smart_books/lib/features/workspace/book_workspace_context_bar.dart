import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/theme/margen_iconography.dart';
/// Barra contextual mínima para Estudiar / Practicar (sin controles de página PDF).
class BookWorkspaceContextBar extends StatelessWidget {
  const BookWorkspaceContextBar({
    super.key,
    required this.bookId,
    required this.title,
    this.subtitle,
    this.page,
  });

  final String bookId;
  final String title;
  final String? subtitle;
  final int? page;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF0B1220).withValues(alpha: 0.92)
          : Colors.white.withValues(alpha: 0.96),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
            ),
          ),
        ),
        child: Row(
          children: [
            TextButton.icon(
              onPressed: () => context.go('/'),
              icon: const MIcon(MargenLucide.back, size: 16),
              label: const Text('Biblioteca'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Leer PDF',
              onPressed: () {
                final q = page != null ? '?page=$page' : '';
                context.go('/libro/$bookId$q');
              },
              icon: MIcon(MargenLucide.fileText, size: 20, color: AppTokens.purple),
            ),
          ],
        ),
      ),
    );
  }
}
