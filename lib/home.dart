import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'call.dart';
import 'chat.dart';
import 'info.dart';
import 'main.dart' show navKey;
import 'profile.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final String _me = FirebaseAuth.instance.currentUser!.uid;
  final _shown = <String>{};
  StreamSubscription? _callSub, _usersSub, _msgSub;
  final _notified = <String, String>{};
  Timer? _presence;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _usersSub =
        FirebaseFirestore.instance.collection('users').snapshots().listen((s) {
      usersCache.value = {for (final d in s.docs) d.id: d.data()};
    });
    _msgSub = FirebaseFirestore.instance
        .collection('chats')
        .where('members', arrayContains: _me)
        .snapshots()
        .listen(_onChatChanges);
    _ping();
    _presence = Timer.periodic(const Duration(seconds: 30), (_) => _ping());
    _callSub = FirebaseFirestore.instance
        .collection('calls')
        .where('to', isEqualTo: _me)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen((snap) {
      for (final ch in snap.docChanges) {
        if (ch.type != DocumentChangeType.added) continue;
        final data = ch.doc.data();
        if (data == null) continue;
        final ts = (data['ts'] ?? 0) as int;
        if (DateTime.now().millisecondsSinceEpoch - ts > 45000) continue;
        if (_shown.add(ch.doc.id)) _showIncoming(ch.doc.id, data);
      }
    });
  }

  void _onChatChanges(QuerySnapshot<Map<String, dynamic>> snap) {
    for (final ch in snap.docChanges) {
      if (ch.type != DocumentChangeType.modified) continue;
      final d = ch.doc.data();
      if (d == null) continue;
      final from = (d['lastFrom'] ?? '') as String;
      if (from.isEmpty || from == _me) continue;
      final unread = ((d['unread'] as Map?)?[_me] ?? 0) as int;
      if (unread <= 0 || openChatId == ch.doc.id) continue;
      final key = '$unread|${d['lastText']}';
      if (_notified[ch.doc.id] == key) continue;
      _notified[ch.doc.id] = key;
      final isGroup = d['isGroup'] == true;
      final title = isGroup ? ((d['name'] ?? 'Guruh') as String) : userName(from);
      final ctx = navKey.currentContext;
      if (ctx == null) continue;
      HapticFeedback.mediumImpact();
      final m = ScaffoldMessenger.of(ctx);
      m.hideCurrentSnackBar();
      m.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        content: Text('$title: ${d['lastText'] ?? ''}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        action: SnackBarAction(
          label: 'Ochish',
          onPressed: () => navKey.currentState?.push(MaterialPageRoute(
              builder: (_) => ChatScreen(
                  chatId: ch.doc.id,
                  title: title,
                  isGroup: isGroup,
                  peerId: isGroup ? null : from))),
        ),
      ));
    }
  }

  Future<void> _ping() async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(_me).set(
          {'lastSeen': DateTime.now().millisecondsSinceEpoch},
          SetOptions(merge: true));
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _ping();
  }

  Future<void> _showIncoming(String id, Map<String, dynamic> data) async {
    final ctx = navKey.currentContext;
    if (ctx == null) return;
    final accepted = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _IncomingDialog(
          callId: id,
          fromId: data['from'] as String,
          name: (data['fromName'] ?? '?') as String,
          video: data['video'] == true),
    );
    final ref = FirebaseFirestore.instance.collection('calls').doc(id);
    if (accepted == true) {
      navKey.currentState?.push(MaterialPageRoute(
          builder: (_) => CallScreen(
              callId: id,
              isCaller: false,
              video: data['video'] == true,
              peerName: (data['fromName'] ?? '?') as String,
              peerId: data['from'] as String,
              myName: '')));
    } else if (accepted == false) {
      await ref.update({'status': 'declined'});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callSub?.cancel();
    _usersSub?.cancel();
    _msgSub?.cancel();
    _presence?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: [
          ChatsTab(me: _me),
          ContactsTab(me: _me),
          ProfileScreen(me: _me),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: 'Chatlar'),
            NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Kontaktlar'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profil'),
          ],
        ),
      );
}

class _IncomingDialog extends StatefulWidget {
  final String callId, fromId, name;
  final bool video;
  const _IncomingDialog(
      {required this.callId,
      required this.fromId,
      required this.name,
      required this.video});
  @override
  State<_IncomingDialog> createState() => _IncomingDialogState();
}

class _IncomingDialogState extends State<_IncomingDialog> {
  StreamSubscription? _sub;
  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .snapshots()
        .listen((s) {
      final st = s.data()?['status'];
      if (st != 'ringing' && mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          UserAvatar(uid: widget.fromId, size: 80, showOnline: false),
          const SizedBox(height: 14),
          Text(widget.name,
              style:
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(widget.video ? "Video qo'ng'iroq" : "Audio qo'ng'iroq"),
        ]),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: Colors.red),
              iconSize: 30,
              onPressed: () => Navigator.pop(context, false),
              icon: const Icon(Icons.call_end)),
          IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: Colors.green),
              iconSize: 30,
              onPressed: () => Navigator.pop(context, true),
              icon: Icon(widget.video ? Icons.videocam : Icons.call)),
        ],
      );
}

// ===================== CHATLAR =====================

class _ChatItem {
  final String id, title;
  final bool isGroup, saved, pinned, archived;
  final String? peer;
  final String lastText, lastFrom;
  final DateTime? time;
  final int unread;
  _ChatItem(
      {required this.id,
      required this.title,
      required this.isGroup,
      required this.saved,
      required this.pinned,
      required this.archived,
      this.peer,
      this.lastText = '',
      this.lastFrom = '',
      this.time,
      this.unread = 0});
}

class ChatsTab extends StatefulWidget {
  final String me;
  const ChatsTab({super.key, required this.me});
  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> {
  int _filter = 0;
  String _q = '';

  List<_ChatItem> _build(QuerySnapshot<Map<String, dynamic>> snap) {
    final me = widget.me;
    final pinnedIds =
        ((usersCache.value[me]?['pinned']) as List?)?.cast<String>() ??
            <String>[];
    final archivedIds =
        ((usersCache.value[me]?['archived']) as List?)?.cast<String>() ??
            <String>[];
    final items = <_ChatItem>[];
    var hasSaved = false;
    for (final d in snap.docs) {
      final data = d.data();
      final isGroup = data['isGroup'] == true;
      final saved = d.id == 'saved_$me';
      if (saved) hasSaved = true;
      String title;
      String? peer;
      if (isGroup) {
        title = (data['name'] ?? 'Guruh') as String;
      } else if (saved) {
        title = 'Saqlangan xabarlar';
      } else {
        final members = ((data['members'] as List?) ?? []).cast<String>();
        peer = members.firstWhere((m) => m != me, orElse: () => me);
        title = userName(peer);
      }
      final unreadMap = (data['unread'] as Map?) ?? {};
      items.add(_ChatItem(
        id: d.id,
        title: title,
        isGroup: isGroup,
        saved: saved,
        pinned: pinnedIds.contains(d.id),
        archived: archivedIds.contains(d.id),
        peer: peer,
        lastText: (data['lastText'] ?? '') as String,
        lastFrom: (data['lastFrom'] ?? '') as String,
        time: (data['lastTime'] as Timestamp?)?.toDate(),
        unread: (unreadMap[me] ?? 0) as int,
      ));
    }
    if (!hasSaved) {
      items.add(_ChatItem(
          id: 'saved_$me',
          title: 'Saqlangan xabarlar',
          isGroup: false,
          saved: true,
          pinned: pinnedIds.contains('saved_$me'),
          archived: archivedIds.contains('saved_$me')));
    }
    return items;
  }

  void _pinSheet(_ChatItem it) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(it.pinned ? Icons.push_pin_outlined : Icons.push_pin),
            title: Text(it.pinned ? 'Qadashni olib tashlash' : 'Qadash'),
            onTap: () {
              Navigator.pop(ctx);
              FirebaseFirestore.instance.collection('users').doc(widget.me).set({
                'pinned': it.pinned
                    ? FieldValue.arrayRemove([it.id])
                    : FieldValue.arrayUnion([it.id])
              }, SetOptions(merge: true));
            },
          ),
          ListTile(
            leading: Icon(it.archived ? Icons.unarchive : Icons.archive_outlined),
            title: Text(it.archived ? 'Arxivdan chiqarish' : 'Arxivlash'),
            onTap: () {
              Navigator.pop(ctx);
              FirebaseFirestore.instance.collection('users').doc(widget.me).set({
                'archived': it.archived
                    ? FieldValue.arrayRemove([it.id])
                    : FieldValue.arrayUnion([it.id])
              }, SetOptions(merge: true));
            },
          ),
        ]),
      ),
    );
  }

  Widget _leading(_ChatItem it) {
    if (it.isGroup) {
      return Avatar(
          name: it.title,
          group: true,
          size: 54,
          colorIdx: it.title.codeUnits.fold<int>(0, (a, b) => a + b) %
              accents.length);
    }
    if (it.saved) {
      return CircleAvatar(
          radius: 27,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Icon(Icons.bookmark,
              color: Theme.of(context).colorScheme.onPrimary));
    }
    return UserAvatar(uid: it.peer!, size: 54);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset('assets/logo.png', width: 30, height: 30)),
          const SizedBox(width: 10),
          const Text('Djigarlar',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        ]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CreateGroupScreen())),
        child: const Icon(Icons.group_add),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
            decoration: const InputDecoration(
                hintText: 'Qidirish', prefixIcon: Icon(Icons.search)),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final e in ['Hammasi', 'Shaxsiy', 'Guruhlar', 'Arxiv'].asMap().entries)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: _filter == e.key,
                    onSelected: (_) => setState(() => _filter = e.key),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: usersCache,
            builder: (c, _, __) =>
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .where('members', arrayContains: widget.me)
                  .snapshots(),
              builder: (c, s) {
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                var items = _build(s.data!);
                items = _filter == 3
                    ? items.where((i) => i.archived).toList()
                    : items.where((i) => !i.archived).toList();
                if (_filter == 1) items = items.where((i) => !i.isGroup).toList();
                if (_filter == 2) items = items.where((i) => i.isGroup).toList();
                if (_q.isNotEmpty) {
                  items = items
                      .where((i) => i.title.toLowerCase().contains(_q))
                      .toList();
                }
                items.sort((a, b) {
                  if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
                  final ta = a.time ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final tb = b.time ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return tb.compareTo(ta);
                });
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (c, i) {
                    final it = items[i];
                    final peerStatus = it.peer == null
                        ? ''
                        : (usersCache.value[it.peer]?['status'] ?? '') as String;
                    final mineLast = it.lastFrom == widget.me;
                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      leading: _leading(it),
                      title: Row(children: [
                        Flexible(
                            child: Text(it.title,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 16))),
                        if (peerStatus.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Text(peerStatus)
                        ],
                        if (it.pinned) ...[
                          const SizedBox(width: 4),
                          Icon(Icons.push_pin, size: 14, color: cs.outline)
                        ],
                      ]),
                      subtitle: Text(
                        it.lastText.isEmpty
                            ? (it.saved ? "Eslatmalar va fayllar" : 'Xabar yo\'q')
                            : (mineLast ? 'Siz: ${it.lastText}' : it.lastText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (it.time != null)
                            Text(fmtChatTime(it.time!),
                                style: TextStyle(
                                    fontSize: 12, color: cs.onSurfaceVariant)),
                          if (it.unread > 0) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                  color: cs.primary,
                                  borderRadius: BorderRadius.circular(12)),
                              child: Text('${it.unread}',
                                  style: TextStyle(
                                      color: cs.onPrimary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ],
                      ),
                      onLongPress: () => _pinSheet(it),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                    chatId: it.id,
                                    title: it.title,
                                    isGroup: it.isGroup,
                                    saved: it.saved,
                                    peerId: it.peer,
                                  ))),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

// ===================== KONTAKTLAR =====================

class ContactsTab extends StatefulWidget {
  final String me;
  const ContactsTab({super.key, required this.me});
  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
          title: const Text('Kontaktlar',
              style: TextStyle(fontWeight: FontWeight.w700))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
            decoration: const InputDecoration(
                hintText: 'Ism bo\'yicha qidirish', prefixIcon: Icon(Icons.search)),
          ),
        ),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: usersCache,
            builder: (c, map, _) {
              final list = map.entries
                  .where((e) => e.key != widget.me)
                  .where((e) =>
                      ((e.value['name'] ?? '') as String)
                          .toLowerCase()
                          .contains(_q))
                  .toList();
              if (list.isEmpty) {
                return const Center(child: Text('Hech kim topilmadi'));
              }
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (c, i) {
                  final id = list[i].key;
                  final u = list[i].value;
                  final name = (u['name'] ?? '?') as String;
                  final status = (u['status'] ?? '') as String;
                  final bio = (u['bio'] ?? '') as String;
                  return ListTile(
                    leading: GestureDetector(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => UserProfileScreen(uid: id))),
                      child: UserAvatar(uid: id, size: 50),
                    ),
                    title: Row(children: [
                      Flexible(
                          child: Text(name,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600))),
                      if (status.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(status)
                      ],
                    ]),
                    subtitle: Text(
                      isOnline(u) ? 'onlayn' : (bio.isNotEmpty ? bio : lastSeenText(u)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: isOnline(u) ? cs.primary : cs.onSurfaceVariant),
                    ),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ChatScreen(
                                chatId: pairId(widget.me, id),
                                title: name,
                                isGroup: false,
                                peerId: id))),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ===================== GURUH YARATISH =====================

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});
  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _name = TextEditingController();
  final _picked = <String>{};
  final String _me = FirebaseAuth.instance.currentUser!.uid;
  bool _busy = false;

  Future<void> _create() async {
    if (_name.text.trim().isEmpty || _picked.isEmpty) return;
    setState(() => _busy = true);
    await FirebaseFirestore.instance.collection('chats').add({
      'name': _name.text.trim(),
      'isGroup': true,
      'members': [_me, ..._picked],
      'createdBy': _me,
      'createdAt': FieldValue.serverTimestamp(),
      'lastTime': FieldValue.serverTimestamp(),
      'lastText': 'Guruh yaratildi',
      'lastFrom': '',
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Yangi guruh')),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
                controller: _name,
                decoration: const InputDecoration(
                    labelText: 'Guruh nomi', prefixIcon: Icon(Icons.group))),
          ),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: usersCache,
              builder: (c, map, _) => ListView(
                children: map.entries
                    .where((e) => e.key != _me)
                    .map((e) => CheckboxListTile(
                          secondary: UserAvatar(uid: e.key, size: 42),
                          title: Text((e.value['name'] ?? '?') as String),
                          value: _picked.contains(e.key),
                          onChanged: (v) => setState(() {
                            v == true ? _picked.add(e.key) : _picked.remove(e.key);
                          }),
                        ))
                    .toList(),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                  onPressed: _busy ? null : _create,
                  child: const Text('Guruh yaratish')),
            ),
          ),
        ]),
      );
}
