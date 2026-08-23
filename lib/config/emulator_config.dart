import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Flip this by hand when you want to point the app at local emulators
/// instead of your real Firebase project. Off by default — you're
/// testing on a real phone against the real talk-app-f9b3c project, and
/// no emulator suite is running anywhere the phone could reach anyway.
/// Only flip this on once you're deliberately running
/// `firebase emulators:start` somewhere reachable from wherever the app
/// is running.
///
/// The `&& kDebugMode` guard below is deliberate and not just decoration:
/// even if someone forgets this set to `true` before a release build,
/// Flutter strips debug-only code paths in release mode, so it can never
/// ship and point real users' data at your laptop.
const bool _wantEmulators = false;

bool get useFirebaseEmulators => _wantEmulators && kDebugMode;

/// Call once, right after Firebase.initializeApp() and before anything
/// else touches Auth or Firestore.
void connectToEmulatorsIfEnabled() {
  if (!useFirebaseEmulators) return;

  final host = _emulatorHost();

  FirebaseAuth.instance.useAuthEmulator(host, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);

  // No client-side wiring needed for the Functions emulator: this app
  // never calls a function directly — the one Cloud Function
  // (onReportCreated) only listens to Firestore, and `firebase
  // emulators:start` automatically makes local Firestore trigger the
  // local function. It just needs to be running alongside the others.

  // ignore: avoid_print
  print('🔧 Using Firebase EMULATORS at $host (auth:9099, firestore:8080)');
}

/// Android's emulator runs in its own virtual network, so "localhost"
/// from inside it means the emulator itself, not your dev machine —
/// 10.0.2.2 is the special alias Android provides for that. iOS
/// simulators and web share your machine's network directly, so
/// "localhost" works as-is there.
///
/// Testing on a PHYSICAL device instead of a simulator? Neither of these
/// works — replace the return value with your dev machine's LAN IP
/// (e.g. 192.168.1.23) and start emulators with `--host 0.0.0.0` so
/// they accept connections from other devices on the network.
String _emulatorHost() {
  if (kIsWeb) return 'localhost';
  if (Platform.isAndroid) return '10.0.2.2';
  return 'localhost';
}
