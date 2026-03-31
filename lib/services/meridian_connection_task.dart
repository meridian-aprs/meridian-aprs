import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Entry point called by flutter_foreground_task when the foreground service
/// starts. Runs in the background isolate.
///
/// Must be a top-level function annotated with @pragma('vm:entry-point') to
/// prevent tree-shaking in release builds.
@pragma('vm:entry-point')
void startMeridianConnectionTask() {
  FlutterForegroundTask.setTaskHandler(MeridianConnectionTask());
}

/// Minimal [TaskHandler] that keeps the Android foreground service alive.
///
/// This handler intentionally contains no application logic. Its sole purpose
/// is to satisfy the Android foreground service lifecycle requirement so that
/// the OS does not kill the app process while it is backgrounded.
///
/// All transport, beaconing, and packet-processing logic continues to run in
/// the main Dart isolate via the existing service layer (TncService,
/// StationService, BeaconingService). The [BackgroundServiceManager] on the
/// main isolate owns notification content and calls
/// [FlutterForegroundTask.updateService] directly.
///
/// The [onRepeatEvent] fires every 60 seconds as a heartbeat. This prevents
/// aggressive OEM firmware (MIUI, OneUI) from terminating services that show
/// no activity.
class MeridianConnectionTask extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Intentionally empty. Main isolate services handle all state.
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Heartbeat — keeps the service alive on aggressive OEMs.
    // No app logic runs here.
  }

  @override
  void onReceiveData(Object data) {
    // Reserved for future bidirectional communication, e.g. notification
    // button actions (Send Beacon, Disconnect). Unused in v0.7.
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    // Intentionally empty. Main isolate services manage their own teardown.
  }
}
