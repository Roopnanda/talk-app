import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class CallForegroundService {
  CallForegroundService._();
  static final CallForegroundService instance = CallForegroundService._();

  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'talk_call_channel',
        channelName: 'Ongoing call',
        channelDescription: 'Shown while a voice call is active, so the microphone keeps working.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // No repeating work needed; the service existing keeps the mic alive.
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWifiLock: false,
      ),
    );
  }

  Future<void> start() async {
    await _ensureInitialized();

    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    await FlutterForegroundTask.startService(
      serviceId: 501,
      serviceTypes: [ForegroundServiceTypes.microphone],
      notificationTitle: 'Talk — call in progress',
      notificationText: 'Tap to return to your call.',
      callback: startCallback,
    );
  }

  Future<void> stop() async {
    await FlutterForegroundTask.stopService();
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
