import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers.dart';
import '../../core/supabase/supabase_password_auth.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/margen_iconography.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/theme/theme_mode_control.dart';
import '../../data/models/book.dart';
import '../auth/auth_errors.dart';
import '../chatgpt/chatgpt_platform.dart';
import '../shared/bookifi_ui.dart';
import 'profile_user_stats.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(supabaseClientProvider).auth.currentUser;
    final mobile = MediaQuery.sizeOf(context).width < 720;

    if (user == null) {
      return BookifiPage(
        child: Center(
          child: Text(
            'No hay sesión activa.',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    if (mobile) {
      return BookifiPage(scroll: false, child: _ProfileMobileView(user: user));
    }

    return BookifiPage(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: _ProfileMobileView(user: user),
        ),
      ),
    );
  }
}

class _ProfileMobileView extends ConsumerStatefulWidget {
  const _ProfileMobileView({required this.user});

  final User user;

  @override
  ConsumerState<_ProfileMobileView> createState() => _ProfileMobileViewState();
}

class _ProfileMobileViewState extends ConsumerState<_ProfileMobileView> {
  Future<void> _signOut() async {
    await ref.read(supabaseClientProvider).auth.signOut();
    if (!mounted) return;
    context.go('/login');
  }

  String _displayName(User user) {
    final meta = user.userMetadata ?? {};
    final fromMeta =
        meta['display_name']?.toString().trim() ??
        meta['full_name']?.toString().trim() ??
        meta['name']?.toString().trim();
    if (fromMeta != null && fromMeta.isNotEmpty) return fromMeta;
    return 'Sin nombre';
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final list = parts.toList();
    if (list.isEmpty) return '?';
    if (list.length == 1) {
      final w = list.first;
      return w.length >= 2 ? w.substring(0, 2).toUpperCase() : w.toUpperCase();
    }
    return '${list.first[0]}${list.last[0]}'.toUpperCase();
  }

  bool _isActiveAccount(User user) => user.emailConfirmedAt != null;

  String _languageSubtitle(List<Book> books) {
    if (books.isEmpty) return 'Español';
    final langs = books.map((b) => b.explanationLanguage).toSet();
    if (langs.length == 1 && langs.first == 'es') return 'Español';
    if (langs.length == 1 && langs.first == 'en') return 'English';
    return 'Por libro';
  }

  AppThemePreference _themePref(ThemeMode mode) =>
      themePreferenceFromMode(mode);

  String _themePrefLabel(AppThemePreference pref) => switch (pref) {
    AppThemePreference.system => 'Sistema',
    AppThemePreference.light => 'Claro',
    AppThemePreference.dark => 'Oscuro',
  };

  Future<void> _editDisplayName() async {
    final ctrl = TextEditingController(text: _displayName(widget.user));
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Información personal'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final name = ctrl.text.trim();
    ctrl.dispose();
    if (saved != true || !mounted) return;
    await ref
        .read(supabaseClientProvider)
        .auth
        .updateUser(UserAttributes(data: {'display_name': name}));
    if (mounted) setState(() {});
  }

  Future<void> _changePassword() async {
    final email = widget.user.email?.trim() ?? '';
    if (email.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cambiar contraseña'),
        content: Text(
          'Enviaremos un enlace a $email para restablecer tu contraseña.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar enlace'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await SupabasePasswordAuth().resetPasswordForEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Te enviamos un enlace para restablecer tu contraseña.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyAuthError(e))));
    }
  }

  void _openLanguageSheet(List<Book> books) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Idioma de explicaciones',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'El idioma de las explicaciones se configura por libro.',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (books.isEmpty)
                  Text(
                    'Español (predeterminado)',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  )
                else
                  for (final book in books)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(book.title, overflow: TextOverflow.ellipsis),
                      trailing: DropdownButton<String>(
                        value: book.explanationLanguage,
                        items: const [
                          DropdownMenuItem(value: 'es', child: Text('ES')),
                          DropdownMenuItem(value: 'en', child: Text('EN')),
                        ],
                        onChanged: (value) async {
                          if (value == null) return;
                          await ref.read(booksRepositoryProvider).updateBook(
                            book.id,
                            {'explanation_language': value},
                          );
                          ref.invalidate(_booksProvider);
                          if (ctx.mounted) setState(() {});
                        },
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final name = _displayName(user);
    final email = user.email ?? 'Sin correo';
    final active = _isActiveAccount(user);
    final themeMode = ref.watch(themeControllerProvider);
    final themePref = _themePref(themeMode);
    final statsAsync = ref.watch(_profileStatsProvider);
    final booksAsync = ref.watch(_booksProvider);
    final chatGptAsync = ref.watch(chatGptLinkProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final muted = isDark
        ? const Color(0xFF94A3B8)
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final cardBorder = Theme.of(context).dividerColor.withValues(alpha: 0.45);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
      children: [
        Text(
          'Perfil',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Gestiona tu cuenta, preferencias y más.',
          style: TextStyle(color: muted, fontSize: 14, height: 1.35),
        ),
        const SizedBox(height: 22),

        _ProfileHeroCard(
          name: name,
          email: email,
          initials: _initials(name),
          active: active,
          stats: statsAsync.valueOrNull ?? ProfileUserStats.empty,
          statsLoading: statsAsync.isLoading,
          onEdit: _editDisplayName,
        ),

        const SizedBox(height: 20),

        _ProfileSectionCard(
          title: 'Mi cuenta',
          child: Column(
            children: [
              _ProfileNavRow(
                icon: MargenLucide.profile,
                title: 'Información personal',
                onTap: _editDisplayName,
              ),
              _ProfileDivider(color: cardBorder),
              _ProfileNavRow(
                icon: LucideIcons.mail,
                title: 'Correo',
                subtitle: email,
                onTap: () {},
                showChevron: true,
              ),
              _ProfileDivider(color: cardBorder),
              _ProfileNavRow(
                icon: LucideIcons.lock,
                title: 'Cambiar contraseña',
                onTap: _changePassword,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        _ProfileSectionCard(
          title: 'ChatGPT',
          child: chatGptAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator(minHeight: 2),
            ),
            error: (e, _) => Text('$e'),
            data: (link) => _ProfileChatGptBlock(
              connected: link.connected,
              label: link.label,
              muted: muted,
              onManage: () => context.push('/conectar-chatgpt'),
            ),
          ),
        ),

        const SizedBox(height: 20),

        _ProfileSectionCard(
          title: 'Preferencias',
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 340;
                    final themeControl = _ProfileThemeSegmented(
                      selected: themePref,
                      onSelect: (p) => ref
                          .read(themeControllerProvider.notifier)
                          .setPreference(p),
                    );
                    final labels = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Apariencia',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _themePrefLabel(themePref),
                          style: TextStyle(color: muted, fontSize: 13),
                        ),
                      ],
                    );
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              MIcon(
                                LucideIcons.palette,
                                size: 20,
                                color: muted,
                              ),
                              const SizedBox(width: 14),
                              Expanded(child: labels),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: themeControl,
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MIcon(LucideIcons.palette, size: 20, color: muted),
                        const SizedBox(width: 14),
                        Expanded(child: labels),
                        themeControl,
                      ],
                    );
                  },
                ),
              ),
              _ProfileDivider(color: cardBorder),
              _ProfileNavRow(
                icon: LucideIcons.globe,
                title: 'Idioma',
                subtitle: booksAsync.maybeWhen(
                  data: _languageSubtitle,
                  orElse: () => 'Español',
                ),
                onTap: () {
                  booksAsync.whenData((books) => _openLanguageSheet(books));
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        _ProfileSectionCard(
          title: 'Cuenta',
          child: _ProfileNavRow(
            icon: LucideIcons.logOut,
            title: 'Cerrar sesión',
            destructive: true,
            onTap: _signOut,
          ),
        ),
      ],
    );
  }
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.name,
    required this.email,
    required this.initials,
    required this.active,
    required this.stats,
    required this.statsLoading,
    required this.onEdit,
  });

  final String name;
  final String email;
  final String initials;
  final bool active;
  final ProfileUserStats stats;
  final bool statsLoading;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? const Color(0xFF94A3B8) : AppTokens.textMuted;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  AppTokens.purple.withValues(alpha: 0.38),
                  const Color(0xFF111827),
                  const Color(0xFF0F172A),
                ]
              : [AppTokens.purple.withValues(alpha: 0.14), Colors.white],
        ),
        border: Border.all(
          color: AppTokens.purple.withValues(alpha: isDark ? 0.35 : 0.2),
        ),
        boxShadow: [
          BoxShadow(
            color: AppTokens.purple.withValues(alpha: isDark ? 0.12 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppTokens.purple.withValues(alpha: 0.85),
                child: Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(email, style: TextStyle(fontSize: 13, color: muted)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: active
                                ? const Color(0xFF22C55E)
                                : AppTokens.warning,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          active ? 'Cuenta activa' : 'Cuenta pendiente',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: active
                                ? const Color(0xFF22C55E)
                                : AppTokens.warning,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onEdit,
                style: TextButton.styleFrom(
                  foregroundColor: AppTokens.purple,
                  backgroundColor: AppTokens.purple.withValues(
                    alpha: isDark ? 0.22 : 0.1,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Text(
                  'Editar',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(color: muted.withValues(alpha: 0.25), height: 1),
          const SizedBox(height: 14),
          statsLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : Row(
                  children: [
                    Expanded(
                      child: _ProfileStatCell(
                        icon: MargenLucide.library,
                        iconColor: AppTokens.purple,
                        value: '${stats.bookCount}',
                        label: 'libros',
                      ),
                    ),
                    _ProfileStatDivider(color: muted.withValues(alpha: 0.2)),
                    Expanded(
                      child: _ProfileStatCell(
                        icon: MargenLucide.scanLine,
                        iconColor: AppTokens.cyan,
                        value: '${stats.fragmentCount}',
                        label: 'fragmentos',
                      ),
                    ),
                    _ProfileStatDivider(color: muted.withValues(alpha: 0.2)),
                    Expanded(
                      child: _ProfileStatCell(
                        icon: MargenLucide.review,
                        iconColor: AppTokens.teal,
                        value: '${stats.questionCount}',
                        label: 'preguntas',
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }
}

class _ProfileStatCell extends StatelessWidget {
  const _ProfileStatCell({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      children: [
        MIcon(icon, size: 20, color: iconColor),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: muted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ProfileStatDivider extends StatelessWidget {
  const _ProfileStatDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 52, color: color);
  }
}

class _ProfileSectionCard extends StatelessWidget {
  const _ProfileSectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111827) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.45),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ProfileDivider extends StatelessWidget {
  const _ProfileDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, thickness: 1, color: color);
  }
}

class _ProfileNavRow extends StatelessWidget {
  const _ProfileNavRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.destructive = false,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final fg = destructive
        ? const Color(0xFFEF4444)
        : Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: destructive ? fg : muted),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: fg,
                        fontSize: 15,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                    ],
                  ],
                ),
              ),
              if (showChevron)
                Icon(
                  LucideIcons.chevronRight,
                  size: 18,
                  color: destructive ? fg.withValues(alpha: 0.7) : muted,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileChatGptBlock extends ConsumerWidget {
  const _ProfileChatGptBlock({
    required this.connected,
    required this.label,
    required this.muted,
    required this.onManage,
  });

  final bool connected;
  final String? label;
  final Color muted;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!connected) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ChatGPT no conectado',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Conecta tu plan Plus para resúmenes, explicaciones y preguntas.',
            style: TextStyle(fontSize: 13, color: muted, height: 1.4),
          ),
          const SizedBox(height: 14),
          BookifiPrimaryButton(
            label: chatGptConnectEnabled
                ? 'Conectar ChatGPT'
                : 'No disponible en esta plataforma',
            onPressed: chatGptConnectEnabled ? onManage : null,
          ),
        ],
      );
    }

    final credsAsync = ref.watch(chatGptCredentialsProvider);
    final connectedEmail =
        credsAsync.valueOrNull?.email ??
        credsAsync.valueOrNull?.subject ??
        label ??
        '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                LucideIcons.sparkles,
                size: 20,
                color: Color(0xFF22C55E),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'ChatGPT conectado',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF22C55E,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Plus',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF22C55E),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (connectedEmail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      connectedEmail,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Usa ChatGPT para obtener resúmenes, explicaciones y preguntas de tus libros.',
          style: TextStyle(fontSize: 13, color: muted, height: 1.45),
        ),
        const SizedBox(height: 14),
        Material(
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onManage,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Gestionar conexión',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(LucideIcons.chevronRight, size: 18, color: muted),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileThemeSegmented extends StatelessWidget {
  const _ProfileThemeSegmented({
    required this.selected,
    required this.onSelect,
  });

  final AppThemePreference selected;
  final ValueChanged<AppThemePreference> onSelect;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E293B)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _seg('Sistema', AppThemePreference.system),
            _seg('Claro', AppThemePreference.light),
            _seg('Oscuro', AppThemePreference.dark),
          ],
        ),
      ),
    );
  }

  Widget _seg(String label, AppThemePreference value) {
    return Builder(
      builder: (context) {
        final sel = selected == value;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Material(
          color: sel
              ? (isDark
                    ? AppTokens.purple.withValues(alpha: 0.55)
                    : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: () => onSelect(value),
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: sel
                      ? (isDark ? Colors.white : AppTokens.purple)
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

final _booksProvider = FutureProvider<List<Book>>((ref) {
  return ref.watch(booksRepositoryProvider).listBooks();
});

final _profileStatsProvider = FutureProvider<ProfileUserStats>((ref) async {
  ref.watch(repasoReloadTickProvider);
  final books = await ref.watch(_booksProvider.future);
  return computeProfileUserStats(ref.read(booksRepositoryProvider), books);
});
