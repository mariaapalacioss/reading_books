import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../chatgpt/chatgpt_platform.dart';
import '../chatgpt/chatgpt_verify_service.dart';
import '../shared/bookifi_ui.dart';
import 'auth_shell.dart';

/// Bloque «Conectar con ChatGPT» en la pantalla de bienvenida (sin requerir Supabase).
class AuthChatGptSection extends ConsumerStatefulWidget {
  const AuthChatGptSection({super.key});

  @override
  ConsumerState<AuthChatGptSection> createState() => _AuthChatGptSectionState();
}

class _AuthChatGptSectionState extends ConsumerState<AuthChatGptSection> {
  var _busy = false;
  String? _error;
  ChatGptVerifyResult? _verify;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _verifyIfLinked());
  }

  Future<void> _verifyIfLinked() async {
    final link = await ref.read(chatGptLinkProvider.future);
    if (link.connected && mounted) await _runVerify();
  }

  Future<void> _connect() async {
    if (!chatGptConnectEnabled) return;
    setState(() {
      _busy = true;
      _error = null;
      _verify = null;
    });
    try {
      final sessionUser = ref.read(supabaseClientProvider).auth.currentUser?.id;
      await ref
          .read(chatGptAuthServiceProvider)
          .signInOrLink(sessionUserId: sessionUser);
      if (!mounted) return;
      ref.invalidate(chatGptLinkProvider);
      ref.invalidate(chatGptCredentialsProvider);
      await _runVerify();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyChatGptError(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _runVerify() async {
    final result = await ref.read(chatGptVerifyServiceProvider).verify();
    if (mounted) setState(() => _verify = result);
  }

  Future<void> _disconnect() async {
    final sessionUser = ref.read(supabaseClientProvider).auth.currentUser?.id;
    final service = ref.read(chatGptAuthServiceProvider);
    if (sessionUser != null) {
      await service.signOut(sessionUser);
    } else {
      await service.signOutPending();
    }
    if (!mounted) return;
    ref.invalidate(chatGptLinkProvider);
    ref.invalidate(chatGptCredentialsProvider);
    setState(() {
      _error = null;
      _verify = null;
    });
  }

  String _friendlyChatGptError(Object e) {
    return e
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('UnsupportedError: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final link = ref.watch(chatGptLinkProvider);
    final platformOk = chatGptConnectEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthDividerLabel('ChatGPT Plus'),
        Text(
          platformOk
              ? 'Cuenta independiente de Smart Books. Puedes conectarla antes o después de entrar a la biblioteca.'
              : chatGptPlatformLabel(chatGptPlatformSupport()),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        link.when(
          loading: () =>
              const SizedBox(height: 4, child: LinearProgressIndicator()),
          error: (e, _) => AuthInlineError(e.toString()),
          data: (state) {
            if (state.connected) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BookifiCallout(
                    'ChatGPT conectado · ${state.label}',
                    good: true,
                  ),
                  if (_verify != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _verify!.summary,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _verify!.ok
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.error,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: BookifiGhostButton(
                          label: 'Probar conexión',
                          onPressed: _busy ? null : _runVerify,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: BookifiGhostButton(
                          label: 'Desconectar ChatGPT',
                          danger: true,
                          onPressed: _busy ? null : _disconnect,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }
            if (!platformOk) {
              return const AuthInlineError(
                'ChatGPT Plus requiere iPhone, iPad o Mac con el flujo loopback OSS.',
              );
            }
            return BookifiPrimaryButton(
              label: _busy
                  ? 'Esperando en el navegador…'
                  : 'Conectar con ChatGPT',
              loading: _busy,
              onPressed: _busy ? null : _connect,
            );
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          AuthInlineError(_error!),
        ],
      ],
    );
  }
}
