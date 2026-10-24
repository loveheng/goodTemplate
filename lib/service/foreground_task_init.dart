import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// 前台服务统一通道（含真机踩坑结论：Doze 下 MCP 应答须持 CPU 键+Wi-Fi 键，
/// 无锁即假死超时）。
///
/// `flutter_foreground_task` 仅支持单个前台服务实例，故集中初始化，
/// 避免多处各自 `init` 互相覆盖或冲突；各自按需 `startService` 拉起。
const String fgChannelId = 'app_fg';
const String fgChannelName = 'MCP 后台任务';
const String fgChannelDesc = 'MCP 服务后台应答通知';

bool _initialized = false;

/// 幂等初始化前台服务：常驻服务（如 MCP）均应先调此，再由各自 `startService` 拉起。
Future<void> ensureForegroundTaskInit() async {
  if (_initialized) return;
  _initialized = true;
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: fgChannelId,
      channelName: fgChannelName,
      channelDescription: fgChannelDesc,
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(showNotification: true),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      // MCP 服务须在 Doze 深度休眠下仍可应答桌面客户端：持 CPU 锁防 accept 线程
      // 被挂起，持 Wi-Fi 锁防 Wi-Fi 休眠断链（真机 force-idle 实测：无锁即假死超时）。
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}
