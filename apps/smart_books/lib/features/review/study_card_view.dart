import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../shared/bookifi_ui.dart';
import '../shared/markdown_body.dart' show SmartMarkdown;

/// Réplica de `StudyCardView.tsx`.
class StudyCardView extends StatefulWidget {
  const StudyCardView({
    super.key,
    required this.card,
    required this.bookId,
    required this.onReviewed,
    required this.onRepasar,
    this.onDelete,
  });

  final Map<String, dynamic> card;
  final String bookId;
  final VoidCallback onReviewed;
  final VoidCallback onRepasar;
  final VoidCallback? onDelete;

  @override
  State<StudyCardView> createState() => _StudyCardViewState();
}

class _StudyCardViewState extends State<StudyCardView> {
  var _revealed = false;

  static const _kindLabels = {
    'note': 'Nota',
    'qa': 'Pregunta',
    'summary': 'Resumen',
    'review': 'Repaso',
    'explain': 'Explicación',
    'capture': 'Resaltado',
  };

  @override
  Widget build(BuildContext context) {
    final kind = widget.card['kind']?.toString() ?? 'note';
    final source = widget.card['source']?.toString() ?? 'assist';
    final title = widget.card['title']?.toString() ?? 'Sin título';
    final body = widget.card['body']?.toString() ?? '';
    final back = widget.card['back']?.toString();
    final quote = widget.card['quote']?.toString();
    final page = widget.card['page_number'];
    final pageNum = page is num ? page.toInt() : int.tryParse('$page');
    final contextQ = widget.card['context_question']?.toString();
    final isQa = kind == 'qa' && back != null && back.isNotEmpty;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return BookifiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              BookifiChip(
                '${_kindLabels[kind] ?? kind} · ${source == 'chat' ? 'Chat' : 'Asistencia'}',
              ),
              const Spacer(),
              if (pageNum != null)
                TextButton(
                  onPressed: () =>
                      context.push('/libro/${widget.bookId}?page=$pageNum'),
                  child: Text(
                    'PDF $pageNum',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: -0.02,
            ),
          ),
          if (quote != null && quote.isNotEmpty) ...[
            const SizedBox(height: 10),
            BookifiLeftAccent(
              child: Text(
                quote.length > 280 ? '${quote.substring(0, 280)}…' : quote,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (isQa) ...[
            Text(body, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 8),
            if (_revealed)
              SmartMarkdown(data: back!)
            else
              BookifiGhostButton(
                label: 'Mostrar respuesta',
                onPressed: () => setState(() => _revealed = true),
              ),
          ] else
            SmartMarkdown(data: body),
          if (contextQ != null && source == 'chat') ...[
            const SizedBox(height: 10),
            Text(
              'Pregunta: ${contextQ.length > 160 ? '${contextQ.substring(0, 160)}…' : contextQ}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (pageNum != null)
                BookifiPrimaryButton(
                  label: 'Abrir en el libro',
                  icon: Icons.menu_book_outlined,
                  onPressed: () =>
                      context.push('/libro/${widget.bookId}?page=$pageNum'),
                ),
              BookifiGhostButton(
                label: 'Revisado',
                onPressed: widget.onReviewed,
              ),
              BookifiGhostButton(label: 'Repasar', onPressed: widget.onRepasar),
              if (widget.onDelete != null)
                BookifiGhostButton(
                  label: 'Quitar',
                  danger: true,
                  onPressed: widget.onDelete,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
