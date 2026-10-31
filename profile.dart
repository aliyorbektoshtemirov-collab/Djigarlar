import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'theme.dart';

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
    super.dispose();
  }

  Future<void> _save() async {
    await _doc.set({
      'name': _name.text.trim().isEmpty ? 'Djigar' : _name.text.trim(),
      'bio': _bio.text.trim(),
      'status': _status.text.trim(),
    }, SetOptions(merge: true));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Saqlandi')));
    }
  }

  Future<void> _pickPhoto() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 256, imageQuality: 70);
    if (x == null) return;
    await _doc.set({'photo': base64Encode(await x.readAsBytes())},
        SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(
              height: 150,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: headerGradient(),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(36)),
              ),
              child: const SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 14, 24, 0),
                  child: Text('Profil',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800)),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: -56,
              child: Center(
            child: GestureDetector(
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
                        colorIdx: colorIndexFor(widget.me));
                  },
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: cs.primary,
                    child: Icon(Icons.camera_alt, size: 18, color: cs.onPrimary),
                  ),
                ),
              ]),
            ),
          ),
            ),
          ]),
          const SizedBox(height: 64),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Ism', prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 12),
          TextField(
              controller: _status,
              decoration: const InputDecoration(
                  labelText: 'Emoji holat (masalan 😎)',
                  prefixIcon: Icon(Icons.emoji_emotions_outlined))),
          const SizedBox(height: 12),
          TextField(
              controller: _bio,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Bio', prefixIcon: Icon(Icons.info_outline))),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Saqlash')),
          const SizedBox(height: 28),
          const Text('Mavzu',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ValueListenableBuilder<int>(
            valueListenable: accentIndex,
            builder: (c, sel, _) => Wrap(spacing: 12, runSpacing: 12, children: [
              for (var i = 0; i < accents.length; i++)
                GestureDetector(
                  onTap: () {
                    saveAccent(i);
                    _doc.set({'color': i}, SetOptions(merge: true));
                  },
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: accents[i],
                    child: sel == i
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeMode,
            builder: (c, mode, _) => SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('Avto'),
                    icon: Icon(Icons.brightness_auto)),
                ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Kun'),
                    icon: Icon(Icons.light_mode)),
                ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Tun'),
                    icon: Icon(Icons.dark_mode)),
              ],
              selected: {mode},
              onSelectionChanged: (s) => saveMode(s.first),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Chat foni',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ValueListenableBuilder<int>(
            valueListenable: wallpaperIndex,
            builder: (c, sel, _) => Wrap(spacing: 12, runSpacing: 12, children: [
              for (var i = 0; i < wallpapers.length; i++)
                GestureDetector(
                  onTap: () => saveWallpaper(i),
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: wallpapers[i] == null ? cs.surfaceContainerHighest : null,
                      gradient: wallpapers[i] == null
                          ? null
                          : LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: wallpapers[i]!),
                      border: Border.all(
                          color: sel == i ? cs.primary : cs.outlineVariant,
                          width: sel == i ? 3 : 1),
                    ),
                    child: wallpapers[i] == null
                        ? const Icon(Icons.format_color_reset, size: 20)
                        : null,
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cs.primary, cs.tertiary]),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.star, color: Colors.amber),
                const SizedBox(width: 8),
                Text('Djigarlar Premium',
                    style: TextStyle(
                        color: cs.onPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w800)),
              ]),
              const SizedBox(height: 4),
              Text('Hammasi sizga bepul ochiq',
                  style: TextStyle(color: cs.onPrimary.withOpacity(0.85))),
              const SizedBox(height: 12),
              for (final f in [
                'Reaksiyalar (8 xil emoji)',
                'Stikerlar va katta emoji',
                'Ovozli xabarlar',
                "So'rovnomalar",
                'Xabarni uzatish, qadash, qidirish',
                'Guruh boshqaruvi (a\'zo qo\'shish, nom, chiqish)',
                'Chat fonlari',
                'Matn formati: **qalin** __kursiv__ `kod` ~~chiziq~~',
                'Arxiv',
                'Chat papkalari va cheksiz qadash',
                'Emoji holat, bio va profil rasmi',
                'Rangli mavzular, kun/tun rejimi',
                'Saqlangan xabarlar',
                'Xabarni tahrirlash va javob berish',
                "O'qildi belgilari, yozmoqda, onlayn holat",
                "Audio va video qo'ng'iroq",
                'Reklama yo\'q',
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Icon(Icons.check_circle, size: 18, color: cs.onPrimary),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(f, style: TextStyle(color: cs.onPrimary))),
                  ]),
                ),
            ]),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout),
            label: const Text('Chiqish'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16))),
          ),
        ])),
        ],
      ),
    );
  }
}
