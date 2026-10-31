import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_config.dart';
import 'home.dart';
import 'notify.dart';
import 'theme.dart';
import 'ui.dart';
import 'username.dart';

final navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadPrefs();
  if (firebaseOptions.apiKey.contains('SHU_YERGA')) {
    runApp(const _SetupApp());
    return;
  }
  await Firebase.initializeApp(options: firebaseOptions);
  // Oflayn kesh — xabarlar va chatlar darrov ko'rinadi, internet sekin bo'lsa ham.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  await notify.init();
  runApp(const DjigarlarApp());
}

class _SetupApp extends StatelessWidget {
  const _SetupApp();
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(accents[2], Brightness.light),
        home: const Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  "Firebase sozlanmagan.\n\nlib/firebase_config.dart fayliga Firebase qiymatlarini yozing "
                  "(yoki GitHub Secrets orqali kiriting) va ilovani qayta yig'ing.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, height: 1.5),
                ),
              ),
            ),
          ),
        ),
      );
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
                  return const _Splash();
                }
                return s.data == null ? const AuthScreen() : const HomeScreen();
              },
            ),
          ),
        ),
      );
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(26),
            child: Image.asset('assets/logo.png',
                width: 88,
                height: 88,
                errorBuilder: (c, e, s) => const SizedBox(width: 88)),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: p.muted),
          ),
        ]),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_register) {
      final err = validateUsername(_username.text);
      if (err != null) {
        setState(() => _error = err);
        return;
      }
    }
    FocusScope.of(context).unfocus();
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
        await claimUsername(cred.user!.uid, _username.text);
      } else {
        await auth.signInWithEmailAndPassword(
            email: _email.text.trim(), password: _pass.text);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _msg(e.code, e.message));
    } catch (_) {
      setState(() => _error = 'Xatolik yuz berdi. Qayta urinib ko\'ring.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _msg(String code, String? fallback) {
    switch (code) {
      case 'invalid-email':
        return "Email noto'g'ri yozilgan";
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return "Email yoki parol noto'g'ri";
      case 'email-already-in-use':
        return 'Bu email allaqachon ro\'yxatdan o\'tgan';
      case 'weak-password':
        return 'Parol juda sodda — kamida 6 ta belgi';
      case 'network-request-failed':
        return 'Internet yo\'q';
      default:
        return fallback ?? 'Xatolik';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.dj;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            physics: const BouncingScrollPhysics(),
            child: FadeSlideIn(
              offsetY: 26,
              duration: const Duration(milliseconds: 560),
              child: Column(children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: p.lift,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset('assets/logo.png',
                        width: 92,
                        height: 92,
                        errorBuilder: (c, e, s) => Container(
                              width: 92,
                              height: 92,
                              color: p.ink,
                              child: Icon(Icons.send_rounded,
                                  color: p.inkOn, size: 40),
                            )),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'DJIGARLAR',
                  style: TextStyle(
                    color: p.ink,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "DO'STLAR BILAN YAQIN SUHBAT",
                  style: TextStyle(
                    color: p.gold,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.4,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  decoration: BoxDecoration(
                    color: p.card,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: p.hairline, width: 0.8),
                    boxShadow: p.soft,
                  ),
                  child: Column(children: [
                    Text(
                      _register ? 'Akkaunt ochish' : 'Xush kelibsiz',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: p.ink,
                      ),
                    ),
                    const SizedBox(height: 20),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      child: Column(children: [
                        if (_register) ...[
                          TextField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                                labelText: 'Ism',
                                prefixIcon: Icon(Icons.person_outline)),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _username,
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              hintText: 'masalan: ali_01',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ]),
                    ),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.mail_outline_rounded)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pass,
                      obscureText: _hide,
                      decoration: InputDecoration(
                        labelText: 'Parol',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                              _hide
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: p.faint),
                          onPressed: () => setState(() => _hide = !_hide),
                        ),
                      ),
                    ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Row(children: [
                          Icon(Icons.error_outline_rounded,
                              size: 17, color: p.danger),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(_error!,
                                style: TextStyle(
                                    color: p.danger,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: p.inkOn),
                            )
                          : Text(_register ? "Ro'yxatdan o'tish" : 'Kirish'),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () => setState(() {
                        _register = !_register;
                        _error = null;
                      }),
                      child: Text(
                        _register ? 'Akkauntim bor' : 'Yangi akkaunt ochish',
                        style: TextStyle(color: p.muted),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
