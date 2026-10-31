import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'theme.dart';

class UserProfileScreen extends StatelessWidget {
  final String uid;
  const UserProfileScreen({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ValueListenableBuilder(
        valueListenable: usersCache,
        builder: (c, map, _) {
          final u = map[uid];
          if (u == null) return const Center(child: Text('Topilmadi'));
          final name = (u['name'] ?? '?') as String;
          final status = (u['status'] ?? '') as String;
          final bio = (u['bio'] ?? '') as String;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                  child: Avatar(
                      name: name,
                      photo: u['photo'] as String?,
                      size: 140,
                      colorIdx: colorIndexFor(uid))),
              const SizedBox(height: 16),
              Center(
                child: Text('$name $status',
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(lastSeenText(u),
                    style: TextStyle(
                        color: isOnline(u) ? cs.primary : cs.onSurfaceVariant)),
              ),
              const SizedBox(height: 24),
              if (bio.isNotEmpty)
                Card(
                  elevation: 0,
                  color: cs.surfaceContainerHighest.withOpacity(0.6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('Bio'),
                    subtitle: Text(bio),
                  ),
                ),
              Card(
                elevation: 0,
                color: cs.surfaceContainerHighest.withOpacity(0.6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: const Text('Email'),
                  subtitle: Text((u['email'] ?? '') as String),
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
        content: TextField(controller: ctl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Bekor')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Saqlash')),
        ],
      ),
    );
    if (ok == true && ctl.text.trim().isNotEmpty) {
      await _ref.update({'name': ctl.text.trim()});
    }
  }

  Future<void> _addMembers(BuildContext context, List<String> members) async {
    final picked = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final candidates = usersCache.value.entries
              .where((e) => !members.contains(e.key))
              .toList();
          return AlertDialog(
            title: const Text("A'zo qo'shish"),
            content: SizedBox(
              width: double.maxFinite,
              child: candidates.isEmpty
                  ? const Text("Qo'shiladigan odam qolmadi")
                  : ListView(
                      shrinkWrap: true,
                      children: candidates
                          .map((e) => CheckboxListTile(
                                title: Text((e.value['name'] ?? '?') as String),
                                value: picked.contains(e.key),
                                onChanged: (v) => setS(() {
                                  v == true
                                      ? picked.add(e.key)
                                      : picked.remove(e.key);
                                }),
                              ))
                          .toList(),
                    ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Bekor')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text("Qo'shish")),
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
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Yo'q")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Chiqish')),
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Guruh haqida')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _ref.snapshots(),
        builder: (c, s) {
          final d = s.data?.data();
          if (d == null) return const Center(child: CircularProgressIndicator());
          final name = (d['name'] ?? 'Guruh') as String;
          final members = ((d['members'] as List?) ?? []).cast<String>();
          final admin = (d['createdBy'] ?? '') as String;
          final iAmAdmin = admin == me;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Center(child: Avatar(name: name, group: true, size: 110)),
              const SizedBox(height: 12),
              Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Text(name,
                        style: const TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w800)),
                  ),
                  if (iAmAdmin)
                    IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _rename(context, name)),
                ]),
              ),
              Center(child: Text("${members.length} a'zo")),
              const SizedBox(height: 16),
              ListTile(
                leading: CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Icon(Icons.person_add, color: cs.primary)),
                title: Text("A'zo qo'shish",
                    style: TextStyle(
                        color: cs.primary, fontWeight: FontWeight.w600)),
                onTap: () => _addMembers(context, members),
              ),
              ValueListenableBuilder(
                valueListenable: usersCache,
                builder: (c, map, _) => Column(
                  children: members
                      .map((uid) => ListTile(
                            leading: UserAvatar(uid: uid, size: 44),
                            title: Text(uid == me ? 'Siz' : userName(uid)),
                            subtitle: uid == admin ? const Text('admin') : null,
                            trailing: (iAmAdmin && uid != me)
                                ? IconButton(
                                    icon: const Icon(Icons.remove_circle_outline,
                                        color: Colors.red),
                                    onPressed: () => _ref.update({
                                          'members':
                                              FieldValue.arrayRemove([uid])
                                        }))
                                : null,
                            onTap: uid == me
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            UserProfileScreen(uid: uid))),
                          ))
                      .toList(),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                title: const Text('Guruhdan chiqish',
                    style: TextStyle(color: Colors.red)),
                onTap: () => _leave(context, me),
              ),
            ],
          );
        },
      ),
    );
  }
}
