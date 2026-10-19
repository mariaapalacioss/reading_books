class PageSlice {
  const PageSlice({required this.page, required this.text});

  final int page;
  final String text;
}

class ChunkDraft {
  const ChunkDraft({
    required this.pageStart,
    required this.pageEnd,
    required this.content,
  });

  final int pageStart;
  final int pageEnd;
  final String content;
}

const _target = 1800;

List<ChunkDraft> buildChunks(List<PageSlice> pages) {
  final usable = pages.where((p) => p.text.trim().isNotEmpty).toList();
  final chunks = <ChunkDraft>[];
  var current = <PageSlice>[];
  var size = 0;

  void flush() {
    if (current.isEmpty) return;
    chunks.add(
      ChunkDraft(
        pageStart: current.first.page,
        pageEnd: current.last.page,
        content: current
            .map((p) => '[p.${p.page}]\n${p.text.trim()}')
            .join('\n\n'),
      ),
    );
    current = [];
    size = 0;
  }

  for (final page in usable) {
    final block = page.text.trim();
    if (size > 0 && size + block.length > _target) flush();
    current.add(page);
    size += block.length;
    if (size >= _target) flush();
  }
  flush();
  return chunks;
}

List<ChunkDraft> windowsForAnalysis(
  List<PageSlice> pages, {
  int maxChars = 12000,
}) {
  final built = buildChunks(pages);
  final groups = <ChunkDraft>[];
  for (final chunk in built) {
    final last = groups.isEmpty ? null : groups.last;
    if (last == null || last.content.length + chunk.content.length > maxChars) {
      groups.add(
        ChunkDraft(
          pageStart: chunk.pageStart,
          pageEnd: chunk.pageEnd,
          content: chunk.content,
        ),
      );
    } else {
      groups[groups.length - 1] = ChunkDraft(
        pageStart: last.pageStart,
        pageEnd: chunk.pageEnd,
        content: '${last.content}\n\n${chunk.content}',
      );
    }
  }
  return groups;
}
