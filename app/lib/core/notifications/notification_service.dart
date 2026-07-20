/// Local notifications for transit alerts (opt-in — RF/onboarding "alertas").
///
/// Two kinds of alert:
///  * scheduled — satellite passes are deterministic, so once the user enables
///    alerts we schedule a local notification `lead` minutes before each
///    upcoming pass (survives app close / reboot via the plugin's receivers);
///  * immediate — a live aircraft candidate detected while the app is open.
///
/// All times are anchored in UTC instants (`tz.UTC`), so device timezone
/// changes never shift an alarm.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Ids for scheduled pass alerts live in this range so they can be cancelled
  /// without touching immediate alerts.
  static const _passIdBase = 100000;
  static const _passIdRange = 1000;
  static const _liveId = 1;

  static const _passChannel = AndroidNotificationDetails(
    'transit_pass_alerts',
    'Alertas de passagens',
    channelDescription:
        'Avisos antes de trânsitos previstos de satélites (ISS, Tiangong).',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.reminder,
  );

  static const _liveChannel = AndroidNotificationDetails(
    'transit_live_alerts',
    'Trânsitos ao vivo',
    channelDescription:
        'Avisos imediatos quando um avião tem trânsito provável no seu céu.',
    importance: Importance.max,
    priority: Priority.high,
    category: AndroidNotificationCategory.event,
  );

  Future<void> init() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  /// Requests the runtime notification permission (Android 13+ / iOS) inside
  /// the app. Returns true when notifications may be shown.
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? true;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final granted =
          await ios.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    return true;
  }

  /// Replaces every scheduled pass alert with the given batch.
  /// [passes] carries `(whenUtc, title, body)` already offset by the lead time.
  Future<void> reschedulePassAlerts(
    List<({DateTime whenUtc, String title, String body})> passes,
  ) async {
    await init();
    await cancelPassAlerts();
    final now = DateTime.now().toUtc();
    var id = _passIdBase;
    for (final p in passes) {
      if (p.whenUtc.isBefore(now)) continue;
      if (id >= _passIdBase + _passIdRange) break;
      final when = tz.TZDateTime.from(p.whenUtc, tz.UTC);
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: p.title,
          body: p.body,
          scheduledDate: when,
          notificationDetails: const NotificationDetails(android: _passChannel),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        );
      } catch (e) {
        // Exact alarms can be restricted (Android 14+): degrade to inexact
        // rather than silently dropping the alert.
        try {
          await _plugin.zonedSchedule(
            id: id,
            title: p.title,
            body: p.body,
            scheduledDate: when,
            notificationDetails:
                const NotificationDetails(android: _passChannel),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
        } catch (e2) {
          debugPrint('notificação não agendada: $e2');
        }
      }
      id++;
    }
  }

  Future<void> cancelPassAlerts() async {
    await init();
    final pending = await _plugin.pendingNotificationRequests();
    for (final p in pending) {
      if (p.id >= _passIdBase && p.id < _passIdBase + _passIdRange) {
        await _plugin.cancel(id: p.id);
      }
    }
  }

  /// Immediate alert for a live aircraft transit candidate.
  Future<void> showLiveCandidate({
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(
      id: _liveId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(android: _liveChannel),
    );
  }
}
