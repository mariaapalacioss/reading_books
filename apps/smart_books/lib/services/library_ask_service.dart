import '../data/repositories/books_repository.dart';
import '../domain/study_text.dart';
import '../features/chatgpt/plan_api.dart';

class LibrarySourceCitation {
  const LibrarySourceCitation({
    required this.bookId,
    required this.bookTitle,
    required this.pageNumber,
    required this.snippet,
  });

  final String bookId;
  final String bookTitle;
  final int pageNumber;
  final String snippet;
}

class LibraryAskResult {
  const LibraryAskResult({
    required this.answer,
    required this.sources,
    required this.insufficientEvidence,
  });

  final String answer;
  final List<LibrarySourceCitation> sources;
  final bool insufficientEvidence;

  factory LibraryAskResult.noEvidence() => const LibraryAskResult(
    answer:
        'No encontré suficiente información en tu biblioteca para responder con certeza.',
    sources: [],
    insufficientEvidence: true,
  );
}

/// «Preguntar a mi biblioteca»: solo pasajes recuperados + citas trazables.
class LibraryAskService {
  LibraryAskService(BooksRepository repo, {PlanApi? api}) : _api = api ?? PlanApi();

  final PlanApi _api;

  Future<LibraryAskResult> ask({
    required String userId,
    required String question,
    required Future<List<Map<String, dynamic>>> Function(String q) search,
  }) async {
    final q = question.trim();
    if (q.length < 4) {
      return LibraryAskResult.noEvidence();
    }

    final hits = await search(q);
    if (hits.isEmpty) return LibraryAskResult.noEvidence();

    final sources = <LibrarySourceCitation>[];
    final packed = StringBuffer();
    for (final h in hits.take(12)) {
      final bookId = h['book_id']?.toString() ?? '';
      final page = (h['page_number'] as num?)?.toInt() ?? 0;
      final books = h['books'];
      final title = books is Map
          ? books['title']?.toString() ?? 'Libro'
          : 'Libro';
      final text = normalizeStudyText(h['text']?.toString() ?? '');
      if (text.isEmpty) continue;
      final snippet = text.length > 280 ? '${text.substring(0, 277)}…' : text;
      sources.add(
        LibrarySourceCitation(
          bookId: bookId,
          bookTitle: title,
          pageNumber: page,
          snippet: snippet,
        ),
      );
      packed.writeln('[$title · p.$page]\n$snippet\n');
    }

    if (sources.isEmpty) return LibraryAskResult.noEvidence();

    final answer = await _api.completePlanTextOnce(
      userId: userId,
      instructions: '''
Responde en español usando ÚNICAMENTE los extractos proporcionados de la biblioteca del usuario.
Si no alcanza, dilo explícitamente.
Cita siempre libro y página entre corchetes, p. ej. [Título · p.12].
No inventes contenido fuera de los extractos.
''',
      input: [
        {
          'role': 'user',
          'content': 'Pregunta: $q\n\nExtractos:\n${packed.toString()}',
        },
      ],
    );

    final insufficient = answer.contains('no encontr') ||
        answer.contains('No hay suficiente') ||
        answer.length < 12;

    return LibraryAskResult(
      answer: answer.trim(),
      sources: sources,
      insufficientEvidence: insufficient,
    );
  }
}
