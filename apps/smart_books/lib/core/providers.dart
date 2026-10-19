import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/repositories/books_repository.dart';
import '../features/chatgpt/chatgpt_auth_service.dart';
import '../features/chatgpt/chatgpt_credentials.dart';
import '../features/chatgpt/credential_store.dart';
import '../features/chatgpt/oauth_loopback_server.dart';
import '../features/chatgpt/plan_api.dart';
import '../services/analysis_service.dart';
import '../services/review_questions_service.dart';
import '../services/ingest_service.dart';
import '../services/ocr_job_service.dart';
import '../services/document_profile_service.dart';
import '../services/library_ask_service.dart';
import '../services/semantic_search_service.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final booksRepositoryProvider = Provider<BooksRepository>((ref) {
  return BooksRepository(ref.watch(supabaseClientProvider));
});

final oauthLoopbackServerProvider = Provider<OAuthLoopbackServer>((ref) {
  final server = OAuthLoopbackServer();
  ref.onDispose(() => server.stop());
  return server;
});

final chatGptCredentialStoreProvider = Provider<ChatGptCredentialStore>((ref) {
  return ChatGptCredentialStore();
});

final chatGptAuthServiceProvider = Provider<ChatGptAuthService>((ref) {
  return ChatGptAuthService(
    store: ref.watch(chatGptCredentialStoreProvider),
    loopback: ref.watch(oauthLoopbackServerProvider),
  );
});

final authSessionProvider = StreamProvider<Session?>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange.map(
    (event) => event.session,
  );
});

class ChatGptLinkState {
  const ChatGptLinkState._({required this.connected, this.label});

  const ChatGptLinkState.disconnected() : this._(connected: false);

  const ChatGptLinkState.connected(this.label) : connected = true;

  final bool connected;
  final String? label;
}

final chatGptLinkProvider = FutureProvider<ChatGptLinkState>((ref) async {
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
  final service = ref.read(chatGptAuthServiceProvider);
  if (userId != null) {
    final c = await service.load(userId);
    if (c != null && c.hasPlanUsage) {
      return ChatGptLinkState.connected(c.email ?? c.subject ?? 'Plus');
    }
  }
  final pending = await service.loadPending();
  if (pending != null && pending.hasPlanUsage) {
    return ChatGptLinkState.connected(
      pending.email ?? pending.subject ?? 'Plus',
    );
  }
  return const ChatGptLinkState.disconnected();
});

/// Credenciales ChatGPT: usuario Supabase o enlace pendiente pre-login.
final chatGptCredentialsProvider = FutureProvider<ChatGptCredentials?>((
  ref,
) async {
  ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
  final service = ref.read(chatGptAuthServiceProvider);
  final userId = ref.watch(supabaseClientProvider).auth.currentUser?.id;
  if (userId != null) {
    final linked = await service.load(userId);
    if (linked != null) return linked;
  }
  return service.loadPending();
});

final ingestServiceProvider = Provider<IngestService>((ref) {
  return IngestService(ref.watch(booksRepositoryProvider));
});

final analysisServiceProvider = Provider<AnalysisService>((ref) {
  return AnalysisService(ref.watch(booksRepositoryProvider));
});

final ocrJobServiceProvider = Provider<OcrJobService>((ref) {
  return OcrJobService(
    ref.watch(booksRepositoryProvider),
    ref.watch(analysisServiceProvider),
  );
});

/// Una sola instancia: cachea el modelo preferido entre llamadas de IA.
final planApiProvider = Provider<PlanApi>((ref) {
  return PlanApi(
    store: ref.watch(chatGptCredentialStoreProvider),
    loopback: ref.watch(oauthLoopbackServerProvider),
  );
});

final reviewQuestionsServiceProvider = Provider<ReviewQuestionsService>((ref) {
  return ReviewQuestionsService(
    ref.watch(booksRepositoryProvider),
    planApi: ref.watch(planApiProvider),
  );
});

/// Incrementar tras guardar preguntas para refrescar la pantalla Repaso.
final repasoReloadTickProvider = StateProvider<int>((ref) => 0);

void bumpRepasoReloadTick(WidgetRef ref) {
  ref.read(repasoReloadTickProvider.notifier).state++;
}

final semanticSearchServiceProvider = Provider<SemanticSearchService>((ref) {
  return SemanticSearchService(ref.watch(booksRepositoryProvider));
});

final libraryAskServiceProvider = Provider<LibraryAskService>((ref) {
  return LibraryAskService(
    ref.watch(booksRepositoryProvider),
    api: ref.watch(planApiProvider),
  );
});

final documentProfileServiceProvider = Provider<DocumentProfileService>((ref) {
  return DocumentProfileService(ref.watch(booksRepositoryProvider));
});
