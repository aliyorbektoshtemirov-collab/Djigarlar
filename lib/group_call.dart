import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call.dart' show iceServers, callBg, CallBackdrop;
import 'theme.dart';
import 'ui.dart';

// ============================================================================
//  Guruh qo'ng'irog'i — mesh (har bir a'zo bilan alohida ulanish)
//  Firestore tuzilishi:
//    groupCalls/{chatId}                     -> {name, video, startedAt, active}
//    groupCalls/{chatId}/members/{uid}       -> {name, ts, muted, cam}
//    groupCalls/{chatId}/signals/{autoId}    -> {from, to, kind, ...}
// ============================================================================

/// Guruh qo'ng'irog'ini boshlash yoki unga qo'shilish.
Future<void> joinGroupCall(
  BuildContext context, {
  required String chatId,
  required String title,
  required bool video,
}) async {
  await Navigator.of(context).push(DjPage<void>(
    GroupCallScreen(chatId: chatId, title: title, video: video),
  ));
}

class _Peer {
  RTCPeerConnection? pc;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  final List<RTCIceCandidate> pending = <RTCIceCandidate>[];
  bool remoteSet = false;
  bool hasVideo = false;
  bool ready = false;
}

class GroupCallScreen extends StatefulWidget {
  final String chatId;
  final String title;
  final bool video;
  const GroupCallScreen({
    super.key,
    required this.chatId,
    required this.title,
    required this.video,
  });

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  final String _me = FirebaseAuth.instance.currentUser!.uid;
  final _localR = RTCVideoRenderer();
  final Map<String, _Peer> _peers = {};
  final Map<String, Map<String, dynamic>> _memberData = {};
  final Map<String, List<RTCIceCandidate>> _orphan = {};
  final _subs = <StreamSubscription>[];

  MediaStream? _stream;
  Timer? _ticker;
  DateTime? _start;

  bool _muted = false;
  bool _camOff = false;
  bool _speaker = true;
  bool _front = true;
  bool _controls = true;
  bool _closing = false;
  bool _ready = false;
  int _seconds = 0;
  String? _focus; // kattalashtirilgan ishtirokchi

  DocumentReference<Map<String, dynamic>> get _call =>
      FirebaseFirestore.instance.collection('groupCalls').doc(widget.chatId);
  CollectionReference<Map<String, dynamic>> get _members =>
      _call.collection('members');
  CollectionReference<Map<String, dynamic>> get _signals =>
      _call.collection('signals');

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _init();
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  // --------------------------------------------------------------- start

  Future<void> _init() async {
    try {
      await _localR.initialize();
      _stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': widget.video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
              }
            : false,
      });
      _localR.srcObject = _stream;
      try {
        await Helper.setSpeakerphoneOn(true);
      } catch (_) {}
      _set(() => _ready = true);

      final now = DateTime.now().millisecondsSinceEpoch;
      await _call.set({
        'chatId': widget.chatId,
        'name': widget.title,
        'video': widget.video,
        'active': true,
        'startedAt': now,
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .set({
        'activeCall': {'id': widget.chatId, 'video': widget.video, 'ts': now},
      }, SetOptions(merge: true));

      await _members.doc(_me).set({
        'name': userName(_me),
        'ts': now,
        'muted': false,
        'cam': widget.video,
      });

      _start = DateTime.now();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_start == null) return;
        _set(() => _seconds = DateTime.now().difference(_start!).inSeconds);
      });

      _subs.add(_signals
          .where('to', isEqualTo: _me)
          .snapshots()
          .listen(_onSignals));
      _subs.add(_members.snapshots().listen(_onMembers));
    } catch (_) {
      _snack('Kamera yoki mikrofonga ruxsat bering');
      _leave();
    }
  }

  // --------------------------------------------------------------- a'zolar

  void _onMembers(QuerySnapshot<Map<String, dynamic>> s) {
    final ids = <String>{};
    for (final d in s.docs) {
      ids.add(d.id);
      _memberData[d.id] = d.data();
    }
    // chiqib ketganlar
    for (final gone in _peers.keys.toList()) {
      if (!ids.contains(gone)) _dropPeer(gone);
    }
    for (final id in ids) {
      if (id == _me || _peers.containsKey(id)) continue;
      // Determinizm: kichik uid taklif (offer) yuboradi.
      if (_me.compareTo(id) < 0) {
        _connectTo(id, initiator: true);
      }
    }
    _set(() {});
  }

  Future<void> _dropPeer(String id) async {
    final p = _peers.remove(id);
    if (p == null) return;
    try {
      p.renderer.srcObject = null;
      await p.renderer.dispose();
      await p.pc?.close();
    } catch (_) {}
    _set(() {
      if (_focus == id) _focus = null;
    });
  }

  Future<_Peer> _ensurePeer(String id) async {
    final exist = _peers[id];
    if (exist != null) return exist;
    final peer = _Peer();
    _peers[id] = peer;
    await peer.renderer.initialize();
    final pc = await createPeerConnection(iceServers);
    peer.pc = pc;

    for (final t in _stream?.getTracks() ?? <MediaStreamTrack>[]) {
      await pc.addTrack(t, _stream!);
    }

    pc.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        peer.renderer.srcObject = e.streams[0];
        peer.hasVideo = e.streams[0].getVideoTracks().isNotEmpty;
        _set(() => peer.ready = true);
      }
    };

    // Ulanish tayyor bo'lgunicha kelgan ICE nomzodlarini olib qo'yamiz
    final waiting = _orphan.remove(id);
    if (waiting != null) peer.pending.addAll(waiting);

    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      _signals.add({
        'from': _me,
        'to': id,
        'kind': 'ice',
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    };

    return peer;
  }

  Future<void> _connectTo(String id, {required bool initiator}) async {
    final peer = await _ensurePeer(id);
    if (!initiator) return;
    final pc = peer.pc;
    if (pc == null) return;
    final offer = await pc.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await pc.setLocalDescription(offer);
    await _signals.add({
      'from': _me,
      'to': id,
      'kind': 'offer',
      'sdp': offer.sdp,
      'type': offer.type,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // --------------------------------------------------------------- signal

  Future<void> _onSignals(QuerySnapshot<Map<String, dynamic>> s) async {
    for (final ch in s.docChanges) {
      if (ch.type != DocumentChangeType.added) continue;
      final d = ch.doc.data();
      if (d == null) continue;
      try {
        await _handle(d);
      } catch (_) {}
      try {
        await ch.doc.reference.delete();
      } catch (_) {}
    }
  }

  Future<void> _handle(Map<String, dynamic> d) async {
    final from = (d['from'] ?? '') as String;
    final kind = (d['kind'] ?? '') as String;
    if (from.isEmpty || from == _me) return;

    if (kind == 'offer') {
      final peer = await _ensurePeer(from);
      final pc = peer.pc;
      if (pc == null) return;
      await pc.setRemoteDescription(
          RTCSessionDescription(d['sdp'] as String?, d['type'] as String?));
      peer.remoteSet = true;
      await _flush(peer);
      final ans = await pc.createAnswer();
      await pc.setLocalDescription(ans);
      await _signals.add({
        'from': _me,
        'to': from,
        'kind': 'answer',
        'sdp': ans.sdp,
        'type': ans.type,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    } else if (kind == 'answer') {
      final peer = _peers[from];
      final pc = peer?.pc;
      if (peer == null || pc == null) return;
      await pc.setRemoteDescription(
          RTCSessionDescription(d['sdp'] as String?, d['type'] as String?));
      peer.remoteSet = true;
      await _flush(peer);
    } else if (kind == 'ice') {
      final cand = RTCIceCandidate(d['candidate'] as String?,
          d['sdpMid'] as String?, d['sdpMLineIndex'] as int?);
      final peer = _peers[from];
      if (peer == null) {
        // taklif hali kelmagan — saqlab turamiz
        (_orphan[from] ??= <RTCIceCandidate>[]).add(cand);
        return;
      }
      if (!peer.remoteSet) {
        peer.pending.add(cand);
      } else {
        try {
          await peer.pc?.addCandidate(cand);
        } catch (_) {}
      }
    }
  }

  Future<void> _flush(_Peer peer) async {
    for (final c in peer.pending) {
      try {
        await peer.pc?.addCandidate(c);
      } catch (_) {}
    }
    peer.pending.clear();
  }

  // --------------------------------------------------------------- amallar

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t)));
  }

  MediaStreamTrack? get _videoTrack {
    final list = _stream?.getVideoTracks();
    if (list == null || list.isEmpty) return null;
    return list.first;
  }

  void _toggleMute() {
    final next = !_muted;
    for (final t in _stream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !next;
    }
    HapticFeedback.selectionClick();
    _set(() => _muted = next);
    _members.doc(_me).set({'muted': next}, SetOptions(merge: true));
  }

  void _toggleCam() {
    final t = _videoTrack;
    if (t == null) return;
    final next = !_camOff;
    t.enabled = !next;
    HapticFeedback.selectionClick();
    _set(() => _camOff = next);
    _members.doc(_me).set({'cam': !next}, SetOptions(merge: true));
  }

  Future<void> _switchCam() async {
    final t = _videoTrack;
    if (t == null) return;
    try {
      await Helper.switchCamera(t);
      _set(() => _front = !_front);
    } catch (_) {}
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speaker;
    try {
      await Helper.setSpeakerphoneOn(next);
    } catch (_) {}
    _set(() => _speaker = next);
  }

  Future<void> _leave() async {
    if (_closing) return;
    _closing = true;
    HapticFeedback.mediumImpact();
    if (mounted) Navigator.of(context).maybePop();
    try {
      await _members.doc(_me).delete();
      final rest = await _members.get();
      if (rest.docs.isEmpty) {
        await _call.set({'active': false}, SetOptions(merge: true));
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .set({'activeCall': FieldValue.delete()}, SetOptions(merge: true));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    for (final p in _peers.values) {
      p.renderer.srcObject = null;
      p.renderer.dispose();
      p.pc?.close();
    }
    _peers.clear();
    try {
      _stream?.getTracks().forEach((t) => t.stop());
    } catch (_) {}
    _localR.srcObject = null;
    _stream?.dispose();
    _localR.dispose();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    super.dispose();
  }

  // --------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final ids = <String>[_me, ..._peers.keys];
    final count = ids.length;
    final cross = count <= 1
        ? 1
        : count <= 4
            ? 2
            : count <= 9
                ? 3
                : 3;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: callBg,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _set(() => _controls = !_controls),
          child: Stack(fit: StackFit.expand, children: [
            const Positioned.fill(child: CallBackdrop()),
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 74, 10, 190),
                  child: _focus != null
                      ? _tile(_focus!, big: true)
                      : (!_ready
                          ? const Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white54))
                          : GridView.builder(
                              physics: const BouncingScrollPhysics(),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cross,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: count <= 1 ? 0.72 : 0.78,
                              ),
                              itemCount: count,
                              itemBuilder: (c, i) =>
                                  FadeSlideIn(index: i, child: _tile(ids[i])),
                            )),
                ),
              ),
            ),
            // sarlavha
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            '$count ishtirokchi · ${fmtDuration(_seconds)}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_focus != null)
                      IconButton(
                        onPressed: () => _set(() => _focus = null),
                        icon: const Icon(Icons.grid_view_rounded,
                            color: Colors.white),
                      ),
                  ]),
                ),
              ),
            ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSlide(
                offset: _controls ? Offset.zero : const Offset(0, 1),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _controls ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: _controlBar(),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tile(String uid, {bool big = false}) {
    final mine = uid == _me;
    final peer = _peers[uid];
    final data = _memberData[uid];
    final name = mine ? 'Siz' : ((data?['name'] ?? userName(uid)) as String);
    final muted = mine ? _muted : (data?['muted'] == true);
    final camOn = mine ? !_camOff : (data?['cam'] != false);
    final showVideo =
        mine ? (widget.video && !_camOff) : (peer?.ready == true && camOn);

    return GestureDetector(
      onTap: () => _set(() => _focus = big ? null : uid),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF131318),
          borderRadius: BorderRadius.circular(big ? 26 : 20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.09),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (showVideo)
            RTCVideoView(
              mine ? _localR : peer!.renderer,
              mirror: mine && _front,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          else
            Center(
              child: UserAvatar(
                  uid: uid, size: big ? 110 : 62, showOnline: false),
            ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Row(children: [
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (muted)
                      const Padding(
                        padding: EdgeInsets.only(right: 5),
                        child: Icon(Icons.mic_off_rounded,
                            size: 13, color: Color(0xFFE23D3D)),
                      ),
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
          if (!mine && peer?.ready != true)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'ulanmoqda...',
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _controlBar() {
    const glass = Color(0x33FFFFFF);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(34),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SizedBox(
                width: 58,
                child: Center(
                  child: CircleIconButton(
                    icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    onTap: _toggleMute,
                    size: 52,
                    bg: _muted ? Colors.white : glass,
                    fg: _muted ? const Color(0xFF111114) : Colors.white,
                  ),
                ),
              ),
              if (widget.video)
                SizedBox(
                  width: 58,
                  child: Center(
                    child: CircleIconButton(
                      icon: _camOff
                          ? Icons.videocam_off_rounded
                          : Icons.videocam_rounded,
                      onTap: _toggleCam,
                      size: 52,
                      bg: _camOff ? Colors.white : glass,
                      fg: _camOff ? const Color(0xFF111114) : Colors.white,
                    ),
                  ),
                ),
              if (widget.video)
                SizedBox(
                  width: 58,
                  child: Center(
                    child: CircleIconButton(
                      icon: Icons.flip_camera_ios_rounded,
                      onTap: _switchCam,
                      size: 52,
                      bg: glass,
                    ),
                  ),
                ),
              SizedBox(
                width: 58,
                child: Center(
                  child: CircleIconButton(
                    icon: _speaker
                        ? Icons.volume_up_rounded
                        : Icons.phone_in_talk_rounded,
                    onTap: _toggleSpeaker,
                    size: 52,
                    bg: _speaker ? Colors.white : glass,
                    fg: _speaker ? const Color(0xFF111114) : Colors.white,
                  ),
                ),
              ),
              SizedBox(
                width: 72,
                child: Center(
                  child: CircleIconButton(
                    icon: Icons.call_end_rounded,
                    onTap: _leave,
                    size: 62,
                    bg: const Color(0xFFE23D3D),
                    glow: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
