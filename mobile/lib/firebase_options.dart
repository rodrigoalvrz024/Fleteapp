import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static const firebaseWebApiKey = String.fromEnvironment(
    'FIREBASE_WEB_API_KEY',
  );

  static bool get isWebConfigured => firebaseWebApiKey.isNotEmpty;

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: firebaseWebApiKey,
    appId: '1:591141449914:web:e40e11290732d577395283',
    messagingSenderId: '591141449914',
    projectId: 'fleteapp-8d8f7',
    authDomain: 'fleteapp-8d8f7.firebaseapp.com',
    storageBucket: 'fleteapp-8d8f7.firebasestorage.app',
  );
}
