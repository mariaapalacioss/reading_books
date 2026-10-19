import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/ui/app_snackbar.dart';
import '../shared/bookifi_ui.dart';
import '../workspace/book_notes_service.dart';
import 'pdf_interactive_page.dart';
import 'reader_margin_note.dart';
import 'selection_crop_preview.dart';

const _kNoteMaxLength = 500;

Future<bool> showReaderAddNoteSheet(
  BuildContext context,
  WidgetRef ref, {
  required String bookId,
  required int pageNumber,
  required PdfSelection selection,
  String? chapterId,
  ReaderMarginNote? existing,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _ReaderNoteEditorSheet(
      bookId: bookId,
      pageNumber: pageNumber,
      chapterId: chapterId,
      selection: selection,
      existing: existing,
    ),
  );
  return result == true;
}

Future<void> showReaderViewNoteSheet(
  BuildContext context,
  WidgetRef ref, {
  required ReaderMarginNote note,
  required PdfSelection? selectionForEdit,
  String? chapterId,
  required VoidCallback onChanged,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _ReaderNoteViewSheet(
      note: note,
      onEdit: () async {
        Navigator.pop(ctx);
        if (selectionForEdit == null) {
          final sel = _syntheticSelection(note);
          final ok = await showReaderAddNoteSheet(
            context,
            ref,
            bookId: note.bookId,
            pageNumber: note.pageNumber,
            selection: sel,
            chapterId: chapterId,
            existing: note,
          );
          if (ok) onChanged();
        } else {
          final ok = await showReaderAddNoteSheet(
            context,
            ref,
            bookId: note.bookId,
            pageNumber: note.pageNumber,
            selection: selectionForEdit,
            chapterId: chapterId,
            existing: note,
          );
          if (ok) onChanged();
        }
      },
      onDelete: () async {
        final confirm = await showDialog<bool>(
          context: ctx,
          builder: (d) => AlertDialog(
            title: const Text('Eliminar nota'),
            content: const Text('¿Eliminar esta nota? No se puede deshacer.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        await ref.read(booksRepositoryProvider).deleteStudyCard(note.id);
        if (ctx.mounted) Navigator.pop(ctx);
        onChanged();
        showAppSnackBar('Nota eliminada');
      },
    ),
  );
}

PdfSelection _syntheticSelection(ReaderMarginNote note) {
  return (
    quote: note.quote ?? '',
    rects: note.rects,
    anchor: Offset.zero,
    previewPixels: null,
    previewWidth: null,
    previewHeight: null,
  );
}

class _ReaderNoteEditorSheet extends ConsumerStatefulWidget {
  const _ReaderNoteEditorSheet({
    required this.bookId,
    required this.pageNumber,
    required this.selection,
    this.chapterId,
    this.existing,
  });

  final String bookId;
  final int pageNumber;
  final String? chapterId;
  final PdfSelection selection;
  final ReaderMarginNote? existing;

  @override
  ConsumerState<_ReaderNoteEditorSheet> createState() =>
      _ReaderNoteEditorSheetState();
}

class _ReaderNoteEditorSheetState extends ConsumerState<_ReaderNoteEditorSheet> {
  late final TextEditingController _body;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _body = TextEditingController(text: widget.existing?.body ?? '');
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _body.text.trim();
    if (text.isEmpty) {
      showAppSnackBar('Escribe algo en la nota.');
      return;
    }
    if (text.length > _kNoteMaxLength) return;
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (userId == null) return;
    setState(() => _saving = true);
    try {
      final svc = BookNotesService(ref.read(booksRepositoryProvider));
      if (widget.existing != null) {
        await svc.updateReaderSelectionNote(
          widget.existing!.id,
          body: text,
        );
      } else {
        await svc.saveReaderSelectionNote(
          bookId: widget.bookId,
          userId: userId,
          pageNumber: widget.pageNumber,
          quote: widget.selection.quote,
          rects: widget.selection.rects,
          body: text,
          chapterId: widget.chapterId,
        );
      }
      bumpRepasoReloadTick(ref);
      if (!mounted) return;
      Navigator.pop(context, true);
      showAppSnackBar('Nota guardada');
    } catch (_) {
      if (mounted) {
        showAppSnackBar('No se pudo guardar la nota. Intenta nuevamente.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final quote = widget.selection.quote.trim();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.existing == null ? 'Añadir nota' : 'Editar nota',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (widget.selection.previewPixels != null &&
              widget.selection.previewWidth != null &&
              widget.selection.previewHeight != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SelectionCropPreview(
                pixels: widget.selection.previewPixels!,
                width: widget.selection.previewWidth!,
                height: widget.selection.previewHeight!,
              ),
            ),
          if (quote.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                quote,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 8,
            maxLength: _kNoteMaxLength,
            decoration: const InputDecoration(
              hintText: 'Tu anotación…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Página ${widget.pageNumber}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: BookifiGhostButton(
                  label: 'Cancelar',
                  onPressed: _saving ? null : () => Navigator.pop(context, false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: BookifiPrimaryButton(
                  label: 'Guardar',
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReaderNoteViewSheet extends StatelessWidget {
  const _ReaderNoteViewSheet({
    required this.note,
    required this.onEdit,
    required this.onDelete,
  });

  final ReaderMarginNote note;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final when = note.createdAt;
    final dateLabel = when != null
        ? '${when.day} ${_month(when.month)} ${when.year} · ${_time(when)}'
        : '';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Nota',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (note.quote != null && note.quote!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(note.quote!, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
            const SizedBox(height: 12),
            Text(note.body, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text(
              'Página ${note.pageNumber}${dateLabel.isNotEmpty ? ' · $dateLabel' : ''}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: Icon(Icons.edit_outlined, color: AppTokens.purple),
                    label: Text('Editar', style: TextStyle(color: AppTokens.purple)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: Icon(Icons.delete_outline, color: AppTokens.danger),
                    label: Text('Eliminar', style: TextStyle(color: AppTokens.danger)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _month(int m) {
    const names = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    return names[(m - 1).clamp(0, 11)];
  }

  String _time(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$h:$min';
  }
}
