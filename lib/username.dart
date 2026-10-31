import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'theme.dart';

typedef UserEntry = MapEntry<String, Map<String, dynamic>>;

final _usernameRe = RegExp(r'^[a-z0-9_]{3,20}$');

String normalizeUsername(String s) =>
    s.trim().toLowerCase().replaceFirst(RegExp(r'^@+'), '');

String? validateUsername(String raw) {
  final u = normalizeUsername(raw);
  if (u.isEmpty) return 'Username kiriting';
  if (!_usernameRe.hasMatch(u)) {
    return '3-20 ta belgi: a-z, 0-9 va _ (pastki chiziq)';
  }
  return null;
}

String usernameOf(String uid) =>
    (usersCache.value[uid]?['username'] ?? '') as String;

/// Username'ni band qiladi (noyob). Xato bo'lsa matn qaytaradi, muvaffaqiyatda null.
Future<String?> claimUsername(String uid, String raw) async {
  final err = validateUsername(raw);
  if (err != null) return err;
  final u = normalizeUsername(raw);
  final db = FirebaseFirestore.instance;
  try {
    await db.runTransaction((tx) async {
      final ref = db.collection('usernames').doc(u);
      final snap = await tx.get(ref);
      if (snap.exists && snap.data()?['uid'] != uid) {
        throw Exception('USERNAME_TAKEN');
      }
      final userRef = db.collection('users').doc(uid);
      final userSnap = await tx.get(userRef);
      final old = (userSnap.data()?['username'] ?? '') as String;
      if (old.isNotEmpty && old != u) {
        tx.delete(db.collection('usernames').doc(old));
      }
      tx.set(ref, {'uid': uid});
      tx.set(userRef, {'username': u}, SetOptions(merge: true));
    });
    return null;
  } catch (e) {
    if (e.toString().contains('USERNAME_TAKEN')) return 'Bu username band';
    return 'Xatolik: $e';
  }
}

/// Username bo'yicha foydalanuvchilarni topish (o'zimizdan tashqari).
List<UserEntry> findByUsername(String q, String me) {
  final s = normalizeUsername(q);
  if (s.length < 2) return <UserEntry>[];
  final list = usersCache.value.entries.where((e) {
    if (e.key == me) return false;
    final un = (e.value['username'] ?? '') as String;
    return un.isNotEmpty && un.contains(s);
  }).toList();
  list.sort((a, b) {
    final ea = a.value['username'] == s ? 0 : 1;
    final eb = b.value['username'] == s ? 0 : 1;
    if (ea != eb) return ea - eb;
    return ((a.value['username'] ?? '') as String)
        .compareTo((b.value['username'] ?? '') as String);
  });
  return list;
}

List<String> myContacts(String me) =>
    ((usersCache.value[me]?['contacts']) as List?)?.cast<String>() ??
    <String>[];

Future<void> addContact(String me, String uid) =>
    FirebaseFirestore.instance.collection('users').doc(me).set({
      'contacts': FieldValue.arrayUnion([uid])
    }, SetOptions(merge: true));

Future<void> removeContact(String me, String uid) =>
    FirebaseFirestore.instance.collection('users').doc(me).set({
      'contacts': FieldValue.arrayRemove([uid])
    }, SetOptions(merge: true));

Future<void> showUsernameDialog(BuildContext context, String uid,
    {bool required = false, String current = ''}) async {
  final ctl = TextEditingController(text: current);
  String? error;
  var busy = false;
  await showDialog(
    context: context,
    barrierDismissible: !required,
    builder: (ctx) => PopScope(
      canPop: !required,
      child: StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(required ? 'Username tanlang' : "Username o'zgartirish"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (required)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text("Do'stlaringiz sizni shu username orqali topadi."),
                ),
              TextField(
                controller: ctl,
                autofocus: true,
                autocorrect: false,
                decoration: InputDecoration(
                    prefixText: '@', hintText: 'username', errorText: error),
              ),
            ],
          ),
          actions: [
            if (!required)
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Bekor')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
              onPressed: busy
                  ? null
                  : () async {
                      final v = validateUsername(ctl.text);
                      if (v != null) {
                        setS(() => error = v);
                        return;
                      }
                      setS(() {
                        busy = true;
                        error = null;
                      });
                      final err = await claimUsername(uid, ctl.text);
                      if (err == null) {
                        if (ctx.mounted) Navigator.pop(ctx);
                      } else {
                        setS(() {
                          busy = false;
                          error = err;
                        });
                      }
                    },
              child: const Text('Saqlash'),
            ),
          ],
        ),
      ),
    ),
  );
}
