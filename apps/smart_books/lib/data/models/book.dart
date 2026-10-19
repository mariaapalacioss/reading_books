class Book {
  const Book({
    required this.id,
    required this.userId,
    required this.title,
    this.author,
    required this.language,
    required this.storagePath,
    required this.pageCount,
    required this.status,
    this.statusDetail,
    required this.highlightIntensity,
    required this.analysisProgress,
    required this.currentPage,
    required this.zoom,
    required this.showAiHighlights,
    required this.explanationLanguage,
    this.lastReadAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String title;
  final String? author;
  final String language;
  final String storagePath;
  final int pageCount;
  final String status;
  final String? statusDetail;
  final String highlightIntensity;
  final double analysisProgress;
  final int currentPage;
  final double zoom;
  final bool showAiHighlights;
  final String explanationLanguage;
  final DateTime? lastReadAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      title: json['title'] as String,
      author: json['author'] as String?,
      language: json['language'] as String? ?? 'unknown',
      storagePath: json['storage_path'] as String,
      pageCount: (json['page_count'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'ready',
      statusDetail: json['status_detail'] as String?,
      highlightIntensity: json['highlight_intensity'] as String? ?? 'balanced',
      analysisProgress: (json['analysis_progress'] as num?)?.toDouble() ?? 0,
      currentPage: (json['current_page'] as num?)?.toInt() ?? 1,
      zoom: (json['zoom'] as num?)?.toDouble() ?? 1.15,
      showAiHighlights: json['show_ai_highlights'] as bool? ?? true,
      explanationLanguage: json['explanation_language'] as String? ?? 'es',
      lastReadAt: json['last_read_at'] != null
          ? DateTime.tryParse(json['last_read_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  bool get isLocalStorage => storagePath.startsWith('local/');
}
