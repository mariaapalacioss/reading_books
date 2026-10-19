import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdfrx/pdfrx.dart';
import 'app/bootstrap_material_app.dart';
import 'app/smart_books_app.dart';
import 'core/config/app_config.dart';
import 'core/supabase/supabase_init.dart';
import 'features/setup/supabase_config_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  await initializeDateFormatting('es', null);

  if (!AppConfig.supabaseReady) {
    runApp(
      const ProviderScope(
        child: BootstrapMaterialApp(home: SupabaseConfigScreen()),
      ),
    );
    return;
  }

  await initializeSupabase();

  runApp(const ProviderScope(child: SmartBooksApp()));
}
