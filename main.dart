import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_config.dart';
import 'home.dart';
import 'theme.dart';

final navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadPrefs();
  await Firebase.initializeApp(options: firebaseOptions);
  runApp(const DjigarlarApp());
}

class DjigarlarApp extends StatelessWidget {
  const DjigarlarApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: accentIndex,
        builder: (c, ai, _) => ValueListenableBuilder<ThemeMode>(
          valueListenable: themeMode,
          builder: (c, mode, _) => MaterialApp(
            title: 'Djigarlar',
            navigatorKey: navKey,
            debugShowCheckedModeBanner: false,
            themeMode: mode,
            theme: buildTheme(accents[ai], Brightness.light),
            darkTheme: buildTheme(accents[ai], Brightness.dark),
            home: StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (c, s) {
                if (s.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                      body: Center(child: CircularProgressIndicator()));
                }
                return s.data == null ? const AuthScreen() : const HomeScreen();
              },
            ),
          ),
        ),
      );
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (_register) {
        final cred = await auth.createUserWithEmailAndPassword(
            email: _email.text.trim(), password: _pass.text);
        final name = _name.text.trim().isEmpty
            ? _email.text.trim().split('@').first
            : _name.text.trim();
        await FirebaseFirestore.instance
            .collection('users')
            .doc(cred.user!.uid)
            .set({
          'name': name,
          'email': _email.text.trim(),
          'color': accentIndex.value,
          'lastSeen': DateTime.now().millisecondsSinceEpoch,
        });
      } else {
        await auth.signInWithEmailAndPassword(
            email: _email.text.trim(), password: _pass.text);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _blob(double size, double o) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            shape: BoxShape.circle, color: Colors.white.withOpacity(o)),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Stack(children: [
        Container(decoration: BoxDecoration(gradient: headerGradient())),
        Positioned(top: -80, right: -60, child: _blob(240, 0.12)),
        Positioned(top: 160, left: -90, child: _blob(180, 0.08)),
        Positioned(bottom: -110, right: -70, child: _blob(300, 0.10)),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 24,
                          offset: const Offset(0, 10)),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: Image.asset('assets/logo.png', width: 96, height: 96),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Djigarlar',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text("Do'stlar bilan yaqin suhbat",
                    style: TextStyle(color: Colors.white.withOpacity(0.85))),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 30,
                          offset: const Offset(0, 12)),
                    ],
                  ),
                  child: Column(children: [
                    Text(_register ? 'Akkaunt ochish' : 'Xush kelibsiz!',
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 18),
                    if (_register) ...[
                      TextField(
                          controller: _name,
                          decoration: const InputDecoration(
                              labelText: 'Ism',
                              prefixIcon: Icon(Icons.person_outline))),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.mail_outline))),
                    const SizedBox(height: 12),
                    TextField(
                        controller: _pass,
                        obscureText: true,
                        decoration: const InputDecoration(
                            labelText: 'Parol',
                            prefixIcon: Icon(Icons.lock_outline))),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!, style: TextStyle(color: cs.error)),
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5))
                            : Text(_register ? "Ro'yxatdan o'tish" : 'Kirish')),
                    TextButton(
                        onPressed: () => setState(() => _register = !_register),
                        child: Text(_register
                            ? 'Akkauntim bor'
                            : 'Yangi akkaunt ochish')),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
