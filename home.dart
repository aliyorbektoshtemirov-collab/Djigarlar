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
import 'username.dart';

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
  final _totalUnread = ValueNotifier<int>(0);
  Timer? _presence;
  int _tab = 0;
  bool _askingUsername = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _usersSub =
        FirebaseFirestore.instance.collection('users').snapshots().listen((s) {
      usersCache.value = {for (final d in s.docs) d.id: d.data()};
      _checkUsername();
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

  void _checkUsername() {
    final u = usersCache.value[_me];
    if (u == null || _askingUsername) return;
    if (((u['username'] ?? '') as String).isNotEmpty) return;
    _askingUsername = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showUsernameDialog(context, _me, required: true);
      _askingUsername = false;
    });
  }

  void _onChatChanges(QuerySnapshot<Map<String, dynamic>> snap) {
    var total = 0;
    for (final d in snap.docs) {
      final u = (d.data()['unread'] as Map?)?[_me];
      if (u is int) total += u;
    }
    _totalUnread.value = total;
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
    _totalUnread.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      ChatsTab(me: _me),
      ContactsTab(me: _me),
      ProfileScreen(me: _me),
    ];
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        for (var i = 0; i < pages.length; i++)
          IgnorePointer(
            ignoring: i != _tab,
            child: AnimatedOpacity(
              opacity: i == _tab ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              child: AnimatedSlide(
                offset: Offset((i - _tab) * 0.05, 0),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: pages[i],
              ),
            ),
          ),
      ]),
      bottomNavigationBar: _IosTabBar(
        index: _tab,
        unread: _totalUnread,
        onTap: (i) {
          if (i == _tab) return;
          HapticFeedback.selectionClick();
          setState(() => _tab = i);
        },
      ),
    );
  }
}

// ===================== iOS (Telegram) uslubidagi pastki panel =====================

class _TabDef {
  final IconData outline, filled;
  final String label;
  const _TabDef(this.outline, this.filled, this.label);
}

class _IosTabBar extends StatelessWidget {
  final int index;
  final ValueNotifier<int> unread;
  final ValueChanged<int> onTap;
  const _IosTabBar(
      {required this.index, required this.unread, required this.onTap});

  static const _items = [
    _TabDef(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Chatlar'),
    _TabDef(Icons.people_outline_rounded, Icons.people_rounded, 'Kontaktlar'),
    _TabDef(Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final light = Theme.of(context).brightness == Brightness.light;
    return Container(
      decoration: BoxDecoration(
        color: (light ? Colors.white : cs.surface).withValues(alpha: 0.97),
        border: Border(
            top: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.6), width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: _TabButton(
                  def: _items[i],
                  selected: i == index,
                  onTap: () => onTap(i),
                  badge: i == 0 ? unread : null,
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final _TabDef def;
  final bool selected;
  final VoidCallback onTap;
  final ValueNotifier<int>? badge;
  const _TabButton(
      {required this.def,
      required this.selected,
      required this.onTap,
      this.badge});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final target = selected ? cs.primary : cs.onSurfaceVariant;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: target),
        duration: const Duration(milliseconds: 220),
        builder: (c, col, _) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(clipBehavior: Clip.none, children: [
              AnimatedScale(
                scale: selected ? 1.12 : 1.0,
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Icon(selected ? def.filled : def.outline,
                      key: ValueKey(selected), size: 27, color: col),
                ),
              ),
              if (badge != null)
                Positioned(
                  right: -11,
                  top: -4,
                  child: ValueListenableBuilder<int>(
                    valueListenable: badge!,
                    builder: (c, n, _) => AnimatedScale(
                      scale: n > 0 ? 1 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutBack,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        padding:
                            const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(n > 99 ? '99+' : '$n',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 3),
            Text(def.label,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: col)),
          ],
        ),
      ),
    );
  }
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

  Widget _foundTile(BuildContext context, String id, Map<String, dynamic> u) {
    final cs = Theme.of(context).colorScheme;
    final name = (u['name'] ?? '?') as String;
    return SoftCard(
      child: ListTile(
        leading: UserAvatar(uid: id, size: 50),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('@${u['username']}', style: TextStyle(color: cs.primary)),
        trailing: IconButton(
          tooltip: 'Kontaktga saqlash',
          icon: const Icon(Icons.person_add_alt_1),
          onPressed: () async {
            await addContact(widget.me, id);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$name kontaktlarga saqlandi')));
            }
          },
        ),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ChatScreen(
                    chatId: pairId(widget.me, id),
                    title: name,
                    isGroup: false,
                    peerId: id))),
      ),
    );
  }

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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CreateGroupScreen())),
        icon: const Icon(Icons.group_add),
        label: const Text('Guruh', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(children: [
        Container(
          decoration: BoxDecoration(
            gradient: headerGradient(),
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(32)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              child: Column(children: [
                Row(children: [
                  ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.asset('assets/logo.png',
                          width: 38, height: 38)),
                  const SizedBox(width: 12),
                  const Text('Djigarlar',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 14),
                TextField(
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  onChanged: (v) => setState(() => _q = v.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Qidirish',
                    hintStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(Icons.search, color: Colors.white70),
                    fillColor: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
              ]),
            ),
          ),
        ),
        SizedBox(
          height: 54,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final e in ['Hammasi', 'Shaxsiy', 'Guruhlar', 'Arxiv']
                  .asMap()
                  .entries)
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
                final allItems = _build(s.data!);
                var items = allItems;
                items = _filter == 3
                    ? items.where((i) => i.archived).toList()
                    : items.where((i) => !i.archived).toList();
                if (_filter == 1) items = items.where((i) => !i.isGroup).toList();
                if (_filter == 2) items = items.where((i) => i.isGroup).toList();
                final qn = normalizeUsername(_q);
                if (_q.isNotEmpty) {
                  items = items
                      .where((i) =>
                          i.title.toLowerCase().contains(qn) ||
                          (i.peer != null && usernameOf(i.peer!).contains(qn)))
                      .toList();
                }
                final chatPeers =
                    allItems.map((i) => i.peer).whereType<String>().toSet();
                final found = (qn.length >= 2 && _filter != 2 && _filter != 3)
                    ? findByUsername(qn, widget.me)
                        .where((e) => !chatPeers.contains(e.key))
                        .toList()
                    : <UserEntry>[];
                items.sort((a, b) {
                  if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
                  final ta = a.time ?? DateTime.fromMillisecondsSinceEpoch(0);
                  final tb = b.time ?? DateTime.fromMillisecondsSinceEpoch(0);
                  return tb.compareTo(ta);
                });
                if (items.isEmpty && found.isEmpty) {
                  return Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.chat_bubble_outline,
                          size: 56, color: cs.outlineVariant),
                      const SizedBox(height: 12),
                      Text('Bu yerda hali hech narsa yo\'q',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ]),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(top: 2, bottom: 96),
                  itemCount: items.length + (found.isEmpty ? 0 : found.length + 1),
                  itemBuilder: (c, i) {
                    if (i >= items.length) {
                      final k = i - items.length;
                      if (k == 0) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                          child: Text("Username bo'yicha topildi",
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary)),
                        );
                      }
                      return _foundTile(context, found[k - 1].key, found[k - 1].value);
                    }
                    final it = items[i];
                    final peerStatus = it.peer == null
                        ? ''
                        : (usersCache.value[it.peer]?['status'] ?? '') as String;
                    final mineLast = it.lastFrom == widget.me;
                    final unread = it.unread > 0;
                    return SoftCard(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 4),
                        leading: _leading(it),
                        title: Row(children: [
                          Flexible(
                              child: Text(it.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16))),
                          if (peerStatus.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(peerStatus)
                          ],
                          if (it.pinned) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.push_pin, size: 14, color: cs.outline)
                          ],
                        ]),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            it.lastText.isEmpty
                                ? (it.saved
                                    ? 'Eslatmalar va fayllar'
                                    : "Xabar yo'q")
                                : (mineLast ? 'Siz: ${it.lastText}' : it.lastText),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontWeight:
                                    unread ? FontWeight.w600 : FontWeight.w400,
                                color: unread
                                    ? cs.onSurface
                                    : cs.onSurfaceVariant),
                          ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (it.time != null)
                              Text(fmtChatTime(it.time!),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: unread
                                          ? cs.primary
                                          : cs.onSurfaceVariant)),
                            if (unread) ...[
                              const SizedBox(height: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                    gradient: headerGradient(),
                                    borderRadius: BorderRadius.circular(12)),
                                child: Text('${it.unread}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
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
                      ),
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

  Widget _header(String t) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: Text(t,
          style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary)),
    );
  }

  Widget _tile(String id, Map<String, dynamic> u, {required bool saved}) {
    final cs = Theme.of(context).colorScheme;
    final name = (u['name'] ?? '?') as String;
    final status = (u['status'] ?? '') as String;
    final un = (u['username'] ?? '') as String;
    final online = isOnline(u);
    final sub = un.isNotEmpty
        ? '@$un${online ? ' · onlayn' : ''}'
        : (online ? 'onlayn' : lastSeenText(u));
    return SoftCard(
      child: ListTile(
        leading: GestureDetector(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => UserProfileScreen(uid: id))),
          child: UserAvatar(uid: id, size: 50),
        ),
        title: Row(children: [
          Flexible(
              child: Text(name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          if (status.isNotEmpty) ...[const SizedBox(width: 4), Text(status)],
        ]),
        subtitle: Text(sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: online ? cs.primary : cs.onSurfaceVariant)),
        trailing: saved
            ? PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'del') removeContact(widget.me, id);
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'del', child: Text("Kontaktdan o'chirish")),
                ],
              )
            : IconButton(
                tooltip: 'Kontaktga saqlash',
                icon: const Icon(Icons.person_add_alt_1),
                onPressed: () async {
                  await addContact(widget.me, id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$name kontaktlarga saqlandi')));
                  }
                },
              ),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ChatScreen(
                    chatId: pairId(widget.me, id),
                    title: name,
                    isGroup: false,
                    peerId: id))),
      ),
    );
  }

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
            autocorrect: false,
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(
                hintText: 'Ism yoki @username',
                prefixIcon: Icon(Icons.search)),
          ),
        ),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: usersCache,
            builder: (c, map, _) {
              final qn = normalizeUsername(_q);
              final saved = myContacts(widget.me).where(map.containsKey).toList();
              final mine = saved.where((id) {
                if (qn.isEmpty) return true;
                final u = map[id]!;
                return ((u['name'] ?? '') as String).toLowerCase().contains(qn) ||
                    ((u['username'] ?? '') as String).contains(qn);
              }).toList()
                ..sort((a, b) => ((map[a]!['name'] ?? '') as String)
                    .toLowerCase()
                    .compareTo(((map[b]!['name'] ?? '') as String).toLowerCase()));
              final found = qn.length >= 2
                  ? findByUsername(qn, widget.me)
                      .where((e) => !saved.contains(e.key))
                      .toList()
                  : <UserEntry>[];
              if (mine.isEmpty && found.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      qn.isEmpty
                          ? "Kontaktlar yo'q.\nDo'stingizning @username ini qidiruvga yozing va saqlang."
                          : 'Hech kim topilmadi',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  if (mine.isNotEmpty) _header('Mening kontaktlarim'),
                  for (final id in mine) _tile(id, map[id]!, saved: true),
                  if (found.isNotEmpty) _header("Username bo'yicha topildi"),
                  for (final e in found) _tile(e.key, e.value, saved: false),
                ],
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
  String _q = '';
  bool _busy = false;

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return _snack('Guruh nomini kiriting');
    if (_picked.isEmpty) return _snack("Kamida bitta a'zo tanlang");
    setState(() => _busy = true);
    try {
      final ref = await FirebaseFirestore.instance.collection('chats').add({
        'name': name,
        'isGroup': true,
        'members': [_me, ..._picked],
        'createdBy': _me,
        'createdAt': FieldValue.serverTimestamp(),
        'lastTime': FieldValue.serverTimestamp(),
        'lastText': 'Guruh yaratildi',
        'lastFrom': '',
      });
      if (!mounted) return;
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  ChatScreen(chatId: ref.id, title: name, isGroup: true)));
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('Guruh yaratib bo\'lmadi: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Yangi guruh')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Guruh nomi', prefixIcon: Icon(Icons.group))),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autocorrect: false,
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(
                hintText: "Kontakt yoki @username qidirish",
                prefixIcon: Icon(Icons.search)),
          ),
        ),
        Expanded(
          child: ValueListenableBuilder(
            valueListenable: usersCache,
            builder: (c, map, _) {
              final qn = normalizeUsername(_q);
              final saved = myContacts(_me).where(map.containsKey).toList();
              final matchSaved = saved.where((id) {
                if (qn.isEmpty) return true;
                final u = map[id]!;
                return ((u['name'] ?? '') as String).toLowerCase().contains(qn) ||
                    ((u['username'] ?? '') as String).contains(qn);
              });
              final found = qn.length >= 2
                  ? findByUsername(qn, _me).map((e) => e.key)
                  : <String>[];
              final ids = <String>[
                ...matchSaved,
                ..._picked.where((id) => !saved.contains(id) && map.containsKey(id)),
                ...found.where((id) => !saved.contains(id) && !_picked.contains(id)),
              ];
              if (ids.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      "Kontaktlar yo'q.\nDo'stingizning @username ini qidiruvga yozing.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                );
              }
              return ListView(
                children: [
                  for (final id in ids)
                    CheckboxListTile(
                      secondary: UserAvatar(uid: id, size: 42),
                      title: Text((map[id]?['name'] ?? '?') as String),
                      subtitle: ((map[id]?['username'] ?? '') as String).isEmpty
                          ? null
                          : Text('@${map[id]!['username']}'),
                      value: _picked.contains(id),
                      onChanged: (v) => setState(() {
                        v == true ? _picked.add(id) : _picked.remove(id);
                      }),
                    ),
                ],
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
                onPressed: _busy ? null : _create,
                child: Text(_picked.isEmpty
                    ? 'Guruh yaratish'
                    : 'Guruh yaratish (${_picked.length + 1} a\'zo)')),
          ),
        ),
      ]),
    );
  }
}
