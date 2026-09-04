import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';

// ─── Background message handler (MUST be top-level function) ─────────────────
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // Android/iOS system tray handles display automatically.
  // Nothing extra needed here — FCM renders the notification for us.
}

// ─── Notification channels ────────────────────────────────────────────────────
const _orderChannel = AndroidNotificationChannel(
  'order_updates',
  'Order Updates',
  description: 'Notifications about your order status',
  importance: Importance.high,
  playSound: true,
);

const _promoChannel = AndroidNotificationChannel(
  'promotions',
  'Offers & Promotions',
  description: 'Deals and promotional offers',
  importance: Importance.defaultImportance,
);

// ─── NotificationService ──────────────────────────────────────────────────────
class NotificationService {
  NotificationService._();
  static final NotificationService _instance = NotificationService._();
  static NotificationService get instance => _instance;

  FirebaseMessaging? get _fcm {
    try {
      return FirebaseMessaging.instance;
    } catch (_) {
      return null;
    }
  }

  final FlutterLocalNotificationsPlugin _localNotif =
      FlutterLocalNotificationsPlugin();

  // Navigation callback — set from main.dart
  static void Function(String route, {Object? arguments})? onNavigate;

  // ─── Initialize ───────────────────────────────────────────────────────────
  Future<void> initialize() async {
    try {
      // 1. Setup local notifications
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _localNotif.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      final fcm = _fcm;
      if (fcm != null) {
        // 2. Configure iOS foreground presentation options
        await fcm.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );

        // 3. Handle FCM foreground messages
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

        // 4. Handle notification tap when app is in background (not closed)
        FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

        // 5. Handle notification tap when app was fully closed
        final initialMessage = await fcm.getInitialMessage();
        if (initialMessage != null) {
          _handleNotificationTap(initialMessage);
        }
      }

      // Create Android notification channels
      final androidPlugin = _localNotif
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_orderChannel);
      await androidPlugin?.createNotificationChannel(_promoChannel);
    } catch (e) {
      debugPrint('[NotificationService] Initialize error: $e');
    }
  }

  // ─── Request permission ────────────────────────────────────────────────────
  Future<bool> requestPermission() async {
    try {
      // Request local notification permissions on iOS
      if (Platform.isIOS) {
        final iosPlugin = _localNotif
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>();
        await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      final fcm = _fcm;
      if (fcm != null) {
        final settings = await fcm.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        return settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
      }
      return false;
    } catch (e) {
      debugPrint('[NotificationService] Request permission error: $e');
      return false;
    }
  }

  // ─── Get FCM token and register with backend ───────────────────────────────
  Future<void> getAndRegisterToken() async {
    try {
      final fcm = _fcm;
      if (fcm == null) return;

      // On iOS, wait for APNs token before requesting FCM token
      if (Platform.isIOS) {
        String? apnsToken = await fcm.getAPNSToken();
        int retryCount = 0;
        while (apnsToken == null && retryCount < 6) {
          debugPrint('[FCM] Waiting for APNs token... retry $retryCount');
          await Future.delayed(const Duration(milliseconds: 1000));
          apnsToken = await fcm.getAPNSToken();
          retryCount++;
        }
        if (apnsToken != null) {
          debugPrint('[FCM] APNs token received: $apnsToken');
        } else {
          debugPrint('[FCM] Warning: APNs token not received yet. FCM getToken might fail or fallback.');
        }
      }

      final token = await fcm.getToken();
      if (token != null) {
        debugPrint('[FCM] FCM Token obtained: $token');
        final platform = Platform.isIOS ? 'ios' : 'android';

        // 1. Register device token (accessible for all devices, including guests)
        try {
          await ApiService.registerDeviceToken(token: token, platform: platform);
          debugPrint('[FCM] Device token registered to backend ($platform).');
        } catch (e) {
          debugPrint('[FCM] Failed to register device token: $e');
        }

        // 2. Also register user token if logged in
        try {
          await ApiService.registerFCMToken(token);
          debugPrint('[FCM] User FCM token registered to backend.');
        } catch (e) {
          debugPrint('[FCM] User FCM token registration skipped/failed: $e');
        }
      } else {
        debugPrint('[FCM] Warning: _fcm.getToken() returned null');
      }

      // Listen for token refresh (e.g., app reinstall, token rotation)
      fcm.onTokenRefresh.listen((newToken) async {
        try {
          debugPrint('[FCM] Token refreshed: $newToken');
          final platform = Platform.isIOS ? 'ios' : 'android';
          await ApiService.registerDeviceToken(token: newToken, platform: platform);
          await ApiService.registerFCMToken(newToken);
        } catch (e) {
          debugPrint('[FCM] Error updating refreshed token: $e');
        }
      });
    } catch (e, stack) {
      debugPrint('[FCM] Error in getAndRegisterToken: $e\n$stack');
    }
  }

  // ─── Show a local heads-up notification ───────────────────────────────────
  Future<void> showLocalNotification({
    required String title,
    required String body,
    String channelId = 'order_updates',
    String? payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelId == 'order_updates' ? 'Order Updates' : 'Offers & Promotions',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: true,
    );
    final notifDetails = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    await _localNotif.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      notifDetails,
      payload: payload,
    );
  }

  // ─── Internal: foreground FCM message received ────────────────────────────
  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification != null) {
      final channelId = message.data['channel'] ?? 'order_updates';
      showLocalNotification(
        title: notification.title ?? 'FreshInBasket',
        body: notification.body ?? '',
        channelId: channelId,
        payload: message.data['route'],
      );
    }
  }

  // ─── Internal: user tapped a notification (background / closed) ───────────
  void _handleNotificationTap(RemoteMessage message) {
    final route = message.data['route'];
    if (route != null && onNavigate != null) {
      // Navigate to orders tab (index 3) when order notification is tapped
      if (route == 'orders') {
        onNavigate!('/main', arguments: 3);
      } else {
        onNavigate!(route);
      }
    }
  }

  // ─── Internal: local notification tapped ──────────────────────────────────
  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && onNavigate != null) {
      if (payload == 'orders') {
        onNavigate!('/main', arguments: 3);
      } else {
        onNavigate!(payload);
      }
    }
  }
}
