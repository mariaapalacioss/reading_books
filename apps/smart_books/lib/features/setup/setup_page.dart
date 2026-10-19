import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/theme_mode_control.dart';

class SetupPage extends ConsumerWidget {
  const SetupPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar Smart Books'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 12),
            child: AppThemeModeControl(dense: true, showLabels: false),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Configurar Smart Books',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Faltan variables de Supabase. Compila o ejecuta con:',
              ),
              const SizedBox(height: 12),
              const SelectableText(
                'flutter run -d macos \\\n'
                '  --dart-define=SUPABASE_URL=https://TU_PROYECTO.supabase.co \\\n'
                '  --dart-define=SUPABASE_ANON_KEY=tu_anon_key',
              ),
              const SizedBox(height: 8),
              Text('Estado: ${AppConfig.supabaseReady ? "OK" : "incompleto"}'),
            ],
          ),
        ),
      ),
    );
  }
}
