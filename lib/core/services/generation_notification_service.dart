import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class GenerationNotificationService {
  GenerationNotificationService._();
  static final GenerationNotificationService instance =
      GenerationNotificationService._();

  static const _generationChannelId = 'glaze_generation';
  static const _generationChannelName = 'Generation';
  static const _messageChannelId = 'glaze_message';
  static const _messageChannelName = 'New Messages';
  static const _messageNotificationId = 2001;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _navigationController =
      StreamController<String>.broadcast();

  bool _isGenerating = false;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  Stream<String> get navigationStream => _navigationController.stream;

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
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
        settings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
    } catch (_) {
      return;
    }

    if (Platform.isAndroid) {
      final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
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
    } else if (Platform.isIOS) {
      final iosPlugin = _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
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
  }

  void updateLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
  }

  Future<void> onGenerationStarted(String charName) async {
    _isGenerating = true;
    if (_isMobile) {
      try {
        if (!await FlutterForegroundTask.isRunningService) {
          await FlutterForegroundTask.startService(
            notificationTitle: charName,
            notificationText: 'Generating response...',
            callback: _foregroundTaskCallback,
          );
        }
      } catch (e) {
        debugPrint('NOTIF: foreground task start failed: $e');
      }
    }
  }

  Future<void> onGenerationCompleted(
    String charName,
    String charId, {
    String? messagePreview,
  }) async {
    _isGenerating = false;
    await _stopForegroundTask();

    if (_isMobile && _lifecycleState != AppLifecycleState.resumed) {
      await _showMessageNotification(charName, charId,
          messagePreview: messagePreview);
    }
  }

  Future<void> onGenerationAborted() async {
    _isGenerating = false;
    await _stopForegroundTask();
  }

  bool get isGenerating => _isGenerating;

  Future<void> _stopForegroundTask() async {
    if (_isMobile) {
      try {
        if (await FlutterForegroundTask.isRunningService) {
          await FlutterForegroundTask.stopService();
        }
      } catch (e) {
        debugPrint('NOTIF: foreground task stop failed: $e');
      }
    }
  }

  Future<void> _showMessageNotification(
    String charName,
    String charId, {
    String? messagePreview,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _messageChannelId,
      _messageChannelName,
      channelDescription: 'Notifications for new chat messages',
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
      icon: '@drawable/new_message',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final body = messagePreview ?? 'New message received';

    await _notifications.show(
      _messageNotificationId,
      charName,
      body,
      details,
      payload: 'chat:$charId',
    );
  }

  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.startsWith('chat:')) {
      final charId = payload.substring(5);
      _navigationController.add(charId);
    }
  }

  void dispose() {
    _navigationController.close();
  }
}

@pragma('vm:entry-point')
void _foregroundTaskCallback() {}
