import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'call.dart';
import 'info.dart';
import 'theme.dart';

const _reactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏', '🔥', '🎉'];
const _stickers = [
  '😀', '😂', '🥹', '😍', '😎', '🤩', '😭', '😡', '🥳', '🤔', '🙄', '😴',
  '👍', '👎', '👏', '🙏', '💪', '🤝', '❤️', '🔥', '🎉', '✨', '💯', '🤣',
  '😘', '😇', '🤗', '😱', '🥰', '😉', '😅', '🫶'
];

/// Istalgan chatga xabar yozadi (oddiy yuborish, uzatish, saqlash uchun).
Future<void> writeMessage({
  required String chatId,
  required List<String> members,
  required bool isGroup,
  required bool saved,
  required Map<String, dynamic> data,
  required String preview,
}) async {
  final me = FirebaseAuth.instance.currentUser!.uid;
  final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);
  if (!isGroup) {
    await chatRef.set({
      'members': members,
      'isGroup': false,
      'saved': saved,
    }, SetOptions(merge: true));
  }
  await chatRef.collection('messages').add({
    'from': me,
    'fromName': userName(me),
    'time': FieldValue.serverTimestamp(),
    ...data,
  });
  final others = members.where((m) => m != me).toList();
  await chatRef.set({
    'lastText': preview,
    'lastFrom': me,
    'lastTime': FieldValue.serverTimestamp(),
    if (others.isNotEmpty)
      'unread': {for (final o in others) o: FieldValue.increment(1)},
  }, SetOptions(merge: true));
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
  const ChatScreen(
      {super.key,
      required this.chatId,
      required this.title,
      required this.isGroup,
      this.saved = false,
      this.peerId});
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
  Timer? _tick;
  int _lastTyping = 0;
  String? _readUpTo;
  List<String> _groupMembers = [];
  bool _chatExists = false;
  bool _searching = false;
  String _q = '';
  bool _recording = false;
  DateTime? _recStart;

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
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_recording &&
          _recStart != null &&
          DateTime.now().difference(_recStart!).inSeconds >= 60) {
        _stopRec();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    if (openChatId == widget.chatId) openChatId = null;
    _tick?.cancel();
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
    setState(() => _reply = null);
    await writeMessage(
        chatId: widget.chatId,
        members: _members,
        isGroup: widget.isGroup,
        saved: widget.saved,
        data: data,
        preview: preview);
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    setState(() {});
    if (_editingId != null) {
      final id = _editingId!;
      setState(() => _editingId = null);
      await _msgs.doc(id).update({'text': t, 'edited': true});
      return;
    }
    await _post({'text': t}, t);
  }

  Future<void> _sendImage() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 1024, imageQuality: 60);
    if (x == null) return;
    final b64 = base64Encode(await x.readAsBytes());
    if (b64.length > 900000) {
      _snack('Rasm juda katta');
      return;
    }
    await _post({'text': '', 'image': b64}, '📷 Rasm');
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
              numChannels: 1),
          path: path);
      setState(() {
        _recording = true;
        _recStart = DateTime.now();
      });
    } catch (e) {
      _snack('Yozib bo\'lmadi: $e');
    }
  }

  Future<void> _stopRec({bool send = true}) async {
    if (!_recording) return;
    final secs = DateTime.now().difference(_recStart!).inSeconds;
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    setState(() => _recording = false);
    if (!send || path == null || secs < 1) return;
    final bytes = await File(path).readAsBytes();
    final b64 = base64Encode(bytes);
    if (b64.length > 900000) {
      _snack('Ovozli xabar juda uzun');
      return;
    }
    await _post({'text': '', 'voice': b64, 'dur': secs}, '🎤 Ovozli xabar');
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
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                    controller: os[i],
                    decoration: InputDecoration(labelText: 'Variant ${i + 1}')),
              ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yuborish')),
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
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('Rasm'),
            onTap: () {
              Navigator.pop(ctx);
              _sendImage();
            },
          ),
          ListTile(
            leading: const Icon(Icons.poll_outlined),
            title: const Text("So'rovnoma"),
            onTap: () {
              Navigator.pop(ctx);
              _newPoll();
            },
          ),
        ]),
      ),
    );
  }

  // ---------------- boshqa amallar ----------------

  void _onChanged(String _) {
    setState(() {});
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTyping > 2500 && _chatExists) {
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
    _msgs.doc(id).update({
      'reactions.$_me': remove ? FieldValue.delete() : emoji,
    });
  }

  Map<String, dynamic> _copyData(Map<String, dynamic> m) {
    final d = <String, dynamic>{};
    for (final k in ['text', 'image', 'sticker', 'voice', 'dur']) {
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
        preview: _preview(m));
    _snack('Saqlangan xabarlarga qo\'shildi');
  }

  void _forward(Map<String, dynamic> m) {
    final data = _copyData(m);
    final preview = _preview(m);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.65,
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
                title = userName(members.firstWhere((e) => e != _me,
                    orElse: () => _me));
              }
              targets.add(_Target(d.id, title, isGroup, saved, members));
            }
            if (!hasSaved) {
              targets.add(_Target('saved_$_me', 'Saqlangan xabarlar', false,
                  true, [_me]));
            }
            for (final e in usersCache.value.entries) {
              if (e.key == _me) continue;
              final id = pairId(_me, e.key);
              if (seen.contains(id)) continue;
              targets.add(_Target(id, (e.value['name'] ?? '?') as String,
                  false, false, [_me, e.key]));
            }
            return ListView(
              children: targets
                  .map((t) => ListTile(
                        leading: t.isGroup
                            ? Avatar(name: t.title, group: true, size: 42)
                            : t.saved
                                ? const CircleAvatar(child: Icon(Icons.bookmark))
                                : UserAvatar(
                                    uid: t.members.firstWhere((e) => e != _me,
                                        orElse: () => _me),
                                    size: 42,
                                    showOnline: false),
                        title: Text(t.title),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await writeMessage(
                              chatId: t.id,
                              members: t.members,
                              isGroup: t.isGroup,
                              saved: t.saved,
                              data: data,
                              preview: preview);
                          _snack('Yuborildi: ${t.title}');
                        },
                      ))
                  .toList(),
            );
          },
        ),
      ),
    );
  }

  void _options(String id, Map<String, dynamic> m, bool isPinned) {
    final mine = m['from'] == _me;
    final reactions = (m['reactions'] as Map?)?.cast<String, dynamic>() ?? {};
    final hasText = ((m['text'] ?? '') as String).isNotEmpty;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: _reactionEmojis
                    .map((e) => InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () {
                            Navigator.pop(ctx);
                            _react(id, e, reactions[_me] == e);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Text(e, style: const TextStyle(fontSize: 30)),
                          ),
                        ))
                    .toList(),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.reply),
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
              leading: const Icon(Icons.forward),
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
              leading: Icon(isPinned ? Icons.push_pin_outlined : Icons.push_pin),
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
                leading: const Icon(Icons.copy),
                title: const Text('Nusxalash'),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: m['text'] as String));
                },
              ),
            if (mine && hasText)
              ListTile(
                leading: const Icon(Icons.edit),
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
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title:
                    const Text("O'chirish", style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _msgs.doc(id).delete();
                },
              ),
          ]),
        ),
      ),
    );
  }

  void _openStickers() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 280,
          child: GridView.count(
            crossAxisCount: 6,
            padding: const EdgeInsets.all(12),
            children: _stickers
                .map((s) => InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.pop(ctx);
                        _sendSticker(s);
                      },
                      child: Center(
                          child: Text(s, style: const TextStyle(fontSize: 34))),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  void _call(bool video) {
    final id = FirebaseFirestore.instance.collection('calls').doc().id;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CallScreen(
                callId: id,
                isCaller: true,
                video: video,
                peerName: widget.title,
                peerId: widget.peerId!,
                myName: _myName)));
  }

  void _openInfo() {
    if (widget.isGroup) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => GroupInfoScreen(chatId: widget.chatId)));
    } else if (!widget.saved && widget.peerId != null) {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => UserProfileScreen(uid: widget.peerId!)));
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
      Text('📊 ${poll['q']}',
          style: TextStyle(
              color: textColor, fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      for (var i = 0; i < opts.length; i++)
        Builder(builder: (_) {
          final cnt = votes.values.where((v) => v == i).length;
          final frac = total == 0 ? 0.0 : cnt / total;
          return InkWell(
            onTap: () => _vote(id, i, my == i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(my == i ? Icons.check_circle : Icons.circle_outlined,
                      size: 18, color: textColor),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(opts[i], style: TextStyle(color: textColor))),
                  Text('$cnt', style: TextStyle(color: textColor)),
                ]),
                const SizedBox(height: 3),
                Container(
                  height: 5,
                  decoration: BoxDecoration(
                      color: textColor.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(3)),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: frac,
                    child: Container(
                        decoration: BoxDecoration(
                            color: textColor,
                            borderRadius: BorderRadius.circular(3))),
                  ),
                ),
              ]),
            ),
          );
        }),
      Text('$total ovoz',
          style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.7))),
    ]);
  }

  Widget _bubble(String id, Map<String, dynamic> m, bool mine, DateTime? time,
      bool read, bool isPinned) {
    final cs = Theme.of(context).colorScheme;
    final reactions = (m['reactions'] as Map?)?.cast<String, dynamic>() ?? {};
    final counts = <String, int>{};
    for (final e in reactions.values) {
      counts[e as String] = (counts[e] ?? 0) + 1;
    }
    final sticker = m['sticker'] as String?;
    final textColor = mine ? cs.onPrimary : cs.onSurface;
    final text = (m['text'] ?? '') as String;
    final reply = m['reply'] as Map?;
    final fixed = m['poll'] != null || m['voice'] != null;

    Widget body;
    if (sticker != null) {
      body = Text(sticker, style: const TextStyle(fontSize: 70));
    } else {
      final col = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (m['fwd'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text('↪ ${m['fwd']}',
                style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: textColor.withOpacity(0.8))),
          ),
        if (widget.isGroup && !mine)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text((m['fromName'] ?? '') as String,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accents[colorIndexFor(m['from'] as String)])),
          ),
        if (reply != null)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            decoration: BoxDecoration(
              color: textColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                  left: BorderSide(
                      color: mine ? cs.onPrimary : cs.primary, width: 3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((reply['name'] ?? '') as String,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: mine ? cs.onPrimary : cs.primary)),
              Text((reply['text'] ?? '') as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: textColor)),
            ]),
          ),
        if (m['image'] != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: GestureDetector(
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => _ImageView(b64: m['image'] as String))),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(base64Decode(m['image'] as String),
                    gaplessPlayback: true),
              ),
            ),
          ),
        if (m['voice'] != null)
          _VoiceBubble(
              b64: m['voice'] as String,
              dur: (m['dur'] ?? 0) as int,
              color: textColor),
        if (m['poll'] != null) _pollView(id, m, textColor),
        if (text.isNotEmpty)
          Text.rich(formatText(
              text,
              TextStyle(
                  color: textColor, fontSize: isEmojiOnly(text) ? 40 : 16))),
        Align(
          alignment: Alignment.centerRight,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (isPinned)
              Icon(Icons.push_pin, size: 11, color: textColor.withOpacity(0.7)),
            if (m['edited'] == true)
              Text(' tahrirlangan ',
                  style: TextStyle(
                      fontSize: 10, color: textColor.withOpacity(0.7))),
            Text(time == null ? '' : ' ${fmtTime(time)}',
                style:
                    TextStyle(fontSize: 11, color: textColor.withOpacity(0.7))),
            if (mine && !widget.isGroup && !widget.saved) ...[
              const SizedBox(width: 3),
              Icon(read ? Icons.done_all : Icons.done,
                  size: 15,
                  color: read
                      ? const Color(0xFF9BE7FF)
                      : textColor.withOpacity(0.7)),
            ],
          ]),
        ),
      ]);

      body = Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          gradient: mine
              ? LinearGradient(colors: [
                  cs.primary,
                  Color.lerp(cs.primary, cs.tertiary, 0.35)!
                ])
              : null,
          color: mine ? null : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: fixed ? SizedBox(width: 250, child: col) : IntrinsicWidth(child: col),
      );
    }

    return GestureDetector(
      onLongPress: () => _options(id, m, isPinned),
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
                  padding: const EdgeInsets.only(top: 2),
                  child: Wrap(spacing: 4, children: [
                    for (final e in counts.entries)
                      GestureDetector(
                        onTap: () => _react(id, e.key, reactions[_me] == e.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: reactions[_me] == e.key
                                ? cs.primaryContainer
                                : cs.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: cs.outlineVariant),
                          ),
                          child: Text(
                              e.value > 1 ? '${e.key} ${e.value}' : e.key,
                              style: const TextStyle(fontSize: 14)),
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
      child: Row(children: [
        Icon(icon, color: cs.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        IconButton(icon: const Icon(Icons.close), onPressed: onClose),
      ]),
    );
  }

  Widget _inputBar(ColorScheme cs) {
    if (_recording) {
      final secs = _recStart == null
          ? 0
          : DateTime.now().difference(_recStart!).inSeconds;
      return Container(
        color: cs.surface,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: SafeArea(
          top: false,
          child: Row(children: [
            IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _stopRec(send: false)),
            const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
            const SizedBox(width: 6),
            Text('${secs ~/ 60}:${two(secs % 60)}',
                style: const TextStyle(fontSize: 16)),
            const Spacer(),
            CircleAvatar(
              radius: 24,
              backgroundColor: cs.primary,
              child: IconButton(
                  icon: Icon(Icons.send, color: cs.onPrimary),
                  onPressed: () => _stopRec()),
            ),
          ]),
        ),
      );
    }
    final hasText = _text.text.trim().isNotEmpty || _editingId != null;
    return Container(
      color: cs.surface,
      padding: const EdgeInsets.fromLTRB(6, 6, 8, 8),
      child: SafeArea(
        top: false,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(
              icon: const Icon(Icons.emoji_emotions_outlined),
              onPressed: _openStickers),
          Expanded(
            child: TextField(
              controller: _text,
              onChanged: _onChanged,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Xabar'),
            ),
          ),
          IconButton(icon: const Icon(Icons.attach_file), onPressed: _attachMenu),
          CircleAvatar(
            radius: 24,
            backgroundColor: cs.primary,
            child: IconButton(
              icon: Icon(
                  _editingId != null
                      ? Icons.check
                      : hasText
                          ? Icons.send
                          : Icons.mic,
                  color: cs.onPrimary),
              onPressed: hasText ? _send : _startRec,
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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

        Timestamp? peerRead;
        if (!widget.isGroup && !widget.saved && widget.peerId != null) {
          final lr = chat?['lastRead'];
          if (lr is Map && lr[widget.peerId] is Timestamp) {
            peerRead = lr[widget.peerId] as Timestamp;
          }
        }

        final now = DateTime.now().millisecondsSinceEpoch;
        final typingMap = (chat?['typing'] as Map?) ?? {};
        final typers = typingMap.entries
            .where((e) =>
                e.key != _me && e.value is int && now - (e.value as int) < 4000)
            .map((e) => e.key as String)
            .toList();
        final typing = typers.isNotEmpty;

        String sub;
        if (typing) {
          sub = widget.isGroup
              ? '${userName(typers.first)} yozmoqda...'
              : 'yozmoqda...';
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
          avatar = CircleAvatar(
              radius: 20,
              backgroundColor: cs.primary,
              child: Icon(Icons.bookmark, color: cs.onPrimary));
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
                    decoration: const InputDecoration(hintText: 'Xabarlardan qidirish'),
                  )
                : GestureDetector(
                    onTap: _openInfo,
                    behavior: HitTestBehavior.opaque,
                    child: Row(children: [
                      avatar,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 17, fontWeight: FontWeight.w700)),
                              Text(sub,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: subActive
                                          ? cs.primary
                                          : cs.onSurfaceVariant)),
                            ]),
                      ),
                    ]),
                  ),
            actions: [
              IconButton(
                  icon: Icon(_searching ? Icons.close : Icons.search),
                  onPressed: () => setState(() {
                        _searching = !_searching;
                        _q = '';
                        _searchCtl.clear();
                      })),
              if (!_searching && !widget.isGroup && !widget.saved) ...[
                IconButton(
                    tooltip: "Audio qo'ng'iroq",
                    icon: const Icon(Icons.call),
                    onPressed: () => _call(false)),
                IconButton(
                    tooltip: "Video qo'ng'iroq",
                    icon: const Icon(Icons.videocam),
                    onPressed: () => _call(true)),
              ],
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
                    color: cs.surface,
                    padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                    child: Row(children: [
                      Container(width: 3, height: 34, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Qadalgan xabar',
                                  style: TextStyle(
                                      color: cs.primary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                              Text((pinned['text'] ?? '') as String,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ]),
                      ),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () =>
                              _chatRef.update({'pinnedMsg': FieldValue.delete()})),
                    ]),
                  ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _msgs
                        .orderBy('time', descending: true)
                        .limit(200)
                        .snapshots(),
                    builder: (c, s) {
                      if (!s.hasData) return const SizedBox();
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
                        return Center(
                            child: Text(
                                _searching
                                    ? 'Hech narsa topilmadi'
                                    : "Hali xabar yo'q. Birinchi bo'lib yozing 👋",
                                style: TextStyle(color: cs.onSurfaceVariant)));
                      }
                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        itemCount: docs.length,
                        itemBuilder: (c, i) {
                          final m = docs[i].data();
                          final mine = m['from'] == _me;
                          final time = (m['time'] as Timestamp?)?.toDate();
                          final read = mine &&
                              peerRead != null &&
                              time != null &&
                              !time.isAfter(peerRead.toDate());
                          return _bubble(docs[i].id, m, mine, time, read,
                              docs[i].id == pinnedId);
                        },
                      );
                    },
                  ),
                ),
                if (_editingId != null)
                  _banner(Icons.edit, 'Tahrirlash', _text.text, () {
                    setState(() => _editingId = null);
                    _text.clear();
                  }),
                if (_reply != null)
                  _banner(Icons.reply, (_reply!['name'] ?? '') as String,
                      (_reply!['text'] ?? '') as String,
                      () => setState(() => _reply = null)),
                _inputBar(cs),
              ]),
            ),
          ),
        );
      },
    );
  }
}

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
    if (_playing) {
      await _p.pause();
    } else if (_started) {
      await _p.resume();
    } else {
      _started = true;
      await _p.play(BytesSource(base64Decode(widget.b64)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final frac = _total.inMilliseconds == 0
        ? 0.0
        : (_pos.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0);
    final shown = _playing || _started ? _pos.inSeconds : widget.dur;
    return Row(children: [
      IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle,
            size: 38, color: widget.color),
        onPressed: _toggle,
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Container(
          height: 4,
          decoration: BoxDecoration(
              color: widget.color.withOpacity(0.25),
              borderRadius: BorderRadius.circular(2)),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: frac,
            child: Container(
                decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(2))),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text('${shown ~/ 60}:${two(shown % 60)}',
          style: TextStyle(color: widget.color, fontSize: 12)),
    ]);
  }
}

class _ImageView extends StatelessWidget {
  final String b64;
  const _ImageView({required this.b64});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(
          child: InteractiveViewer(child: Image.memory(base64Decode(b64))),
        ),
      );
}
