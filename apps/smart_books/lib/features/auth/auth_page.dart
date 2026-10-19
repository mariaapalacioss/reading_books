import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../core/supabase/supabase_auth_log.dart';
import '../../core/supabase/supabase_password_auth.dart';
import '../../core/theme/app_tokens.dart';
import '../setup/supabase_config_screen.dart';
import '../shared/bookifi_ui.dart';
import 'auth_chatgpt_section.dart';
import 'auth_errors.dart';
import 'auth_shell.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  var _modeCreate = false;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  var _busy = false;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!AppConfig.supabaseReady) return;
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final email = _email.text.trim();
      supabaseAuthLog(
        'signInWithPassword intent=${_modeCreate ? "signup" : "login"} host=${Uri.parse(AppConfig.supabaseUrl).host} emailDomain=${email.contains("@") ? email.split("@").last : "?"}',
      );
      final passwordAuth = SupabasePasswordAuth();
      if (_modeCreate) {
        final displayName = _name.text.trim();
        final result = await passwordAuth.signUp(
          email: email,
          password: _password.text,
          data: displayName.isEmpty ? null : {'display_name': displayName},
        );
        if (result.session == null) {
          if (mounted) {
            setState(
              () => _message =
                  'Cuenta creada. Si la confirmación por correo está activa, abre el enlace antes de entrar.',
            );
          }
        } else if (mounted) {
          await _afterAuth();
        }
      } else {
        await passwordAuth.signInWithPassword(
          email: email,
          password: _password.text,
        );
        supabaseAuthLog('signInWithPassword OK');
        if (mounted) await _afterAuth();
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final emailCtrl = TextEditingController(text: _email.text.trim());
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Recuperar contraseña'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Te enviaremos un enlace a tu correo para restablecer la contraseña.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Correo',
                  hintText: 'tu@correo.com',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enviar enlace'),
            ),
          ],
        );
      },
    );
    final email = emailCtrl.text.trim();
    emailCtrl.dispose();
    if (sent != true || email.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await SupabasePasswordAuth().resetPasswordForEmail(email: email);
      if (mounted) {
        setState(
          () => _message =
              'Te enviamos un enlace para restablecer tu contraseña.',
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e));
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _afterAuth() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      await ref.read(chatGptAuthServiceProvider).adoptPendingForUser(userId);
      ref.invalidate(chatGptLinkProvider);
      ref.invalidate(chatGptCredentialsProvider);
    }
    if (!mounted) return;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.supabaseReady) {
      return const SupabaseConfigScreen();
    }

    return AuthShell(
      title: _modeCreate ? 'Crea tu cuenta' : 'Bienvenida de vuelta',
      subtitle: _modeCreate
          ? 'Tu biblioteca privada en Supabase. Cada usuario tiene libros y datos separados.'
          : 'Ingresa a tu biblioteca privada y continúa tu lectura.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthDividerLabel('Acceso a tu biblioteca'),
            AuthModeSegment(
              createMode: _modeCreate,
              onChanged: (v) => setState(() => _modeCreate = v),
            ),
            const SizedBox(height: 12),
            if (_modeCreate)
              AuthTextField(
                label: 'Nombre',
                controller: _name,
                placeholder: 'Tu nombre',
                autofillHints: const [AutofillHints.name],
              ),
            AuthTextField(
              label: 'Correo',
              controller: _email,
              icon: Icons.alternate_email_outlined,
              keyboardType: TextInputType.emailAddress,
              placeholder: 'tu@correo.com',
              autofillHints: const [AutofillHints.email],
            ),
            AuthPasswordField(
              controller: _password,
              onSubmit: _submit,
              autofillHints: _modeCreate
                  ? const [AutofillHints.newPassword]
                  : const [AutofillHints.password],
            ),
            if (!_modeCreate)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : _forgotPassword,
                  child: const Text('¿Olvidaste tu contraseña?'),
                ),
              ),
            if (_error != null) AuthInlineError(_error!),
            if (_message != null) ...[
              const SizedBox(height: 4),
              Text(
                _message!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTokens.teal,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: BookifiPrimaryButton(
                label: _busy
                    ? 'Verificando…'
                    : (_modeCreate ? 'Crear cuenta' : 'Entrar'),
                loading: _busy,
                onPressed: _busy ? null : _submit,
              ),
            ),
            const AuthChatGptSection(),
          ],
        ),
      ),
    );
  }
}
