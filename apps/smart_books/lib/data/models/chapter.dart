class Chapter {
  const Chapter({
    required this.id,
    required this.bookId,
    required this.position,
    required this.title,
    required this.startPage,
    required this.endPage,
    required this.analysisStatus,
    this.analysisError,
  });

  final String id;
  final String bookId;
  final int position;
  final String title;
  final int startPage;
  final int endPage;
  final String analysisStatus;
  final String? analysisError;

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      id: json['id'] as String,
      bookId: json['book_id'] as String,
      position: (json['position'] as num).toInt(),
      title: json['title'] as String,
      startPage: (json['start_page'] as num).toInt(),
      endPage: (json['end_page'] as num).toInt(),
      analysisStatus: json['analysis_status'] as String? ?? 'pending',
      analysisError: json['analysis_error'] as String?,
    );
  }
}
