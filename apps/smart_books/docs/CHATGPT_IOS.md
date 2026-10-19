# ChatGPT Plus en iOS

## Estado

**iPhone e iPad usan el mismo flujo OSS que macOS:** PKCE, `redirect_uri` en `http://127.0.0.1:1455/auth/callback`, scopes `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct`, registro dinámico de agente y guardado en llavero (Keychain) por usuario Smart Books.

La diferencia es solo **cómo se abre el navegador de autorización**:

| Plataforma | UI de login OpenAI |
|------------|-------------------|
| **macOS** | Safari externo + puente HTTP local (`OAuthLoopbackServer`) |
| **iOS** | `ASWebAuthenticationSession` vía `flutter_web_auth_2`, con el mismo redirect loopback; si falla, fallback a Safari + puente local |

Requisito recomendado: **iOS 17.4+** (API de callback HTTP en sesión de autenticación). En dispositivos anteriores puede usarse el fallback con Safari externo.

## Pasos para probar en dispositivo

1. `flutter run -d ios` con `--dart-define` de Supabase (ver README).
2. Inicia sesión en Smart Books (opcional antes de ChatGPT; también puedes conectar ChatGPT primero).
3. **Ajustes / Conectar ChatGPT** → **Continuar con ChatGPT**.
4. Acepta compartir el plan Plus en la pantalla de OpenAI.
5. **Probar conexión** y generar preguntas desde Asistencia o Repaso.

## Diagnóstico

- Logs `[ChatGPT OAuth]` en consola de `flutter run` (sin tokens).
- Puerto **1455** ocupado: cierra otra instancia de Smart Books o el puente npm de la web (`npm run dev`).
- Si OAuth termina pero no guarda: revisa Keychain / permisos de la app.

## Referencias OpenAI

- https://developers.openai.com/siwc/token-sharing-open-source  
- https://developers.openai.com/siwc/token-sharing-open-source/sign-in  
