# Matriz de paridad React → Flutter

Leyenda **Estado:** `P` pendiente · `I` implementada (código) · `V` verificada en dispositivo · `L` limitación oficial

Referencia web: `src/` · Flutter: `apps/smart_books/lib/`

| # | Funcionalidad | Flutter | Estado | Archivos Flutter | Pruebas |
|---|---------------|---------|--------|------------------|---------|
| 1 | Setup Supabase | dart-define | I | `main.dart`, `setup_page.dart` | manual |
| 2 | Auth email/password | Supabase Auth + GoTrue explícito | I | `auth_page.dart`, `supabase_password_auth.dart` | manual macOS |
| 3 | ChatGPT macOS loopback | OAuth + Plan API | I | `features/chatgpt/*` | manual macOS |
| 4 | ChatGPT iOS | No conectar Plus | L | `CHATGPT_IOS.md` | N/A |
| 5 | Navegación shell | tabs + rutas | I | `app_shell.dart`, `router.dart` | manual |
| 6 | Tema sistema/claro/oscuro | ThemeController | I | `theme_controller.dart` | manual |
| 7 | Biblioteca listar | listBooks + filtros Material | I | `library_page.dart`, `bookifi_ui.dart` | manual |
| 8 | Subir PDF ingest completo | extract + pages + chapters + chunks | I | `ingest_service.dart`, `pdf_extractor.dart` | manual |
| 9 | Eliminar libro | deleteBook | I | `books_repository.dart` | manual |
| 10 | Metadatos upload | diálogo | I | `upload_book_sheet.dart` | manual |
| 11 | PDF local (nube 413 / grande) | `local/` en dispositivo | I | `local_pdf_store.dart`, `ingest_service.dart` | manual |
| 12 | Progreso lectura | current_page | I | `reader_page.dart` | manual |
| 13 | Render PDF | pdfrx | I | `pdf_interactive_page.dart` | manual |
| 14 | Nav / zoom | toolbar + InteractiveViewer | I | `reader_page.dart` | manual |
| 15 | Panel capítulos desktop | ReaderLayout | I | `reader_layout.dart` | manual |
| 16 | Capítulos móvil sheet | bottom sheet | I | `reader_layout.dart` | manual |
| 17 | Capítulos detectados | detectChapters | I | `domain/chapters.dart` | manual |
| 18 | Editar capítulos usuario | replaceChapters | P | — | — |
| 19 | Marcadores | toggleBookmark | I | `reader_page.dart` | manual |
| 20 | Resaltados AI + manual | list + create manual | I | `books_repository.dart`, `pdf_interactive_page.dart` | manual |
| 21 | Selección texto PDF | capa items + menú | I | `pdf_interactive_page.dart` | manual |
| 22 | Captura OCR región | — | P | web `regionOcr` | — |
| 23 | OCR progresivo | Vision macOS + jobs | I | `ocr_job_service.dart`, `MainFlutterWindow.swift` | manual macOS |
| 24 | OCR iOS Vision | canal nativo | I | `ios/Runner/AppDelegate.swift` | manual iOS |
| 25 | Reanudar OCR | resumeForLibrary | I | `ocr_job_service.dart`, `library_page.dart` | manual |
| 26 | Priorizar 1.er capítulo OCR | prioritizePages | I | `ocr_job_service.dart` | manual |
| 27 | Análisis capítulo Plan API | analysis_service | I | `analysis_service.dart` | manual macOS |
| 28 | Asistencia modos | summary/key/review/page | I | `book_assist_service.dart`, `assist_sheet.dart` | manual |
| 29 | Chat streaming | Plan API | I | `plan_api.dart`, `assist_sheet.dart` | manual |
| 30 | Historial chat | SharedPreferences por libro | I | `assist_sheet.dart` | manual |
| 31 | Markdown respuestas | SmartMarkdown | I | `markdown_body.dart` | manual |
| 32 | Guardar repaso | study_cards insert | I | `assist_sheet.dart` | manual |
| 33 | Repaso lectura tarjetas | ReviewPage expand | I | `review_page.dart` | manual |
| 34 | Repaso interactivo flip | — | P | web `StudyCardView` | — |
| 35 | Búsqueda textual | textSearchLibrary | I | `search_page.dart` | manual |
| 36 | Búsqueda semántica | edge function | L | doc en UI | — |
| 37 | ES/EN explicaciones | settings | I | `settings_page.dart` | manual |
| 38 | show_ai_highlights | flag book | I | `reader_page.dart` | manual |
| 39 | Citas asistencia | pasajes búsqueda | I | `book_assist_service.dart` | parcial |
| 40 | Caché asistencia | — | P | `assistCache.ts` | — |
| 41 | Puntos capítulo | chapter_points | I | `analysis_service.dart` | manual |
| 42 | Notas en highlights | patch note | P | web | — |
| 43 | Preguntas guardadas | questions table | P | web | — |
| 44 | Embeddings | embed-book | P | web | — |
| 45 | Atajos ←/→ macOS | Shortcuts | I | `reader_page.dart` | manual |
| 46 | Validación highlights estricta | validate.ts | P | simplificado | — |
| 47 | GitHub Pages producto | N/A | L | — | — |

**Resumen:** Implementadas ~32 · Pendientes ~10 · Limitaciones 4

**Verificado (`V`):** ninguna fila marcada `V` en esta revisión — falta prueba manual en macOS/iOS tras liberar espacio en disco.

**Bloqueo pruebas:** el entorno llegó a **ENOSPC** (~99 % disco). `flutter test` puede fallar hasta liberar varios GB.
