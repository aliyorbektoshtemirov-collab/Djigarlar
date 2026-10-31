import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const accents = <Color>[
  Color(0xFF0F9D8A),
  Color(0xFF5B6CFF),
  Color(0xFFE1306C),
  Color(0xFFFF8A3D),
  Color(0xFF8E44AD),
  Color(0xFF2E86DE),
  Color(0xFF16A34A),
  Color(0xFFEF4444),
];

final accentIndex = ValueNotifier<int>(0);
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
final wallpaperIndex = ValueNotifier<int>(0);

/// Hozir ochiq turgan chat (ilova ichidagi bildirishnomalar uchun).
String? openChatId;

const List<List<Color>?> wallpapers = [
  null,
  [Color(0xFFDFF5EE), Color(0xFFE5EAFF)],
  [Color(0xFFFFE5EC), Color(0xFFFFF1E0)],
  [Color(0xFFE3F2FD), Color(0xFFEDE7F6)],
  [Color(0xFF0F2027), Color(0xFF2C5364)],
  [Color(0xFF1A1A2E), Color(0xFF3D1E6D)],
];

String pairId(String a, String b) => ([a, b]..sort()).join('_');

/// Barcha foydalanuvchilar (uid -> ma'lumot). HomeScreen to'ldiradi.
final usersCache = ValueNotifier<Map<String, Map<String, dynamic>>>({});

Future<void> loadPrefs() async {
  final p = await SharedPreferences.getInstance();
  accentIndex.value = (p.getInt('accent') ?? 0).clamp(0, accents.length - 1);
  themeMode.value = ThemeMode.values[(p.getInt('mode') ?? 0).clamp(0, 2)];
  wallpaperIndex.value = (p.getInt('wall') ?? 0).clamp(0, wallpapers.length - 1);
}

Future<void> saveAccent(int i) async {
  accentIndex.value = i;
  (await SharedPreferences.getInstance()).setInt('accent', i);
}

Future<void> saveWallpaper(int i) async {
  wallpaperIndex.value = i;
  (await SharedPreferences.getInstance()).setInt('wall', i);
}

Future<void> saveMode(ThemeMode m) async {
  themeMode.value = m;
  (await SharedPreferences.getInstance()).setInt('mode', m.index);
}

LinearGradient headerGradient() {
  final seed = accents[accentIndex.value];
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [seed, Color.lerp(seed, const Color(0xFF3B2A8C), 0.5)!],
  );
}

ThemeData buildTheme(Color seed, Brightness b) {
  final cs = ColorScheme.fromSeed(seedColor: seed, brightness: b);
  final light = b == Brightness.light;
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: light
        ? Color.alphaBlend(cs.primary.withOpacity(0.05), const Color(0xFFF6F7FB))
        : cs.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: light
          ? Color.alphaBlend(cs.primary.withOpacity(0.05), const Color(0xFFF6F7FB))
          : cs.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
          color: cs.onSurface, fontSize: 20, fontWeight: FontWeight.w700),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light
          ? Colors.white
          : cs.surfaceContainerHighest.withOpacity(0.6),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        elevation: 0,
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: light ? Colors.white : cs.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: cs.primaryContainer,
      labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: light ? Colors.white : cs.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: light ? Colors.white : cs.surfaceContainerHigh,
      selectedColor: cs.primaryContainer,
      labelStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}

/// Yumshoq yumaloq karta (ro'yxat elementlari uchun).
class SoftCard extends StatelessWidget {
  final Widget child;
  const SoftCard({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: light ? Colors.white : cs.surfaceContainerLow,
        elevation: light ? 1 : 0,
        shadowColor: Colors.black.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

// ---------- yordamchi funksiyalar ----------

String userName(String uid) => (usersCache.value[uid]?['name'] ?? '?') as String;

int colorIndexFor(String uid) {
  final c = usersCache.value[uid]?['color'];
  if (c is int && c >= 0 && c < accents.length) return c;
  return uid.codeUnits.fold<int>(0, (a, b) => a + b) % accents.length;
}

bool isOnline(Map<String, dynamic>? u) {
  final t = (u?['lastSeen'] ?? 0) as int;
  return DateTime.now().millisecondsSinceEpoch - t < 70000;
}

String two(int n) => n.toString().padLeft(2, '0');
String fmtTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
String fmtChatTime(DateTime d) {
  final n = DateTime.now();
  if (d.year == n.year && d.month == n.month && d.day == n.day) {
    return fmtTime(d);
  }
  return '${two(d.day)}.${two(d.month)}';
}

String lastSeenText(Map<String, dynamic>? u) {
  if (u == null) return '';
  if (isOnline(u)) return 'onlayn';
  final t = (u['lastSeen'] ?? 0) as int;
  if (t == 0) return 'yaqinda bo\'lmagan';
  return 'oxirgi marta ${fmtChatTime(DateTime.fromMillisecondsSinceEpoch(t))} ${fmtTime(DateTime.fromMillisecondsSinceEpoch(t))}';
}

// ---------- avatar ----------

class Avatar extends StatelessWidget {
  final String name;
  final String? photo;
  final double size;
  final int colorIdx;
  final bool group;
  const Avatar(
      {super.key,
      required this.name,
      this.photo,
      this.size = 48,
      this.colorIdx = 0,
      this.group = false});

  @override
  Widget build(BuildContext context) {
    final base = accents[colorIdx % accents.length];
    Widget child;
    if (photo != null && photo!.isNotEmpty) {
      child = Image.memory(base64Decode(photo!),
          width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true);
    } else {
      child = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [base, Color.lerp(base, Colors.black, 0.25)!]),
        ),
        alignment: Alignment.center,
        child: group
            ? Icon(Icons.group, color: Colors.white, size: size * 0.5)
            : Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.42,
                    fontWeight: FontWeight.w600)),
      );
    }
    return ClipOval(child: SizedBox(width: size, height: size, child: child));
  }
}

class UserAvatar extends StatelessWidget {
  final String uid;
  final double size;
  final bool showOnline;
  const UserAvatar(
      {super.key, required this.uid, this.size = 48, this.showOnline = true});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: usersCache,
        builder: (c, map, _) {
          final u = map[uid];
          final a = Avatar(
              name: (u?['name'] ?? '?') as String,
              photo: u?['photo'] as String?,
              size: size,
              colorIdx: colorIndexFor(uid));
          if (!showOnline || !isOnline(u)) return a;
          return Stack(children: [
            a,
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: size * 0.26,
                height: size * 0.26,
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Theme.of(context).colorScheme.surface, width: 2),
                ),
              ),
            ),
          ]);
        },
      );
}

// ---------- matn formatlash: **qalin**, __kursiv__, `kod`, ~~chizilgan~~ ----------

InlineSpan formatText(String s, TextStyle base) {
  final re = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|`(.+?)`|~~(.+?)~~');
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in re.allMatches(s)) {
    if (m.start > last) spans.add(TextSpan(text: s.substring(last, m.start)));
    if (m.group(1) != null) {
      spans.add(TextSpan(
          text: m.group(1), style: const TextStyle(fontWeight: FontWeight.bold)));
    } else if (m.group(2) != null) {
      spans.add(TextSpan(
          text: m.group(2), style: const TextStyle(fontStyle: FontStyle.italic)));
    } else if (m.group(3) != null) {
      spans.add(TextSpan(
          text: m.group(3),
          style: TextStyle(
              fontFamily: 'monospace',
              backgroundColor: (base.color ?? Colors.grey).withOpacity(0.15))));
    } else {
      spans.add(TextSpan(
          text: m.group(4),
          style: const TextStyle(decoration: TextDecoration.lineThrough)));
    }
    last = m.end;
  }
  if (last < s.length) spans.add(TextSpan(text: s.substring(last)));
  return TextSpan(style: base, children: spans);
}

bool isEmojiOnly(String t) {
  final s = t.trim();
  if (s.isEmpty || s.runes.length > 6) return false;
  return s.runes.every((r) => r > 0x2000 || r == 0xFE0F);
}
