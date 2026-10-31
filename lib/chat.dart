import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'call.dart';
import 'group_call.dart';
import 'info.dart';
import 'theme.dart';
import 'ui.dart';

const _reactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏', '🔥', '🎉'];
const _stickers = [
  '😀', '😂', '🥹', '😍', '😎', '🤩', '😭', '😡', '🥳', '🤔', '🙄', '😴',
  '👍', '👎', '👏', '🙏', '💪', '🤝', '❤️', '🔥', '🎉', '✨', '💯', '🤣',
  '😘', '😇', '🤗', '😱', '🥰', '😉', '😅', '🫶'
];

/// Rasm chegarasi — Firestore hujjati 1 MB dan oshmasligi uchun.
const _maxImageChars = 700000;

// ---------------------------------------------------------------------------
//  base64 rasm keshi — har qayta chizishda qayta dekod qilmaslik uchun
// ---------------------------------------------------------------------------
final _imgCache = <String, Uint8List>{};
final _imgOrder = <String>[];

Uint8List? imgBytes(String key, String b64) {
  final hit = _imgCache[key];
  if (hit != null) return hit;
  try {
    final bytes = base64Decode(b64);
    _imgCache[key] = bytes;
    _imgOrder.add(key);
    if (_imgOrder.length > 40) {
      _imgCache.remove(_imgOrder.removeAt(0));
    }
    return bytes;
  } catch (_) {
    return null;
  }
}

/// `time` serverTimestamp — yuborilgan zahoti `null` bo'ladi.
/// Shuning uchun avval mijoz vaqti (`timeMs`) o'qiladi.
DateTime? msgTime(Map<String, dynamic> m) {
  final ms = m['timeMs'];
  if (ms is int && ms > 0) return DateTime.fromMillisecondsSinceEpoch(ms);
  final t = m['time'];
  if (t is Timestamp) return t.toDate();
  return null;
}

/// Istalgan chatga xabar yozadi (yuborish, uzatish, saqlash uchun).
/// Hammasi bitta batch bilan — tezroq va chat ro'yxati darrov yangilanadi.
Future<void> writeMessage({
  required String chatId,
  required List<String> members,
  required bool isGroup,
  required bool saved,
  required Map<String, dynamic> data,
  required String preview,
}) async {
  final me = FirebaseAuth.instance.currentUser!.uid;
  final db = FirebaseFirestore.instance;
  final now = DateTime.now().millisecondsSinceEpoch;
  final chatRef = db.collection('chats').doc(chatId);
  final msgRef = chatRef.collection('messages').doc();
  final others = members.where((m) => m != me).toList();

  final batch = db.batch();
  batch.set(msgRef, {
    'from': me,
    'fromName': userName(me),
    'time': FieldValue.serverTimestamp(),
    'timeMs': now,
    ...data,
  });
  batch.set(
    chatRef,
    {
      if (!isGroup) ...{
        'members': members,
        'isGroup': false,
        'saved': saved,
      },
      'lastText': preview,
      'lastFrom': me,
      'lastTime': FieldValue.serverTimestamp(),
      'lastTimeMs': now,
      if (others.isNotEmpty)
        'unread': {for (final o in others) o: FieldValue.increment(1)},
    },
    SetOptions(merge: true),
  );
  await batch.commit();
}

class _Target {
  final String id, title;
  final bool isGroup, saved;
  final List<String> members;
  _Target(this.id, this.title, this.isGroup, this.saved, this.members);
}

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String title;
  final bool isGroup;
  final bool saved;
  final String? peerId;
  const ChatScreen({
    super.key,
    required this.chatId,
    required this.title,
    required this.isGroup,
    this.saved = false,
    this.peerId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _searchCtl = TextEditingController();
  final String _me = FirebaseAuth.instance.currentUser!.uid;
  final _rec = AudioRecorder();

  Map<String, dynamic>? _reply;
  String? _editingId;
  Timer? _recTick;
  int _lastTyping = 0;
  String? _readUpTo;
  List<String> _groupMembers = [];
  bool _chatExists = false;
  bool _searching = false;
  bool _sending = false;
  String _q = '';
  bool _recording = false;
  DateTime? _recStart;
  int _recSecs = 0;

  String get _myName => userName(_me);
  List<String> get _members => widget.isGroup
      ? _groupMembers
      : widget.saved
          ? [_me]
          : [_me, widget.peerId!];
  DocumentReference<Map<String, dynamic>> get _chatRef =>
      FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
  CollectionReference<Map<String, dynamic>> get _msgs =>
      _chatRef.collection('messages');

  @override
  void initState() {
    super.initState();
    openChatId = widget.chatId;
  }

  @override
  void dispose() {
    if (openChatId == widget.chatId) openChatId = null;
    _recTick?.cancel();
    _text.dispose();
    _searchCtl.dispose();
    _rec.dispose();
    super.dispose();
  }

  void _snack(String t) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
    }
  }

  // ---------------- yuborish ----------------

  Future<void> _post(Map<String, dynamic> extra, String preview) async {
    final data = <String, dynamic>{...extra};
    if (_reply != null) data['reply'] = _reply;
    if (mounted) setState(() => _reply = null);
    try {
      await writeMessage(
        chatId: widget.chatId,
        members: _members,
        isGroup: widget.isGroup,
        saved: widget.saved,
        data: data,
        preview: preview,
      );
    } catch (_) {
      _snack("Yuborib bo'lmadi — internetni tekshiring");
    }
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    HapticFeedback.lightImpact();
    if (mounted) setState(() {});
    if (_editingId != null) {
      final id = _editingId!;
      if (mounted) setState(() => _editingId = null);
      try {
        await _msgs.doc(id).update({'text': t, 'edited': true});
      } catch (_) {}
      return;
    }
    await _post({'text': t}, t);
  }

  Future<void> _sendImage(ImageSource source) async {
    try {
      final x = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1080,
        maxHeight: 1080,
        imageQuality: 55,
      );
      if (x == null) return;
      if (mounted) setState(() => _sending = true);
      final bytes = await x.readAsBytes();
      final b64 = base64Encode(bytes);
      if (b64.length > _maxImageChars) {
        if (mounted) setState(() => _sending = false);
        _snack('Rasm juda katta — kichikroq rasm tanlang');
        return;
      }
      // o'lchamlarni saqlaymiz: pufak joyni oldindan egallaydi (silkinmaydi)
      var w = 0, h = 0;
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        w = frame.image.width;
        h = frame.image.height;
        frame.image.dispose();
        codec.dispose();
      } catch (_) {}
      await _post({'text': '', 'image': b64, 'w': w, 'h': h}, '📷 Rasm');
      if (mounted) setState(() => _sending = false);
    } catch (_) {
      if (mounted) setState(() => _sending = false);
      _snack("Rasmni yuborib bo'lmadi");
    }
  }

  Future<void> _sendSticker(String s) => _post({'sticker': s}, s);

  // ---------------- ovozli xabar ----------------

  Future<void> _startRec() async {
    try {
      if (!await _rec.hasPermission()) {
        _snack('Mikrofonga ruxsat bering');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/v_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 48000,
          sampleRate: 22050,
          numChannels: 1,
        ),
        path: path,
      );
      HapticFeedback.mediumImpact();
      if (mounted) {
        setState(() {
          _recording = true;
          _recStart = DateTime.now();
          _recSecs = 0;
        });
      }
      _recTick?.cancel();
      _recTick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _recStart == null) return;
        final s = DateTime.now().difference(_recStart!).inSeconds;
        setState(() => _recSecs = s);
        if (s >= 60) _stopRec();
      });
    } catch (_) {
      _snack("Yozib bo'lmadi");
    }
  }

  Future<void> _stopRec({bool send = true}) async {
    if (!_recording) return;
    _recTick?.cancel();
    final secs =
        _recStart == null ? 0 : DateTime.now().difference(_recStart!).inSeconds;
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
    if (!send || path == null || secs < 1) return;
    try {
      final bytes = await File(path).readAsBytes();
      final b64 = base64Encode(bytes);
      if (b64.length > _maxImageChars) {
        _snack('Ovozli xabar juda uzun');
        return;
      }
      await _post({'text': '', 'voice': b64, 'dur': secs}, '🎤 Ovozli xabar');
    } catch (_) {
      _snack("Ovozli xabarni yuborib bo'lmadi");
    }
  }

  // ---------------- so'rovnoma ----------------

  Future<void> _newPoll() async {
    final q = TextEditingController();
    final os = List.generate(4, (_) => TextEditingController());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("So'rovnoma"),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: q,
                decoration: const InputDecoration(labelText: 'Savol')),
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: TextField(
                    controller: os[i],
                    decoration:
                        InputDecoration(labelText: 'Variant ${i + 1}')),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 46)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yuborish'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final opts =
        os.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (q.text.trim().isEmpty || opts.length < 2) {
      _snack('Savol va kamida 2 ta variant kerak');
      return;
    }
    await _post({
      'text': '',
      'poll': {'q': q.text.trim(), 'opts': opts, 'votes': {}},
    }, '📊 ${q.text.trim()}');
  }

  void _vote(String id, int idx, bool remove) {
    _msgs.doc(id).update({
      'poll.votes.$_me': remove ? FieldValue.delete() : idx,
    });
  }

  void _attachMenu() {
    final p = context.dj;
    Widget tile(IconData i, String t, String s, VoidCallback onTap) => ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: p.cardHi,
                shape: BoxShape.circle,
                border: Border.all(color: p.hairline)),
            child: Icon(i, color: p.ink, size: 21),
          ),
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(s),
          onTap: onTap,
        );
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SectionLabel('Qo\'shish',
              padding: EdgeInsets.fromLTRB(24, 4, 24, 4)),
          tile(Icons.image_outlined, 'Galereya', 'Telefondagi rasm', () {
            Navigator.pop(ctx);
            _sendImage(ImageSource.gallery);
          }),
          tile(Icons.photo_camera_outlined, 'Kamera', 'Hozir suratga olish',
              () {
            Navigator.pop(ctx);
            _sendImage(ImageSource.camera);
          }),
          tile(Icons.poll_outlined, "So'rovnoma", 'Variantlar bilan savol',
              () {
            Navigator.pop(ctx);
            _newPoll();
          }),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  // ---------------- boshqa amallar ----------------

  void _onChanged(String _) {
    setState(() {});
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTyping > 2500 && _chatExists && !widget.saved) {
      _lastTyping = now;
      _chatRef.set({
        'typing': {_me: now}
      }, SetOptions(merge: true));
    }
  }

  void _markRead(bool exists) {
    if (!exists) return;
    _chatRef.set({
      'unread': {_me: 0},
      'lastRead': {_me: FieldValue.serverTimestamp()},
      'lastReadMs': {_me: DateTime.now().millisecondsSinceEpoch},
    }, SetOptions(merge: true));
  }

  String _preview(Map<String, dynamic> m) {
    if (m['image'] != null) return '📷 Rasm';
    if (m['voice'] != null) return '🎤 Ovozli xabar';
    if (m['poll'] != null) return '📊 ${(m['poll'] as Map)['q']}';
    if (m['sticker'] != null) return m['sticker'] as String;
    return (m['text'] ?? '') as String;
  }

  void _react(String id, String emoji, bool remove) {
    HapticFeedback.selectionClick();
    _msgs.doc(id).update({
      'reactions.$_me': remove ? FieldValue.delete() : emoji,
    });
  }

  Map<String, dynamic> _copyData(Map<String, dynamic> m) {
    final d = <String, dynamic>{};
    for (final k in ['text', 'image', 'sticker', 'voice', 'dur', 'w', 'h']) {
      if (m[k] != null) d[k] = m[k];
    }
    if (m['poll'] != null) {
      final p = m['poll'] as Map;
      d['poll'] = {'q': p['q'], 'opts': p['opts'], 'votes': {}};
    }
    d['fwd'] = m['from'] == _me ? _myName : (m['fromName'] ?? '');
    return d;
  }

  Future<void> _saveToSaved(Map<String, dynamic> m) async {
    await writeMessage(
      chatId: 'saved_$_me',
      members: [_me],
      isGroup: false,
      saved: true,
      data: _copyData(m),
      preview: _preview(m),
    );
    _snack("Saqlangan xabarlarga qo'shildi");
  }

  void _forward(Map<String, dynamic> m) {
    final data = _copyData(m);
    final preview = _preview(m);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.68,
        child: Column(children: [
          const SectionLabel('Kimga uzatish',
              padding: EdgeInsets.fromLTRB(24, 4, 24, 6)),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .where('members', arrayContains: _me)
                  .snapshots(),
              builder: (c, s) {
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final targets = <_Target>[];
                var hasSaved = false;
                final seen = <String>{};
                for (final d in s.data!.docs) {
                  final x = d.data();
                  final isGroup = x['isGroup'] == true;
                  final saved = d.id == 'saved_$_me';
                  final members = ((x['members'] as List?) ?? []).cast<String>();
                  if (saved) hasSaved = true;
                  seen.add(d.id);
                  String title;
                  if (isGroup) {
                    title = (x['name'] ?? 'Guruh') as String;
                  } else if (saved) {
                    title = 'Saqlangan xabarlar';
                  } else {
                    title = userName(
                        members.firstWhere((e) => e != _me, orElse: () => _me));
                  }
                  targets.add(_Target(d.id, title, isGroup, saved, members));
                }
                if (!hasSaved) {
                  targets.add(_Target(
                      'saved_$_me', 'Saqlangan xabarlar', false, true, [_me]));
                }
                for (final e in usersCache.value.entries) {
                  if (e.key == _me) continue;
                  final id = pairId(_me, e.key);
                  if (seen.contains(id)) continue;
                  targets.add(_Target(id, (e.value['name'] ?? '?') as String,
                      false, false, [_me, e.key]));
                }
                return ListView.builder(
                  itemCount: targets.length,
                  itemBuilder: (c, i) {
                    final t = targets[i];
                    return ListTile(
                      leading: t.isGroup
                          ? Avatar(name: t.title, group: true, size: 44)
                          : t.saved
                              ? Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: goldGradient()),
                                  child: const Icon(Icons.bookmark_rounded,
                                      color: Colors.white, size: 20),
                                )
                              : UserAvatar(
                                  uid: t.members.firstWhere((e) => e != _me,
                                      orElse: () => _me),
                                  size: 44,
                                  showOnline: false),
                      title: Text(t.title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await writeMessage(
                          chatId: t.id,
                          members: t.members,
                          isGroup: t.isGroup,
                          saved: t.saved,
                          data: data,
                          preview: preview,
                        );
                        _snack('Yuborildi: ${t.title}');
                      },
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _options(String id, Map<String, dynamic> m, bool isPinned) {
    final mine = m['from'] == _me;
    final reactions = (m['reactions'] as Map?)?.cast<String, dynamic>() ?? {};
    final hasText = ((m['text'] ?? '') as String).isNotEmpty;
    final p = context.dj;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: _reactionEmojis.map((e) {
                  final on = reactions[_me] == e;
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _react(id, e, on);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(
                          horizontal: 3, vertical: 4),
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: on ? p.cardHi : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: on ? p.ink : Colors.transparent, width: 1.4),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 27)),
                    ),
                  );
                }).toList(),
              ),
            ),
            Divider(color: p.hairline, height: 10),
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Javob berish'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _editingId = null;
                  _reply = {
                    'id': id,
                    'name': mine ? 'Siz' : (m['fromName'] ?? '') as String,
                    'text': _preview(m),
                  };
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.forward_rounded),
              title: const Text('Uzatish'),
              onTap: () {
                Navigator.pop(ctx);
                _forward(m);
              },
            ),
            if (!widget.saved)
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: const Text('Saqlangan xabarlarga'),
                onTap: () {
                  Navigator.pop(ctx);
                  _saveToSaved(m);
                },
              ),
            ListTile(
              leading: Icon(isPinned
                  ? Icons.push_pin_outlined
                  : Icons.push_pin_rounded),
              title: Text(isPinned ? 'Qadashni olib tashlash' : 'Qadash'),
              onTap: () {
                Navigator.pop(ctx);
                if (isPinned) {
                  _chatRef.update({'pinnedMsg': FieldValue.delete()});
                } else {
                  _chatRef.set({
                    'pinnedMsg': {'id': id, 'text': _preview(m)}
                  }, SetOptions(merge: true));
                }
              },
            ),
            if (hasText)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Nusxalash'),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: m['text'] as String));
                  _snack('Nusxalandi');
                },
              ),
            if (mine && hasText)
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Tahrirlash'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _editingId = id;
                    _reply = null;
                    _text.text = m['text'] as String;
                  });
                },
              ),
            if (mine)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: p.danger),
                title: Text("O'chirish", style: TextStyle(color: p.danger)),
                onTap: () {
                  Navigator.pop(ctx);
                  _msgs.doc(id).delete();
                },
              ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  void _openStickers() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 300,
          child: GridView.count(
            crossAxisCount: 6,
            padding: const EdgeInsets.all(14),
            children: _stickers
                .map((s) => PressScale(
                      onTap: () {
                        Navigator.pop(ctx);
                        _sendSticker(s);
                      },
                      child: Center(
                          child:
                              Text(s, style: const TextStyle(fontSize: 34))),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  void _call(bool video) {
    final id = FirebaseFirestore.instance.collection('calls').doc().id;
    push(
      context,
      CallScreen(
        callId: id,
        isCaller: true,
        video: video,
        peerName: widget.title,
        peerId: widget.peerId!,
        myName: _myName,
      ),
      fullscreen: true,
    );
  }

  void _openInfo() {
    if (widget.isGroup) {
      push(context, GroupInfoScreen(chatId: widget.chatId));
    } else if (!widget.saved && widget.peerId != null) {
      push(context, UserProfileScreen(uid: widget.peerId!));
    }
  }

  // ---------------- pufak ----------------

  Widget _pollView(String id, Map<String, dynamic> m, Color textColor) {
    final poll = m['poll'] as Map;
    final opts = (poll['opts'] as List).cast<String>();
    final votes = (poll['votes'] as Map?)?.cast<String, dynamic>() ?? {};
    final total = votes.length;
    final my = votes[_me] as int?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${poll['q']}',
          style: TextStyle(
              color: textColor, fontSize: 15.5, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      for (var i = 0; i < opts.length; i++)
        Builder(builder: (_) {
          final cnt = votes.values.where((v) => v == i).length;
          final frac = total == 0 ? 0.0 : cnt / total;
          return InkWell(
            onTap: () => _vote(id, i, my == i),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(
                          my == i
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          size: 17,
                          color: textColor),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(opts[i],
                              style: TextStyle(color: textColor, fontSize: 14))),
                      Text('$cnt',
                          style: TextStyle(
                              color: textColor,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: frac),
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutCubic,
                        builder: (c, v, _) => Container(
                          height: 5,
                          color: textColor.withValues(alpha: 0.18),
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: v.clamp(0.0, 1.0),
                            child: Container(color: textColor),
                          ),
                        ),
                      ),
                    ),
                  ]),
            ),
          );
        }),
      const SizedBox(height: 2),
      Text('$total ovoz',
          style:
              TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.65))),
    ]);
  }

  Widget _imageView(String id, Map<String, dynamic> m) {
    final b64 = m['image'] as String;
    final bytes = imgBytes(id, b64);
    final w = (m['w'] is int && m['w'] > 0) ? (m['w'] as int) : 4;
    final h = (m['h'] is int && m['h'] > 0) ? (m['h'] as int) : 3;
    final ratio = (w / h).clamp(0.5, 2.0).toDouble();
    if (bytes == null) {
      return Container(
        width: 220,
        height: 160,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.broken_image_outlined, size: 30),
      );
    }
    return GestureDetector(
      onTap: () => Navigator.of(context).push(PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (c, a, b) => FadeTransition(
          opacity: a,
          child: FullImageView(tag: id, bytes: bytes),
        ),
      )),
      child: Hero(
        tag: id,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 248,
            height: 248 / ratio,
            child: Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              cacheWidth: 620,
              errorBuilder: (c, e, s) => Container(
                color: Colors.black12,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubble(String id, Map<String, dynamic> m, bool mine, DateTime? time,
      bool read, bool isPinned) {
    final p = context.dj;
    final reactions = (m['reactions'] as Map?)?.cast<String, dynamic>() ?? {};
    final counts = <String, int>{};
    for (final e in reactions.values) {
      counts[e as String] = (counts[e] ?? 0) + 1;
    }
    final sticker = m['sticker'] as String?;
    final textColor = mine ? p.mineOn : p.theirsOn;
    final text = (m['text'] ?? '') as String;
    final reply = m['reply'] as Map?;
    final wide = m['poll'] != null || m['voice'] != null;

    Widget body;
    if (sticker != null) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(sticker, style: const TextStyle(fontSize: 68)),
      );
    } else {
      final col =
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (m['fwd'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.subdirectory_arrow_right_rounded,
                  size: 13, color: textColor.withValues(alpha: 0.7)),
              const SizedBox(width: 3),
              Text('${m['fwd']}',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: textColor.withValues(alpha: 0.75))),
            ]),
          ),
        if (widget.isGroup && !mine)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              (m['fromName'] ?? '') as String,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.1,
                color: accents[colorIndexFor((m['from'] ?? '') as String)],
              ),
            ),
          ),
        if (reply != null)
          Container(
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.fromLTRB(9, 5, 9, 5),
            decoration: BoxDecoration(
              color: textColor.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(10),
              border: Border(
                  left: BorderSide(
                      color: textColor.withValues(alpha: 0.55), width: 2.5)),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((reply['name'] ?? '') as String,
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: textColor.withValues(alpha: 0.9))),
                  Text((reply['text'] ?? '') as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: textColor.withValues(alpha: 0.75))),
                ]),
          ),
        if (m['image'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: _imageView(id, m),
          ),
        if (m['voice'] != null)
          _VoiceBubble(
              b64: m['voice'] as String,
              dur: (m['dur'] is int) ? m['dur'] as int : 0,
              color: textColor),
        if (m['poll'] != null) _pollView(id, m, textColor),
        if (text.isNotEmpty)
          Text.rich(
            formatText(
              text,
              TextStyle(
                color: textColor,
                fontSize: isEmojiOnly(text) ? 38 : 15.5,
                height: 1.32,
              ),
            ),
          ),
        const SizedBox(height: 2),
        Align(
          alignment: Alignment.centerRight,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (isPinned)
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: Icon(Icons.push_pin_rounded,
                    size: 10, color: textColor.withValues(alpha: 0.6)),
              ),
            if (m['edited'] == true)
              Text('tahrirlangan · ',
                  style: TextStyle(
                      fontSize: 10, color: textColor.withValues(alpha: 0.6))),
            Text(
              time == null ? '' : fmtTime(time),
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: textColor.withValues(alpha: 0.6)),
            ),
            if (mine && !widget.isGroup && !widget.saved) ...[
              const SizedBox(width: 4),
              Icon(read ? Icons.done_all_rounded : Icons.done_rounded,
                  size: 14,
                  color: read ? p.gold : textColor.withValues(alpha: 0.6)),
            ],
          ]),
        ),
      ]);

      body = Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.fromLTRB(13, 9, 13, 7),
        decoration: BoxDecoration(
          color: mine ? p.mine : p.theirs,
          border: mine ? null : Border.all(color: p.hairline, width: 0.8),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(mine ? 20 : 6),
            bottomRight: Radius.circular(mine ? 6 : 20),
          ),
        ),
        child: wide ? SizedBox(width: 248, child: col) : IntrinsicWidth(child: col),
      );
    }

    return GestureDetector(
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _options(id, m, isPinned);
        },
        child: Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Column(
              crossAxisAlignment:
                  mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                body,
                if (counts.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Wrap(spacing: 4, children: [
                      for (final e in counts.entries)
                        GestureDetector(
                          onTap: () =>
                              _react(id, e.key, reactions[_me] == e.key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: reactions[_me] == e.key
                                  ? p.ink
                                  : p.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: p.hairline),
                            ),
                            child: Text(
                              e.value > 1 ? '${e.key} ${e.value}' : e.key,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: reactions[_me] == e.key
                                      ? p.inkOn
                                      : p.ink),
                            ),
                          ),
                        ),
                    ]),
                  ),
              ],
            ),
          ),
        ),
      );
  }

  Widget _banner(IconData icon, String title, String text, VoidCallback onClose) {
    final p = context.dj;
    return Container(
      color: p.bg,
      padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
      child: Row(children: [
        Icon(icon, color: p.gold, size: 19),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: p.gold, fontWeight: FontWeight.w800, fontSize: 12.5)),
            Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: p.muted)),
          ]),
        ),
        IconButton(
            icon: Icon(Icons.close_rounded, color: p.muted),
            onPressed: onClose),
      ]),
    );
  }

  Widget _inputBar() {
    final p = context.dj;
    if (_recording) {
      return Container(
        color: p.bg,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: SafeArea(
          top: false,
          child: Row(children: [
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: p.danger),
              onPressed: () => _stopRec(send: false),
            ),
            _RecDot(color: p.danger),
            const SizedBox(width: 8),
            Text(fmtDuration(_recSecs),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: p.ink)),
            const SizedBox(width: 12),
            Expanded(
                child: Text('Yozilmoqda...',
                    style: TextStyle(color: p.muted, fontSize: 13))),
            PressScale(
              onTap: () => _stopRec(),
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: p.ink, shape: BoxShape.circle),
                child: Icon(Icons.send_rounded, color: p.inkOn, size: 22),
              ),
            ),
          ]),
        ),
      );
    }

    final hasText = _text.text.trim().isNotEmpty || _editingId != null;
    final icon = _editingId != null
        ? Icons.check_rounded
        : hasText
            ? Icons.send_rounded
            : Icons.mic_rounded;
    return Container(
      color: p.bg,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: SafeArea(
        top: false,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: p.card,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: p.hairline, width: 0.8),
                boxShadow: p.soft,
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                IconButton(
                  icon: Icon(Icons.emoji_emotions_outlined, color: p.muted),
                  onPressed: _openStickers,
                ),
                Expanded(
                  child: TextField(
                    controller: _text,
                    onChanged: _onChanged,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(fontSize: 15.5, color: p.ink),
                    decoration: InputDecoration(
                      hintText: 'Xabar yozing',
                      hintStyle: TextStyle(color: p.faint),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 13),
                    ),
                  ),
                ),
                IconButton(
                  icon: _sending
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: p.muted),
                        )
                      : Icon(Icons.attach_file_rounded, color: p.muted),
                  onPressed: _sending ? null : _attachMenu,
                ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          PressScale(
            haptic: false,
            onTap: hasText ? _send : _startRec,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.ink,
                boxShadow: [
                  BoxShadow(
                    color: p.ink.withValues(alpha: 0.22),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (ch, an) =>
                    ScaleTransition(scale: an, child: ch),
                child: Icon(icon,
                    key: ValueKey(icon), color: p.inkOn, size: 22),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _dayChip(DateTime d) {
    final p = context.dj;
    final n = DateTime.now();
    String label;
    if (sameDay(d, n)) {
      label = 'Bugun';
    } else if (sameDay(d, n.subtract(const Duration(days: 1)))) {
      label = 'Kecha';
    } else {
      label = '${two(d.day)}.${two(d.month)}.${d.year}';
    }
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: p.card.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.hairline, width: 0.8),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: p.muted),
        ),
      ),
    );
  }

  Widget _callBanner(Map<String, dynamic> call) {
    final p = context.dj;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: p.online.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.online.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(Icons.videocam_rounded, color: p.online, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            "Guruhda qo'ng'iroq ketmoqda",
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 13.5, color: p.ink),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: p.online,
            foregroundColor: Colors.white,
            minimumSize: const Size(100, 38),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () => joinGroupCall(
            context,
            chatId: widget.chatId,
            title: widget.title,
            video: call['video'] != false,
          ),
          child: const Text("Qo'shilish"),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _chatRef.snapshots(),
      builder: (c, chatSnap) {
        final chat = chatSnap.data?.data();
        _chatExists = chatSnap.data?.exists ?? false;
        if (widget.isGroup && chat != null) {
          _groupMembers = ((chat['members'] as List?) ?? []).cast<String>();
        }
        final pinned = chat?['pinnedMsg'] as Map?;
        final pinnedId = pinned?['id'] as String?;
        final activeCall = chat?['activeCall'] as Map?;

        DateTime? peerRead;
        if (!widget.isGroup && !widget.saved && widget.peerId != null) {
          final lr = chat?['lastRead'];
          if (lr is Map && lr[widget.peerId] is Timestamp) {
            peerRead = (lr[widget.peerId] as Timestamp).toDate();
          }
          final lrm = chat?['lastReadMs'];
          if (lrm is Map && lrm[widget.peerId] is int) {
            final t = DateTime.fromMillisecondsSinceEpoch(
                lrm[widget.peerId] as int);
            if (peerRead == null || t.isAfter(peerRead)) peerRead = t;
          }
        }

        final now = DateTime.now().millisecondsSinceEpoch;
        final typingMap = (chat?['typing'] as Map?) ?? {};
        final typers = typingMap.entries
            .where((e) =>
                e.key != _me && e.value is int && now - (e.value as int) < 5000)
            .map((e) => e.key as String)
            .toList();
        final typing = typers.isNotEmpty;

        String sub;
        if (typing) {
          sub = widget.isGroup
              ? '${userName(typers.first)} yozmoqda'
              : 'yozmoqda';
        } else if (widget.saved) {
          sub = "o'zingiz uchun";
        } else if (widget.isGroup) {
          sub = "${_groupMembers.length} a'zo";
        } else {
          sub = lastSeenText(usersCache.value[widget.peerId]);
        }
        final subActive = typing || sub == 'onlayn';

        Widget avatar;
        if (widget.isGroup) {
          avatar = Avatar(name: widget.title, group: true, size: 40);
        } else if (widget.saved) {
          avatar = Container(
            width: 40,
            height: 40,
            decoration:
                BoxDecoration(shape: BoxShape.circle, gradient: goldGradient()),
            child: const Icon(Icons.bookmark_rounded,
                color: Colors.white, size: 19),
          );
        } else {
          avatar = UserAvatar(uid: widget.peerId!, size: 40);
        }

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: _searching
                ? TextField(
                    controller: _searchCtl,
                    autofocus: true,
                    onChanged: (v) => setState(() => _q = v.toLowerCase()),
                    decoration: const InputDecoration(
                      hintText: 'Xabarlardan qidirish',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  )
                : GestureDetector(
                    onTap: _openInfo,
                    behavior: HitTestBehavior.opaque,
                    child: Row(children: [
                      avatar,
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                  color: p.ink),
                            ),
                            Row(children: [
                              Flexible(
                                child: Text(
                                  sub,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        subActive ? p.online : p.muted,
                                  ),
                                ),
                              ),
                              if (typing) ...[
                                const SizedBox(width: 4),
                                TypingDots(color: p.online, size: 4),
                              ],
                            ]),
                          ],
                        ),
                      ),
                    ]),
                  ),
            actions: [
              IconButton(
                icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  _q = '';
                  _searchCtl.clear();
                }),
              ),
              if (!_searching && !widget.isGroup && !widget.saved) ...[
                IconButton(
                  tooltip: "Audio qo'ng'iroq",
                  icon: const Icon(Icons.call_rounded),
                  onPressed: () => _call(false),
                ),
                IconButton(
                  tooltip: "Video qo'ng'iroq",
                  icon: const Icon(Icons.videocam_rounded),
                  onPressed: () => _call(true),
                ),
              ],
              if (!_searching && widget.isGroup)
                IconButton(
                  tooltip: "Guruh video chat",
                  icon: const Icon(Icons.videocam_rounded),
                  onPressed: () => joinGroupCall(
                    context,
                    chatId: widget.chatId,
                    title: widget.title,
                    video: true,
                  ),
                ),
              const SizedBox(width: 4),
            ],
          ),
          body: ValueListenableBuilder<int>(
            valueListenable: wallpaperIndex,
            builder: (c, w, _) => Container(
              decoration: wallpapers[w] == null
                  ? null
                  : BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: wallpapers[w]!)),
              child: Column(children: [
                if (pinned != null)
                  Container(
                    color: p.bg,
                    padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                    child: Row(children: [
                      Container(width: 3, height: 32, color: p.gold),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Qadalgan xabar',
                                style: TextStyle(
                                    color: p.gold,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800)),
                            Text((pinned['text'] ?? '') as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    TextStyle(fontSize: 13, color: p.muted)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: p.muted),
                        onPressed: () =>
                            _chatRef.update({'pinnedMsg': FieldValue.delete()}),
                      ),
                    ]),
                  ),
                if (widget.isGroup && activeCall != null)
                  _callBanner(Map<String, dynamic>.from(activeCall)),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _msgs
                        .orderBy('time', descending: true)
                        .limit(200)
                        .snapshots(),
                    builder: (c, s) {
                      if (!s.hasData) {
                        return const Center(
                            child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ));
                      }
                      var docs = s.data!.docs;
                      if (docs.isNotEmpty && docs.first.id != _readUpTo) {
                        _readUpTo = docs.first.id;
                        final ex = _chatExists;
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) => _markRead(ex));
                      }
                      if (_searching && _q.isNotEmpty) {
                        docs = docs
                            .where((d) => ((d.data()['text'] ?? '') as String)
                                .toLowerCase()
                                .contains(_q))
                            .toList();
                      }
                      if (docs.isEmpty) {
                        return EmptyState(
                          icon: _searching
                              ? Icons.search_off_rounded
                              : Icons.waving_hand_outlined,
                          title: _searching
                              ? 'Hech narsa topilmadi'
                              : "Hali xabar yo'q",
                          subtitle: _searching
                              ? null
                              : "Birinchi bo'lib salom yozing",
                        );
                      }
                      return ListView.builder(
                        reverse: true,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        itemCount: docs.length,
                        itemBuilder: (c, i) {
                          final m = docs[i].data();
                          final mine = m['from'] == _me;
                          final time = msgTime(m);
                          final read = mine &&
                              peerRead != null &&
                              time != null &&
                              !time.isAfter(peerRead!);
                          final bubble = _bubble(docs[i].id, m, mine, time,
                              read, docs[i].id == pinnedId);
                          final older = i + 1 < docs.length
                              ? msgTime(docs[i + 1].data())
                              : null;
                          if (time != null &&
                              (older == null || !sameDay(time, older))) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [_dayChip(time), bubble],
                            );
                          }
                          return bubble;
                        },
                      );
                    },
                  ),
                ),
                if (_editingId != null)
                  _banner(Icons.edit_rounded, 'Tahrirlash', _text.text, () {
                    setState(() => _editingId = null);
                    _text.clear();
                  }),
                if (_reply != null)
                  _banner(
                    Icons.reply_rounded,
                    (_reply!['name'] ?? '') as String,
                    (_reply!['text'] ?? '') as String,
                    () => setState(() => _reply = null),
                  ),
                _inputBar(),
              ]),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
//  Yozib olish nuqtasi
// ---------------------------------------------------------------------------

class _RecDot extends StatefulWidget {
  final Color color;
  const _RecDot({required this.color});
  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _c,
        child: Container(
          width: 11,
          height: 11,
          decoration:
              BoxDecoration(color: widget.color, shape: BoxShape.circle),
        ),
      );
}

// ---------------------------------------------------------------------------
//  Ovozli xabar
// ---------------------------------------------------------------------------

class _VoiceBubble extends StatefulWidget {
  final String b64;
  final int dur;
  final Color color;
  const _VoiceBubble(
      {required this.b64, required this.dur, required this.color});
  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  final _p = AudioPlayer();
  final _subs = <StreamSubscription>[];
  bool _playing = false;
  bool _started = false;
  Duration _pos = Duration.zero;
  Duration _total = Duration.zero;
  late final List<double> _bars = List.generate(
      28, (i) => 0.25 + ((math.sin(i * 1.7) + 1) / 2) * 0.75);

  @override
  void initState() {
    super.initState();
    _subs.add(_p.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    }));
    _subs.add(_p.onPositionChanged.listen((d) {
      if (mounted) setState(() => _pos = d);
    }));
    _subs.add(_p.onDurationChanged.listen((d) {
      if (mounted) setState(() => _total = d);
    }));
    _subs.add(_p.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _playing = false;
          _started = false;
          _pos = Duration.zero;
        });
      }
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _p.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _p.pause();
      } else if (_started) {
        await _p.resume();
      } else {
        _started = true;
        await _p.play(BytesSource(base64Decode(widget.b64)));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final frac = _total.inMilliseconds == 0
        ? 0.0
        : (_pos.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0);
    final shown = (_playing || _started) ? _pos.inSeconds : widget.dur;
    return Row(children: [
      PressScale(
        haptic: false,
        onTap: _toggle,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: widget.color,
              size: 23),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: SizedBox(
          height: 26,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < _bars.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0.9),
                    child: Container(
                      height: 26 * _bars[i],
                      decoration: BoxDecoration(
                        color: widget.color.withValues(
                            alpha: (i / _bars.length) <= frac ? 0.95 : 0.28),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 9),
      Text(fmtDuration(shown),
          style: TextStyle(
              color: widget.color.withValues(alpha: 0.8),
              fontSize: 11.5,
              fontWeight: FontWeight.w600)),
    ]);
  }
}

// ---------------------------------------------------------------------------
//  Rasmni to'liq ekranda ochish
// ---------------------------------------------------------------------------

class FullImageView extends StatefulWidget {
  final String tag;
  final Uint8List bytes;
  const FullImageView({super.key, required this.tag, required this.bytes});

  @override
  State<FullImageView> createState() => _FullImageViewState();
}

class _FullImageViewState extends State<FullImageView> {
  final _ctl = TransformationController();
  double _drag = 0;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _doubleTap() {
    final zoomed = _ctl.value.getMaxScaleOnAxis() > 1.2;
    _ctl.value = zoomed
        ? Matrix4.identity()
        : Matrix4.diagonal3Values(2.4, 2.4, 1.0);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final opacity = (1 - (_drag.abs() / 320)).clamp(0.3, 1.0).toDouble();
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: opacity),
      body: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            onDoubleTap: _doubleTap,
            onVerticalDragUpdate: (d) {
              if (_ctl.value.getMaxScaleOnAxis() > 1.05) return;
              setState(() => _drag += d.delta.dy);
            },
            onVerticalDragEnd: (d) {
              if (_drag.abs() > 110) {
                Navigator.of(context).pop();
              } else {
                setState(() => _drag = 0);
              }
            },
            child: Transform.translate(
              offset: Offset(0, _drag),
              child: Center(
                child: Hero(
                  tag: widget.tag,
                  child: InteractiveViewer(
                    transformationController: _ctl,
                    minScale: 1,
                    maxScale: 5,
                    child: Image.memory(
                      widget.bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (c, e, s) => const Padding(
                        padding: EdgeInsets.all(40),
                        child: Text(
                          'Rasmni ochib bo\'lmadi',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 6,
          right: 8,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ]),
    );
  }
}
