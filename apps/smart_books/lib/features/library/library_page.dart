import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../core/providers.dart';

import '../../core/theme/app_tokens.dart';

import '../../data/models/book.dart';

import '../shared/book_status_labels.dart';

import '../shared/bookifi_ui.dart';

import 'upload_book_dialog.dart';

abstract final class _LibraryColors {
  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color pageBg(BuildContext context) =>
      _isDark(context) ? const Color(0xFF0F1118) : const Color(0xFFF7F7FC);

  static Color heroBg(BuildContext context) =>
      _isDark(context) ? const Color(0xFF151821) : const Color(0xFFFCFCFF);

  static Color surface(BuildContext context) =>
      _isDark(context) ? const Color(0xFF171A24) : Colors.white;

  static Color input(BuildContext context) =>
      _isDark(context) ? const Color(0xFF1D202B) : const Color(0xFFFBFBFD);

  static Color text(BuildContext context) =>
      _isDark(context) ? const Color(0xFFF4F5FA) : const Color(0xFF11182A);

  static Color muted(BuildContext context) =>
      _isDark(context) ? const Color(0xFFA7B0C3) : const Color(0xFF66758F);

  static Color border(BuildContext context) =>
      _isDark(context) ? const Color(0xFF292D3A) : const Color(0xFFE5E7F0);

  static Color borderSoft(BuildContext context) =>
      _isDark(context) ? const Color(0xFF232734) : const Color(0xFFEEF0F6);

  static Color purpleSoft(BuildContext context) =>
      _isDark(context) ? const Color(0xFF28203A) : const Color(0xFFF2ECFF);

  static Color greenSoft(BuildContext context) =>
      _isDark(context) ? const Color(0xFF153129) : const Color(0xFFE4F8F0);

  static Color blueSoft(BuildContext context) =>
      _isDark(context) ? const Color(0xFF17283A) : const Color(0xFFEAF5FF);

  static Color orangeSoft(BuildContext context) =>
      _isDark(context) ? const Color(0xFF332818) : const Color(0xFFFFF2DA);

  static Color redSoft(BuildContext context) =>
      _isDark(context) ? const Color(0xFF351E22) : const Color(0xFFFFECEB);

  static Color unreadSoft(BuildContext context) =>
      _isDark(context) ? const Color(0xFF222633) : const Color(0xFFF0F2F7);

  static const purple = Color(0xFF6222E0);
  static const purpleStrong = Color(0xFF601DE8);
  static const cyan = Color(0xFF0FCDEF);

  static const green = Color(0xFF009D78);
  static const blue = Color(0xFF238CF5);
  static const orange = Color(0xFFE58A00);
  static const red = Color(0xFFE94D4D);
}

enum _LibrarySort { recientes, titulo, progreso }

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  var _query = '';

  var _language = 'all';

  var _status = 'all';

  var _gridView = true;

  var _sort = _LibrarySort.recientes;

  String? _lastOcrResumeSig;
  String? _lastLocalSyncSig;

  @override
  Widget build(BuildContext context) {
    ref.listen(_booksProvider, (_, next) {
      next.whenData((books) {
        final sig = books.map((b) => '${b.id}:${b.status}').join('|');

        if (sig == _lastOcrResumeSig) {
          return;
        }

        _lastOcrResumeSig = sig;

        ref.read(ocrJobServiceProvider).resumeForLibrary(books);

        final localSig = books
            .where((b) => b.isLocalStorage)
            .map((b) => b.id)
            .join(',');
        if (localSig.isNotEmpty && localSig != _lastLocalSyncSig) {
          _lastLocalSyncSig = localSig;
          unawaited(() async {
            await ref
                .read(booksRepositoryProvider)
                .syncLocalBooksToCloud(books);
            ref.invalidate(_booksProvider);
          }());
        }
      });
    });

    final booksAsync = ref.watch(_booksProvider);

    final displayName =
        ref
                .watch(authSessionProvider)
                .valueOrNull
                ?.user
                .userMetadata?['display_name']
            as String?;

    return ColoredBox(
      color: _LibraryColors.pageBg(context),

      child: BookifiPage(
        child: booksAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 120),

            child: Center(
              child: CircularProgressIndicator(color: AppTokens.purple),
            ),
          ),

          error: (error, _) => BookifiCallout(
            'No se pudo cargar la biblioteca: $error',

            bad: true,
          ),

          data: (books) {
            final visible = _sortBooks(_filter(books));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,

              children: [
                _LibraryHero(displayName: displayName, onUpload: _uploadBook),

                const SizedBox(height: 14),

                _LibraryToolbar(
                  language: _language,

                  status: _status,

                  gridView: _gridView,

                  onQueryChanged: (value) {
                    setState(() => _query = value);
                  },

                  onLanguageChanged: (value) {
                    setState(() => _language = value);
                  },

                  onStatusChanged: (value) {
                    setState(() => _status = value);
                  },

                  onToggleView: () {
                    setState(() {
                      _gridView = !_gridView;
                    });
                  },
                ),

                const SizedBox(height: 22),

                _LibrarySectionHeader(
                  count: visible.length,

                  sort: _sort,

                  onSortChanged: (value) {
                    setState(() => _sort = value);
                  },
                ),

                const SizedBox(height: 12),

                if (visible.isEmpty)
                  _LibraryEmptyState(onUpload: _uploadBook)
                else if (_gridView)
                  _LibraryGrid(books: visible)
                else
                  _LibraryList(books: visible),

                const SizedBox(height: 30),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _uploadBook() async {
    final ok = await showUploadBookDialog(context);

    if (!mounted) {
      return;
    }

    if (ok == true) {
      ref.invalidate(_booksProvider);
    }
  }

  List<Book> _filter(List<Book> books) {
    return books.where((book) {
      final searchable = '${book.title} ${book.author ?? ''}'.toLowerCase();

      if (_query.isNotEmpty && !searchable.contains(_query.toLowerCase())) {
        return false;
      }

      if (_language != 'all' && book.language != _language) {
        return false;
      }

      if (_status == 'ocr') {
        return book.status == 'needs_ocr' || book.status == 'extracting';
      }

      if (_status == 'analysis') {
        return book.status == 'analyzing' || book.status == 'partial';
      }

      if (_status == 'ready') {
        return book.status == 'analyzed' || book.status == 'ready';
      }

      if (_status == 'error') {
        return book.status == 'error';
      }

      return true;
    }).toList();
  }

  List<Book> _sortBooks(List<Book> books) {
    final copy = List<Book>.from(books);

    switch (_sort) {
      case _LibrarySort.recientes:
        copy.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        break;

      case _LibrarySort.titulo:
        copy.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );

        break;

      case _LibrarySort.progreso:
        copy.sort((a, b) => _readProgress(b).compareTo(_readProgress(a)));

        break;
    }

    return copy;
  }

  static double _readProgress(Book book) {
    if (book.pageCount <= 0) {
      return book.analysisProgress.clamp(0.0, 1.0);
    }

    return (book.currentPage / book.pageCount).clamp(0.0, 1.0);
  }
}

final _booksProvider = FutureProvider<List<Book>>((ref) {
  return ref.watch(booksRepositoryProvider).listBooks();
});

// ============================================================

// HERO

// ============================================================

class _LibraryHero extends StatelessWidget {
  const _LibraryHero({required this.displayName, required this.onUpload});

  final String? displayName;

  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final hasName = displayName?.trim().isNotEmpty == true;

    final titleName = hasName ? displayName!.trim().toLowerCase() : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;

        final showArt = constraints.maxWidth >= 1080;

        return Container(
          constraints: const BoxConstraints(minHeight: 198),

          decoration: BoxDecoration(
            color: _LibraryColors.heroBg(context),

            borderRadius: BorderRadius.circular(24),

            border: Border.all(color: _LibraryColors.border(context)),

            boxShadow: [
              BoxShadow(
                color: _LibraryColors.purple.withValues(alpha: 0.035),

                blurRadius: 28,

                offset: const Offset(0, 8),
              ),
            ],
          ),

          clipBehavior: Clip.antiAlias,

          child: Stack(
            children: [
              const Positioned.fill(child: _HeroBackgroundGlow()),

              Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 22 : 32,

                  compact ? 22 : 26,

                  compact ? 22 : 30,

                  compact ? 22 : 24,
                ),

                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          _HeroCopy(
                            title: hasName
                                ? 'Biblioteca de $titleName'
                                : 'Tu biblioteca',
                          ),

                          const SizedBox(height: 20),

                          SizedBox(
                            width: double.infinity,

                            child: _HeroUpload(
                              onUpload: onUpload,

                              centered: false,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.center,

                        children: [
                          Expanded(
                            flex: 7,

                            child: _HeroCopy(
                              title: hasName
                                  ? 'Biblioteca de $titleName'
                                  : 'Tu biblioteca',
                            ),
                          ),

                          if (showArt) ...[
                            const SizedBox(width: 16),

                            const SizedBox(width: 250, child: _HeroBookArt()),
                          ],

                          const SizedBox(width: 20),

                          SizedBox(
                            width: 225,

                            child: _HeroUpload(
                              onUpload: onUpload,

                              centered: true,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroBackgroundGlow extends StatelessWidget {
  const _HeroBackgroundGlow();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.42, -0.1),

          radius: 1.25,

          colors: [
            _LibraryColors.cyan.withValues(alpha: 0.055),

            _LibraryColors.purple.withValues(alpha: 0.025),

            Colors.transparent,
          ],

          stops: const [0, 0.52, 1],
        ),
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Text(
          'SMART BOOKS',

          style: TextStyle(
            color: _LibraryColors.purple,

            fontSize: 11.5,

            fontWeight: FontWeight.w800,

            letterSpacing: 0.3,
          ),
        ),

        const SizedBox(height: 7),

        Text(
          title,

          style: TextStyle(
            color: _LibraryColors.text(context),

            fontSize: 34,

            height: 1.08,

            letterSpacing: -1.1,

            fontWeight: FontWeight.w800,
          ),
        ),

        const SizedBox(height: 7),

        Text(
          'PDFs académicos con resaltados, OCR y asistencia conectada a tu plan ChatGPT Plus.',

          style: TextStyle(
            color: _LibraryColors.muted(context),

            fontSize: 14.5,

            height: 1.4,

            fontWeight: FontWeight.w500,
          ),
        ),

        const SizedBox(height: 20),

        const Wrap(
          spacing: 34,

          runSpacing: 14,

          children: [
            _HeroBenefit(
              icon: Icons.description_outlined,

              title: 'Organiza tus lecturas',

              subtitle: 'Todos tus PDFs en un solo lugar',
            ),

            _HeroBenefit(
              icon: Icons.auto_awesome_outlined,

              title: 'Resalta y estudia',

              subtitle: 'Con ayuda de ChatGPT',
            ),

            _HeroBenefit(
              icon: Icons.bar_chart_rounded,

              title: 'Haz seguimiento',

              subtitle: 'Tu progreso de lectura',
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroBenefit extends StatelessWidget {
  const _HeroBenefit({
    required this.icon,

    required this.title,

    required this.subtitle,
  });

  final IconData icon;

  final String title;

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,

      children: [
        Container(
          width: 38,

          height: 38,

          decoration: BoxDecoration(
            color: _LibraryColors.purpleSoft(context),

            borderRadius: BorderRadius.circular(12),

            border: Border.all(
              color: _LibraryColors.purple.withValues(alpha: 0.09),
            ),
          ),

          alignment: Alignment.center,

          child: Icon(icon, size: 20, color: _LibraryColors.purple),
        ),

        const SizedBox(width: 10),

        Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Text(
              title,

              style: TextStyle(
                color: _LibraryColors.text(context),

                fontSize: 12,

                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 2),

            Text(
              subtitle,

              style: TextStyle(
                color: _LibraryColors.muted(context),

                fontSize: 11,

                height: 1.2,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeroUpload extends StatelessWidget {
  const _HeroUpload({required this.onUpload, required this.centered});

  final VoidCallback onUpload;

  final bool centered;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,

      children: [
        SizedBox(
          width: centered ? double.infinity : 190,

          height: 50,

          child: FilledButton.icon(
            onPressed: onUpload,

            icon: Icon(Icons.upload_file_rounded, size: 20),

            label: Text(
              'Subir PDF',

              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
            ),

            style: FilledButton.styleFrom(
              backgroundColor: _LibraryColors.purpleStrong,

              foregroundColor: Colors.white,

              elevation: 0,

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        Text(
          'Añade nuevos libros a tu biblioteca',

          textAlign: TextAlign.center,

          style: TextStyle(
            color: _LibraryColors.muted(context),

            fontSize: 10.5,

            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _HeroBookArt extends StatelessWidget {
  const _HeroBookArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 145,

      child: Stack(
        alignment: Alignment.center,

        children: [
          Positioned(
            bottom: 6,

            child: Container(
              width: 220,

              height: 46,

              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),

                gradient: LinearGradient(
                  colors: [
                    _LibraryColors.purple.withValues(alpha: 0.05),

                    _LibraryColors.cyan.withValues(alpha: 0.09),
                  ],
                ),
              ),
            ),
          ),

          ShaderMask(
            shaderCallback: (bounds) {
              return const LinearGradient(
                begin: Alignment.bottomLeft,

                end: Alignment.topRight,

                colors: [
                  Color(0xFF9A7BFF),

                  Color(0xFF7B9CFF),

                  Color(0xFF55D6F4),
                ],
              ).createShader(bounds);
            },

            child: Icon(
              Icons.auto_stories_rounded,

              size: 125,

              color: Colors.white,
            ),
          ),

          const Positioned(
            top: 10,

            right: 40,

            child: Icon(
              Icons.auto_awesome,

              color: _LibraryColors.cyan,

              size: 22,
            ),
          ),

          Positioned(
            top: 34,

            left: 43,

            child: Icon(
              Icons.auto_awesome,

              color: _LibraryColors.purple.withValues(alpha: 0.82),

              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================

// TOOLBAR

// ============================================================

class _LibraryToolbar extends StatelessWidget {
  const _LibraryToolbar({
    required this.language,

    required this.status,

    required this.gridView,

    required this.onQueryChanged,

    required this.onLanguageChanged,

    required this.onStatusChanged,

    required this.onToggleView,
  });

  final String language;

  final String status;

  final bool gridView;

  final ValueChanged<String> onQueryChanged;

  final ValueChanged<String> onLanguageChanged;

  final ValueChanged<String> onStatusChanged;

  final VoidCallback onToggleView;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),

      decoration: BoxDecoration(
        color: _LibraryColors.surface(context),

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: _LibraryColors.border(context)),

        boxShadow: [
          BoxShadow(
            color: _LibraryColors.purple.withValues(alpha: 0.025),

            blurRadius: 18,

            offset: const Offset(0, 5),
          ),
        ],
      ),

      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 840;

          final search = SizedBox(
            height: 52,

            child: TextField(
              onChanged: onQueryChanged,

              style: TextStyle(
                fontSize: 13.5,

                color: _LibraryColors.text(context),
              ),

              decoration: InputDecoration(
                hintText: 'Buscar por título, autor o tema...',

                hintStyle: TextStyle(
                  color: _LibraryColors.muted(context),

                  fontSize: 13.5,
                ),

                prefixIcon: Icon(
                  Icons.search_rounded,

                  size: 23,

                  color: _LibraryColors.muted(context),
                ),

                filled: true,

                fillColor: _LibraryColors.input(context),

                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,

                  vertical: 12,
                ),

                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),

                  borderSide: BorderSide(
                    color: _LibraryColors.borderSoft(context),
                  ),
                ),

                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(13),

                  borderSide: BorderSide(
                    color: _LibraryColors.purple,

                    width: 1.2,
                  ),
                ),
              ),
            ),
          );

          final languageDropdown = _LibraryDropdown(
            label: 'Idioma',

            icon: Icons.language_rounded,

            value: language,

            width: 250,

            items: const [
              ('all', 'Todos los idiomas'),

              ('es', 'Español'),

              ('en', 'Inglés'),

              ('unknown', 'Sin detectar'),
            ],

            onChanged: onLanguageChanged,
          );

          final statusDropdown = _LibraryDropdown(
            label: 'Estado',

            icon: Icons.school_outlined,

            value: status,

            width: 230,

            items: const [
              ('all', 'Todos'),

              ('ready', 'Listos'),

              ('analysis', 'En análisis'),

              ('ocr', 'Requieren OCR'),

              ('error', 'Con error'),
            ],

            onChanged: onStatusChanged,
          );

          final toggle = _ViewToggle(
            gridView: gridView,

            onToggle: onToggleView,
          );

          if (stacked) {
            return Column(
              children: [
                search,

                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(child: languageDropdown),

                    const SizedBox(width: 10),

                    Expanded(child: statusDropdown),
                  ],
                ),

                const SizedBox(height: 10),

                Align(alignment: Alignment.centerRight, child: toggle),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: search),

              const SizedBox(width: 12),

              languageDropdown,

              const SizedBox(width: 12),

              statusDropdown,

              const SizedBox(width: 12),

              toggle,
            ],
          );
        },
      ),
    );
  }
}

class _LibraryDropdown extends StatelessWidget {
  const _LibraryDropdown({
    required this.label,

    required this.icon,

    required this.value,

    required this.items,

    required this.onChanged,

    required this.width,
  });

  final String label;

  final IconData icon;

  final String value;

  final List<(String, String)> items;

  final ValueChanged<String> onChanged;

  final double width;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: 150, maxWidth: width),

      child: Container(
        height: 52,

        padding: const EdgeInsets.symmetric(horizontal: 12),

        decoration: BoxDecoration(
          color: _LibraryColors.input(context),

          borderRadius: BorderRadius.circular(13),

          border: Border.all(color: _LibraryColors.borderSoft(context)),
        ),

        child: Row(
          children: [
            Icon(icon, size: 20, color: _LibraryColors.muted(context)),

            const SizedBox(width: 10),

            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  Text(
                    label,

                    style: TextStyle(
                      color: _LibraryColors.muted(context),

                      fontSize: 9.5,

                      height: 1,

                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 3),

                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: value,

                      isExpanded: true,

                      isDense: true,

                      icon: Icon(Icons.keyboard_arrow_down_rounded, size: 19),

                      style: TextStyle(
                        color: _LibraryColors.text(context),

                        fontSize: 12.5,

                        fontWeight: FontWeight.w700,
                      ),

                      items: [
                        for (final (itemValue, label) in items)
                          DropdownMenuItem(
                            value: itemValue,

                            child: Text(label, overflow: TextOverflow.ellipsis),
                          ),
                      ],

                      onChanged: (next) {
                        if (next != null) {
                          onChanged(next);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.gridView, required this.onToggle});

  final bool gridView;

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,

      padding: const EdgeInsets.all(5),

      decoration: BoxDecoration(
        color: _LibraryColors.surface(context),

        borderRadius: BorderRadius.circular(14),

        border: Border.all(color: _LibraryColors.border(context)),
      ),

      child: Row(
        mainAxisSize: MainAxisSize.min,

        children: [
          _ToggleButton(
            active: gridView,

            icon: Icons.grid_view_rounded,

            onPressed: gridView ? null : onToggle,
          ),

          const SizedBox(width: 3),

          _ToggleButton(
            active: !gridView,

            icon: Icons.view_list_rounded,

            onPressed: !gridView ? null : onToggle,
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.active,

    required this.icon,

    required this.onPressed,
  });

  final bool active;

  final IconData icon;

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? _LibraryColors.purpleSoft(context) : Colors.transparent,

      borderRadius: BorderRadius.circular(10),

      child: InkWell(
        onTap: onPressed,

        borderRadius: BorderRadius.circular(10),

        child: SizedBox(
          width: 38,

          height: 38,

          child: Icon(
            icon,

            size: 20,

            color: active
                ? _LibraryColors.purple
                : _LibraryColors.muted(context),
          ),
        ),
      ),
    );
  }
}

// ============================================================

// SECTION HEADER

// ============================================================

class _LibrarySectionHeader extends StatelessWidget {
  const _LibrarySectionHeader({
    required this.count,

    required this.sort,

    required this.onSortChanged,
  });

  final int count;

  final _LibrarySort sort;

  final ValueChanged<_LibrarySort> onSortChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;

        final heading = Row(
          children: [
            Icon(
              Icons.auto_stories_rounded,

              size: 24,

              color: _LibraryColors.purple,
            ),

            const SizedBox(width: 10),

            Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  'Todos los libros',

                  style: TextStyle(
                    color: _LibraryColors.text(context),

                    fontSize: 20,

                    fontWeight: FontWeight.w800,

                    letterSpacing: -0.3,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  '$count ${count == 1 ? 'libro' : 'libros'} en tu biblioteca',

                  style: TextStyle(
                    color: _LibraryColors.muted(context),

                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ],
        );

        final sorting = Row(
          mainAxisSize: MainAxisSize.min,

          children: [
            Text(
              'Ordenar por',

              style: TextStyle(
                color: _LibraryColors.muted(context),

                fontSize: 11.5,

                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(width: 10),

            Container(
              width: 168,

              height: 42,

              padding: const EdgeInsets.symmetric(horizontal: 13),

              decoration: BoxDecoration(
                color: _LibraryColors.surface(context),

                borderRadius: BorderRadius.circular(13),

                border: Border.all(color: _LibraryColors.border(context)),
              ),

              child: DropdownButtonHideUnderline(
                child: DropdownButton<_LibrarySort>(
                  value: sort,

                  isExpanded: true,

                  icon: Icon(Icons.keyboard_arrow_down, size: 18),

                  style: TextStyle(
                    color: _LibraryColors.text(context),

                    fontSize: 11.5,

                    fontWeight: FontWeight.w700,
                  ),

                  items: const [
                    DropdownMenuItem(
                      value: _LibrarySort.recientes,

                      child: Text('Más recientes'),
                    ),

                    DropdownMenuItem(
                      value: _LibrarySort.titulo,

                      child: Text('Título A–Z'),
                    ),

                    DropdownMenuItem(
                      value: _LibrarySort.progreso,

                      child: Text('Más avanzados'),
                    ),
                  ],

                  onChanged: (value) {
                    if (value != null) {
                      onSortChanged(value);
                    }
                  },
                ),
              ),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [heading, const SizedBox(height: 12), sorting],
          );
        }

        return Row(
          children: [
            Expanded(child: heading),

            sorting,
          ],
        );
      },
    );
  }
}

// ============================================================

// GRID + LIST

// ============================================================

class _LibraryGrid extends StatelessWidget {
  const _LibraryGrid({required this.books});

  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final columns = width >= 1120
            ? 3
            : width >= 720
            ? 2
            : 1;

        final cardHeight = columns == 1 ? 220.0 : 216.0;

        return GridView.builder(
          shrinkWrap: true,

          physics: const NeverScrollableScrollPhysics(),

          itemCount: books.length,

          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,

            crossAxisSpacing: 14,

            mainAxisSpacing: 14,

            mainAxisExtent: cardHeight,
          ),

          itemBuilder: (context, index) {
            return _LibraryBookCard(book: books[index]);
          },
        );
      },
    );
  }
}

class _LibraryList extends StatelessWidget {
  const _LibraryList({required this.books});

  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < books.length; index++) ...[
          SizedBox(height: 216, child: _LibraryBookCard(book: books[index])),

          if (index != books.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

// ============================================================

// BOOK CARD

// ============================================================

class _LibraryBookCard extends ConsumerWidget {
  const _LibraryBookCard({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = _LibraryPageState._readProgress(book);

    final percent = (progress * 100).round();

    final status = _cardStatus(book);

    final cta = _ctaForBook(book);

    final seed = coverGradientSeed(book);

    return Material(
      color: _LibraryColors.surface(context),

      elevation: 0,

      borderRadius: BorderRadius.circular(18),

      child: InkWell(
        onTap: () {
          context.push('/libro/${book.id}');
        },

        borderRadius: BorderRadius.circular(18),

        child: Ink(
          decoration: BoxDecoration(
            color: _LibraryColors.surface(context),

            borderRadius: BorderRadius.circular(18),

            border: Border.all(color: _LibraryColors.border(context)),

            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),

                blurRadius: 16,

                offset: const Offset(0, 4),
              ),
            ],
          ),

          child: Padding(
            padding: const EdgeInsets.all(12),

            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,

              children: [
                _BookCover(book: book, seed: seed),

                const SizedBox(width: 13),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    children: [
                      _StatusChip(status: status),

                      const SizedBox(height: 7),

                      Text(
                        book.title,

                        maxLines: 2,

                        overflow: TextOverflow.ellipsis,

                        style: TextStyle(
                          color: _LibraryColors.text(context),

                          fontSize: 15.5,

                          height: 1.14,

                          fontWeight: FontWeight.w800,

                          letterSpacing: -0.15,
                        ),
                      ),

                      const SizedBox(height: 7),

                      _BookAuthor(author: book.author),

                      const SizedBox(height: 7),

                      _BookMetadata(book: book),

                      const Spacer(),

                      _ProgressLine(value: progress, percent: percent),

                      const SizedBox(height: 9),

                      Row(
                        children: [
                          Expanded(
                            child: _BookPrimaryAction(
                              label: cta.label,

                              icon: cta.icon,

                              kind: cta.kind,

                              onPressed: () {
                                context.push('/libro/${book.id}');
                              },
                            ),
                          ),

                          const SizedBox(width: 8),

                          _BookMenu(
                            book: book,

                            onDeleted: () {
                              ref.invalidate(_booksProvider);
                            },
                          ),
                        ],
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

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book, required this.seed});

  final Book book;

  final Color seed;

  @override
  Widget build(BuildContext context) {
    final titleWords = book.title
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(5)
        .join('\n')
        .toUpperCase();

    final darkSeed = Color.lerp(const Color(0xFF0A1D45), seed, 0.28)!;

    final accent = Color.lerp(_LibraryColors.cyan, seed, 0.32)!;

    return Container(
      width: 126,

      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),

        gradient: LinearGradient(
          begin: Alignment.topLeft,

          end: Alignment.bottomRight,

          colors: [
            darkSeed,

            Color.lerp(darkSeed, _LibraryColors.purple, 0.28)!,

            accent,
          ],

          stops: const [0, 0.62, 1],
        ),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.13),

            blurRadius: 10,

            offset: const Offset(0, 4),
          ),
        ],
      ),

      clipBehavior: Clip.antiAlias,

      child: Stack(
        children: [
          Positioned(
            right: -32,

            bottom: -28,

            child: Container(
              width: 105,

              height: 105,

              decoration: BoxDecoration(
                shape: BoxShape.circle,

                color: Colors.white.withValues(alpha: 0.09),
              ),
            ),
          ),

          Positioned(
            left: -26,

            bottom: 8,

            child: Container(
              width: 94,

              height: 94,

              decoration: BoxDecoration(
                shape: BoxShape.circle,

                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),

                  width: 12,
                ),
              ),
            ),
          ),

          Positioned(
            right: 9,

            top: 9,

            child: Icon(
              Icons.auto_stories_outlined,

              size: 17,

              color: Colors.white.withValues(alpha: 0.52),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(13, 15, 11, 13),

            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  titleWords,

                  maxLines: 5,

                  overflow: TextOverflow.ellipsis,

                  style: TextStyle(
                    color: Colors.white,

                    fontSize: 13,

                    height: 1.07,

                    fontWeight: FontWeight.w900,

                    letterSpacing: 0.25,
                  ),
                ),

                const Spacer(),

                Text(
                  book.author?.trim().isNotEmpty == true
                      ? book.author!
                      : 'Bookifi',

                  maxLines: 1,

                  overflow: TextOverflow.ellipsis,

                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),

                    fontSize: 8.5,

                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BookAuthor extends StatelessWidget {
  const _BookAuthor({required this.author});

  final String? author;

  @override
  Widget build(BuildContext context) {
    final label = author?.trim().isNotEmpty == true
        ? author!.trim()
        : 'Autor sin indicar';

    return Row(
      children: [
        Icon(
          Icons.person_outline_rounded,

          size: 15,

          color: _LibraryColors.muted(context),
        ),

        const SizedBox(width: 5),

        Expanded(
          child: Text(
            label,

            maxLines: 1,

            overflow: TextOverflow.ellipsis,

            style: TextStyle(
              color: _LibraryColors.muted(context),

              fontSize: 11.5,

              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _BookMetadata extends StatelessWidget {
  const _BookMetadata({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final language = languageLabels[book.language] ?? book.language;

    return Wrap(
      spacing: 13,

      runSpacing: 5,

      children: [
        _MetadataItem(
          icon: Icons.description_outlined,

          label: '${book.pageCount} páginas',
        ),

        _MetadataItem(icon: Icons.language_rounded, label: language),
      ],
    );
  }
}

class _MetadataItem extends StatelessWidget {
  const _MetadataItem({required this.icon, required this.label});

  final IconData icon;

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,

      children: [
        Icon(icon, size: 14, color: _LibraryColors.muted(context)),

        const SizedBox(width: 4),

        Text(
          label,

          style: TextStyle(
            color: _LibraryColors.muted(context),

            fontSize: 10.8,

            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.value, required this.percent});

  final double value;

  final int percent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),

            child: LinearProgressIndicator(
              value: value,

              minHeight: 5,

              backgroundColor: _LibraryColors.borderSoft(context),

              valueColor: const AlwaysStoppedAnimation(_LibraryColors.purple),
            ),
          ),
        ),

        const SizedBox(width: 8),

        Text(
          '$percent%',

          style: TextStyle(
            color: _LibraryColors.muted(context),

            fontSize: 10.5,

            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

// ============================================================

// CARD ACTION

// ============================================================

enum _BookCtaKind { primary, secondary, start }

class _BookCta {
  const _BookCta({required this.label, required this.icon, required this.kind});

  final String label;

  final IconData icon;

  final _BookCtaKind kind;
}

_BookCta _ctaForBook(Book book) {
  final progress = _LibraryPageState._readProgress(book);

  if (progress >= 0.98 ||
      (book.pageCount > 0 && book.currentPage >= book.pageCount)) {
    return const _BookCta(
      label: 'Revisar apuntes',

      icon: Icons.note_alt_outlined,

      kind: _BookCtaKind.secondary,
    );
  }

  if (book.currentPage > 1 || progress > 0.05) {
    return const _BookCta(
      label: 'Continuar lectura',

      icon: Icons.menu_book_rounded,

      kind: _BookCtaKind.primary,
    );
  }

  return const _BookCta(
    label: 'Empezar lectura',

    icon: Icons.play_arrow_rounded,

    kind: _BookCtaKind.start,
  );
}

class _BookPrimaryAction extends StatelessWidget {
  const _BookPrimaryAction({
    required this.label,

    required this.icon,

    required this.kind,

    required this.onPressed,
  });

  final String label;

  final IconData icon;

  final _BookCtaKind kind;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final filled = kind == _BookCtaKind.primary;

    return SizedBox(
      height: 37,

      child: filled
          ? FilledButton.icon(
              onPressed: onPressed,

              icon: Icon(icon, size: 16),

              label: Text(label, overflow: TextOverflow.ellipsis),

              style: FilledButton.styleFrom(
                backgroundColor: _LibraryColors.purpleStrong,

                foregroundColor: Colors.white,

                padding: const EdgeInsets.symmetric(horizontal: 10),

                textStyle: TextStyle(
                  fontSize: 11.5,

                  fontWeight: FontWeight.w800,
                ),

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,

              icon: Icon(icon, size: 16),

              label: Text(label, overflow: TextOverflow.ellipsis),

              style: OutlinedButton.styleFrom(
                foregroundColor: _LibraryColors.purple,

                backgroundColor: kind == _BookCtaKind.secondary
                    ? _LibraryColors.purpleSoft(context)
                    : _LibraryColors.surface(context),

                side: BorderSide(
                  color: _LibraryColors.purple.withValues(alpha: 0.27),
                ),

                padding: const EdgeInsets.symmetric(horizontal: 10),

                textStyle: TextStyle(
                  fontSize: 11.5,

                  fontWeight: FontWeight.w800,
                ),

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
    );
  }
}

class _BookMenu extends ConsumerWidget {
  const _BookMenu({required this.book, required this.onDeleted});

  final Book book;

  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: 38,

      height: 37,

      decoration: BoxDecoration(
        color: _LibraryColors.surface(context),

        borderRadius: BorderRadius.circular(10),

        border: Border.all(color: _LibraryColors.border(context)),
      ),

      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,

        tooltip: 'Más opciones',

        icon: Icon(
          Icons.more_horiz_rounded,

          size: 19,

          color: _LibraryColors.purple,
        ),

        onSelected: (value) async {
          if (value != 'delete') {
            return;
          }

          final confirmed = await showDialog<bool>(
            context: context,

            builder: (dialogContext) {
              return AlertDialog(
                title: Text('Quitar de la biblioteca'),

                content: Text('¿Quitar «${book.title}»?'),

                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(dialogContext, false);
                    },

                    child: Text('Cancelar'),
                  ),

                  FilledButton(
                    onPressed: () {
                      Navigator.pop(dialogContext, true);
                    },

                    style: FilledButton.styleFrom(
                      backgroundColor: _LibraryColors.red,
                    ),

                    child: Text('Quitar'),
                  ),
                ],
              );
            },
          );

          if (confirmed != true) {
            return;
          }

          await ref.read(booksRepositoryProvider).deleteBook(book);

          onDeleted();
        },

        itemBuilder: (context) {
          return const [
            PopupMenuItem(
              value: 'delete',

              child: Row(
                children: [
                  Icon(
                    Icons.delete_outline,

                    size: 18,

                    color: _LibraryColors.red,
                  ),

                  SizedBox(width: 8),

                  Text('Quitar', style: TextStyle(color: _LibraryColors.red)),
                ],
              ),
            ),
          ];
        },
      ),
    );
  }
}

// ============================================================

// STATUS

// ============================================================

enum _CardStatusKind { local, completed, inProgress, unread, processing, error }

class _CardStatus {
  const _CardStatus(this.kind, this.label);

  final _CardStatusKind kind;

  final String label;
}

_CardStatus _cardStatus(Book book) {
  if (book.isLocalStorage) {
    return const _CardStatus(_CardStatusKind.processing, 'Sincronizando PDF…');
  }

  if (book.status == 'partial') {
    return _CardStatus(_CardStatusKind.inProgress, statusLabel(book.status));
  }

  if (book.status == 'error') {
    final detail = book.statusDetail?.trim();
    if (detail != null && detail.isNotEmpty) {
      return _CardStatus(_CardStatusKind.error, 'Revisar');
    }
    return const _CardStatus(_CardStatusKind.error, 'Revisar');
  }

  if (book.status == 'extracting' ||
      book.status == 'needs_ocr' ||
      book.status == 'analyzing') {
    return _CardStatus(_CardStatusKind.processing, statusLabel(book.status));
  }

  final progress = _LibraryPageState._readProgress(book);

  if (progress >= 0.98 ||
      (book.pageCount > 0 && book.currentPage >= book.pageCount)) {
    return const _CardStatus(_CardStatusKind.completed, 'Completado');
  }

  if (book.currentPage > 1 || progress > 0.05) {
    return const _CardStatus(_CardStatusKind.inProgress, 'En progreso');
  }

  return const _CardStatus(_CardStatusKind.unread, 'Sin leer');
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final _CardStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon) = switch (status.kind) {
      _CardStatusKind.local => (
        _LibraryColors.orangeSoft(context),

        _LibraryColors.orange,

        Icons.computer_rounded,
      ),

      _CardStatusKind.completed => (
        _LibraryColors.greenSoft(context),

        _LibraryColors.green,

        Icons.check_circle_rounded,
      ),

      _CardStatusKind.inProgress => (
        _LibraryColors.blueSoft(context),

        _LibraryColors.blue,

        Icons.auto_stories_rounded,
      ),

      _CardStatusKind.unread => (
        _LibraryColors.unreadSoft(context),

        _LibraryColors.muted(context),

        Icons.circle_outlined,
      ),

      _CardStatusKind.processing => (
        _LibraryColors.purpleSoft(context),

        _LibraryColors.purple,

        Icons.hourglass_top_rounded,
      ),

      _CardStatusKind.error => (
        _LibraryColors.redSoft(context),

        _LibraryColors.red,

        Icons.error_outline_rounded,
      ),
    };

    return Align(
      alignment: Alignment.centerLeft,

      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),

        decoration: BoxDecoration(
          color: background,

          borderRadius: BorderRadius.circular(999),
        ),

        child: Row(
          mainAxisSize: MainAxisSize.min,

          children: [
            Icon(icon, size: 12, color: foreground),

            const SizedBox(width: 4),

            Text(
              status.label,

              style: TextStyle(
                color: foreground,

                fontSize: 9.5,

                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================

// EMPTY STATE

// ============================================================

class _LibraryEmptyState extends StatelessWidget {
  const _LibraryEmptyState({required this.onUpload});

  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),

      decoration: BoxDecoration(
        color: _LibraryColors.surface(context),

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: _LibraryColors.border(context)),
      ),

      child: Column(
        children: [
          Container(
            width: 64,

            height: 64,

            decoration: BoxDecoration(
              color: _LibraryColors.purpleSoft(context),

              borderRadius: BorderRadius.circular(20),
            ),

            alignment: Alignment.center,

            child: Icon(
              Icons.auto_stories_rounded,

              color: _LibraryColors.purple,

              size: 30,
            ),
          ),

          const SizedBox(height: 18),

          Text(
            'Tu biblioteca está vacía',

            style: TextStyle(
              color: _LibraryColors.text(context),

              fontSize: 20,

              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 7),

          Text(
            'Sube un PDF para comenzar a leer, resaltar y estudiar.',

            textAlign: TextAlign.center,

            style: TextStyle(
              color: _LibraryColors.muted(context),
              fontSize: 13,
            ),
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: 180,

            height: 44,

            child: FilledButton.icon(
              onPressed: onUpload,

              icon: Icon(Icons.upload_file_rounded, size: 18),

              label: Text('Subir PDF'),

              style: FilledButton.styleFrom(
                backgroundColor: _LibraryColors.purple,

                foregroundColor: Colors.white,

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
