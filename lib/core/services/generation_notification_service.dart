import 'dart:async';
import 'dart:io';
import 'dart:ui';

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

  Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

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
    }

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _generationChannelId,
        channelName: _generationChannelName,
        channelDescription: 'Shown while generating a response',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
      ),
    );
  }

  void updateLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
  }

  Future<void> onGenerationStarted() async {
    _isGenerating = true;
    if (Platform.isAndroid) {
      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.startService(
          notificationTitle: 'Glaze',
          notificationText: 'Generating response...',
          callback: _foregroundTaskCallback,
        );
      }
    }
  }

  Future<void> onGenerationCompleted(
    String charName,
    String charId,
  ) async {
    _isGenerating = false;
    if (Platform.isAndroid) {
      if (await FlutterForegroundTask.isRunningService) {
        FlutterForegroundTask.stopService();
      }
    }

    if (_lifecycleState != AppLifecycleState.resumed) {
      await _showMessageNotification(charName, charId);
    }
  }

  Future<void> onGenerationAborted() async {
    _isGenerating = false;
    if (Platform.isAndroid) {
      if (await FlutterForegroundTask.isRunningService) {
        FlutterForegroundTask.stopService();
      }
    }
  }

  bool get isGenerating => _isGenerating;

  Future<void> _showMessageNotification(
    String charName,
    String charId,
  ) async {
    const androidDetails = AndroidNotificationDetails(
      _messageChannelId,
      _messageChannelName,
      channelDescription: 'Notifications for new chat messages',
      importance: Importance.high,
      priority: Priority.high,
      autoCancel: true,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      _messageNotificationId,
      charName,
      'New message received',
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
