import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the microphone alive for the length of a call, and keeps
/// matching/signaling alive while waiting — both suspended by Android
/// once the screen turns off, without this.
class CallForegroundService {
  CallForegroundService._();
  static final CallForegroundService instance = CallForegroundService._();

  bool _initialized = false;
  bool _running = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'talk_call_channel',
        channelName: 'Ongoing call',
        channelDescription: 'Shown while matching or on a call, so the app keeps working with the screen off.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 60000,
        autoRunOnBoot: false,
        allowWifiLock: true, // stops the WiFi radio sleeping with the screen off, which can stall Firestore's realtime listeners
      ),
      printDevLog: false,
    );
  }

  /// Safe to call even if already running — it just does nothing in that
  /// case. Calling start() a second time (e.g. once on the matching
  /// screen, again when the call screen opens) previously risked a brief
  /// stop/restart gap right as WebRTC's signaling listeners were being
  /// set up, which is the likely cause of connections stalling until the
  /// screen was turned back on.
  Future<void> start() async {
    if (_running) return;
    await _ensureInitialized();

    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (Platform.isAndroid && !await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    await FlutterForegroundTask.startService(
      serviceId: 501,
      notificationTitle: 'Talk — call in progress',
      notificationText: 'Tap to return to your call.',
      callback: startCallback,
    );
    _running = true;
  }

  Future<void> stop() async {
    if (!_running) return;
    await FlutterForegroundTask.stopService();
    _running = false;
  }
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(_CallTaskHandler());
}

class _CallTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
