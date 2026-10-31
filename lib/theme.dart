import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
//  DJIGARLAR — "Ivory & Ink" dizayn tizimi
//  Issiq oq (fil suyagi) fon, qora siyoh matn, oltin urg'u.
// ============================================================================

/// Avatar / profil ranglari (noziklashtirilgan palitra).
const accents = <Color>[
  Color(0xFF1F6F5C), // zumrad
  Color(0xFF2F4C8C), // indigo
  Color(0xFFB8893B), // oltin
  Color(0xFF8C3B4A), // vino
  Color(0xFF4A4E69), // kulrang-ko'k
  Color(0xFF2E7D8A), // feruza
  Color(0xFF7A5C3E), // bronza
  Color(0xFF5B3E7A), // olxo'ri
];

const accentNames = <String>[
  'Zumrad',
  'Indigo',
  'Oltin',
  'Vino',
  'Tun',
  'Feruza',
  'Bronza',
  "Olxo'ri",
];

final accentIndex = ValueNotifier<int>(2);
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
final wallpaperIndex = ValueNotifier<int>(0);

/// Hozir ochiq turgan chat (ilova ichidagi bildirishnomalar uchun).
String? openChatId;

/// Chat fonlari.
const List<List<Color>?> wallpapers = [
  null, // standart (fil suyagi / tun)
  [Color(0xFFF4F1EA), Color(0xFFE8E4D9)], // qog'oz
  [Color(0xFFF3EDE4), Color(0xFFE7DBC9)], // qum
  [Color(0xFFEAF0EE), Color(0xFFDAE6E1)], // adir
  [Color(0xFFF0EDF4), Color(0xFFE2DDEA)], // siyohrang
  [Color(0xFF101014), Color(0xFF1C1C23)], // tun
  [Color(0xFF0C1512), Color(0xFF16231E)], // o'rmon
  [Color(0xFF141018), Color(0xFF231A2B)], // binafsha tun
];

const wallpaperNames = <String>[
  'Standart',
  "Qog'oz",
  'Qum',
  'Adir',
  'Siyoh',
  'Tun',
  "O'rmon",
  'Binafsha',
];

String pairId(String a, String b) => ([a, b]..sort()).join('_');

/// Barcha foydalanuvchilar (uid -> ma'lumot). HomeScreen to'ldiradi.
final usersCache = ValueNotifier<Map<String, Map<String, dynamic>>>({});

Future<void> loadPrefs() async {
  final p = await SharedPreferences.getInstance();
  accentIndex.value = (p.getInt('accent') ?? 2).clamp(0, accents.length - 1);
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

// ---------------------------------------------------------------------------
//  Palitra
// ---------------------------------------------------------------------------

class DjPalette {
  final bool light;
  const DjPalette(this.light);

  Color get bg => light ? const Color(0xFFF2F0EA) : const Color(0xFF0A0A0B);
  Color get card => light ? Colors.white : const Color(0xFF17171A);
  Color get cardHi => light ? const Color(0xFFFAF8F3) : const Color(0xFF212126);
  Color get ink => light ? const Color(0xFF0D0D0F) : const Color(0xFFF4F2EC);
  Color get inkOn => light ? const Color(0xFFFAF8F3) : const Color(0xFF0D0D0F);
  Color get muted => light ? const Color(0xFF78787F) : const Color(0xFF97979E);
  Color get faint => light ? const Color(0xFFA8A8AE) : const Color(0xFF6A6A72);
  Color get hairline => light ? const Color(0xFFE7E4DC) : const Color(0xFF26262B);
  Color get gold => const Color(0xFFB8893B);
  Color get goldSoft => light ? const Color(0xFFF0E3CB) : const Color(0xFF3A2F1C);
  Color get online => const Color(0xFF2FB573);
  Color get danger => const Color(0xFFE23D3D);
  Color get accept => const Color(0xFF28B463);

  /// Mening xabarim pufagi — fon rangiga teskari (siyoh / fil suyagi).
  Color get mine => light ? const Color(0xFF131316) : const Color(0xFFEFEDE6);
  Color get mineOn => light ? const Color(0xFFF7F5F0) : const Color(0xFF131316);
  Color get theirs => light ? Colors.white : const Color(0xFF1E1E23);
  Color get theirsOn => light ? const Color(0xFF131316) : const Color(0xFFF1EFE9);

  List<BoxShadow> get soft => [
        BoxShadow(
          color: light
              ? const Color(0x14000000)
              : const Color(0x33000000),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];

  List<BoxShadow> get lift => [
        BoxShadow(
          color: light ? const Color(0x1F000000) : const Color(0x4D000000),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ];
}

DjPalette djOf(BuildContext c) =>
    DjPalette(Theme.of(c).brightness == Brightness.light);

extension DjContext on BuildContext {
  DjPalette get dj => djOf(this);
}

/// Oltin urg'uli gradient (tugmalar, nishonlar uchun).
LinearGradient goldGradient() => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFD9AE62), Color(0xFFB8893B), Color(0xFF8E672A)],
    );

/// Eski kod bilan moslik uchun saqlangan.
LinearGradient headerGradient() => goldGradient();

// ---------------------------------------------------------------------------
//  Mavzu
// ---------------------------------------------------------------------------

ThemeData buildTheme(Color seed, Brightness b) {
  final light = b == Brightness.light;
  final p = DjPalette(light);
  final cs = ColorScheme(
    brightness: b,
    primary: p.ink,
    onPrimary: p.inkOn,
    primaryContainer: light ? const Color(0xFFE9E6DE) : const Color(0xFF26262C),
    onPrimaryContainer: p.ink,
    secondary: p.gold,
    onSecondary: Colors.white,
    secondaryContainer: p.goldSoft,
    onSecondaryContainer: light ? const Color(0xFF5E4418) : p.gold,
    tertiary: p.gold,
    onTertiary: Colors.white,
    error: p.danger,
    onError: Colors.white,
    surface: p.bg,
    onSurface: p.ink,
    surfaceContainerLowest: p.card,
    surfaceContainerLow: p.card,
    surfaceContainer: p.card,
    surfaceContainerHigh: p.cardHi,
    surfaceContainerHighest: p.cardHi,
    onSurfaceVariant: p.muted,
    outline: p.faint,
    outlineVariant: p.hairline,
    shadow: Colors.black,
    inverseSurface: p.ink,
    onInverseSurface: p.inkOn,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    splashFactory: InkSparkle.splashFactory,
    highlightColor: Colors.transparent,
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle:
          light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(
        color: p.ink,
        fontSize: 20,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
    ),
    iconTheme: IconThemeData(color: p.ink, size: 22),
    dividerTheme: DividerThemeData(space: 1, thickness: 0.7, color: p.hairline),
    listTileTheme: ListTileThemeData(
      iconColor: p.ink,
      textColor: p.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: p.hairline, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: p.ink.withValues(alpha: 0.55), width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: p.danger, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: p.danger, width: 1.4),
      ),
      labelStyle: TextStyle(color: p.muted),
      hintStyle: TextStyle(color: p.faint),
      prefixIconColor: p.muted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.inkOn,
        minimumSize: const Size.fromHeight(54),
        elevation: 0,
        textStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.ink,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        side: BorderSide(color: p.hairline, width: 1.2),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.hairline,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: TextStyle(
          color: p.ink, fontSize: 19, fontWeight: FontWeight.w800),
      contentTextStyle: TextStyle(color: p.ink, fontSize: 15),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.card,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: p.ink,
      contentTextStyle: TextStyle(color: p.inkOn, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      backgroundColor: p.card,
      selectedColor: p.ink,
      labelStyle: TextStyle(fontWeight: FontWeight.w700, color: p.ink),
      secondaryLabelStyle:
          TextStyle(fontWeight: FontWeight.w700, color: p.inkOn),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      showCheckmark: false,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.ink,
      linearTrackColor: p.hairline,
      circularTrackColor: Colors.transparent,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.ink,
      inactiveTrackColor: p.hairline,
      thumbColor: p.ink,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.inkOn : p.card),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.ink : p.hairline),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.ink,
      foregroundColor: p.inkOn,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

// ---------------------------------------------------------------------------
//  Karta
// ---------------------------------------------------------------------------

/// Yumshoq, yumaloq oq karta.
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? margin;
  final double radius;
  const SoftCard({super.key, required this.child, this.margin, this.radius = 22});

  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    return Container(
      margin:
          margin ?? const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: p.hairline, width: 0.8),
        boxShadow: p.soft,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Bir nechta qatorni bitta oq "varaq"ga yig'adi.
class SheetGroup extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets margin;
  const SheetGroup({
    super.key,
    required this.children,
    this.margin = const EdgeInsets.fromLTRB(14, 6, 14, 6),
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Padding(
          padding: const EdgeInsets.only(left: 78),
          child: Divider(height: 1, thickness: 0.7, color: p.hairline),
        ));
      }
      rows.add(children[i]);
    }
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.hairline, width: 0.8),
        boxShadow: p.soft,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

/// Kichik, harflar orasi keng bo'lgan bo'lim sarlavhasi.
class SectionLabel extends StatelessWidget {
  final String text;
  final EdgeInsets padding;
  const SectionLabel(this.text,
      {super.key, this.padding = const EdgeInsets.fromLTRB(22, 18, 22, 8)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
            color: context.dj.muted,
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
//  Yordamchi funksiyalar
// ---------------------------------------------------------------------------

String userName(String uid) => (usersCache.value[uid]?['name'] ?? '?') as String;

int colorIndexFor(String uid) {
  final c = usersCache.value[uid]?['color'];
  if (c is int && c >= 0 && c < accents.length) return c;
  if (uid.isEmpty) return 0;
  return uid.codeUnits.fold<int>(0, (a, b) => a + b) % accents.length;
}

bool isOnline(Map<String, dynamic>? u) {
  final t = (u?['lastSeen'] ?? 0);
  if (t is! int) return false;
  return DateTime.now().millisecondsSinceEpoch - t < 70000;
}

String two(int n) => n.toString().padLeft(2, '0');

String fmtTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

const _weekdays = ['Du', 'Se', 'Chor', 'Pay', 'Ju', 'Sha', 'Yak'];

String fmtChatTime(DateTime d) {
  final n = DateTime.now();
  if (sameDay(d, n)) return fmtTime(d);
  if (sameDay(d, n.subtract(const Duration(days: 1)))) return 'Kecha';
  if (n.difference(d).inDays < 7) {
    return _weekdays[(d.weekday - 1).clamp(0, 6)];
  }
  return '${two(d.day)}.${two(d.month)}';
}

String fmtDuration(int secs) {
  final h = secs ~/ 3600;
  final m = (secs % 3600) ~/ 60;
  final s = secs % 60;
  if (h > 0) return '$h:${two(m)}:${two(s)}';
  return '$m:${two(s)}';
}

String lastSeenText(Map<String, dynamic>? u) {
  if (u == null) return '';
  if (isOnline(u)) return 'onlayn';
  final t = (u['lastSeen'] ?? 0);
  if (t is! int || t == 0) return "yaqinda bo'lmagan";
  final d = DateTime.fromMillisecondsSinceEpoch(t);
  final n = DateTime.now();
  if (sameDay(d, n)) return 'oxirgi marta ${fmtTime(d)} da';
  if (sameDay(d, n.subtract(const Duration(days: 1)))) {
    return 'kecha ${fmtTime(d)} da';
  }
  return 'oxirgi marta ${two(d.day)}.${two(d.month)}';
}

// ---------------------------------------------------------------------------
//  Avatar
// ---------------------------------------------------------------------------

class Avatar extends StatelessWidget {
  final String name;
  final String? photo;
  final double size;
  final int colorIdx;
  final bool group;
  final bool ring;
  const Avatar({
    super.key,
    required this.name,
    this.photo,
    this.size = 48,
    this.colorIdx = 0,
    this.group = false,
    this.ring = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    final base = accents[colorIdx % accents.length];
    Widget child;
    final ph = photo;
    if (ph != null && ph.isNotEmpty) {
      Widget img;
      try {
        img = Image.memory(
          base64Decode(ph),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (c, e, s) => _letter(base),
        );
      } catch (_) {
        img = _letter(base);
      }
      child = img;
    } else {
      child = _letter(base);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: ring
            ? Border.all(color: p.hairline.withValues(alpha: 0.9), width: 0.8)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _letter(Color base) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(base, Colors.white, 0.22)!,
              Color.lerp(base, Colors.black, 0.22)!,
            ],
          ),
        ),
        alignment: Alignment.center,
        child: group
            ? Icon(Icons.groups_rounded, color: Colors.white, size: size * 0.5)
            : Text(
                name.trim().isEmpty
                    ? '?'
                    : name.trim().characters.first.toUpperCase(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.40,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
      );
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
            colorIdx: colorIndexFor(uid),
          );
          if (!showOnline || !isOnline(u)) return a;
          final p = c.dj;
          return SizedBox(
            width: size,
            height: size,
            child: Stack(children: [
              a,
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: size * 0.27,
                  height: size * 0.27,
                  decoration: BoxDecoration(
                    color: p.online,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.bg, width: 2),
                  ),
                ),
              ),
            ]),
          );
        },
      );
}

// ---------------------------------------------------------------------------
//  Matn formatlash: **qalin**, __kursiv__, `kod`, ~~chizilgan~~
// ---------------------------------------------------------------------------

InlineSpan formatText(String s, TextStyle base) {
  final re = RegExp(r'\*\*(.+?)\*\*|__(.+?)__|`(.+?)`|~~(.+?)~~');
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in re.allMatches(s)) {
    if (m.start > last) spans.add(TextSpan(text: s.substring(last, m.start)));
    if (m.group(1) != null) {
      spans.add(TextSpan(
          text: m.group(1),
          style: const TextStyle(fontWeight: FontWeight.bold)));
    } else if (m.group(2) != null) {
      spans.add(TextSpan(
          text: m.group(2),
          style: const TextStyle(fontStyle: FontStyle.italic)));
    } else if (m.group(3) != null) {
      spans.add(TextSpan(
        text: m.group(3),
        style: TextStyle(
          fontFamily: 'monospace',
          backgroundColor:
              (base.color ?? Colors.grey).withValues(alpha: 0.14),
        ),
      ));
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
