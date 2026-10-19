import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_shell.dart';
import '../../app/margen_scaffold.dart';
import '../../core/theme/theme_mode_control.dart';
import '../../core/providers.dart';
import '../auth/auth_chatgpt_section.dart';
import '../shared/bookifi_ui.dart';
import 'chatgpt_platform.dart';

class ConnectChatGptPage extends ConsumerWidget {
  const ConnectChatGptPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final desktop = useDesktopChrome(context);
    final enabled = chatGptConnectEnabled;

    final content = BookifiPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!desktop)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: BookifiGhostButton(
                  label: '← Volver',
                  onPressed: () => context.pop(),
                ),
              ),
            ),
          BookifiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BookifiBrand(),
                const SizedBox(height: 16),
                Text(
                  'ChatGPT Plus',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.03,
                  ),
                ),
                const SizedBox(height: 8),
                BookifiChip(
                  chatGptPlatformLabel(chatGptPlatformSupport()),
                  teal: enabled,
                ),
                const SizedBox(height: 12),
                Text(
                  'Sign in with ChatGPT open-source (loopback 127.0.0.1:1455 en Mac; '
                  'misma política OAuth en iPhone/iPad vía sesión segura del sistema). '
                  'No requiere API key de pago; requiere consentimiento explícito del plan Plus.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
                const SizedBox(height: 16),
                const AuthChatGptSection(),
                if (desktop)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: BookifiGhostButton(
                      label:
                          ref
                                  .watch(supabaseClientProvider)
                                  .auth
                                  .currentSession !=
                              null
                          ? 'Ir a biblioteca'
                          : 'Ir al login',
                      onPressed: () => context.go(
                        ref.read(supabaseClientProvider).auth.currentSession !=
                                null
                            ? '/'
                            : '/login',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    if (desktop) return MargenScaffold(body: content);
    return Scaffold(
      appBar: AppBar(
        title: const Text('ChatGPT Plus'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: AppThemeModeControl(dense: true, showLabels: false),
          ),
        ],
      ),
      body: content,
    );
  }
}
