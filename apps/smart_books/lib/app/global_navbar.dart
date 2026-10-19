import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers.dart';
import '../core/theme/app_tokens.dart';
import '../core/theme/margen_iconography.dart';
import '../core/theme/theme_mode_control.dart';
import '../features/shared/bookifi_ui.dart';

/// Rutas principales de Margen / Smart Books (sin duplicar funcionalidad).
enum MargenNavSection { library, search, review, settings }

MargenNavSection? sectionForPath(String path) {
  if (path.startsWith('/libro/')) return MargenNavSection.library;
  if (path == '/' || path.isEmpty) return MargenNavSection.library;
  if (path.startsWith('/buscar')) return MargenNavSection.search;
  if (path.startsWith('/repaso')) return MargenNavSection.review;
  if (path.startsWith('/ajustes')) return MargenNavSection.settings;
  return null;
}

/// Barra global persistente (escritorio).
class GlobalNavbar extends ConsumerWidget {
  const GlobalNavbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = GoRouterState.of(context).uri.path;
    final section = sectionForPath(path);
    final size = MediaQuery.sizeOf(context);
    final compactNav = size.width < 980;
    final tightNav = size.width < 1100;

    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
      child: Container(
        height: 56,
        padding: EdgeInsets.symmetric(horizontal: tightNav ? 14 : 20),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.7),
            ),
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => context.go('/'),
              child: const BookifiBrand(compact: true),
            ),
            SizedBox(width: tightNav ? 12 : 24),
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _GlobalNavItem(
                      icon: MargenLucide.library,
                      label: 'Biblioteca',
                      compact: tightNav,
                      active: section == MargenNavSection.library,
                      onTap: () => context.go('/'),
                    ),
                    _GlobalNavItem(
                      icon: MargenLucide.search,
                      label: 'Buscar',
                      compact: tightNav,
                      active: section == MargenNavSection.search,
                      onTap: () => context.go('/buscar'),
                    ),
                    _GlobalNavItem(
                      icon: MargenLucide.review,
                      label: 'Repaso',
                      compact: tightNav,
                      active: section == MargenNavSection.review,
                      onTap: () => context.go('/repaso'),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            AppThemeModeControl(dense: compactNav, showLabels: !compactNav),
            _GlobalNavItem(
              icon: MargenLucide.profile,
              label: 'Perfil',
              compact: tightNav,
              active: section == MargenNavSection.settings,
              onTap: () => context.go('/ajustes'),
            ),
            if (!tightNav) ...[
              const SizedBox(width: 4),
              BookifiGhostButton(
                label: 'Salir',
                compact: true,
                onPressed: () =>
                    ref.read(supabaseClientProvider).auth.signOut(),
              ),
            ] else
              IconButton(
                tooltip: 'Salir',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    ref.read(supabaseClientProvider).auth.signOut(),
                icon: Icon(
                  Icons.logout_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GlobalNavItem extends StatefulWidget {
  const _GlobalNavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool compact;

  @override
  State<_GlobalNavItem> createState() => _GlobalNavItemState();
}

class _GlobalNavItemState extends State<_GlobalNavItem> {
  var _hover = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final active = widget.active;
    final fg = active
        ? AppTokens.purple
        : (isDark ? AppTokens.textSoft : AppTokens.textMuted);

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: TextButton(
          onPressed: widget.onTap,
          style: TextButton.styleFrom(
            foregroundColor: fg,
            backgroundColor: active
                ? AppTokens.purple.withValues(alpha: isDark ? 0.2 : 0.1)
                : (_hover
                      ? AppTokens.purple.withValues(alpha: 0.06)
                      : Colors.transparent),
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 10 : 12,
              vertical: widget.compact ? 8 : 10,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MIcon(widget.icon, size: 18, color: fg),
              if (!widget.compact) ...[
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Cabecera móvil: marca + acciones (la nave principal va abajo).
class MobileShellHeader extends ConsumerWidget {
  const MobileShellHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final narrow = size.width < 380;
    final horizontalPad = landscape ? 20.0 : 16.0;
    final barHeight = landscape ? 48.0 : 52.0;
    final themeDense = landscape || narrow;

    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: barHeight,
          padding: EdgeInsets.symmetric(horizontal: horizontalPad),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.65),
              ),
            ),
          ),
          child: Row(
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => context.go('/'),
                    child: const BookifiBrand(compact: true),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AppThemeModeControl(dense: themeDense, showLabels: false),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Perfil',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onPressed: () => context.go('/ajustes'),
                icon: MIcon(
                  MargenLucide.profile,
                  size: 20,
                  color: isDark ? AppTokens.textSoft : AppTokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Navegación inferior en móvil/tablet estrecho.
class GlobalBottomNav extends StatelessWidget {
  const GlobalBottomNav({super.key});

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final section = sectionForPath(path);
    var index = 0;
    if (section == MargenNavSection.review) index = 1;
    if (section == MargenNavSection.search) index = 2;
    if (section == MargenNavSection.settings) index = 3;

    return NavigationBar(
      height: 64,
      selectedIndex: index,
      onDestinationSelected: (i) {
        switch (i) {
          case 0:
            context.go('/');
          case 1:
            context.go('/repaso');
          case 2:
            context.go('/buscar');
          case 3:
            context.go('/ajustes');
        }
      },
      destinations: const [
        NavigationDestination(
          icon: MIcon(MargenLucide.library, size: 22),
          label: 'Biblioteca',
        ),
        NavigationDestination(
          icon: MIcon(MargenLucide.review, size: 22),
          label: 'Repaso',
        ),
        NavigationDestination(
          icon: MIcon(MargenLucide.search, size: 22),
          label: 'Buscar',
        ),
        NavigationDestination(
          icon: MIcon(MargenLucide.profile, size: 22),
          label: 'Perfil',
        ),
      ],
    );
  }
}
