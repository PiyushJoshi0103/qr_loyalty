
import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart'; // flutterfire configure isse bana deta hai

// ============ SETTINGS ============
const int kScans = 6;             // scan 1-6 count, 7th = reward ready
const int kCooldownMinutes = 1;   // testing ke liye 1. Asli use me 60 kar do
const String kOwnerEmail = 'piyush3joshi@gmail.com'; // owner ka email (rules wala same)
// ==================================

final _db = FirebaseFirestore.instance;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    final t = Uri.base.queryParameters['t'];
    return MaterialApp(
      title: 'Scan & Play',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: t != null ? CustomerPage(token: t) : const OwnerPage(),
    );
  }
}

Widget _page(Widget child) => Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: child),
        ),
      ),
    );

// ===================== CUSTOMER =====================
class CustomerPage extends StatefulWidget {
  final String token;
  const CustomerPage({super.key, required this.token});
  @override
  State<CustomerPage> createState() => _CustomerPageState();
}

class _CustomerPageState extends State<CustomerPage> {
  final _phoneCtrl = TextEditingController();
  String? phone;
  String? msg;
  bool busy = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      final p = await SharedPreferences.getInstance();
      phone = p.getString('phone');
      if (phone != null) await _scan();
    } catch (_) {
      msg = 'Connection problem. Internet check karke page refresh karo.';
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _submit() async {
    final v = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (v.length != 10) {
      setState(() => msg = '10 digit mobile number dalo');
      return;
    }
    final p = await SharedPreferences.getInstance();
    await p.setString('phone', v);
    setState(() {
      phone = v;
      busy = true;
      msg = null;
    });
    await _scan();
    if (mounted) setState(() => busy = false);
  }

  Future<void> _scan() async {
    final ref = _db.collection('customers').doc(phone);
    try {
      final snap = await ref.get();
      if (!snap.exists) {
        await ref.set({
          'phone': phone,
          'points': 1,
          'lastScan': FieldValue.serverTimestamp(),
          'token': widget.token,
        });
        msg = 'Scan count ho gaya! ✅';
        return;
      }
      final d = snap.data()!;
      final pts = (d['points'] as num).toInt();
      if (pts > kScans) return; // reward pending
      if (d['token'] == widget.token) {
        msg = 'Ye scan already count ho chuka hai.';
        return;
      }
      final last = (d['lastScan'] as Timestamp?)?.toDate();
      if (last != null && DateTime.now().difference(last).inMinutes < kCooldownMinutes) {
        msg = 'Abhi scan ho chuka hai. Thodi der baad dobara aana.';
        return;
      }
      await ref.update({
        'points': FieldValue.increment(1),
        'lastScan': FieldValue.serverTimestamp(),
        'token': widget.token,
      });
      msg = 'Scan count ho gaya! ✅';
    } on FirebaseException {
      msg = 'QR purana ho gaya ya network issue. Counter pe naya QR scan karo.';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (busy) return _page(const Center(child: CircularProgressIndicator()));
    if (phone == null) {
      return _page(Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Apna mobile number dalo', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Mobile (10 digit)', border: OutlineInputBorder()),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
        if (msg != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(msg!)),
      ]));
    }
    return _page(StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('customers').doc(phone).snapshots(),
      builder: (c, s) {
        final pts = ((s.data?.data()?['points']) as num?)?.toInt() ?? 0;
        if (pts > kScans) {
          return Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.emoji_events, size: 72, color: Colors.amber),
            const SizedBox(height: 12),
            Text('Reward ready! 🎉', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Staff ko ye screen dikhao.\nMobile: $phone\nPlay for free ya Discount, choose karo.',
                textAlign: TextAlign.center),
          ]);
        }
        final left = kScans - pts;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Points: $pts / $kScans', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            children: List.generate(
              kScans,
              (i) => CircleAvatar(
                radius: 18,
                backgroundColor: i < pts ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                child: i < pts ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (msg != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(msg!, textAlign: TextAlign.center)),
          Text(left == 0 ? 'Next scan pe reward! 🎁' : '$left aur scan, phir reward!', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Mobile: $phone', style: const TextStyle(fontSize: 12)),
        ]);
      },
    ));
  }
}

// ===================== OWNER =====================
class OwnerPage extends StatefulWidget {
  const OwnerPage({super.key});
  @override
  State<OwnerPage> createState() => _OwnerPageState();
}

class _OwnerPageState extends State<OwnerPage> {
  String? err;

  Future<void> _google() async {
    try {
      await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
    } on FirebaseAuthException catch (e) {
      setState(() => err = '${e.code}: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (c, s) {
          final u = s.data;
          if (u != null && !u.isAnonymous) {
            if (u.email?.toLowerCase() != kOwnerEmail.toLowerCase()) {
              return _page(Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Ye account owner nahi hai.', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: () => FirebaseAuth.instance.signOut(), child: const Text('Logout')),
              ]));
            }
            return const Dashboard();
          }
          return _page(Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Owner Login', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _google,
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google'),
            ),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(err!)),
          ]));
        },
      );
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Owner'),
            actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => FirebaseAuth.instance.signOut())],
            bottom: const TabBar(tabs: [Tab(text: 'QR'), Tab(text: 'Customers')]),
          ),
          body: const TabBarView(children: [QrTab(), CustomersTab()]),
        ),
      );
}

String _newToken() {
  const c = 'abcdefghijkmnpqrstuvwxyz23456789';
  final r = Random.secure();
  return List.generate(10, (_) => c[r.nextInt(c.length)]).join();
}

class QrTab extends StatefulWidget {
  const QrTab({super.key});
  @override
  State<QrTab> createState() => _QrTabState();
}

class _QrTabState extends State<QrTab> {
  String token = '';
  String? err;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _rotate();
    _t = Timer.periodic(const Duration(seconds: 20), (_) => _rotate());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _rotate() async {
    final n = _newToken();
    try {
      await _db.collection('config').doc('qr').set({'cur': n, 'prev': token});
      if (mounted) setState(() { token = n; err = null; });
    } catch (e) {
      if (mounted) setState(() => err = 'QR update fail: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (token.isEmpty) return Center(child: err != null ? Text(err!) : const CircularProgressIndicator());
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        QrImageView(data: '${Uri.base.origin}${Uri.base.path}?t=$token', size: 260, backgroundColor: Colors.white),
        const SizedBox(height: 12),
        const Text('Har 20 sec me auto-refresh. Screen khula rakho.', style: TextStyle(fontSize: 12)),
        if (err != null) Text(err!, style: const TextStyle(color: Colors.red)),
      ]),
    );
  }
}

Future<void> _redeem(String phone, String choice) async {
  final b = _db.batch();
  b.update(_db.collection('customers').doc(phone), {'points': 0});
  b.set(_db.collection('redemptions').doc(), {
    'phone': phone,
    'choice': choice,
    'at': FieldValue.serverTimestamp(),
  });
  await b.commit();
}

class CustomersTab extends StatelessWidget {
  const CustomersTab({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db.collection('customers').orderBy('points', descending: true).snapshots(),
        builder: (c, s) {
          if (s.hasError) return Center(child: Text('Error: ${s.error}'));
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final docs = s.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('Abhi koi customer nahi'));
          return ListView(
            children: docs.map((d) {
              final pts = (d['points'] as num).toInt();
              final ready = pts > kScans;
              return ListTile(
                title: Text(d.id),
                subtitle: Text(ready ? 'REWARD READY' : 'Points: $pts / $kScans'),
                trailing: ready
                    ? Wrap(spacing: 8, children: [
                        FilledButton(onPressed: () => _redeem(d.id, 'Play for FREE'), child: const Text('Free play')),
                        OutlinedButton(onPressed: () => _redeem(d.id, 'Discount'), child: const Text('Discount')),
                      ])
                    : null,
              );
            }).toList(),
          );
        },
      );
}
