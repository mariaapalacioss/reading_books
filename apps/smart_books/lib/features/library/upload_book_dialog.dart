import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/ui/friendly_errors.dart';
import '../../core/ui/pdf_file_bytes.dart';
import '../shared/bookifi_ui.dart';

Future<bool?> showUploadBookDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: const Color(0xFF08111F).withValues(alpha: 0.46),
    builder: (_) => const _UploadBookDialog(),
  );
}

class _UploadBookDialog extends ConsumerStatefulWidget {
  const _UploadBookDialog();

  @override
  ConsumerState<_UploadBookDialog> createState() => _UploadBookDialogState();
}

class _UploadBookDialogState extends ConsumerState<_UploadBookDialog> {
  final _title = TextEditingController();
  final _author = TextEditingController();
  Uint8List? _bytes;
  String? _fileName;
  var _busy = false;
  String? _error;
  String _progress = '';
  var _picked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
      allowCompression: false,
      dialogTitle: 'Elegir PDF académico',
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }
    final file = result.files.single;
    final data = await readPlatformFileBytes(file);
    if (data == null || data.isEmpty) {
      setState(
        () => _error =
            'No se pudo leer el archivo. Si está en iCloud, descárgalo por completo en Archivos e inténtalo otra vez.',
      );
      return;
    }
    if (!looksLikePdf(data)) {
      setState(
        () => _error = 'El archivo seleccionado no parece un PDF válido.',
      );
      return;
    }
    setState(() {
      _picked = true;
      _bytes = data;
      _fileName = file.name;
      _title.text = file.name.replaceAll(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
    });
  }

  Future<void> _save() async {
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    final bytes = _bytes;
    if (userId == null || bytes == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Guardando…';
    });
    try {
      final bookId = await ref
          .read(ingestServiceProvider)
          .savePdf(
            userId: userId,
            bytes: bytes,
            title: _title.text,
            author: _author.text,
            onProgress: (m) => setState(() => _progress = m),
          );
      final book = await ref.read(booksRepositoryProvider).getBook(bookId);
      if (book != null)
        unawaited(ref.read(ocrJobServiceProvider).ensureOcr(book));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = friendlyUserError(e, logTag: 'upload_book'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_picked) {
      return Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Abriendo selector de PDF…',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  BookifiCallout(_error!, bad: true),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ficha del libro',
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(letterSpacing: -0.03),
              ),
              const SizedBox(height: 6),
              Text(
                _fileName ?? 'PDF',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (_progress.isNotEmpty) ...[
                const SizedBox(height: 12),
                BookifiCallout(_progress),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                BookifiCallout(_error!, bad: true),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _author,
                decoration: const InputDecoration(labelText: 'Autor'),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: BookifiPrimaryButton(
                      label: _busy ? 'Guardando…' : 'Guardar y analizar',
                      loading: _busy,
                      onPressed: _busy || _bytes == null ? null : _save,
                    ),
                  ),
                  const SizedBox(width: 8),
                  BookifiGhostButton(
                    label: 'Cancelar',
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
