import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationNavigationData {
  final String charId;
  final String? sessionId;
  final String? msgId;

  const NotificationNavigationData({
    required this.charId,
    this.sessionId,
    this.msgId,
  });
}

class GenerationNotificationService {
  GenerationNotificationService._();
  static final GenerationNotificationService instance =
      GenerationNotificationService._();

  static const _generationChannelId = 'glaze_generation';
  static const _generationChannelName = 'Generation';
  static const _messageChannelId = 'glaze_message';
  static const _messageChannelName = 'New Messages';
  static const _iosAudioChannel = MethodChannel(
    'com.hydall.glaze/background_audio',
  );

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<NotificationNavigationData> _navigationController =
      StreamController<NotificationNavigationData>.broadcast();

  bool _isGenerating = false;
  bool _initialized = false;
  int _foregroundHoldCount = 0;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  NotificationNavigationData? _pendingNotificationData;
  String? _activeCharId;
  String? _activeSessionId;

  Stream<NotificationNavigationData> get navigationStream =>
      _navigationController.stream;

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Stable notification ID in range 1..2147483646, mirrors Vue stableIdFromString.
  int _stableId(String str) {
    int hash = 0;
    for (int i = 0; i < str.length; i++) {
      hash = ((hash << 5) - hash) + str.codeUnitAt(i);
      hash = hash.toSigned(32);
    }
    return (hash.abs() % 2147483646) + 1;
  }

  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings(
      '@drawable/ic_stat_icon_config_sample',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _notifications.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
      _initialized = true;
    } catch (e, st) {
      debugPrint('NOTIF: initialize failed: $e\n$st');
      return;
    }

    try {
      if (!kIsWeb && Platform.isAndroid) {
        final androidPlugin = _notifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        if (androidPlugin != null) {
          await androidPlugin.createNotificationChannel(
            const AndroidNotificationChannel(
              _messageChannelId,
              _messageChannelName,
              description: 'Notifications for new chat messages',
              importance: Importance.high,
            ),
          );
          await androidPlugin.requestNotificationsPermission();
        }
      } else if (!kIsWeb && Platform.isIOS) {
        final iosPlugin = _notifications
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      if (_isMobile) {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: _generationChannelId,
            channelName: _generationChannelName,
            channelDescription: 'Shown while generating a response',
            channelImportance: NotificationChannelImportance.LOW,
            priority: NotificationPriority.LOW,
          ),
          iosNotificationOptions: const IOSNotificationOptions(
            showNotification: false,
            playSound: false,
          ),
          foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.nothing(),
            allowWakeLock: true,
          ),
        );
      }

      // Restore pending data when app is cold-launched from a notification tap.
      final launchDetails = await _notifications
          .getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        final payload = launchDetails!.notificationResponse?.payload;
        if (payload != null) _pendingNotificationData = _parsePayload(payload);
      }
    } catch (e, st) {
      debugPrint('NOTIF: platform init failed: $e\n$st');
    }
  }

  void updateLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
  }

  /// Call when the user opens / focuses a chat screen to suppress redundant
  /// notifications for that character+session. Pass nulls when leaving.
  void setActiveContext(String? charId, String? sessionId) {
    _activeCharId = charId;
    _activeSessionId = sessionId;
  }

  Future<void> onGenerationStarted(String charName) async {
    _isGenerating = true;
    await _acquireForeground(
      notificationTitle: charName,
      notificationText: 'Generating response...',
    );
  }

  Future<void> onGenerationCompleted(
    String charName,
    String charId, {
    String? messagePreview,
    String? sessionId,
    String? msgId,
    String? avatarPath,
  }) async {
    _isGenerating = false;
    await _releaseForeground();

    if (_isMobile && _lifecycleState != AppLifecycleState.resumed) {
      await sendMessageNotification(
        charName,
        messagePreview ?? 'New message received',
        avatarPath,
        charId,
        sessionId: sessionId,
        msgId: msgId,
      );
    }
  }

  Future<void> onGenerationAborted() async {
    _isGenerating = false;
    await _releaseForeground();
  }

  Future<void> onSyncStarted() async {
    await _acquireForeground(
      notificationTitle: 'Glaze',
      notificationText: 'Syncing with cloud...',
    );
  }

  Future<void> onSyncFinished() async {
    await _releaseForeground();
  }

  bool get isGenerating => _isGenerating;

  /// Shows a message notification. Suppressed while the app is foregrounded
  /// and the user is viewing the same charId+sessionId (mirrors Vue.js
  /// visibility + activeContext check).
  Future<void> sendMessageNotification(
    String title,
    String body,
    String? avatarPath,
    String charId, {
    String? sessionId,
    String? msgId,
  }) async {
    if (_lifecycleState == AppLifecycleState.resumed) {
      if (_activeCharId == charId &&
          (sessionId == null || _activeSessionId == sessionId)) {
        return;
      }
    }

    if (!_isMobile || !_initialized) return;

    try {
      final notifId = _stableId(charId);
      final payload = _buildPayload(charId, sessionId, msgId);

      final NotificationDetails details;
      if (Platform.isAndroid) {
        final personIcon = avatarPath != null && File(avatarPath).existsSync()
            ? BitmapFilePathAndroidIcon(avatarPath)
            : null;
        final person = Person(name: title, icon: personIcon);
        final messagingStyle = MessagingStyleInformation(
          person,
          messages: [Message(body, DateTime.now(), person)],
          conversationTitle: title,
        );
        details = NotificationDetails(
          android: AndroidNotificationDetails(
            _messageChannelId,
            _messageChannelName,
            channelDescription: 'Notifications for new chat messages',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: messagingStyle,
            icon: '@drawable/new_message',
            autoCancel: true,
            groupKey: charId,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        );
      } else {
        final attachments = avatarPath != null && File(avatarPath).existsSync()
            ? [DarwinNotificationAttachment(avatarPath)]
            : <DarwinNotificationAttachment>[];
        details = NotificationDetails(
          iOS: DarwinNotificationDetails(
            attachments: attachments,
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        );
      }

      await _notifications.show(
        id: notifId,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    } catch (e) {
      debugPrint('NOTIF: sendMessageNotification failed: $e');
    }
  }

  /// Cancels delivered notifications for a character (e.g. when the user
  /// opens that chat). Mirrors Vue.js clearMessageNotifications.
  Future<void> clearMessageNotifications(String charId) async {
    if (!_isMobile) return;
    try {
      await _notifications.cancel(id: _stableId(charId));
    } catch (e) {
      debugPrint('NOTIF: clearMessageNotifications failed: $e');
    }
  }

  /// Returns and clears the notification data from the last tap — used to
  /// navigate on app launch from a background/terminated notification.
  NotificationNavigationData? consumePendingNotificationData() {
    final data = _pendingNotificationData;
    _pendingNotificationData = null;
    return data;
  }

  Future<void> _acquireForeground({
    required String notificationTitle,
    required String notificationText,
  }) async {
    if (!_isMobile) return;
    _foregroundHoldCount++;
    if (_foregroundHoldCount > 1) return;
    try {
      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.startService(
          notificationTitle: notificationTitle,
          notificationText: notificationText,
          notificationIcon: const NotificationIcon(
            metaDataName: 'com.hydall.glaze.ic_generation',
          ),
          callback: _foregroundTaskCallback,
        );
      }
    } catch (e) {
      debugPrint('NOTIF: foreground task start failed: $e');
    }
    await _startSilentAudio();
  }

  Future<void> _releaseForeground() async {
    if (!_isMobile) return;
    if (_foregroundHoldCount <= 0) return;
    _foregroundHoldCount--;
    if (_foregroundHoldCount > 0) return;
    await _stopForegroundTask();
  }

  Future<void> _stopForegroundTask() async {
    if (_isMobile) {
      try {
        if (await FlutterForegroundTask.isRunningService) {
          await FlutterForegroundTask.stopService();
        }
      } catch (e) {
        debugPrint('NOTIF: foreground task stop failed: $e');
      }
      await _stopSilentAudio();
    }
  }

  Future<void> _startSilentAudio() async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await _iosAudioChannel.invokeMethod<void>('start');
    } catch (e) {
      debugPrint('NOTIF: silent audio start failed: $e');
    }
  }

  Future<void> _stopSilentAudio() async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await _iosAudioChannel.invokeMethod<void>('stop');
    } catch (e) {
      debugPrint('NOTIF: silent audio stop failed: $e');
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    final data = _parsePayload(payload);
    if (data != null) {
      _pendingNotificationData = data;
      _navigationController.add(data);
    }
  }

  NotificationNavigationData? _parsePayload(String payload) {
    if (!payload.startsWith('chat:')) return null;
    final parts = payload.substring(5).split(':');
    if (parts.isEmpty || parts[0].isEmpty) return null;
    return NotificationNavigationData(
      charId: parts[0],
      sessionId: parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null,
      msgId: parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null,
    );
  }

  String _buildPayload(String charId, String? sessionId, String? msgId) =>
      'chat:$charId:${sessionId ?? ''}:${msgId ?? ''}';

  void dispose() {
    _navigationController.close();
  }
}

@pragma('vm:entry-point')
void _foregroundTaskCallback() {}
