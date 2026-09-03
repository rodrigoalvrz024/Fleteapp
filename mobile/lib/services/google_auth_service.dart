import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthException implements Exception {
  final String message;

  const GoogleAuthException(this.message);

  @override
  String toString() => message;
}

/// Requests only a short-lived Google ID token. Muvv never receives a Google
/// password or an OAuth client secret; the API validates this token server-side.
class GoogleAuthService {
  static const _serverClientId = String.fromEnvironment(
    'GOOGLE_OAUTH_CLIENT_ID',
  );
  static Future<void>? _initialization;

  Future<String?> requestIdToken() async {
    final clientId = _serverClientId.trim();
    if (clientId.isEmpty) {
      throw const GoogleAuthException(
        'El acceso con Google aun no esta configurado.',
      );
    }

    try {
      await (_initialization ??= GoogleSignIn.instance.initialize(
        serverClientId: clientId,
      ));
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw const GoogleAuthException(
          'El acceso con Google se habilitara pronto en esta plataforma.',
        );
      }

      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const GoogleAuthException(
          'Google no entrego una credencial valida. Intenta nuevamente.',
        );
      }
      return idToken;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      throw const GoogleAuthException(
        'No pudimos completar el acceso con Google. Intenta nuevamente.',
      );
    }
  }
}
