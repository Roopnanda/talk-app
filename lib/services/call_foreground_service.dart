import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the microphone and Firestore signaling alive with the screen
/// off — both get suspended by Android otherwise, without this.
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
        // No real repeating work needed — the service existing at all is
        // what keeps things alive. A long, harmless repeat interval
        // stands in for "nothing," since that's the option with solid,
        // current confirmation behind it.
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: false,
        allowWifiLock: true,
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
