import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static const firebaseWebApiKey = String.fromEnvironment(
    'FIREBASE_WEB_API_KEY',
  );
  static const firebaseWebAppId = String.fromEnvironment(
    'FIREBASE_WEB_APP_ID',
    defaultValue: '1:591141449914:web:e40e11290732d577395283',
  );
  static const firebaseMessagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '591141449914',
  );
  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'fleteapp-8d8f7',
  );
  static const firebaseAuthDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
    defaultValue: 'fleteapp-8d8f7.firebaseapp.com',
  );
  static const firebaseStorageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
    defaultValue: 'fleteapp-8d8f7.firebasestorage.app',
  );

  static bool get isWebConfigured => firebaseWebApiKey.isNotEmpty;

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: firebaseWebApiKey,
    appId: firebaseWebAppId,
    messagingSenderId: firebaseMessagingSenderId,
    projectId: firebaseProjectId,
    authDomain: firebaseAuthDomain,
    storageBucket: firebaseStorageBucket,
  );
}
