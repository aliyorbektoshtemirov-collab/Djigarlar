import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'theme.dart';
import 'ui.dart';
import 'username.dart';

class UserProfileScreen extends StatelessWidget {
  final String uid;
  const UserProfileScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    final me = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ValueListenableBuilder(
        valueListenable: usersCache,
        builder: (c, map, _) {
          final u = map[uid];
          if (u == null) {
            return const EmptyState(
                icon: Icons.person_off_outlined, title: 'Topilmadi');
          }
          final name = (u['name'] ?? '?') as String;
          final status = (u['status'] ?? '') as String;
          final bio = (u['bio'] ?? '') as String;
          final un = (u['username'] ?? '') as String;
          final online = isOnline(u);

          Widget info(IconData i, String label, String value) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(i, size: 19, color: p.faint),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label.toUpperCase(),
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.3,
                                color: p.faint)),
                        const SizedBox(height: 3),
                        Text(value,
                            style: TextStyle(
                                fontSize: 14.5,
                                height: 1.35,
                                color: p.ink)),
                      ],
                    ),
                  ),
                ]),
              );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            physics: const BouncingScrollPhysics(),
            children: [
              FadeSlideIn(
                child: Column(children: [
                  Avatar(
                      name: name,
                      photo: u['photo'] as String?,
                      size: 128,
                      colorIdx: colorIndexFor(uid)),
                  const SizedBox(height: 16),
                  Text(
                    status.isEmpty ? name : '$name $status',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        color: p.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    lastSeenText(u),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: online ? p.online : p.muted),
                  ),
                ]),
              ),
              const SizedBox(height: 22),
              if (me != null && uid != me)
                FadeSlideIn(
                  index: 1,
                  child: Builder(builder: (_) {
                    final saved = myContacts(me).contains(uid);
                    return OutlinedButton.icon(
                      onPressed: () =>
                          saved ? removeContact(me, uid) : addContact(me, uid),
                      icon: Icon(
                          saved
                              ? Icons.person_remove_alt_1_rounded
                              : Icons.person_add_alt_1_rounded,
                          size: 19),
                      label: Text(saved
                          ? "Kontaktdan o'chirish"
                          : 'Kontaktlarga saqlash'),
                    );
                  }),
                ),
              const SizedBox(height: 14),
              FadeSlideIn(
                index: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: p.hairline, width: 0.8),
                    boxShadow: p.soft,
                  ),
                  child: Column(children: [
                    if (un.isNotEmpty)
                      info(Icons.alternate_email_rounded, 'Username', '@$un'),
                    if (bio.isNotEmpty)
                      info(Icons.info_outline_rounded, 'Bio', bio),
                    info(Icons.mail_outline_rounded, 'Email',
                        (u['email'] ?? '—') as String),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class GroupInfoScreen extends StatelessWidget {
  final String chatId;
  const GroupInfoScreen({super.key, required this.chatId});

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('chats').doc(chatId);

  Future<void> _rename(BuildContext context, String current) async {
    final ctl = TextEditingController(text: current);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guruh nomi'),
        content: TextField(
            controller: ctl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(110, 46)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Saqlash'),
          ),
        ],
      ),
    );
    if (ok == true && ctl.text.trim().isNotEmpty) {
      await _ref.update({'name': ctl.text.trim()});
    }
  }

  Future<void> _addMembers(BuildContext context, List<String> members) async {
    final picked = <String>{};
    final me = FirebaseAuth.instance.currentUser!.uid;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final contacts = myContacts(me)
              .where((id) =>
                  !members.contains(id) && usersCache.value.containsKey(id))
              .toList();
          final others = usersCache.value.keys
              .where((id) => !members.contains(id) && !contacts.contains(id))
              .toList();
          final candidates = [...contacts, ...others];
          return AlertDialog(
            title: const Text("A'zo qo'shish"),
            content: SizedBox(
              width: double.maxFinite,
              child: candidates.isEmpty
                  ? const Text("Qo'shiladigan odam qolmadi")
                  : ListView(
                      shrinkWrap: true,
                      children: candidates
                          .map((id) => CheckboxListTile(
                                secondary:
                                    UserAvatar(uid: id, size: 38, showOnline: false),
                                title: Text(userName(id)),
                                value: picked.contains(id),
                                onChanged: (v) => setS(() {
                                  v == true ? picked.add(id) : picked.remove(id);
                                }),
                              ))
                          .toList(),
                    ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Bekor')),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(110, 46)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Qo'shish"),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true && picked.isNotEmpty) {
      await _ref.update({'members': FieldValue.arrayUnion(picked.toList())});
    }
  }

  Future<void> _leave(BuildContext context, String me) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guruhdan chiqasizmi?'),
        content: const Text("Chiqsangiz, guruh ro'yxatdan yo'qoladi."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Yo'q")),
          FilledButton(
            style: FilledButton.styleFrom(
                minimumSize: const Size(110, 46),
                backgroundColor: const Color(0xFFE23D3D)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Chiqish'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _ref.update({
      'members': FieldValue.arrayRemove([me])
    });
    if (context.mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = FirebaseAuth.instance.currentUser!.uid;
    final p = context.dj;
    return Scaffold(
      appBar: AppBar(title: const Text('Guruh haqida')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _ref.snapshots(),
        builder: (c, s) {
          final d = s.data?.data();
          if (d == null) {
            return const Center(
                child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ));
          }
          final name = (d['name'] ?? 'Guruh') as String;
          final members = ((d['members'] as List?) ?? []).cast<String>();
          final admin = (d['createdBy'] ?? '') as String;
          final iAmAdmin = admin == me;
          return ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
            physics: const BouncingScrollPhysics(),
            children: [
              FadeSlideIn(
                child: Column(children: [
                  Avatar(name: name, group: true, size: 110),
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 40),
                        child: Text(
                          name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: p.ink),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: iAmAdmin
                          ? IconButton(
                              icon: Icon(Icons.edit_outlined,
                                  size: 18, color: p.muted),
                              onPressed: () => _rename(context, name),
                            )
                          : null,
                    ),
                  ]),
                  Text("${members.length} a'zo",
                      style: TextStyle(color: p.muted, fontSize: 13)),
                  const SizedBox(height: 18),
                ]),
              ),
              const SectionLabel("A'zolar"),
              SheetGroup(
                children: [
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                          color: p.cardHi,
                          shape: BoxShape.circle,
                          border: Border.all(color: p.hairline)),
                      child: Icon(Icons.person_add_rounded,
                          color: p.ink, size: 20),
                    ),
                    title: const Text("A'zo qo'shish",
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    onTap: () => _addMembers(context, members),
                  ),
                  for (final uid in members)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      leading: UserAvatar(uid: uid, size: 46),
                      title: Text(uid == me ? 'Siz' : userName(uid),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: uid == admin
                          ? Text('admin',
                              style: TextStyle(color: p.gold, fontSize: 12.5))
                          : null,
                      trailing: (iAmAdmin && uid != me)
                          ? IconButton(
                              icon: Icon(Icons.remove_circle_outline_rounded,
                                  color: p.danger, size: 20),
                              onPressed: () => _ref.update({
                                'members': FieldValue.arrayRemove([uid])
                              }),
                            )
                          : null,
                      onTap: uid == me
                          ? null
                          : () => push(context, UserProfileScreen(uid: uid)),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  onPressed: () => _leave(context, me),
                  icon: Icon(Icons.exit_to_app_rounded,
                      size: 19, color: p.danger),
                  label: Text('Guruhdan chiqish',
                      style: TextStyle(
                          color: p.danger, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: p.danger.withValues(alpha: 0.35), width: 1.2),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
