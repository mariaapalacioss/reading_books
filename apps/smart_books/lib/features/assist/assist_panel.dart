import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers.dart';
import '../../core/ui/app_snackbar.dart';
import '../../core/ui/friendly_errors.dart';
import '../../domain/content_language.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/margen_iconography.dart';
import '../../data/models/book.dart';
import '../../data/models/chapter.dart';
import '../../data/models/highlight.dart';
import '../../domain/study_scope.dart';
import '../../features/chatgpt/chatgpt_credentials.dart';
import '../../features/chatgpt/chatgpt_platform.dart';
import '../../services/book_assist_service.dart';
import '../review/repaso_feedback.dart';
import '../review/repaso_qa_store.dart';
import '../review/repaso_review_flow.dart';
import '../review/repaso_save_ui.dart';
import '../reader/selection_crop_preview.dart';
import '../shared/bookifi_ui.dart';
import '../shared/markdown_body.dart' show SmartMarkdown;

enum _WorkspaceTab { chat, paginas, fragmentos }

enum _PageStudyMode { currentPage, pageRange }

const _kLiveFragmentId = kLiveStudyFragmentId;

/// Panel de asistencia al estilo `AssistPanel.tsx` (escritorio) o sheet (móvil).
class AssistPanel extends ConsumerStatefulWidget {
  const AssistPanel({
    super.key,
    required this.book,
    required this.page,
    required this.chapters,
    this.quote,
    this.pageHasText = true,
    this.embedded = false,
    this.selectionPreviewPixels,
    this.selectionPreviewWidth,
    this.selectionPreviewHeight,
    this.autoExplain = false,
    this.highlights = const [],
    this.onClose,
  });

  final Book book;
  final int page;
  final List<Chapter> chapters;
  final List<Highlight> highlights;
  final String? quote;
  final bool pageHasText;
  final bool embedded;
  final Uint8List? selectionPreviewPixels;
  final int? selectionPreviewWidth;
  final int? selectionPreviewHeight;
  final bool autoExplain;
  final VoidCallback? onClose;

  @override
  ConsumerState<AssistPanel> createState() => AssistPanelState();
}

class AssistPanelState extends ConsumerState<AssistPanel> {
  final _messages = <({bool user, String text})>[];
  final _input = TextEditingController();
  var _streaming = false;
  var _streamBuffer = '';
  String? _error;
  AssistMode? _activeMode;
  String? _lastAssistText;
  String _modeResponse = '';
  _WorkspaceTab _tab = _WorkspaceTab.chat;
  final _storedResponses = <AssistMode, String>{};
  _PageStudyMode _pageStudyMode = _PageStudyMode.currentPage;
  final _rangeStartCtrl = TextEditingController();
  final _rangeEndCtrl = TextEditingController();
  final _selectedFragmentIds = <String>{};
  StudyScope? _activeStudyScope;
  StudyScope? _cachedFragmentScope;
  String _fragmentScopeCacheKey = '';
  final _repasoSaveStates = <String, RepasoSaveUiState>{};
  String? _cachedSaveContextQuestion;

  @override
  void initState() {
    super.initState();
    _syncRangeFieldsToPage(widget.page);
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _warmChatGptPlan();
      _refreshRepasoSaveStates();
    });
    if (widget.quote != null && widget.quote!.length > 8) {
      _input.text = widget.quote!;
    }
    if (widget.autoExplain) {
      WidgetsBinding.instance.addPostFrameCallback((_) => explainSelection());
    }
  }

  @override
  void didUpdateWidget(covariant AssistPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.quote != oldWidget.quote &&
        widget.quote != null &&
        widget.quote!.length > 8) {
      _input.text = widget.quote!;
    }
    if (widget.page != oldWidget.page &&
        _pageStudyMode == _PageStudyMode.pageRange &&
        _rangeStartCtrl.text == '${oldWidget.page}' &&
        _rangeEndCtrl.text == '${oldWidget.page}') {
      _syncRangeFieldsToPage(widget.page);
    }
    if (oldWidget.page != widget.page ||
        oldWidget.quote != widget.quote ||
        oldWidget.book.id != widget.book.id) {
      _repasoSaveStates.clear();
      _cachedSaveContextQuestion = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshRepasoSaveStates());
    }
  }

  String _repasoSaveKey(AssistMode mode, String contextQuestion) =>
      '${mode.name}|$contextQuestion';

  RepasoSaveUiState _saveStateFor(AssistMode mode) {
    final ctx = _cachedSaveContextQuestion;
    if (ctx == null) return RepasoSaveUiState.ready;
    return _repasoSaveStates[_repasoSaveKey(mode, ctx)] ??
        RepasoSaveUiState.ready;
  }

  Future<String> _contextQuestionForSave() async {
    final scope = _activeStudyScope ?? await _resolveStudyScope();
    if (scope != null && scope.isValidSource) {
      return repasoSourceKeyForStudyScope(scope);
    }
    if (widget.quote != null && widget.quote!.trim().length >= 8) {
      return repasoSourceKeyFragment(
        widget.book.id,
        widget.page,
        widget.quote!,
      );
    }
    return repasoSourceKeyPage(widget.book.id, widget.page);
  }

  Future<void> _refreshRepasoSaveStates() async {
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (userId == null) return;
    try {
      final ctx = await _contextQuestionForSave();
      _cachedSaveContextQuestion = ctx;
      final repo = ref.read(booksRepositoryProvider);
      final updates = <String, RepasoSaveUiState>{};
      for (final mode in AssistMode.values) {
        final hasText = switch (mode) {
          AssistMode.chat =>
            _messages.any((m) => !m.user && m.text.trim().isNotEmpty),
          _ =>
            (_storedResponses[mode]?.trim().isNotEmpty ?? false) ||
                (_activeMode == mode && _modeResponse.trim().isNotEmpty),
        };
        if (!hasText) continue;
        final existing = await findStudyCardForRepasoSave(
          repo,
          bookId: widget.book.id,
          contextQuestion: ctx,
          assistMode: mode.name,
        );
        updates[_repasoSaveKey(mode, ctx)] = existing != null
            ? RepasoSaveUiState.saved
            : RepasoSaveUiState.ready;
      }
      if (!mounted) return;
      setState(() => _repasoSaveStates.addAll(updates));
    } catch (_) {
      // Estado de guardado es UX; errores van en el intento de guardar.
    }
  }

  /// Lanzar explicación del fragmento / recorte (desde el menú del PDF).
  void explainSelection() {
    setState(() {
      _tab = _WorkspaceTab.fragmentos;
      if (widget.quote != null && widget.quote!.trim().length >= 8) {
        _selectedFragmentIds.add(_kLiveFragmentId);
      }
    });
    _runScopedStudy(AssistMode.explain);
  }

  _WorkspaceTab _tabForMode(AssistMode mode) {
    return switch (mode) {
      AssistMode.keyPoints ||
      AssistMode.summary ||
      AssistMode.page ||
      AssistMode.review => _WorkspaceTab.paginas,
      AssistMode.explain ||
      AssistMode.fragmentSummary => _WorkspaceTab.fragmentos,
      AssistMode.chat => _WorkspaceTab.chat,
    };
  }

  void _syncRangeFieldsToPage(int page) {
    _rangeStartCtrl.text = '$page';
    _rangeEndCtrl.text = '$page';
  }

  Future<void> _warmChatGptPlan() async {
    if (!chatGptConnectEnabled) return;
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (userId == null) return;
    final creds = await ref.read(chatGptCredentialsProvider.future);
    if (creds == null || !creds.hasPlanUsage) return;
    try {
      await ref.read(planApiProvider).preferredModel(userId);
    } catch (_) {}
  }

  String _fragmentSelectionKey() {
    final ids = _selectedFragmentRefs().map((f) => f.id).toList()..sort();
    return ids.join('|');
  }

  void _invalidateFragmentScopeCache() {
    _cachedFragmentScope = null;
    _fragmentScopeCacheKey = '';
  }

  List<Highlight> get _userFragments => widget.highlights
      .where(
        (h) => h.origin == 'user' && !h.dismissed && h.quote.trim().length >= 8,
      )
      .toList();

  bool get _hasLiveFragment =>
      widget.quote != null && widget.quote!.trim().length >= 8;

  List<StudyFragmentRef> _selectedFragmentRefs() {
    final out = <StudyFragmentRef>[];
    if (_selectedFragmentIds.contains(_kLiveFragmentId) && _hasLiveFragment) {
      final q = widget.quote!.trim();
      Highlight? match;
      for (final h in _userFragments) {
        final hq = h.quote.trim();
        if (hq == q || hq.contains(q) || q.contains(hq)) {
          match = h;
          break;
        }
      }
      out.add(
        StudyFragmentRef(
          id: match?.id ?? _kLiveFragmentId,
          pageNumber: match?.pageNumber ?? widget.page,
          quote: q,
        ),
      );
    }
    for (final h in _userFragments) {
      if (_selectedFragmentIds.contains(h.id)) {
        out.add(
          StudyFragmentRef(id: h.id, pageNumber: h.pageNumber, quote: h.quote),
        );
      }
    }
    return out;
  }

  Future<StudyScope?> _resolveStudyScope({StudyScope? reuse}) async {
    if (reuse != null) return reuse;
    final repo = ref.read(booksRepositoryProvider);
    final total = widget.book.pageCount;
    if (_tab == _WorkspaceTab.paginas) {
      if (_pageStudyMode == _PageStudyMode.currentPage) {
        return buildStudyScope(
          repo: repo,
          kind: StudyScopeKind.currentPage,
          bookId: widget.book.id,
          currentPage: widget.page,
          totalPages: total,
        );
      }
      final start = int.tryParse(_rangeStartCtrl.text.trim()) ?? widget.page;
      final end = int.tryParse(_rangeEndCtrl.text.trim()) ?? start;
      final err = validatePageRange(start: start, end: end, totalPages: total);
      if (err.isNotEmpty) {
        setState(() => _error = err);
        return null;
      }
      return buildStudyScope(
        repo: repo,
        kind: StudyScopeKind.pageRange,
        bookId: widget.book.id,
        currentPage: widget.page,
        totalPages: total,
        rangeStart: start,
        rangeEnd: end,
      );
    }
    if (_tab == _WorkspaceTab.fragmentos) {
      final key = _fragmentSelectionKey();
      if (_cachedFragmentScope != null && _fragmentScopeCacheKey == key) {
        return _cachedFragmentScope;
      }
      final refs = _selectedFragmentRefs();
      final scope = await buildStudyScope(
        repo: repo,
        kind: StudyScopeKind.fragments,
        bookId: widget.book.id,
        currentPage: widget.page,
        totalPages: total,
        fragments: refs,
      );
      _cachedFragmentScope = scope;
      _fragmentScopeCacheKey = key;
      return scope;
    }
    return null;
  }

  bool _scopedActionsDisabled() {
    if (_streaming) return true;
    if (_tab == _WorkspaceTab.fragmentos) {
      return _selectedFragmentRefs().isEmpty;
    }
    if (_tab == _WorkspaceTab.paginas &&
        _pageStudyMode == _PageStudyMode.pageRange) {
      final start = int.tryParse(_rangeStartCtrl.text.trim()) ?? 0;
      final end = int.tryParse(_rangeEndCtrl.text.trim()) ?? 0;
      return validatePageRange(
        start: start,
        end: end,
        totalPages: widget.book.pageCount,
      ).isNotEmpty;
    }
    return false;
  }

  String _responseText(AssistMode mode) {
    if (_streaming && _activeMode == mode) {
      return _modeResponse.isEmpty ? '…' : _modeResponse;
    }
    return _storedResponses[mode] ?? '';
  }

  String _previewLine(AssistMode mode) {
    final text = _responseText(mode);
    if (text.isEmpty || text == '…') return '';
    final flat = text.replaceAll('\n', ' ').trim();
    return flat.length > 72 ? '${flat.substring(0, 72)}…' : flat;
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('chat_${widget.book.id}');
    if (raw == null) return;
    final list = (jsonDecode(raw) as List).cast<Map>();
    if (!mounted) return;
    setState(() {
      _messages.addAll(
        list.map((m) => (user: m['user'] as bool, text: m['text'] as String)),
      );
    });
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'chat_${widget.book.id}',
      jsonEncode(
        _messages.map((m) => {'user': m.user, 'text': m.text}).toList(),
      ),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    _rangeStartCtrl.dispose();
    _rangeEndCtrl.dispose();
    super.dispose();
  }

  Chapter? get _chapter {
    for (final ch in widget.chapters) {
      if (widget.page >= ch.startPage && widget.page <= ch.endPage) return ch;
    }
    return null;
  }

  Future<void> _runScopedStudy(
    AssistMode mode, {
    StudyScope? scopeOverride,
  }) async {
    if (mode != AssistMode.chat && _scopedActionsDisabled()) return;
    final scope = scopeOverride ?? await _resolveStudyScope();
    if (mode != AssistMode.chat) {
      if (scope == null) return;
      if (!scope.isValidSource) {
        setState(
          () => _error =
              'Todavía no hay texto suficiente en esta selección. Espera el OCR o elige otro rango.',
        );
        return;
      }
    }
    await _runMode(mode, studyScope: scope);
  }

  Future<void> _runMode(AssistMode mode, {StudyScope? studyScope}) async {
    if (mode == AssistMode.chat && _input.text.trim().length < 2) return;
    if (!chatGptConnectEnabled) {
      if (mounted) {
        setState(
          () => _error =
              'Conecta ChatGPT Plus desde Ajustes (iPhone, iPad o Mac).',
        );
      }
      return;
    }
    final linked = await ref.read(chatGptCredentialsProvider.future);
    if (linked == null || !linked.hasPlanUsage) {
      if (mounted) {
        setState(
          () => _error =
              'Conecta ChatGPT Plus antes de usar la asistencia (barra superior → ChatGPT Plus).',
        );
      }
      return;
    }
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (userId == null || _streaming) return;
    final ch = _chapter;
    setState(() {
      _error = null;
      _streaming = true;
      _activeMode = mode;
      _streamBuffer = '';
      _modeResponse = '';
      _lastAssistText = null;
      if (studyScope != null) _activeStudyScope = studyScope;
      if (mode != AssistMode.chat) {
        _tab = _tabForMode(mode);
      }
      if (mode == AssistMode.chat) {
        _tab = _WorkspaceTab.chat;
        final text = _input.text.trim();
        if (text.length >= 2) _messages.add((user: true, text: text));
        _messages.add((user: false, text: ''));
      }
    });
    if (mode == AssistMode.chat) _input.clear();
    try {
      final assist = BookAssistService(ref.read(booksRepositoryProvider));
      await assist.streamAssist(
        userId: userId,
        mode: mode,
        bookId: widget.book.id,
        bookTitle: widget.book.title,
        language: widget.book.explanationLanguage,
        bookLanguage: widget.book.language,
        chapterId: ch?.id,
        chapterTitle: ch?.title,
        chapterStartPage: ch?.startPage,
        chapterEndPage: ch?.endPage,
        pageNumber: widget.page,
        quote: widget.quote ?? _input.text.trim(),
        selectionImagePixels: widget.selectionPreviewPixels,
        selectionImageWidth: widget.selectionPreviewWidth,
        selectionImageHeight: widget.selectionPreviewHeight,
        messages: _messages
            .where((m) => m.text.isNotEmpty)
            .map(
              (m) => {'role': m.user ? 'user' : 'assistant', 'content': m.text},
            )
            .toList(),
        onDelta: (delta) {
          setState(() {
            _streamBuffer += delta;
            if (mode == AssistMode.chat) {
              _messages[_messages.length - 1] = (
                user: false,
                text: _streamBuffer,
              );
            } else {
              _modeResponse = _streamBuffer;
            }
            _lastAssistText = _streamBuffer;
          });
        },
        studyScope: studyScope,
        fragmentSourceOnly:
            _tab == _WorkspaceTab.fragmentos &&
            widget.selectionPreviewPixels == null &&
            (mode == AssistMode.explain || mode == AssistMode.fragmentSummary),
      );
      if (mode != AssistMode.chat && _streamBuffer.trim().isNotEmpty) {
        setState(() => _storedResponses[mode] = _streamBuffer);
      }
      await _saveHistory();
    } catch (e) {
      setState(() => _error = _friendlyError(e.toString()));
    } finally {
      setState(() => _streaming = false);
      _refreshRepasoSaveStates();
    }
  }

  Future<void> _saveStudy({AssistMode? modeOverride, String? textOverride}) async {
    final mode = modeOverride ?? _activeMode ?? AssistMode.chat;
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    final text = textOverride ??
        _lastAssistText ??
        (mode == AssistMode.chat
            ? _messages
                .where((m) => !m.user && m.text.isNotEmpty)
                .map((m) => m.text)
                .lastOrNull
            : _storedResponses[mode]) ??
        (mode == _activeMode ? _modeResponse : null);
    if (userId == null || text == null || text.trim().isEmpty) {
      if (mounted) {
        showAppSnackBar('No hay contenido de la IA para guardar todavía.');
      }
      return;
    }
    final ch = _chapter;
    String? saveKey;
    try {
      final contextQuestion = await _contextQuestionForSave();
      _cachedSaveContextQuestion = contextQuestion;
      final key = _repasoSaveKey(mode, contextQuestion);
      saveKey = key;
      if (_repasoSaveStates[key] == RepasoSaveUiState.saved) return;

      setState(() => _repasoSaveStates[key] = RepasoSaveUiState.saving);

      final repo = ref.read(booksRepositoryProvider);
      final existing = await findStudyCardForRepasoSave(
        repo,
        bookId: widget.book.id,
        contextQuestion: contextQuestion,
        assistMode: mode.name,
      );
      if (existing != null) {
        if (!mounted) return;
        setState(() => _repasoSaveStates[key] = RepasoSaveUiState.saved);
        return;
      }

      await repo.insertStudyCard({
        'book_id': widget.book.id,
        'user_id': userId,
        'chapter_id': ch?.id,
        'page_number': widget.page,
        'kind': 'note',
        'source': 'assist',
        'title': _saveTitleForMode(
          mode,
          ch?.title,
          _assistContentLanguage(text),
        ),
        'body': text,
        'assist_mode': mode.name,
        'quote': widget.quote,
        'context_question': contextQuestion,
      });
      if (!mounted) return;
      setState(() => _repasoSaveStates[key] = RepasoSaveUiState.saved);
      notifyRepasoSaved(ref);
    } catch (e) {
      if (mounted) {
        if (saveKey != null) {
          setState(() => _repasoSaveStates[saveKey!] = RepasoSaveUiState.error);
        }
        showAppSnackBar(kRepasoSaveErrorMessage);
      }
    }
  }

  void _selectTab(_WorkspaceTab tab) {
    setState(() {
      _tab = tab;
      _activeStudyScope = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshRepasoSaveStates());
  }

  ContentLanguage _assistContentLanguage(String text) {
    final sample = text.trim().isNotEmpty ? text : (widget.quote?.trim() ?? '');
    return resolveContentLanguage(
      sourceText: sample,
      metadataLanguage: widget.book.language,
      localeFallback: contentLanguageFromCode(widget.book.explanationLanguage),
    );
  }

  String _saveTitleForMode(
    AssistMode? mode,
    String? chapterTitle,
    ContentLanguage lang,
  ) {
    final scope = _activeStudyScope;
    if (scope != null && mode != AssistMode.chat && mode != AssistMode.review) {
      final kind = switch (mode) {
        AssistMode.summary => AssistResultKind.summary,
        AssistMode.keyPoints => AssistResultKind.keyPoints,
        AssistMode.page ||
        AssistMode.explain ||
        AssistMode.fragmentSummary => AssistResultKind.explain,
        _ => AssistResultKind.summary,
      };
      return studyScopeResultTitle(result: kind, scope: scope, lang: lang);
    }
    final ch = chapterTitle?.trim();
    if (lang == ContentLanguage.en) {
      return switch (mode) {
        AssistMode.summary =>
          ch != null && ch.isNotEmpty ? 'Summary · $ch' : 'Chapter summary',
        AssistMode.keyPoints =>
          ch != null && ch.isNotEmpty ? 'Key points · $ch' : 'Important points',
        AssistMode.page => 'Explanation · p. ${widget.page}',
        AssistMode.explain => 'Fragment · p. ${widget.page}',
        AssistMode.review =>
          ch != null && ch.isNotEmpty ? 'Active review · $ch' : 'Active review',
        AssistMode.fragmentSummary => 'Fragment summary · p. ${widget.page}',
        AssistMode.chat => 'Chat note · p. ${widget.page}',
        null => 'Note · p. ${widget.page}',
      };
    }
    return switch (mode) {
      AssistMode.summary =>
        ch != null && ch.isNotEmpty ? 'Resumen · $ch' : 'Resumen del capítulo',
      AssistMode.keyPoints =>
        ch != null && ch.isNotEmpty
            ? 'Puntos clave · $ch'
            : 'Puntos importantes',
      AssistMode.page => 'Explicación · pág. ${widget.page}',
      AssistMode.explain => 'Fragmento · pág. ${widget.page}',
      AssistMode.review =>
        ch != null && ch.isNotEmpty ? 'Repaso activo · $ch' : 'Repaso activo',
      AssistMode.fragmentSummary => 'Fragmento resumido · pág. ${widget.page}',
      AssistMode.chat => 'Nota de chat · pág. ${widget.page}',
      null => 'Nota · pág. ${widget.page}',
    };
  }

  Future<void> _generateReviewQuestions({StudyScope? scopeOverride}) async {
    final scope =
        scopeOverride ?? _activeStudyScope ?? await _resolveStudyScope();
    if (scope == null || !scope.isValidSource) {
      setState(
        () => _error = _tab == _WorkspaceTab.fragmentos
            ? 'Selecciona al menos un fragmento con texto.'
            : 'No hay texto suficiente en las páginas seleccionadas.',
      );
      return;
    }
    setState(() => _activeStudyScope = scope);
    if (!context.mounted) return;
    await runAssistGenerateReviewFlowForStudyScope(
      context,
      ref,
      book: widget.book,
      scope: scope,
    );
  }

  Color _accentForMode(AssistMode mode) {
    return switch (mode) {
      AssistMode.keyPoints => AppTokens.teal,
      AssistMode.summary => AppTokens.purple,
      AssistMode.page => AppTokens.cyan,
      AssistMode.explain => AppTokens.purple,
      AssistMode.review => AppTokens.warning,
      AssistMode.chat => AppTokens.purple,
      AssistMode.fragmentSummary => AppTokens.purple,
    };
  }

  String _friendlyError(String raw) => friendlyUserError(raw, logTag: 'assist');

  Widget _chatBubble(
    BuildContext context, {
    required bool user,
    required String text,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: widget.embedded ? 300 : 340),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: user
              ? (isDark
                    ? AppTokens.purple.withValues(alpha: 0.22)
                    : AppTokens.purple.withValues(alpha: 0.1))
              : (isDark ? const Color(0xFF111827) : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(user ? 14 : 4),
            bottomRight: Radius.circular(user ? 4 : 14),
          ),
          border: Border.all(
            color: user
                ? AppTokens.purple.withValues(alpha: 0.35)
                : Theme.of(context).dividerColor,
          ),
        ),
        child: user
            ? Text(text, style: Theme.of(context).textTheme.bodyMedium)
            : SmartMarkdown(data: text, compact: true),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required bool hasCreds,
    required bool platformOk,
    required AsyncValue<ChatGptCredentials?> credsAsync,
  }) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded)
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        Row(
          children: [
            MIcon(MargenLucide.sparkles, size: 20, color: AppTokens.purple),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Asistencia',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            if (!widget.embedded && widget.onClose != null)
              IconButton(
                tooltip: 'Cerrar',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (hasCreds)
          BookifiChip(
            'ChatGPT Plus · ${credsAsync.value?.email ?? credsAsync.value?.subject ?? "conectado"}',
            teal: true,
          )
        else if (!platformOk)
          const BookifiCallout(
            'ChatGPT Plus no está disponible en esta plataforma.',
          )
        else
          const BookifiCallout('Conecta ChatGPT Plus para resúmenes y chat.'),
        if (platformOk && !hasCreds)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: BookifiGhostButton(
              label: 'Conectar ChatGPT Plus',
              onPressed: () => context.push('/conectar-chatgpt'),
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          BookifiCallout(_friendlyError(_error!), bad: true),
        ],
        const SizedBox(height: 12),
        Text(
          'Página PDF ${widget.page}${widget.book.pageCount > 0 ? ' / ${widget.book.pageCount}' : ''}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 12),
        _AssistCategoryTabs(selected: _tab, onSelected: _selectTab),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildStudyActions({
    required AssistMode explainMode,
    AssistMode? primary,
  }) {
    final disabled = _scopedActionsDisabled();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MargenAssistAction(
          label: _scopedButtonLabel(explainMode),
          icon: MargenLucide.messageCircle,
          iconAccent: AppTokens.cyan,
          primary: primary == explainMode,
          loading: _streaming && _activeMode == explainMode,
          onPressed: disabled ? null : () => _runScopedStudy(explainMode),
        ),
        MargenAssistAction(
          label: _scopedButtonLabel(AssistMode.summary),
          icon: MargenLucide.fileText,
          iconAccent: AppTokens.purple,
          primary: primary == AssistMode.summary,
          loading: _streaming && _activeMode == AssistMode.summary,
          onPressed: disabled
              ? null
              : () => _runScopedStudy(AssistMode.summary),
        ),
        MargenAssistAction(
          label: _scopedButtonLabel(AssistMode.keyPoints),
          icon: MargenLucide.listChecks,
          iconAccent: AppTokens.teal,
          primary: primary == AssistMode.keyPoints,
          loading: _streaming && _activeMode == AssistMode.keyPoints,
          onPressed: disabled
              ? null
              : () => _runScopedStudy(AssistMode.keyPoints),
        ),
        MargenAssistAction(
          label: _scopedButtonLabel(AssistMode.review, questions: true),
          icon: MargenLucide.circleHelp,
          iconAccent: AppTokens.purple,
          loading: false,
          onPressed: disabled
              ? null
              : () =>
                    _generateReviewQuestions(scopeOverride: _activeStudyScope),
        ),
      ],
    );
  }

  String _scopedButtonLabel(AssistMode mode, {bool questions = false}) {
    if (questions) {
      if (_streaming && _activeMode == AssistMode.review) {
        return 'Generando preguntas…';
      }
      return 'Generar preguntas';
    }
    if (_streaming && _activeMode == mode) {
      return switch (mode) {
        AssistMode.summary => 'Resumiendo…',
        AssistMode.keyPoints => 'Extrayendo puntos…',
        AssistMode.page || AssistMode.explain => 'Explicando…',
        _ => 'Analizando…',
      };
    }
    return switch (mode) {
      AssistMode.summary => 'Resumir',
      AssistMode.keyPoints => 'Puntos importantes',
      AssistMode.page || AssistMode.explain => 'Explicar',
      _ => mode.name,
    };
  }

  Widget _buildScopeFollowUps() {
    if (_activeStudyScope == null) return const SizedBox.shrink();
    final explainMode = _activeStudyScope!.kind == StudyScopeKind.fragments
        ? AssistMode.explain
        : AssistMode.page;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          BookifiGhostButton(
            label: 'Puntos importantes',
            compact: true,
            onPressed: _streaming
                ? null
                : () => _runScopedStudy(
                    AssistMode.keyPoints,
                    scopeOverride: _activeStudyScope,
                  ),
          ),
          BookifiGhostButton(
            label: 'Generar preguntas',
            compact: true,
            onPressed: _streaming
                ? null
                : () => _generateReviewQuestions(
                    scopeOverride: _activeStudyScope,
                  ),
          ),
          BookifiGhostButton(
            label: 'Explicar más simple',
            compact: true,
            onPressed: _streaming
                ? null
                : () => _runScopedStudy(
                    explainMode,
                    scopeOverride: _activeStudyScope,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeResultCard(AssistMode mode) {
    final text = _responseText(mode);
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: BookifiCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SmartMarkdown(data: text, compact: true),
            if (!_streaming &&
                _activeMode != mode &&
                (_storedResponses[mode]?.isNotEmpty ?? false)) ...[
              const SizedBox(height: 10),
              RepasoSaveButton(
                state: _saveStateFor(mode),
                onPressed: () => _saveStudy(
                  modeOverride: mode,
                  textOverride: _storedResponses[mode],
                ),
              ),
            ],
            if (!_streaming &&
                _activeMode == mode &&
                _modeResponse.isNotEmpty) ...[
              const SizedBox(height: 10),
              RepasoSaveButton(
                state: _saveStateFor(mode),
                onPressed: () => _saveStudy(modeOverride: mode),
              ),
            ],
            if ((mode == AssistMode.summary ||
                    mode == AssistMode.keyPoints ||
                    mode == AssistMode.page ||
                    mode == AssistMode.explain) &&
                _responseText(mode).isNotEmpty)
              _buildScopeFollowUps(),
          ],
        ),
      ),
    );
  }

  Widget _buildPagesTab(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        Text(
          'PÁGINAS',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        Text('Analizar:', style: Theme.of(context).textTheme.titleSmall),
        RadioListTile<_PageStudyMode>(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('Página actual — ${widget.page}'),
          value: _PageStudyMode.currentPage,
          groupValue: _pageStudyMode,
          onChanged: _streaming
              ? null
              : (v) => setState(() {
                  _pageStudyMode = v!;
                  _activeStudyScope = null;
                }),
        ),
        RadioListTile<_PageStudyMode>(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Rango de páginas'),
          value: _PageStudyMode.pageRange,
          groupValue: _pageStudyMode,
          onChanged: _streaming
              ? null
              : (v) => setState(() {
                  _pageStudyMode = v!;
                  _syncRangeFieldsToPage(widget.page);
                  _activeStudyScope = null;
                }),
        ),
        if (_pageStudyMode == _PageStudyMode.pageRange) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _rangeStartCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Desde',
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() => _activeStudyScope = null),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _rangeEndCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Hasta',
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() => _activeStudyScope = null),
                ),
              ),
            ],
          ),
          if (validatePageRange(
            start: int.tryParse(_rangeStartCtrl.text.trim()) ?? 0,
            end: int.tryParse(_rangeEndCtrl.text.trim()) ?? 0,
            totalPages: widget.book.pageCount,
          ).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                validatePageRange(
                  start: int.tryParse(_rangeStartCtrl.text.trim()) ?? 0,
                  end: int.tryParse(_rangeEndCtrl.text.trim()) ?? 0,
                  totalPages: widget.book.pageCount,
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
        const SizedBox(height: 12),
        _buildStudyActions(
          explainMode: AssistMode.page,
          primary: AssistMode.page,
        ),
        _buildModeResultCard(AssistMode.page),
        _buildModeResultCard(AssistMode.summary),
        _buildModeResultCard(AssistMode.keyPoints),
        const SizedBox(height: 16),
        _buildRepasoSection(context, muted),
      ],
    );
  }

  Widget _buildFragmentosTab(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final saved = _userFragments;
    final selectedCount = _selectedFragmentRefs().length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        Text(
          'FRAGMENTOS',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Fragmentos guardados',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (!_hasLiveFragment && saved.isEmpty)
          Text(
            'Aún no hay resaltados. Arrastra sobre el PDF para capturar texto.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: muted),
          ),
        if (_hasLiveFragment)
          _FragmentSelectTile(
            selected: _selectedFragmentIds.contains(_kLiveFragmentId),
            quote: widget.quote!.trim(),
            pageNumber: widget.page,
            previewPixels: widget.selectionPreviewPixels,
            previewWidth: widget.selectionPreviewWidth,
            previewHeight: widget.selectionPreviewHeight,
            onChanged: (v) => setState(() {
              if (v) {
                _selectedFragmentIds.add(_kLiveFragmentId);
              } else {
                _selectedFragmentIds.remove(_kLiveFragmentId);
              }
              _activeStudyScope = null;
              _invalidateFragmentScopeCache();
            }),
          ),
        for (final h in saved)
          _FragmentSelectTile(
            selected: _selectedFragmentIds.contains(h.id),
            quote: h.quote,
            pageNumber: h.pageNumber,
            onChanged: (v) => setState(() {
              if (v) {
                _selectedFragmentIds.add(h.id);
              } else {
                _selectedFragmentIds.remove(h.id);
              }
              _activeStudyScope = null;
              _invalidateFragmentScopeCache();
            }),
          ),
        const SizedBox(height: 10),
        if (selectedCount == 0)
          Text(
            'Selecciona uno o varios fragmentos para estudiar este contenido.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: muted),
          )
        else
          Text(
            selectedCount == 1
                ? '1 fragmento seleccionado'
                : '$selectedCount fragmentos seleccionados',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTokens.purple,
            ),
          ),
        const SizedBox(height: 12),
        _buildStudyActions(
          explainMode: AssistMode.explain,
          primary: AssistMode.explain,
        ),
        _buildModeResultCard(AssistMode.explain),
        _buildModeResultCard(AssistMode.summary),
        _buildModeResultCard(AssistMode.keyPoints),
        const SizedBox(height: 16),
        _buildRepasoSection(context, muted),
      ],
    );
  }

  Widget _buildRepasoSection(BuildContext context, Color muted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(color: Theme.of(context).dividerColor),
        const SizedBox(height: 8),
        Text(
          'REPASO',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 8),
        MargenAssistAction(
          label: 'Revisar contenido guardado >',
          icon: MargenLucide.star,
          iconAccent: AppTokens.warning,
          onPressed: () => context.go('/repaso'),
        ),
        TextButton(
          onPressed: () => context.go('/repaso'),
          child: const Text('Ver todo el repaso del libro'),
        ),
      ],
    );
  }

  Widget _buildRecientes(BuildContext context) {
    final items =
        <({String title, AssistMode mode, _WorkspaceTab tab, IconData icon})>[
          if (_previewLine(AssistMode.keyPoints).isNotEmpty ||
              _previewLine(AssistMode.summary).isNotEmpty ||
              _previewLine(AssistMode.page).isNotEmpty)
            (
              title: 'Páginas',
              mode: AssistMode.summary,
              tab: _WorkspaceTab.paginas,
              icon: MargenLucide.fileText,
            ),
          if (_previewLine(AssistMode.explain).isNotEmpty)
            (
              title: 'Fragmentos',
              mode: AssistMode.explain,
              tab: _WorkspaceTab.fragmentos,
              icon: MargenLucide.scanLine,
            ),
        ];
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Recientes',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                if (items.isNotEmpty) setState(() => _tab = items.first.tab);
              },
              child: const Text('Ver todos'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final item = items[i];
              final preview = item.mode == AssistMode.explain
                  ? (_previewLine(AssistMode.explain).isNotEmpty
                        ? _previewLine(AssistMode.explain)
                        : _previewLine(AssistMode.page))
                  : _previewLine(item.mode);
              return _RecentPreviewCard(
                title: item.title,
                preview: preview,
                icon: item.icon,
                iconAccent: _accentForMode(item.mode),
                onTap: () => setState(() => _tab = item.tab),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildChatTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRecientes(context),
        Row(
          children: [
            MIcon(
              MargenLucide.messageCircle,
              size: 18,
              color: AppTokens.purple,
            ),
            const SizedBox(width: 6),
            Text(
              'Chat',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Text(
                    'Pregunta sobre el libro…',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) {
                    final m = _messages[i];
                    if (m.text.isEmpty &&
                        !(_streaming &&
                            _activeMode == AssistMode.chat &&
                            i == _messages.length - 1)) {
                      return const SizedBox.shrink();
                    }
                    final text = m.text.isEmpty && _streaming ? '…' : m.text;
                    return _chatBubble(context, user: m.user, text: text);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTabBody(BuildContext context) {
    return switch (_tab) {
      _WorkspaceTab.chat => _buildChatTab(context),
      _WorkspaceTab.paginas => _buildPagesTab(context),
      _WorkspaceTab.fragmentos => _buildFragmentosTab(context),
    };
  }

  Widget _buildChatComposer(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.7),
          ),
        ),
        color: isDark ? null : Colors.white.withValues(alpha: 0.96),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          MIconBox(
            icon: _saveStateFor(AssistMode.chat) == RepasoSaveUiState.saved
                ? MargenLucide.checkCircle
                : MargenLucide.review,
            accent: _saveStateFor(AssistMode.chat) == RepasoSaveUiState.saved
                ? const Color(0xFF22C55E)
                : AppTokens.purple,
            size: 38,
            iconSize: 18,
            onTap: _streaming ||
                    _saveStateFor(AssistMode.chat) == RepasoSaveUiState.saving ||
                    _saveStateFor(AssistMode.chat) == RepasoSaveUiState.saved
                ? null
                : () => _saveStudy(modeOverride: AssistMode.chat),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: widget.embedded ? 2 : 3,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: const InputDecoration(
                hintText: 'Pregunta sobre el libro…',
              ),
              onSubmitted: _streaming ? null : (_) => _runMode(AssistMode.chat),
            ),
          ),
          const SizedBox(width: 8),
          BookifiPrimaryButton(
            label: 'Enviar',
            icon: LucideIcons.send,
            loading: _streaming && _activeMode == AssistMode.chat,
            onPressed: _streaming ? null : () => _runMode(AssistMode.chat),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final credsAsync = ref.watch(chatGptCredentialsProvider);
    final hasCreds = credsAsync.maybeWhen(
      data: (c) => c != null && c.hasPlanUsage,
      orElse: () => false,
    );
    final platformOk = chatGptConnectEnabled;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(
          context,
          hasCreds: hasCreds,
          platformOk: platformOk,
          credsAsync: credsAsync,
        ),
        Expanded(child: _buildTabBody(context)),
        if (_tab == _WorkspaceTab.chat) _buildChatComposer(context),
      ],
    );

    if (widget.embedded) {
      return Padding(padding: const EdgeInsets.all(12), child: content);
    }

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 4,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
        ),
        child: content,
      ),
    );
  }
}

class _AssistCategoryTabs extends StatelessWidget {
  const _AssistCategoryTabs({required this.selected, required this.onSelected});

  final _WorkspaceTab selected;
  final ValueChanged<_WorkspaceTab> onSelected;

  @override
  Widget build(BuildContext context) {
    const tabs = [
      (
        _WorkspaceTab.chat,
        'Chat',
        MargenLucide.messageCircle,
        AppTokens.purple,
      ),
      (_WorkspaceTab.paginas, 'Páginas', MargenLucide.fileText, AppTokens.teal),
      (
        _WorkspaceTab.fragmentos,
        'Fragmentos',
        MargenLucide.scanLine,
        AppTokens.cyan,
      ),
    ];
    return Row(
      children: [
        for (final (tab, label, icon, accent) in tabs) ...[
          Expanded(
            child: _CategoryTabTile(
              label: label,
              icon: icon,
              iconAccent: accent,
              selected: selected == tab,
              onTap: () => onSelected(tab),
            ),
          ),
        ],
      ],
    );
  }
}

class _CategoryTabTile extends StatefulWidget {
  const _CategoryTabTile({
    required this.label,
    required this.icon,
    required this.iconAccent,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color iconAccent;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_CategoryTabTile> createState() => _CategoryTabTileState();
}

class _CategoryTabTileState extends State<_CategoryTabTile> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = widget.selected;
    final bg = active
        ? AppTokens.purple
        : (_hover
              ? AppTokens.purple.withValues(alpha: 0.08)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)));
    final fg = active
        ? Colors.white
        : (isDark ? AppTokens.textSoft : AppTokens.textMuted);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: active
                    ? null
                    : Border.all(
                        color: Theme.of(
                          context,
                        ).dividerColor.withValues(alpha: 0.45),
                      ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MIcon(
                    widget.icon,
                    size: 20,
                    color: active ? Colors.white : widget.iconAccent,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: fg,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentPreviewCard extends StatefulWidget {
  const _RecentPreviewCard({
    required this.title,
    required this.preview,
    required this.icon,
    required this.iconAccent,
    required this.onTap,
  });

  final String title;
  final String preview;
  final IconData icon;
  final Color iconAccent;
  final VoidCallback onTap;

  @override
  State<_RecentPreviewCard> createState() => _RecentPreviewCardState();
}

class _FragmentSelectTile extends StatelessWidget {
  const _FragmentSelectTile({
    required this.selected,
    required this.quote,
    required this.pageNumber,
    required this.onChanged,
    this.previewPixels,
    this.previewWidth,
    this.previewHeight,
  });

  final bool selected;
  final String quote;
  final int pageNumber;
  final ValueChanged<bool> onChanged;
  final Uint8List? previewPixels;
  final int? previewWidth;
  final int? previewHeight;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final preview = quote.length > 160 ? '${quote.substring(0, 160)}…' : quote;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? AppTokens.purple.withValues(alpha: isDark ? 0.22 : 0.08)
            : (isDark ? const Color(0xFF111827) : Colors.white),
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        child: InkWell(
          onTap: () => onChanged(!selected),
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTokens.radiusMd),
              border: Border.all(
                color: selected
                    ? AppTokens.purple.withValues(alpha: 0.65)
                    : Theme.of(context).dividerColor.withValues(alpha: 0.55),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: selected,
                  onChanged: (v) => onChanged(v ?? false),
                  activeColor: AppTokens.purple,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (previewPixels != null &&
                          previewWidth != null &&
                          previewHeight != null) ...[
                        SelectionCropPreview(
                          pixels: previewPixels!,
                          width: previewWidth!,
                          height: previewHeight!,
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        '“$preview”',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Página $pageNumber',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentPreviewCardState extends State<_RecentPreviewCard> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 200,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111827) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _hover
                    ? AppTokens.purple.withValues(alpha: 0.5)
                    : Theme.of(context).dividerColor.withValues(alpha: 0.55),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    MIconBox(
                      icon: widget.icon,
                      accent: widget.iconAccent,
                      size: 32,
                      iconSize: 16,
                    ),
                    const Spacer(),
                    MIcon(
                      MargenLucide.chevronRight,
                      size: 16,
                      color: AppTokens.purple,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.title,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
