class OutlineEntry {
  const OutlineEntry({required this.title, required this.page});
  final String title;
  final int page;
}

class ChapterDraft {
  const ChapterDraft({
    required this.title,
    required this.startPage,
    required this.endPage,
    required this.source,
  });
  final String title;
  final int startPage;
  final int endPage;
  final String source;
}

final _heading = RegExp(
  r'^(cap[ií]tulo|chapter|parte|part|secci[oó]n|section|unidad|unit)\b(.{0,80})$',
  caseSensitive: false,
);
final _tocLine = RegExp(
  r'^(.*?)\s+\.{2,}\s*(\d{1,4})\s*$|^((?:cap[ií]tulo|chapter|parte|part|secci[oó]n|section|\d{1,2}[\).]).{0,90}?)\s+(\d{1,4})\s*$',
  caseSensitive: false,
);

List<ChapterDraft> detectChapters({
  required int pageCount,
  required List<OutlineEntry> outline,
  required List<String> pageTexts,
}) {
  if (pageCount <= 0) return [];
  final fromOutline = chaptersFromStarts(
    outline
        .where(
          (e) =>
              e.page >= 1 && e.page <= pageCount && e.title.trim().isNotEmpty,
        )
        .map((e) => (title: _cleanTitle(e.title), page: e.page))
        .toList(),
    pageCount,
  );
  if (fromOutline.length >= 2) return fromOutline;
  final toc = _chaptersFromToc(pageTexts, pageCount);
  if (toc.length >= 2) return toc;
  final headings = _chaptersFromHeadings(pageTexts, pageCount);
  if (headings.length >= 2) return headings;
  if (fromOutline.length == 1) return fromOutline;
  return [
    ChapterDraft(
      title: 'Documento completo',
      startPage: 1,
      endPage: pageCount,
      source: 'detected',
    ),
  ];
}

List<ChapterDraft> chaptersFromStarts(
  List<({String title, int page})> starts,
  int pageCount,
) {
  final sorted =
      [...starts].where((i) => i.page >= 1 && i.page <= pageCount).toList()
        ..sort((a, b) => a.page.compareTo(b.page));
  final deduped = <({String title, int page})>[];
  for (final item in sorted) {
    if (deduped.isEmpty || deduped.last.page != item.page) deduped.add(item);
  }
  if (deduped.isEmpty) return [];
  return List.generate(deduped.length, (index) {
    final item = deduped[index];
    final next = index + 1 < deduped.length
        ? deduped[index + 1].page
        : pageCount + 1;
    return ChapterDraft(
      title: item.title.isEmpty ? 'Capítulo ${index + 1}' : item.title,
      startPage: item.page,
      endPage: item.page > next - 1 ? item.page : next - 1,
      source: 'detected',
    );
  });
}

List<ChapterDraft> _chaptersFromToc(List<String> pageTexts, int pageCount) {
  final starts = <({String title, int page})>[];
  final scanUntil = pageTexts.length < 15 ? pageTexts.length : 15;
  for (var i = 0; i < scanUntil; i++) {
    var tocHits = 0;
    for (final line in pageTexts[i].split(RegExp(r'\n+'))) {
      final m = _tocLine.firstMatch(line.trim());
      if (m == null) continue;
      final title = _cleanTitle(m.group(1) ?? m.group(3) ?? '');
      final printed = int.tryParse(m.group(2) ?? m.group(4) ?? '');
      if (title.length < 3 ||
          printed == null ||
          printed < 1 ||
          printed > pageCount)
        continue;
      tocHits++;
      starts.add((title: title, page: printed));
    }
    if (tocHits == 0 && starts.isNotEmpty) break;
  }
  return chaptersFromStarts(starts, pageCount);
}

List<ChapterDraft> _chaptersFromHeadings(
  List<String> pageTexts,
  int pageCount,
) {
  final starts = <({String title, int page})>[];
  for (var i = 0; i < pageTexts.length; i++) {
    final first = pageTexts[i]
        .split(RegExp(r'\n+'))
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (first.isEmpty || first.length > 90 || !_heading.hasMatch(first))
      continue;
    starts.add((title: _cleanTitle(first), page: i + 1));
  }
  return chaptersFromStarts(starts, pageCount);
}

String _cleanTitle(String value) => value
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'[.\s]+$'), '')
    .trim();
