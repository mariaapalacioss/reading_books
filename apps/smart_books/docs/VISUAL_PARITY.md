# Paridad visual React → Flutter

Referencia: `src/styles/global.css`, `src/components/Shell.tsx`, `src/pages/LibraryPage.tsx`, `src/pages/ReaderPage.tsx`.

## Implementado en Flutter (esta iteración)

| Área | Web | Flutter |
|------|-----|---------|
| Tokens Bookifi | CSS variables | `lib/core/theme/app_tokens.dart` |
| Tipografía | Source Sans 3 | `google_fonts` + tema |
| Fondo escritorio | `--desk` gradientes | `AppTokens.deskBackground` |
| Top bar | `Shell.tsx` topbar | `app_shell.dart` (macOS) |
| Biblioteca grid | `.library-grid` / cards | `library_page.dart` |
| Chips / progreso | `.chip`, `.progress` | `BookifiChip`, `BookifiProgressBar` |
| Diálogo upload | `.dialog` 560px | `upload_book_dialog.dart` |
| Lector 3 columnas | `.reader-grid` | `reader_layout.dart` |
| Botones pill | `.btn`, `.btn-ghost` | `BookifiPrimaryButton`, `BookifiGhostButton` |
| Auth hero | `AuthShell` + `notario-auth.css` | `auth_shell.dart`, `auth_page.dart` |
| Panel IA escritorio | `AssistPanel.tsx` | `assist_panel.dart` en `reader_layout` (macOS ancho) |
| Tarjetas repaso | `StudyCardView.tsx` | `study_card_view.dart`, `review_page.dart` |
| Conectar ChatGPT | `ChatGptConnect` | `connect_chatgpt_page.dart` (BookifiCard) |
| Menú selección PDF (desktop) | selection menu | diálogo compacto en `reader_page.dart` |

## Pendiente visual (funcionalidad existe, UI aún no replica web al 100 %)

- `BookChat` citas en panel IA (botones `result-btn` por página citada).
- Animaciones micro (hover herramientas PDF, menú flotante estilo web en todas las plataformas).
- Portadas PDF reales (web tampoco usa thumbnail de storage; Flutter usa gradiente editorial).
- Toolbar del lector alineada con controles web (progreso, zoom, herramientas resaltado).
- Auth: bloque ChatGPT hero idéntico al componente React embebido post-login.

## macOS file picker

Entitlement añadido: `com.apple.security.files.user-selected.read-only` en Debug/Release.
