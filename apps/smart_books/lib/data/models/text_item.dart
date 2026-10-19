class TextItem {
  const TextItem({
    required this.s,
    required this.start,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final String s;
  final int start;
  final double x;
  final double y;
  final double w;
  final double h;

  Map<String, dynamic> toJson() => {
    's': s,
    'start': start,
    'x': x,
    'y': y,
    'w': w,
    'h': h,
  };

  factory TextItem.fromJson(Map<String, dynamic> json) => TextItem(
    s: json['s'] as String,
    start: (json['start'] as num).toInt(),
    x: (json['x'] as num).toDouble(),
    y: (json['y'] as num).toDouble(),
    w: (json['w'] as num).toDouble(),
    h: (json['h'] as num).toDouble(),
  );
}
