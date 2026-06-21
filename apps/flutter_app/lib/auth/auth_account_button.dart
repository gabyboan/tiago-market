import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
const _googleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue:
      '99518273807-ru4jfdia2ku61a7vvhvvg3utc7vo6mqn.apps.googleusercontent.com',
);

final _googleSignIn = GoogleSignIn.instance;
bool _googleSignInInitialized = false;

Future<void> _initializeGoogleSignIn() async {
  if (_googleSignInInitialized) return;

  await _googleSignIn.initialize(
    clientId:
        defaultTargetPlatform == TargetPlatform.iOS ? _googleIosClientId : null,
    serverClientId: _googleWebClientId.isEmpty ? null : _googleWebClientId,
  );

  _googleSignInInitialized = true;
}

class GoogleAuthService {
  static Future<void> signIn() async {
    if (kIsWeb) {
      final launched = await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
      );
      if (!launched) {
        throw AuthException(
          'No se pudo abrir el flujo de inicio de sesión de Google.',
        );
      }
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS &&
        _googleIosClientId.isEmpty) {
      throw AuthException(
        'Falta configurar GOOGLE_IOS_CLIENT_ID en la aplicación.',
      );
    }

    if (_googleWebClientId.isEmpty) {
      throw AuthException(
        'Falta configurar GOOGLE_WEB_CLIENT_ID en la aplicación.',
      );
    }

    await _initializeGoogleSignIn();

    final GoogleSignInAccount googleAccount;
    try {
      googleAccount = await _googleSignIn.authenticate(
        scopeHint: const <String>['email', 'profile'],
      );
    } on PlatformException catch (error) {
      throw AuthException(_googleSignInErrorMessage(error));
    } on GoogleSignInException catch (error) {
      throw AuthException(_googleSignInErrorMessage(error));
    }

    final googleAuth = googleAccount.authentication;
    final idToken = googleAuth.idToken;

    if (idToken == null) {
      throw AuthException('Google no devolvió un ID token.');
    }

    await Supabase.instance.client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
  }

  static Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
    if (!kIsWeb) await _googleSignIn.signOut();
  }

  static Future<void> setRole(String role) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) throw AuthException('No hay una sesión activa.');
    await Supabase.instance.client.auth.updateUser(
      UserAttributes(data: {...?user.userMetadata, 'role': role}),
    );
  }
}

String _googleSignInErrorMessage(Object error) {
  final details = <String>[];
  String code = '';

  if (error is PlatformException) {
    code = error.code;
    if (error.message != null) details.add(error.message!);
    if (error.details != null) details.add(error.details.toString());
  } else if (error is GoogleSignInException) {
    code = error.code.name;
    if (error.description != null) details.add(error.description!);
    if (error.details != null) details.add(error.details.toString());
  } else {
    details.add(error.toString());
  }

  final detailText = details.join(' ');

  if ((code == 'sign_in_failed' && detailText.contains('e: 10')) ||
      detailText.contains('ApiException: 10') ||
      detailText.contains('DEVELOPER_ERROR')) {
    return 'Google rechazó la configuración de Android (ApiException 10). Revisá el SHA-1/SHA-256 de la firma en Firebase/Google Cloud y descargá el google-services.json actualizado.';
  }

  if (detailText.contains('ApiException: 12501') ||
      code == GoogleSignInExceptionCode.canceled.name) {
    return 'Inicio de sesión cancelado.';
  }

  if (detailText.contains('ApiException: 12500')) {
    return 'Google no pudo completar el inicio de sesión. Revisá que Google Play Services esté actualizado y que el cliente OAuth de Android esté bien configurado.';
  }

  final fallback = error is GoogleSignInException
      ? error.description
      : error is PlatformException
          ? error.message
          : null;

  return 'No se pudo iniciar sesión con Google: ${fallback ?? error.toString()}';
}

class GoogleSignInButton extends StatefulWidget {
  const GoogleSignInButton({super.key, this.expanded = false});

  final bool expanded;

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  bool _loading = false;

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      await GoogleAuthService.signIn();
    } on AuthException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('No se pudo iniciar sesión con Google: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final icon = _loading
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.login_rounded);
    final button = FilledButton.icon(
      onPressed: _loading ? null : _signIn,
      icon: icon,
      label: const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Text('Continuar con Google'),
      ),
    );
    return widget.expanded
        ? SizedBox(width: double.infinity, child: button)
        : button;
  }
}

class AuthAccountButton extends StatefulWidget {
  const AuthAccountButton({super.key, this.allowRoleChange = true});

  final bool allowRoleChange;

  @override
  State<AuthAccountButton> createState() => _AuthAccountButtonState();
}

class _AuthAccountButtonState extends State<AuthAccountButton> {
  late final StreamSubscription<AuthState> _authSubscription;
  User? _user;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final auth = Supabase.instance.client.auth;
    _user = auth.currentUser;
    _authSubscription = auth.onAuthStateChange.listen((event) {
      if (mounted) setState(() => _user = event.session?.user);
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      await GoogleAuthService.signIn();
    } on AuthException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('No se pudo iniciar sesión con Google: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _loading = true);
    try {
      await GoogleAuthService.signOut();
    } on AuthException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmRoleChange() async {
    final currentRole = _user?.userMetadata?['role'] as String?;
    final targetRole = currentRole == 'seller' ? 'buyer' : 'seller';
    final targetLabel = targetRole == 'buyer' ? 'comprador' : 'negocio';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar modo'),
        content: Text(
          'Vas a cambiar al modo $targetLabel. Podrás volver a cambiarlo desde tu cuenta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cambiar modo'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      await GoogleAuthService.setRole(targetRole);
    } on AuthException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      final icon = _loading
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.login_rounded);

      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: MediaQuery.sizeOf(context).width >= 600
            ? TextButton.icon(
                onPressed: _loading ? null : _signIn,
                icon: icon,
                label: const Text('Ingresar con Google'),
              )
            : IconButton(
                onPressed: _loading ? null : _signIn,
                icon: icon,
                tooltip: 'Ingresar con Google',
              ),
      );
    }

    final metadata = _user!.userMetadata ?? const <String, dynamic>{};
    final name = metadata['full_name'] as String? ??
        metadata['name'] as String? ??
        _user!.email ??
        'Mi cuenta';
    final avatarUrl = metadata['avatar_url'] as String?;

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: PopupMenuButton<String>(
        enabled: !_loading,
        tooltip: 'Cuenta de $name',
        onSelected: (value) {
          if (value == 'sign-out') _signOut();
          if (value == 'change-role') _confirmRoleChange();
        },
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            enabled: false,
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (widget.allowRoleChange)
            const PopupMenuItem<String>(
              value: 'change-role',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.swap_horiz_rounded),
                title: Text('Cambiar modo'),
              ),
            ),
          const PopupMenuItem<String>(
            value: 'sign-out',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.logout_rounded),
              title: Text('Cerrar sesión'),
            ),
          ),
        ],
        child: CircleAvatar(
          foregroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
          child: avatarUrl == null
              ? Text(name.characters.first.toUpperCase())
              : null,
        ),
      ),
    );
  }
}
