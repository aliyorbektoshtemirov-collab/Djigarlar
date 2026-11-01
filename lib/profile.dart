import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'theme.dart';
import 'ui.dart';
import 'username.dart';

class ProfileScreen extends StatefulWidget {
  final String me;
  const ProfileScreen({super.key, required this.me});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _status = TextEditingController();
  bool _loaded = false;
  bool _busy = false;

  DocumentReference<Map<String, dynamic>> get _doc =>
      FirebaseFirestore.instance.collection('users').doc(widget.me);

  void _fill() {
    final u = usersCache.value[widget.me];
    if (_loaded || u == null) return;
    _loaded = true;
    _name.text = (u['name'] ?? '') as String;
    _bio.text = (u['bio'] ?? '') as String;
    _status.text = (u['status'] ?? '') as String;
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    usersCache.addListener(_fill);
    _fill();
  }

  @override
  void dispose() {
    usersCache.removeListener(_fill);
    _name.dispose();
    _bio.dispose();
    _status.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await _doc.set({
        'name': _name.text.trim().isEmpty ? 'Djigar' : _name.text.trim(),
        'bio': _bio.text.trim(),
        'status': _status.text.trim(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saqlandi')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Saqlab bo'lmadi")));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickPhoto() async {
    try {
      final x = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 320,
          maxHeight: 320,
          imageQuality: 70);
      if (x == null) return;
      final b64 = base64Encode(await x.readAsBytes());
      if (b64.length > 300000) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Rasm juda katta')));
        }
        return;
      }
      await _doc.set({'photo': b64}, SetOptions(merge: true));
    } catch (_) {}
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    final p = context.dj;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      padding: padding ?? const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.hairline, width: 0.8),
        boxShadow: p.soft,
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 130),
          physics: const BouncingScrollPhysics(),
          children: [
            const BigHeader(title: 'Profil', kicker: 'Siz'),

            // ---------- avatar ----------
            FadeSlideIn(
              child: Center(
                child: Column(children: [
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _pickPhoto,
                    child: Stack(children: [
                      ValueListenableBuilder(
                        valueListenable: usersCache,
                        builder: (c, map, _) {
                          final u = map[widget.me];
                          return Avatar(
                            name: (u?['name'] ?? '?') as String,
                            photo: u?['photo'] as String?,
                            size: 112,
                            colorIdx: colorIndexFor(widget.me),
                          );
                        },
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: p.ink,
                            shape: BoxShape.circle,
                            border: Border.all(color: p.bg, width: 2.5),
                          ),
                          child: Icon(Icons.photo_camera_rounded,
                              size: 15, color: p.inkOn),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  ValueListenableBuilder(
                    valueListenable: usersCache,
                    builder: (c, map, _) {
                      final un = (map[widget.me]?['username'] ?? '') as String;
                      return Column(children: [
                        Text(
                          (map[widget.me]?['name'] ?? 'Djigar') as String,
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                              color: p.ink),
                        ),
                        if (un.isNotEmpty)
                          Text('@$un',
                              style: TextStyle(
                                  color: p.gold,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5)),
                      ]);
                    },
                  ),
                  const SizedBox(height: 14),
                ]),
              ),
            ),

            // ---------- username ----------
            FadeSlideIn(
              index: 1,
              child: ValueListenableBuilder(
                valueListenable: usersCache,
                builder: (c, map, _) {
                  final un = (map[widget.me]?['username'] ?? '') as String;
                  return _card(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                      leading: Icon(Icons.alternate_email_rounded, color: p.ink),
                      title: Text(un.isEmpty ? "Username yo'q" : '@$un',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text("Do'stlar sizni shu orqali topadi",
                          style: TextStyle(color: p.muted, fontSize: 12.5)),
                      trailing:
                          Icon(Icons.edit_outlined, size: 19, color: p.faint),
                      onTap: () =>
                          showUsernameDialog(context, widget.me, current: un),
                    ),
                  );
                },
              ),
            ),

            // ---------- ma'lumotlar ----------
            FadeSlideIn(
              index: 2,
              child: _card(
                child: Column(children: [
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                        labelText: 'Ism',
                        prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _status,
                    decoration: const InputDecoration(
                        labelText: 'Emoji holat (masalan 😎)',
                        prefixIcon: Icon(Icons.emoji_emotions_outlined)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bio,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Bio',
                        prefixIcon: Icon(Icons.info_outline_rounded)),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: p.inkOn),
                          )
                        : const Text('Saqlash'),
                  ),
                ]),
              ),
            ),

            // ---------- ko'rinish ----------
            const SectionLabel("Ko'rinish"),
            FadeSlideIn(
              index: 3,
              child: _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rejim',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: p.ink)),
                    const SizedBox(height: 10),
                    ValueListenableBuilder<ThemeMode>(
                      valueListenable: themeMode,
                      builder: (c, mode, _) => Row(children: [
                        for (final e in const [
                          [ThemeMode.system, 'Avto', Icons.brightness_auto],
                          [ThemeMode.light, 'Kun', Icons.light_mode_rounded],
                          [ThemeMode.dark, 'Tun', Icons.dark_mode_rounded],
                        ])
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: PressScale(
                                onTap: () => saveMode(e[0] as ThemeMode),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12),
                                  decoration: BoxDecoration(
                                    color: mode == e[0] ? p.ink : p.cardHi,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: p.hairline),
                                  ),
                                  child: Column(children: [
                                    Icon(e[2] as IconData,
                                        size: 19,
                                        color: mode == e[0] ? p.inkOn : p.muted),
                                    const SizedBox(height: 5),
                                    Text(
                                      e[1] as String,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color:
                                            mode == e[0] ? p.inkOn : p.muted,
                                      ),
                                    ),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 22),
                    Text('Profil rangi',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: p.ink)),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<int>(
                      valueListenable: accentIndex,
                      builder: (c, sel, _) =>
                          Wrap(spacing: 12, runSpacing: 12, children: [
                        for (var i = 0; i < accents.length; i++)
                          PressScale(
                            onTap: () {
                              saveAccent(i);
                              _doc.set({'color': i}, SetOptions(merge: true));
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: accents[i],
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: sel == i ? p.ink : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: sel == i
                                  ? const Icon(Icons.check_rounded,
                                      color: Colors.white, size: 19)
                                  : null,
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 22),
                    Text('Chat foni',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: p.ink)),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<int>(
                      valueListenable: wallpaperIndex,
                      builder: (c, sel, _) =>
                          Wrap(spacing: 10, runSpacing: 10, children: [
                        for (var i = 0; i < wallpapers.length; i++)
                          PressScale(
                            onTap: () => saveWallpaper(i),
                            child: Column(children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  color:
                                      wallpapers[i] == null ? p.cardHi : null,
                                  gradient: wallpapers[i] == null
                                      ? null
                                      : LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: wallpapers[i]!),
                                  border: Border.all(
                                    color: sel == i ? p.ink : p.hairline,
                                    width: sel == i ? 2.5 : 1,
                                  ),
                                ),
                                child: wallpapers[i] == null
                                    ? Icon(Icons.block_rounded,
                                        size: 17, color: p.faint)
                                    : null,
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: 54,
                                child: Text(
                                  wallpaperNames[i],
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: sel == i ? p.ink : p.faint),
                                ),
                              ),
                            ]),
                          ),
                      ]),
                    ),
                  ],
                ),
              ),
            ),

            // ---------- premium ----------
            const SectionLabel('Imkoniyatlar'),
            FadeSlideIn(
              index: 4,
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: p.ink,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: p.soft,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      ShaderMask(
                        shaderCallback: (r) => goldGradient().createShader(r),
                        child: const Icon(Icons.auto_awesome_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Text('Djigarlar Premium',
                          style: TextStyle(
                              color: p.inkOn,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3)),
                    ]),
                    const SizedBox(height: 4),
                    Text('Hammasi sizga bepul ochiq',
                        style: TextStyle(
                            color: p.inkOn.withValues(alpha: 0.6),
                            fontSize: 13)),
                    const SizedBox(height: 16),
                    for (final f in const [
                      "Guruh video chat (mesh)",
                      "Audio va video qo'ng'iroq, orqa/old kamera",
                      'Ovozli xabarlar va stikerlar',
                      "So'rovnomalar va reaksiyalar",
                      'Rasm yuborish va to\'liq ekranda ochish',
                      'Xabarni uzatish, qadash, tahrirlash, qidirish',
                      "Guruh boshqaruvi, arxiv, saqlangan xabarlar",
                      "O'qildi belgilari, yozmoqda, onlayn holat",
                      'Kun/tun rejimi va chat fonlari',
                      "Reklama yo'q",
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Icon(Icons.check_rounded,
                                  size: 15, color: p.gold),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(f,
                                  style: TextStyle(
                                      color: p.inkOn.withValues(alpha: 0.85),
                                      fontSize: 13.5,
                                      height: 1.35)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: Icon(Icons.logout_rounded, size: 19, color: p.danger),
                label: Text('Chiqish',
                    style: TextStyle(
                        color: p.danger, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: p.danger.withValues(alpha: 0.35), width: 1.2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text('Djigarlar v0.8.2',
                  style: TextStyle(color: p.faint, fontSize: 11.5)),
            ),
          ],
        ),
      ),
    );
  }
}
