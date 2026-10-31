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
import 'ui.dart';
import 'username.dart';

/// `lastTime` serverTimestamp bo'lgani uchun xabar yuborilgan zahoti u `null`
/// bo'lib turadi (server javobigacha). Shuning uchun mijoz tomonidagi
/// `lastTimeMs` birinchi o'qiladi — chat darrov tepaga chiqadi va vaqt ko'rinadi.
DateTime? chatTimeOf(Map<String, dynamic> data) {
  final ms = data['lastTimeMs'];
  if (ms is int && ms > 0) return DateTime.fromMillisecondsSinceEpoch(ms);
  final t = data['lastTime'];
  if (t is Timestamp) return t.toDate();
  return null;
}

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
  bool _inCall = false;

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
        final ts = (data['ts'] ?? 0);
        if (ts is! int) continue;
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
      final unread = ((d['unread'] as Map?)?[_me] ?? 0);
      if (unread is! int || unread <= 0 || openChatId == ch.doc.id) continue;
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
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 110),
        content: Row(children: [
          if (!isGroup) UserAvatar(uid: from, size: 32, showOnline: false),
          if (!isGroup) const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${d['lastText'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w400)),
              ],
            ),
          ),
        ]),
        action: SnackBarAction(
          label: 'Ochish',
          onPressed: () => navKey.currentState?.push(DjPage<void>(ChatScreen(
            chatId: ch.doc.id,
            title: title,
            isGroup: isGroup,
            peerId: isGroup ? null : from,
          ))),
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
    if (_inCall) return;
    final nav = navKey.currentState;
    if (nav == null) return;
    _inCall = true;
    final accepted = await nav.push<bool>(DjPage<bool>(
      IncomingCallScreen(
        callId: id,
        fromId: (data['from'] ?? '') as String,
        name: (data['fromName'] ?? '?') as String,
        video: data['video'] == true,
      ),
      fullscreen: true,
    ));
    final ref = FirebaseFirestore.instance.collection('calls').doc(id);
    if (accepted == true) {
      await nav.push<void>(DjPage<void>(
        CallScreen(
          callId: id,
          isCaller: false,
          video: data['video'] == true,
          peerName: (data['fromName'] ?? '?') as String,
          peerId: (data['from'] ?? '') as String,
          myName: userName(_me),
        ),
        fullscreen: true,
      ));
    } else if (accepted == false) {
      try {
        await ref.update({'status': 'declined'});
      } catch (_) {}
    }
    _inCall = false;
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

  void _newSheet() {
    final p = context.dj;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SectionLabel('Yangi', padding: EdgeInsets.fromLTRB(24, 4, 24, 4)),
          ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: p.cardHi,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.hairline)),
              child: Icon(Icons.person_search_rounded, color: p.ink, size: 21),
            ),
            title: const Text('Odam topish',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('@username orqali qidirish'),
            onTap: () {
              Navigator.pop(ctx);
              setState(() => _tab = 1);
            },
          ),
          ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: p.cardHi,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.hairline)),
              child: Icon(Icons.groups_rounded, color: p.ink, size: 21),
            ),
            title: const Text('Yangi guruh',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text("A'zolarni tanlang"),
            onTap: () {
              Navigator.pop(ctx);
              push(context, const CreateGroupScreen());
            },
          ),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      ChatsTab(me: _me),
      ContactsTab(me: _me),
      CallsTab(me: _me),
      ProfileScreen(me: _me),
    ];
    return Scaffold(
      extendBody: true,
      body: Stack(fit: StackFit.expand, children: [
        for (var i = 0; i < pages.length; i++)
          IgnorePointer(
            ignoring: i != _tab,
            child: AnimatedOpacity(
              opacity: i == _tab ? 1 : 0,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOut,
              child: AnimatedSlide(
                offset: Offset(0, i == _tab ? 0 : 0.015),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: pages[i],
              ),
            ),
          ),
      ]),
      bottomNavigationBar: DjTabBar(
        index: _tab,
        badge: _totalUnread,
        onCenter: _newSheet,
        centerIcon: Icons.edit_rounded,
        tabs: const [
          DjTab(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded,
              'Chatlar'),
          DjTab(Icons.people_outline_rounded, Icons.people_rounded,
              'Kontaktlar'),
          DjTab(Icons.call_outlined, Icons.call_rounded, "Qo'ng'iroq"),
          DjTab(Icons.person_outline_rounded, Icons.person_rounded, 'Profil'),
        ],
        onTap: (i) {
          if (i == _tab) return;
          setState(() => _tab = i);
        },
      ),
    );
  }
}

// ===================== CHATLAR =====================

class _ChatItem {
  final String id, title;
  final bool isGroup, saved, pinned, archived;
  final String? peer;
  final String lastText, lastFrom;
  final DateTime? time;
  final int unread;
  final bool hasCall;
  _ChatItem({
    required this.id,
    required this.title,
    required this.isGroup,
    required this.saved,
    required this.pinned,
    required this.archived,
    this.peer,
    this.lastText = '',
    this.lastFrom = '',
    this.time,
    this.unread = 0,
    this.hasCall = false,
  });
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
      final un = unreadMap[me];
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
        time: chatTimeOf(data),
        unread: un is int ? un : 0,
        hasCall: data['activeCall'] != null,
      ));
    }
    if (!hasSaved) {
      items.add(_ChatItem(
        id: 'saved_$me',
        title: 'Saqlangan xabarlar',
        isGroup: false,
        saved: true,
        pinned: pinnedIds.contains('saved_$me'),
        archived: archivedIds.contains('saved_$me'),
      ));
    }
    return items;
  }

  void _longPress(_ChatItem it) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(it.pinned
                ? Icons.push_pin_outlined
                : Icons.push_pin_rounded),
            title: Text(it.pinned ? 'Qadashni olib tashlash' : 'Qadash'),
            onTap: () {
              Navigator.pop(ctx);
              FirebaseFirestore.instance
                  .collection('users')
                  .doc(widget.me)
                  .set({
                'pinned': it.pinned
                    ? FieldValue.arrayRemove([it.id])
                    : FieldValue.arrayUnion([it.id])
              }, SetOptions(merge: true));
            },
          ),
          ListTile(
            leading: Icon(it.archived
                ? Icons.unarchive_outlined
                : Icons.archive_outlined),
            title: Text(it.archived ? 'Arxivdan chiqarish' : 'Arxivlash'),
            onTap: () {
              Navigator.pop(ctx);
              FirebaseFirestore.instance
                  .collection('users')
                  .doc(widget.me)
                  .set({
                'archived': it.archived
                    ? FieldValue.arrayRemove([it.id])
                    : FieldValue.arrayUnion([it.id])
              }, SetOptions(merge: true));
            },
          ),
          const SizedBox(height: 8),
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
        colorIdx:
            it.title.codeUnits.fold<int>(0, (a, b) => a + b) % accents.length,
      );
    }
    if (it.saved) {
      final p = context.dj;
      return Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: goldGradient(),
        ),
        child: const Icon(Icons.bookmark_rounded, color: Colors.white, size: 24),
      ).withRing(p);
    }
    return UserAvatar(uid: it.peer!, size: 54);
  }

  Widget _row(_ChatItem it) {
    final p = context.dj;
    final mineLast = it.lastFrom == widget.me;
    final unread = it.unread > 0;
    final preview = it.lastText.isEmpty
        ? (it.saved ? 'Eslatmalar va fayllar' : "Xabar yo'q")
        : (mineLast ? 'Siz: ${it.lastText}' : it.lastText);
    return PressScale(
      scale: 0.985,
      haptic: false,
      onTap: () => push(
        context,
        ChatScreen(
          chatId: it.id,
          title: it.title,
          isGroup: it.isGroup,
          saved: it.saved,
          peerId: it.peer,
        ),
      ),
      onLongPress: () => _longPress(it),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        child: Row(children: [
          _leading(it),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(
                      it.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.5,
                        letterSpacing: -0.2,
                        color: p.ink,
                      ),
                    ),
                  ),
                  if (it.pinned) ...[
                    const SizedBox(width: 5),
                    Icon(Icons.push_pin_rounded, size: 12, color: p.faint),
                  ],
                  if (it.hasCall) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: p.online.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.videocam_rounded,
                            size: 11, color: p.online),
                        const SizedBox(width: 3),
                        Text('jonli',
                            style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: p.online)),
                      ]),
                    ),
                  ],
                ]),
                const SizedBox(height: 3),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.25,
                    fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                    color: unread ? p.ink : p.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                it.time == null ? '' : fmtChatTime(it.time!),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: unread ? p.gold : p.faint,
                ),
              ),
              const SizedBox(height: 7),
              AnimatedScale(
                scale: unread ? 1 : 0,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutBack,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 21),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.ink,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    it.unread > 99 ? '99+' : '${it.unread}',
                    style: TextStyle(
                      color: p.inkOn,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _foundRow(String id, Map<String, dynamic> u) {
    final p = context.dj;
    final name = (u['name'] ?? '?') as String;
    return PressScale(
      scale: 0.985,
      haptic: false,
      onTap: () => push(
        context,
        ChatScreen(
            chatId: pairId(widget.me, id),
            title: name,
            isGroup: false,
            peerId: id),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(children: [
          UserAvatar(uid: id, size: 50),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: p.ink)),
                Text('@${u['username'] ?? ''}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.gold)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Kontaktga saqlash',
            icon: Icon(Icons.person_add_alt_1_rounded, color: p.ink, size: 20),
            onPressed: () async {
              await addContact(widget.me, id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$name kontaktlarga saqlandi')));
              }
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          BigHeader(
            title: 'Djigarlar',
            kicker: 'Suhbatlar',
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Image.asset('assets/logo.png',
                  width: 42,
                  height: 42,
                  errorBuilder: (c, e, s) => const SizedBox(width: 42)),
            ),
          ),
          SearchPill(
            hint: 'Ism yoki @username',
            onChanged: (v) => setState(() => _q = v.toLowerCase()),
          ),
          FilterPills(
            items: const ['Hammasi', 'Shaxsiy', 'Guruhlar', 'Arxiv'],
            selected: _filter,
            onSelect: (i) => setState(() => _filter = i),
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
                  if (!s.hasData) return const ChatListSkeleton();
                  final allItems = _build(s.data!);
                  var items = _filter == 3
                      ? allItems.where((i) => i.archived).toList()
                      : allItems.where((i) => !i.archived).toList();
                  if (_filter == 1) {
                    items = items.where((i) => !i.isGroup).toList();
                  }
                  if (_filter == 2) {
                    items = items.where((i) => i.isGroup).toList();
                  }
                  final qn = normalizeUsername(_q);
                  if (_q.isNotEmpty) {
                    items = items
                        .where((i) =>
                            i.title.toLowerCase().contains(qn) ||
                            (i.peer != null &&
                                usernameOf(i.peer!).contains(qn)))
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
                    return EmptyState(
                      icon: Icons.forum_outlined,
                      title: _q.isEmpty
                          ? "Hali suhbat yo'q"
                          : 'Hech kim topilmadi',
                      subtitle: _q.isEmpty
                          ? "Do'stingizning @username ini qidiruvga yozing yoki pastdagi tugmadan yangi suhbat boshlang."
                          : "Boshqa @username bilan urinib ko'ring.",
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.only(top: 4, bottom: 130),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      if (items.isNotEmpty)
                        FadeSlideIn(
                          index: 0,
                          child: SheetGroup(
                            children: [for (final it in items) _row(it)],
                          ),
                        ),
                      if (found.isNotEmpty) ...[
                        const SectionLabel("Username bo'yicha topildi"),
                        FadeSlideIn(
                          index: 1,
                          child: SheetGroup(
                            children: [
                              for (final e in found) _foundRow(e.key, e.value)
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

extension _Ring on Widget {
  Widget withRing(DjPalette p) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: p.hairline, width: 0.8),
        ),
        clipBehavior: Clip.antiAlias,
        child: this,
      );
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

  Widget _tile(String id, Map<String, dynamic> u, {required bool saved}) {
    final p = context.dj;
    final name = (u['name'] ?? '?') as String;
    final status = (u['status'] ?? '') as String;
    final un = (u['username'] ?? '') as String;
    final online = isOnline(u);
    final sub = un.isNotEmpty ? '@$un' : lastSeenText(u);
    return PressScale(
      scale: 0.985,
      haptic: false,
      onTap: () => push(
        context,
        ChatScreen(
            chatId: pairId(widget.me, id),
            title: name,
            isGroup: false,
            peerId: id),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(children: [
          GestureDetector(
            onTap: () => push(context, UserProfileScreen(uid: id)),
            child: UserAvatar(uid: id, size: 50),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: p.ink)),
                  ),
                  if (status.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    Text(status, style: const TextStyle(fontSize: 13)),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(
                  online ? '$sub · onlayn' : sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: online ? p.online : p.muted,
                  ),
                ),
              ],
            ),
          ),
          if (saved)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz_rounded, color: p.faint),
              onSelected: (v) {
                if (v == 'del') removeContact(widget.me, id);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'del', child: Text("Kontaktdan o'chirish")),
              ],
            )
          else
            IconButton(
              tooltip: 'Kontaktga saqlash',
              icon: Icon(Icons.person_add_alt_1_rounded, color: p.ink, size: 20),
              onPressed: () async {
                await addContact(widget.me, id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$name kontaktlarga saqlandi')));
                }
              },
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const BigHeader(title: 'Kontaktlar', kicker: "Do'stlar"),
          SearchPill(
            hint: 'Ism yoki @username',
            onChanged: (v) => setState(() => _q = v),
          ),
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: usersCache,
              builder: (c, map, _) {
                final qn = normalizeUsername(_q);
                final saved =
                    myContacts(widget.me).where(map.containsKey).toList();
                final mine = saved.where((id) {
                  if (qn.isEmpty) return true;
                  final u = map[id]!;
                  return ((u['name'] ?? '') as String)
                          .toLowerCase()
                          .contains(qn) ||
                      ((u['username'] ?? '') as String).contains(qn);
                }).toList()
                  ..sort((a, b) => ((map[a]!['name'] ?? '') as String)
                      .toLowerCase()
                      .compareTo(
                          ((map[b]!['name'] ?? '') as String).toLowerCase()));
                final found = qn.length >= 2
                    ? findByUsername(qn, widget.me)
                        .where((e) => !saved.contains(e.key))
                        .toList()
                    : <UserEntry>[];

                if (mine.isEmpty && found.isEmpty) {
                  return EmptyState(
                    icon: Icons.person_search_rounded,
                    title: qn.isEmpty
                        ? "Kontaktlar yo'q"
                        : 'Hech kim topilmadi',
                    subtitle: qn.isEmpty
                        ? "Do'stingizning @username ini qidiruvga yozing va + tugmasi bilan saqlang."
                        : null,
                  );
                }

                return ListView(
                  padding: const EdgeInsets.only(top: 2, bottom: 130),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    if (mine.isNotEmpty) ...[
                      const SectionLabel('Mening kontaktlarim'),
                      FadeSlideIn(
                        index: 0,
                        child: SheetGroup(
                          children: [
                            for (final id in mine)
                              _tile(id, map[id]!, saved: true)
                          ],
                        ),
                      ),
                    ],
                    if (found.isNotEmpty) ...[
                      const SectionLabel("Username bo'yicha topildi"),
                      FadeSlideIn(
                        index: 1,
                        child: SheetGroup(
                          children: [
                            for (final e in found)
                              _tile(e.key, e.value, saved: false)
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ===================== QO'NG'IROQLAR TARIXI =====================

class CallsTab extends StatelessWidget {
  final String me;
  const CallsTab({super.key, required this.me});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const BigHeader(title: "Qo'ng'iroqlar", kicker: 'Tarix'),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db
                  .collection('calls')
                  .where('from', isEqualTo: me)
                  .limit(40)
                  .snapshots(),
              builder: (c, outS) =>
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: db
                    .collection('calls')
                    .where('to', isEqualTo: me)
                    .limit(40)
                    .snapshots(),
                builder: (c2, inS) {
                  final rows = <Map<String, dynamic>>[];
                  for (final d in [
                    ...?outS.data?.docs,
                    ...?inS.data?.docs,
                  ]) {
                    final x = d.data();
                    final ts = x['ts'];
                    if (ts is! int) continue;
                    rows.add({...x, 'id': d.id});
                  }
                  rows.sort((a, b) =>
                      ((b['ts'] ?? 0) as int).compareTo((a['ts'] ?? 0) as int));
                  if (!outS.hasData && !inS.hasData) {
                    return const ChatListSkeleton();
                  }
                  if (rows.isEmpty) {
                    return const EmptyState(
                      icon: Icons.call_outlined,
                      title: "Qo'ng'iroqlar yo'q",
                      subtitle:
                          "Suhbat ichidagi telefon yoki kamera tugmasini bosing.",
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.only(top: 6, bottom: 130),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      FadeSlideIn(
                        child: SheetGroup(
                          children: [
                            for (final r in rows.take(50))
                              _CallRow(row: r, me: me)
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _CallRow extends StatelessWidget {
  final Map<String, dynamic> row;
  final String me;
  const _CallRow({required this.row, required this.me});

  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    final out = row['from'] == me;
    final other = (out ? row['to'] : row['from']) as String? ?? '';
    final video = row['video'] == true;
    final status = (row['status'] ?? '') as String;
    final dur = row['duration'];
    final missed = !out && (status == 'declined' || dur == null || dur == 0);
    final ts = (row['ts'] ?? 0) as int;
    final name = userName(other);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(children: [
        UserAvatar(uid: other, size: 46, showOnline: false),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: missed ? p.danger : p.ink,
                ),
              ),
              const SizedBox(height: 2),
              Row(children: [
                Icon(
                  missed
                      ? Icons.call_missed_rounded
                      : (out
                          ? Icons.call_made_rounded
                          : Icons.call_received_rounded),
                  size: 13,
                  color: missed ? p.danger : p.muted,
                ),
                const SizedBox(width: 5),
                Text(
                  '${video ? 'Video' : 'Audio'}'
                  '${dur is int && dur > 0 ? ' · ${fmtDuration(dur)}' : ''}'
                  '${ts > 0 ? ' · ${fmtChatTime(DateTime.fromMillisecondsSinceEpoch(ts))}' : ''}',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: p.muted),
                ),
              ]),
            ],
          ),
        ),
        if (other.isNotEmpty)
          IconButton(
            icon: Icon(video ? Icons.videocam_rounded : Icons.call_rounded,
                color: p.ink, size: 20),
            onPressed: () => push(
              context,
              ChatScreen(
                chatId: pairId(me, other),
                title: name,
                isGroup: false,
                peerId: other,
              ),
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
      final now = DateTime.now().millisecondsSinceEpoch;
      final ref = await FirebaseFirestore.instance.collection('chats').add({
        'name': name,
        'isGroup': true,
        'members': [_me, ..._picked],
        'createdBy': _me,
        'createdAt': FieldValue.serverTimestamp(),
        'lastTime': FieldValue.serverTimestamp(),
        'lastTimeMs': now,
        'lastText': 'Guruh yaratildi',
        'lastFrom': '',
      });
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        DjPage<void>(ChatScreen(chatId: ref.id, title: name, isGroup: true)),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _snack("Guruh yaratib bo'lmadi");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    return Scaffold(
      appBar: AppBar(title: const Text('Yangi guruh')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Guruh nomi',
                prefixIcon: Icon(Icons.groups_rounded)),
          ),
        ),
        SearchPill(
          hint: "Kontakt yoki @username",
          onChanged: (v) => setState(() => _q = v),
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
                return ((u['name'] ?? '') as String)
                        .toLowerCase()
                        .contains(qn) ||
                    ((u['username'] ?? '') as String).contains(qn);
              });
              final found = qn.length >= 2
                  ? findByUsername(qn, _me).map((e) => e.key)
                  : <String>[];
              final ids = <String>[
                ...matchSaved,
                ..._picked
                    .where((id) => !saved.contains(id) && map.containsKey(id)),
                ...found.where(
                    (id) => !saved.contains(id) && !_picked.contains(id)),
              ];
              if (ids.isEmpty) {
                return const EmptyState(
                  icon: Icons.person_search_rounded,
                  title: "Kontaktlar yo'q",
                  subtitle:
                      "Do'stingizning @username ini qidiruvga yozing.",
                );
              }
              return ListView(
                padding: const EdgeInsets.only(bottom: 20),
                children: [
                  SheetGroup(
                    children: [
                      for (final id in ids)
                        _memberRow(id, map[id] ?? const {}, p),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              onPressed: _busy ? null : _create,
              child: Text(_picked.isEmpty
                  ? 'Guruh yaratish'
                  : "Guruh yaratish (${_picked.length + 1} a'zo)"),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _memberRow(String id, Map<String, dynamic> u, DjPalette p) {
    final sel = _picked.contains(id);
    final un = (u['username'] ?? '') as String;
    return PressScale(
      scale: 0.99,
      haptic: false,
      onTap: () => setState(() {
        sel ? _picked.remove(id) : _picked.add(id);
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
        child: Row(children: [
          UserAvatar(uid: id, size: 46, showOnline: false),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text((u['name'] ?? '?') as String,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: p.ink)),
                if (un.isNotEmpty)
                  Text('@$un',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: p.muted)),
              ],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: sel ? p.ink : Colors.transparent,
              border: Border.all(
                  color: sel ? p.ink : p.hairline, width: sel ? 1 : 1.4),
            ),
            child: sel
                ? Icon(Icons.check_rounded, size: 16, color: p.inkOn)
                : null,
          ),
        ]),
      ),
    );
  }
}
