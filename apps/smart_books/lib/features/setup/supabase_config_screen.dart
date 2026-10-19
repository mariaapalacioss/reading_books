import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/theme_mode_control.dart';
import '../shared/bookifi_ui.dart';

/// Pantalla cuando Supabase no está configurado o la URL/clave son inválidas.
class SupabaseConfigScreen extends ConsumerWidget {
  const SupabaseConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = MediaQuery.sizeOf(context).width < 420;
    final error = AppConfig.supabaseConfigError;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0D3569),
              AppTokens.purple.withValues(alpha: 0.85),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: BookifiCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(child: BookifiBrand()),
                          AppThemeModeControl(
                            dense: compact,
                            showLabels: !compact,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Configura Supabase',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      if (error != null)
                        Text(
                          error,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                                height: 1.4,
                              ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        'Desde terminal (recomendado):',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const SelectableText(
                        'cd apps/smart_books\n'
                        'flutter run -d macos \\\n'
                        '  --dart-define=SUPABASE_URL=https://TU_ID.supabase.co \\\n'
                        '  --dart-define=SUPABASE_ANON_KEY=sb_publishable_…\n\n'
                        'O copia dart_defines.example.json → dart_defines.json y usa:\n'
                        'flutter run -d macos --dart-define-from-file=dart_defines.json',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Si ejecutas desde Xcode, los --dart-define no se aplican solos: usa el comando anterior o define DART_DEFINES en el esquema.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
