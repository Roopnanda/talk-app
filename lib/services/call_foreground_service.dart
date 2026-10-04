import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the microphone, Firestore signaling, AND the actual WebRTC/ICE
/// networking alive with the screen off. allowWifiLock alone kept the
/// radio awake but not the CPU — ICE candidate gathering specifically
/// needs active CPU processing to handle network callbacks, which is
/// what allowWakeLock addresses.
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
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: false,
        allowWifiLock: true,
        allowWakeLock: true, // keeps the CPU itself active, not just the WiFi radio — the likely missing piece
      ),
    );
  }

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
      notificationTitle: 'Talk is active',
      notificationText: 'Keeping your connection alive in the background.',
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
