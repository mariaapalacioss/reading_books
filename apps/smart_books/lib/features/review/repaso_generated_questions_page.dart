import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/margen_iconography.dart';
import '../../data/models/book.dart';
import '../shared/bookifi_ui.dart';
import 'repaso_questions_catalog.dart';
import 'repaso_session_page.dart';

final _repasoCatalogBooksProvider = FutureProvider<List<Book>>((ref) {
  return ref.watch(booksRepositoryProvider).listBooks();
});

final repasoQaCatalogProvider = FutureProvider<RepasoQaCatalog>((ref) async {
  ref.watch(repasoReloadTickProvider);
  final books = await ref.watch(_repasoCatalogBooksProvider.future);
  return loadRepasoQaCatalog(ref.read(booksRepositoryProvider), books);
});

class RepasoGeneratedQuestionsPage extends ConsumerWidget {
  const RepasoGeneratedQuestionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalogAsync = ref.watch(repasoQaCatalogProvider);
    final booksAsync = ref.watch(_repasoCatalogBooksProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Preguntas generadas'),
      ),
      body: catalogAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (catalog) {
          if (catalog.total == 0) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No tienes preguntas generadas todavía.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              BookifiCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'PREGUNTAS DE REPASO',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: AppTokens.purple,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${catalog.total} preguntas disponibles',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    BookifiPrimaryButton(
                      label: 'Comenzar repaso',
                      onPressed: () async {
                        final books = booksAsync.valueOrNull ?? [];
                        await openRepasoSessionAll(context, ref, books);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Por origen',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              for (final group in catalog.groups) ...[
                BookifiCard(
                  onTap: () => openRepasoSessionFromGroup(context, ref, group),
                  child: Row(
                    children: [
                      MIconBox(
                        icon: MargenLucide.notebookTabs,
                        selected: false,
                        size: 44,
                        iconSize: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.title,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${group.bookTitle} · ${group.count} preguntas'
                              '${group.pageNumber != null ? ' · PDF ${group.pageNumber}' : ''}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const MIcon(MargenLucide.chevronRight, size: 20),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}
