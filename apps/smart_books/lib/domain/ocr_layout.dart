import '../data/models/text_item.dart';

const sparsePageChars = 40;
const scannedPageRatio = 0.7;

bool isSparsePage(int charCount) => charCount < sparsePageChars;

bool documentNeedsOcr(List<int> charCounts) {
  if (charCounts.isEmpty) return false;
  final sparse = charCounts.where(isSparsePage).length;
  return sparse / charCounts.length >= scannedPageRatio;
}

class OcrWord {
  const OcrWord({
    required this.text,
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
  });
  final String text;
  final double x0;
  final double y0;
  final double x1;
  final double y1;
}

({String text, List<TextItem> items}) layoutOcrWords(
  List<OcrWord> words,
  double width,
  double height,
) {
  final usable =
      words
          .map(
            (w) => OcrWord(
              text: w.text.replaceAll(RegExp(r'\s+'), ' ').trim(),
              x0: w.x0,
              y0: w.y0,
              x1: w.x1,
              y1: w.y1,
            ),
          )
          .where(
            (w) =>
                w.text.isNotEmpty &&
                width > 0 &&
                height > 0 &&
                w.x1 > w.x0 &&
                w.y1 > w.y0,
          )
          .toList()
        ..sort(
          (a, b) => a.y0.compareTo(b.y0) != 0
              ? a.y0.compareTo(b.y0)
              : a.x0.compareTo(b.x0),
        );

  var text = '';
  final items = <TextItem>[];
  var lineCenter = -1.0;
  var lineHeight = 0.0;

  for (final word in usable) {
    final hPx = word.y1 - word.y0;
    final center = (word.y0 + word.y1) / 2;
    final sameLine =
        lineCenter >= 0 &&
        (center - lineCenter).abs() <=
            (lineHeight > hPx ? lineHeight : hPx) * 0.6;
    if (text.isNotEmpty) text += sameLine ? ' ' : '\n';
    if (!sameLine) {
      lineCenter = center;
      lineHeight = hPx;
    }
    final start = text.length;
    text += word.text;
    items.add(
      TextItem(
        s: word.text,
        start: start,
        x: _round(word.x0 / width),
        y: _round(word.y0 / height),
        w: _round((word.x1 - word.x0) / width),
        h: _round(hPx / height),
      ),
    );
  }
  return (text: text, items: items);
}

double _round(double v) => (v * 10000).roundToDouble() / 10000;
