import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ============================================================================
//  Tizim bildirishnomalari (xabar va qo'ng'iroq)
//  Ilova ochiq yoki fonda turganda ishlaydi.
// ============================================================================

final notify = Notifier();

const _msgChannel = 'djigarlar_messages';
const _callChannel = 'djigarlar_calls';

class Notifier {
  final FlutterLocalNotificationsPlugin _p = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool granted = false;

  /// Bildirishnoma bosilganda chaqiriladi (payload = chat id).
  void Function(String payload)? onOpen;

  Future<void> init() async {
    if (_ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _p.initialize(
        settings,
        onDidReceiveNotificationResponse: (r) {
          final pl = r.payload;
          if (pl != null && pl.isNotEmpty) onOpen?.call(pl);
        },
      );
      final a = _p.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await a?.createNotificationChannel(const AndroidNotificationChannel(
        _msgChannel,
        'Xabarlar',
        description: "Yangi xabarlar haqida bildirishnoma",
        importance: Importance.high,
      ));
      await a?.createNotificationChannel(const AndroidNotificationChannel(
        _callChannel,
        "Qo'ng'iroqlar",
        description: "Kiruvchi qo'ng'iroqlar",
        importance: Importance.max,
      ));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Android 13+ da ruxsat so'raydi. Ruxsat berilgan bo'lsa darrov true qaytaradi.
  Future<bool> ask() async {
    await init();
    try {
      final a = _p.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (a == null) return false;
      final ok = await a.requestNotificationsPermission();
      granted = ok ?? false;
    } catch (_) {
      granted = false;
    }
    return granted;
  }

  Future<void> message({
    required int id,
    required String title,
    required String body,
    required String chatId,
  }) async {
    await init();
    if (!_ready) return;
    try {
      await _p.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _msgChannel,
            'Xabarlar',
            importance: Importance.high,
            priority: Priority.high,
            ticker: 'yangi xabar',
          ),
        ),
        payload: chatId,
      );
    } catch (_) {}
  }

  Future<void> call({
    required int id,
    required String name,
    required bool video,
  }) async {
    await init();
    if (!_ready) return;
    try {
      await _p.show(
        id,
        name,
        video ? "Video qo'ng'iroq" : "Qo'ng'iroq qilmoqda",
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _callChannel,
            "Qo'ng'iroqlar",
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.call,
            fullScreenIntent: true,
            ongoing: true,
            autoCancel: false,
            ticker: "qo'ng'iroq",
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _p.cancel(id);
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _p.cancelAll();
    } catch (_) {}
  }
}

/// Matndan barqaror bildirishnoma ID hosil qiladi.
int notifId(String key) {
  var h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x3FFFFFFF;
  }
  return h;
}
