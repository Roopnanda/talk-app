import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the microphone alive for the length of a call. Without this,
/// Android suspends microphone access once the screen turns off — a
/// deliberate platform restriction (from Android 14 onward), not
/// something wrong with the app. A foreground service with a visible
/// notification is the only sanctioned way around it.
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
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 60000, // no repeating work needed — a long interval just avoids extra wakeups
        autoRunOnBoot: false,
        allowWifiLock: false,
      ),
      printDevLog: false,
    );
  }

  /// Call this right when a call starts, while the app is clearly in the
  /// foreground — Android does not allow a microphone-type foreground
  /// service to be started once the app is already backgrounded.
  Future<void> start() async {
    await _ensureInitialized();

    final permission = await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    await FlutterForegroundTask.startService(
      serviceId: 501,
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

/// No periodic work needed — the service existing at all is what keeps
/// the microphone alive. This just satisfies the plugin's required API.
class _CallTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
