// Generated from your real Firebase project (talk-app-f9b3c).
// Android-only for now — the `ios` branch below is left unconfigured
// since no iOS app was registered in the Firebase console yet.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web is not configured for this project yet.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError('iOS is not configured for this project yet.');
      default:
        throw UnsupportedError('Unsupported platform for this project.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDpYPKx5mbtTGnhBPR3YtKj6wH6vtC546M',
    appId: '1:567602063613:android:b42f86ca895cb98b38b694',
    messagingSenderId: '567602063613',
    projectId: 'talk-app-f9b3c',
    storageBucket: 'talk-app-f9b3c.firebasestorage.app',
  );
}
