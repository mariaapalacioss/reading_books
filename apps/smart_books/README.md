# Smart Books (Flutter — macOS + iOS)

App nativa en migración desde la web React en la raíz del monorepo. **No reemplaza** `src/`; convive como respaldo.

## Requisitos de desarrollo

1. **Flutter SDK** 3.41+ con soporte macOS e iOS:
   ```bash
   flutter doctor
   ```
2. **Xcode** (macOS + simulador/dispositivo iOS).
3. **Cuenta Apple Developer** (solo para distribuir fuera de tu Mac).
4. Mismo **proyecto Supabase** que la app web (`VITE_SUPABASE_URL` / anon key).
5. PDFs grandes: ejecuta el SQL del bucket **`books`** (500 MB) — ver [`docs/SUPABASE_PDF_UPLOAD.md`](docs/SUPABASE_PDF_UPLOAD.md).

## Ejecutar en macOS

```bash
cd apps/smart_books
flutter pub get

flutter run -d macos \
  --dart-define=SUPABASE_URL=https://TU_PROYECTO.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=sb_publishable_…

# Alternativa (gitignored):
cp dart_defines.example.json dart_defines.json
# edita dart_defines.json con tu URL y clave pública
flutter run -d macos --dart-define-from-file=dart_defines.json
```

**Importante:** no uses literales `...` ni ejecutes desde Xcode sin `--dart-define`; el build cacheado puede inyectar placeholders y provocar `No host specified in URI`.

### ChatGPT Plus (macOS)

1. Entra con tu usuario Supabase.
2. Icono ✨ → **Continuar con ChatGPT**.
3. Se inicia el puente loopback en `127.0.0.1:1455` (equivalente al script Node de la web).
4. Autoriza en el navegador con **tu** cuenta Plus.

**iOS:** mismo flujo ChatGPT Plus OSS que macOS (loopback `127.0.0.1:1455`; ver `docs/CHATGPT_IOS.md`). Recomendado iOS 17.4+.

## Ejecutar en iOS

```bash
flutter run -d ios \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
```

## Builds instalables

```bash
# macOS .app
flutter build macos --release \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...

# iOS (requiere firma en Xcode)
flutter build ios --release \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
```

Abre `ios/Runner.xcworkspace` en Xcode para **Team**, **Signing** y Archive → TestFlight.

## Documentación

- `docs/MIGRATION_PLAN.md` — fases y paridad con React.
- `docs/PARITY_MATRIX.md` — auditoría React → Flutter (estado por funcionalidad).
- `docs/CHATGPT_IOS.md` — limitaciones iOS / OpenAI.

## Estructura

```
lib/
  core/         config, theme, providers
  data/         models, repositories (Supabase)
  features/     auth, library, chatgpt, …
  app/          router, SmartBooksApp
```

## Datos existentes

Usa el **mismo email/contraseña** Supabase que en la web. Los libros en la nube aparecen en Biblioteca. PDFs marcados `local/` en web requieren re-subida o sync (fase 4).
