# Plan técnico de migración Smart Books → Flutter (macOS + iOS)

La app **React/Vite** en la raíz del repo (`src/`, `npm run dev`) permanece como respaldo hasta completar paridad. La app nativa vive en **`apps/smart_books/`**.

## Mapa de reutilización

| Capa React/TS | Estrategia Flutter |
|---------------|-------------------|
| `src/lib/types.ts` | `lib/data/models/` (mismos nombres de columnas Supabase) |
| `src/domain/*` | Port gradual a Dart (`lib/domain/`) — tests Dart vs fixtures JSON |
| `src/lib/books.ts`, `session`, storage | `lib/data/repositories/` |
| `src/lib/chatgpt/*` | `lib/features/chatgpt/` — loopback macOS; iOS pendiente oficial |
| `src/lib/pdf.ts`, `ocr*.ts` | Fase 4–5: `pdfx` + ML Kit / Tesseract plugin o FFI |
| `src/components/*` | `lib/features/*/presentation/` |
| `supabase/migrations` | **Sin cambios** — mismo proyecto |
| `scripts/chatgpt-oauth-bridge.mjs` | Referencia para `oauth_loopback_server.dart` (macOS) |

## Fases (orden acordado)

### Fase 1 — Arquitectura compartida ✅ (iniciada)

- Proyecto Flutter solo **iOS + macOS** (sin web).
- Carpetas: `core/`, `data/`, `features/`, `platform/`.
- Tema Bookifi (#6222e0, #00baba, #0fcdef).
- Config vía `--dart-define=SUPABASE_URL=...` y `SUPABASE_ANON_KEY=...`.

### Fase 2 — Supabase Auth ✅ (iniciada)

- `supabase_flutter` init en `main.dart`.
- Pantallas login / registro (email+password, igual que web).
- Perfiles vía trigger `handle_new_user` existente.

### Fase 3 — Biblioteca y PDFs existentes ✅ (iniciada)

- `BooksRepository.listBooks()` → tabla `books` (RLS).
- Descarga PDF cloud con `createSignedUrl`.
- PDFs `local/` en web: en Flutter usar caché local por `{userId}/{bookId}.pdf` al sincronizar (fase 4).

### Fase 4 — Lector PDF y navegación 🔲

- `pdfx` o `pdfrx` render por página.
- Capítulos desde `chapters`; página actual en `books.current_page`.
- Layout: **macOS** `NavigationSplitView` (capítulos | PDF | asistencia); **iOS** full-screen + sheet asistencia.
- Text layer / selección: port `regionSelect`, `textLayerLines`.

### Fase 5 — ChatGPT Plus macOS 🔲 (en progreso)

- **Admitido (OSS/local):** loopback `127.0.0.1:1455`, PKCE, scopes `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct`.
- Credenciales en **flutter_secure_storage** keyed por `supabase_user_id`.
- Inferencia: `POST https://api.openai.com/v1/responses`, SSE, `store: false` (port `planApi.ts`).
- **No afirmar iOS** hasta redirect URI / partner aprobados por OpenAI.

### Fase 6 — IA y análisis progresivo 🔲

- Port `bookAssist.ts`, `analyzeChapterPlan.ts`, caché por libro.
- Jobs OCR/análisis: mismas tablas `analysis_jobs`, `book_pages`.
- Cola: priorizar primer capítulo (`ensureAnalysis`).

### Fase 7 — Mobile UX + evaluación ChatGPT iOS 🔲

- Documento `CHATGPT_IOS.md` con estado OpenAI SIWC mobile.
- Placeholder UI: biblioteca + lectura; IA deshabilitada o solo si hay vía oficial.

### Fase 8 — Builds instalables 🔲

- macOS: notarización (Apple Developer).
- iOS: TestFlight / Ad Hoc; capabilities red, keychain.

## ChatGPT Plus por plataforma (honestidad técnica)

| Plataforma | Estado objetivo | Evidencia OpenAI |
|------------|-----------------|------------------|
| **macOS (Flutter)** | Implementar flujo OSS loopback | [token-sharing open source](https://developers.openai.com/siwc/token-sharing-open-source) |
| **iOS** | **Pendiente verificación** — arquitectura preparada, feature flag | Partner / redirect móvil; no asumir loopback |
| **React web (legacy)** | Sin cambios; respaldo | — |

## Datos existentes

- **No migración de DB:** mismos `book_id`, storage paths `{userId}/{bookId}.pdf`.
- Usuarios entran con las **mismas credenciales Supabase**.
- Tokens ChatGPT web (IndexedDB) **no** se migran; cada usuario reconecta en Flutter.

## Riesgos

- OCR pesado en móvil: limitar resolución y cola en background.
- PDF muy grande: streaming + caché disco.
- iOS background limits para OCR largo.

## Paridad funcional (checklist)

- [ ] Biblioteca, upload PDF
- [ ] OCR / extracting
- [ ] Capítulos, marcadores, resaltados
- [ ] Asistencia + chat streaming Markdown
- [ ] Repaso / study_cards
- [ ] ES/EN explicaciones
- [ ] Tema claro/oscuro/sistema
- [ ] ChatGPT Plus macOS
- [ ] ChatGPT Plus iOS (solo si oficial)
