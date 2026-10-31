import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'theme.dart';
import 'ui.dart';

// ============================================================================
//  1-1 qo'ng'iroq (audio / video)
// ============================================================================

const iceServers = <String, dynamic>{
  'iceServers': [
    {
      'urls': [
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
        'stun:stun2.l.google.com:19302',
        'stun:stun3.l.google.com:19302',
      ]
    }
  ],
  'sdpSemantics': 'unified-plan',
};

const callBg = Color(0xFF07070A);

/// Qo'ng'iroq ekrani foni — chuqur, iliq qorong'ilik.
class CallBackdrop extends StatelessWidget {
  const CallBackdrop({super.key});
  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF14110C), Color(0xFF0A0A0D), Color(0xFF07070A)],
          ),
        ),
        child: SizedBox.expand(),
      );
}

class CallScreen extends StatefulWidget {
  final String callId;
  final bool isCaller;
  final bool video;
  final String peerName;
  final String peerId;
  final String myName;
  const CallScreen({
    super.key,
    required this.callId,
    required this.isCaller,
    required this.video,
    required this.peerName,
    required this.peerId,
    required this.myName,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _localR = RTCVideoRenderer();
  final _remoteR = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _stream;

  late final DocumentReference<Map<String, dynamic>> _doc =
      FirebaseFirestore.instance.collection('calls').doc(widget.callId);

  final _subs = <StreamSubscription>[];
  final _pending = <RTCIceCandidate>[];
  Timer? _timeout, _ticker, _failGuard;

  bool _muted = false;
  bool _camOff = false;
  bool _speaker = false;
  bool _front = true;
  bool _connected = false;
  bool _closing = false;
  bool _answerSet = false;
  bool _remoteReady = false;
  bool _controls = true;
  bool _swap = false;
  int _seconds = 0;
  DateTime? _startedAt;
  Offset _pip = const Offset(double.infinity, 0);
  RTCPeerConnectionState? _pcState;

  late String _status =
      widget.isCaller ? "Qo'ng'iroq qilinmoqda..." : 'Ulanmoqda...';

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _init();
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  // -------------------------------------------------------------- o'rnatish
  Future<void> _init() async {
    try {
      await _localR.initialize();
      await _remoteR.initialize();

      _stream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': widget.video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
              }
            : false,
      });
      _localR.srcObject = _stream;
      _speaker = widget.video;
      try {
        await Helper.setSpeakerphoneOn(_speaker);
      } catch (_) {}
      _set(() {});

      _pc = await createPeerConnection(iceServers);

      for (final t in _stream!.getTracks()) {
        await _pc!.addTrack(t, _stream!);
      }

      _pc!.onTrack = (e) {
        if (e.streams.isNotEmpty) {
          _remoteR.srcObject = e.streams[0];
          _set(() => _remoteReady = true);
        }
      };

      _pc!.onIceCandidate = (c) {
        if (c.candidate == null) return;
        _doc
            .collection(
                widget.isCaller ? 'callerCandidates' : 'calleeCandidates')
            .add(Map<String, dynamic>.from(c.toMap()));
      };

      _pc!.onConnectionState = _onConnState;

      _subs.add(_doc.snapshots().listen(_onDoc));

      if (widget.isCaller) {
        final offer = await _pc!.createOffer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': widget.video,
        });
        await _pc!.setLocalDescription(offer);
        await _doc.set({
          'from': FirebaseAuth.instance.currentUser!.uid,
          'fromName': widget.myName,
          'to': widget.peerId,
          'video': widget.video,
          'status': 'ringing',
          'ts': DateTime.now().millisecondsSinceEpoch,
          'offer': {'sdp': offer.sdp, 'type': offer.type},
        });
        _timeout = Timer(const Duration(seconds: 45), () {
          if (!_connected) {
            _set(() => _status = 'Javob berilmadi');
            _hangup();
          }
        });
      } else {
        final snap = await _doc.get();
        final data = snap.data();
        final o = data?['offer'] as Map?;
        if (o == null) {
          _set(() => _status = "Qo'ng'iroq topilmadi");
          await Future<void>.delayed(const Duration(seconds: 2));
          _close();
          return;
        }
        await _pc!.setRemoteDescription(
            RTCSessionDescription(o['sdp'] as String, o['type'] as String));
        await _flush();
        final ans = await _pc!.createAnswer();
        await _pc!.setLocalDescription(ans);
        await _doc.update({
          'answer': {'sdp': ans.sdp, 'type': ans.type},
          'status': 'accepted',
        });
        _listenCandidates();
      }
    } catch (e) {
      _set(() => _status = 'Xatolik: ulanib bo\'lmadi');
      await Future<void>.delayed(const Duration(seconds: 3));
      _hangup();
    }
  }

  Future<void> _onDoc(DocumentSnapshot<Map<String, dynamic>> s) async {
    final d = s.data();
    if (d == null) return;
    final st = d['status'];
    if (st == 'ended' || st == 'declined') {
      _set(() => _status = st == 'declined' ? 'Rad etildi' : 'Tugadi');
      _close();
      return;
    }
    if (widget.isCaller && d['answer'] != null && !_answerSet) {
      _answerSet = true;
      final a = d['answer'] as Map;
      try {
        await _pc!.setRemoteDescription(
            RTCSessionDescription(a['sdp'] as String, a['type'] as String));
        await _flush();
      } catch (_) {}
      _listenCandidates();
    }
  }

  void _onConnState(RTCPeerConnectionState s) {
    _pcState = s;
    if (_closing) return;
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _failGuard?.cancel();
        _failGuard = null;
        _timeout?.cancel();
        if (!_connected) {
          _startedAt = DateTime.now();
          _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
            if (_startedAt == null) return;
            _set(() =>
                _seconds = DateTime.now().difference(_startedAt!).inSeconds);
          });
        }
        _set(() {
          _connected = true;
          _status = 'Ulandi';
        });
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        // Vaqtinchalik uzilish — qo'ng'iroqni YOPMAYMIZ, qayta ulanishini kutamiz.
        _set(() => _status = 'Qayta ulanmoqda...');
        _failGuard?.cancel();
        _failGuard = Timer(const Duration(seconds: 20), () {
          if (!_closing && !_isLive()) _hangup();
        });
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _set(() => _status = 'Aloqa uzildi');
        _failGuard?.cancel();
        _failGuard = Timer(const Duration(seconds: 6), () {
          if (!_closing && !_isLive()) _hangup();
        });
        break;
      default:
        break;
    }
  }

  bool _isLive() =>
      _pcState == RTCPeerConnectionState.RTCPeerConnectionStateConnected;

  Future<void> _flush() async {
    for (final c in _pending) {
      try {
        await _pc?.addCandidate(c);
      } catch (_) {}
    }
    _pending.clear();
  }

  void _listenCandidates() {
    _subs.add(_doc
        .collection(widget.isCaller ? 'calleeCandidates' : 'callerCandidates')
        .snapshots()
        .listen((s) async {
      for (final ch in s.docChanges) {
        if (ch.type != DocumentChangeType.added) continue;
        final d = ch.doc.data();
        if (d == null) continue;
        final cand = RTCIceCandidate(d['candidate'] as String?,
            d['sdpMid'] as String?, d['sdpMLineIndex'] as int?);
        try {
          await _pc?.addCandidate(cand);
        } catch (_) {
          _pending.add(cand);
        }
      }
    }));
  }

  // -------------------------------------------------------------- boshqaruv

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
  }

  /// Kamerani yoqish/o'chirish — qo'ng'iroqqa TEGMAYDI, faqat trek o'chadi.
  void _toggleCam() {
    final t = _videoTrack;
    if (t == null) return;
    final next = !_camOff;
    t.enabled = !next;
    HapticFeedback.selectionClick();
    _set(() => _camOff = next);
  }

  Future<void> _switchCam() async {
    final t = _videoTrack;
    if (t == null) return;
    try {
      await Helper.switchCamera(t);
      HapticFeedback.selectionClick();
      _set(() => _front = !_front);
    } catch (_) {}
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speaker;
    try {
      await Helper.setSpeakerphoneOn(next);
    } catch (_) {}
    HapticFeedback.selectionClick();
    _set(() => _speaker = next);
  }

  Future<void> _hangup() async {
    if (_closing) return;
    HapticFeedback.mediumImpact();
    // Avval ekranni yopamiz — tarmoq sekin bo'lsa ham tugma "ishlamadi"
    // bo'lib ko'rinmasligi uchun.
    final ref = _doc;
    final secs = _seconds;
    _close();
    try {
      await ref.update({
        'status': 'ended',
        'duration': secs,
        'endedAt': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _ticker?.cancel();
    _failGuard?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    try {
      _stream?.getTracks().forEach((t) => t.stop());
    } catch (_) {}
    _localR.srcObject = null;
    _remoteR.srcObject = null;
    _stream?.dispose();
    _pc?.close();
    _localR.dispose();
    _remoteR.dispose();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    super.dispose();
  }

  // -------------------------------------------------------------- ko'rinish

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final hasRemoteVideo = widget.video && _remoteReady;
    final showLocalBig = _swap && hasRemoteVideo;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hangup();
      },
      child: Scaffold(
        backgroundColor: callBg,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _set(() => _controls = !_controls),
          child: Stack(fit: StackFit.expand, children: [
            const Positioned.fill(child: CallBackdrop()),

            // --- asosiy video / avatar ---
            if (hasRemoteVideo)
              Positioned.fill(
                child: RTCVideoView(
                  showLocalBig ? _localR : _remoteR,
                  mirror: showLocalBig && _front,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              )
            else
              Positioned.fill(child: _waitingView()),

            if (hasRemoteVideo)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.45),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.55),
                        ],
                        stops: const [0, 0.42, 1],
                      ),
                    ),
                  ),
                ),
              ),

            // --- o'zimning kichik oynam ---
            if (widget.video)
              _localPip(size, showLocalBig),

            // --- yuqori ma'lumot ---
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 240),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasRemoteVideo) ...[
                        Text(
                          widget.peerName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _connected ? fmtDuration(_seconds) : _status,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            ),

            // --- pastki boshqaruv ---
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
                  duration: const Duration(milliseconds: 240),
                  child: _controlBar(),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _waitingView() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        PulseRing(
          color: const Color(0xFFB8893B),
          size: 132,
          active: !_connected,
          child: Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2A2A31), Color(0xFF15151A)],
              ),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10), width: 1),
            ),
            alignment: Alignment.center,
            child: Text(
              widget.peerName.trim().isEmpty
                  ? '?'
                  : widget.peerName.trim().characters.first.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 52,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text(
          widget.peerName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 27,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _connected ? fmtDuration(_seconds) : _status,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        if (_connected && !widget.video) ...[
          const SizedBox(height: 6),
          Text(
            'Audio qo\'ng\'iroq',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 12,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ]),
    );
  }

  Widget _localPip(Size size, bool showLocalBig) {
    const w = 108.0;
    const h = 150.0;
    final maxX = (size.width - w - 32.0) < 0.0 ? 0.0 : (size.width - w - 32.0);
    final maxY =
        (size.height - h - 270.0) < 0.0 ? 0.0 : (size.height - h - 270.0);
    final dx = _pip.dx.clamp(0.0, maxX).toDouble();
    final dy = _pip.dy.clamp(0.0, maxY).toDouble();
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16.0 + dy,
      left: 16.0 + dx,
      child: GestureDetector(
        onPanUpdate: (d) => _set(() => _pip = Offset(
              (dx + d.delta.dx).clamp(0.0, maxX).toDouble(),
              (dy + d.delta.dy).clamp(0.0, maxY).toDouble(),
            )),
        onTap: () => _set(() => _swap = !_swap),
        child: Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: const Color(0xFF15151A),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.14), width: 1),
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 18),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: _camOff
              ? Center(
                  child: Icon(Icons.videocam_off_rounded,
                      color: Colors.white.withValues(alpha: 0.5), size: 28),
                )
              : RTCVideoView(
                  showLocalBig ? _remoteR : _localR,
                  mirror: showLocalBig ? false : _front,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
        ),
      ),
    );
  }

  Widget _controlBar() {
    const glass = Color(0x33FFFFFF);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                SizedBox(
                  width: 64,
                  child: Center(
                    child: CircleIconButton(
                      icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      onTap: _toggleMute,
                      size: 54,
                      bg: _muted ? Colors.white : glass,
                      fg: _muted ? const Color(0xFF111114) : Colors.white,
                    ),
                  ),
                ),
                if (widget.video)
                  SizedBox(
                    width: 64,
                    child: Center(
                      child: CircleIconButton(
                        icon: _camOff
                            ? Icons.videocam_off_rounded
                            : Icons.videocam_rounded,
                        onTap: _toggleCam,
                        size: 54,
                        bg: _camOff ? Colors.white : glass,
                        fg: _camOff ? const Color(0xFF111114) : Colors.white,
                      ),
                    ),
                  ),
                if (widget.video)
                  SizedBox(
                    width: 64,
                    child: Center(
                      child: CircleIconButton(
                        icon: Icons.flip_camera_ios_rounded,
                        onTap: _switchCam,
                        size: 54,
                        bg: glass,
                      ),
                    ),
                  ),
                SizedBox(
                  width: 64,
                  child: Center(
                    child: CircleIconButton(
                      icon: _speaker
                          ? Icons.volume_up_rounded
                          : Icons.phone_in_talk_rounded,
                      onTap: _toggleSpeaker,
                      size: 54,
                      bg: _speaker ? Colors.white : glass,
                      fg: _speaker ? const Color(0xFF111114) : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // --- QIZIL TUGMA: katta, aniq, mustaqil bosiladigan maydon ---
          SizedBox(
            width: 84,
            height: 84,
            child: Center(
              child: CircleIconButton(
                icon: Icons.call_end_rounded,
                onTap: _hangup,
                size: 74,
                bg: const Color(0xFFE23D3D),
                glow: true,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tugatish',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ]),
      ),
    );
  }
}

// ============================================================================
//  Kiruvchi qo'ng'iroq — butun ekranli
// ============================================================================

class IncomingCallScreen extends StatefulWidget {
  final String callId, fromId, name;
  final bool video;
  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.fromId,
    required this.name,
    required this.video,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  StreamSubscription? _sub;
  Timer? _buzz;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _sub = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .snapshots()
        .listen((s) {
      final st = s.data()?['status'];
      if (st != 'ringing') _pop(null);
    });
    _buzz = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      HapticFeedback.heavyImpact();
    });
    Timer(const Duration(seconds: 45), () => _pop(null));
  }

  void _pop(bool? result) {
    if (_done || !mounted) return;
    _done = true;
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _buzz?.cancel();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _pop(false);
      },
      child: Scaffold(
        backgroundColor: callBg,
        body: Stack(fit: StackFit.expand, children: [
          const Positioned.fill(child: CallBackdrop()),
          SafeArea(
            child: Column(children: [
              const Spacer(flex: 2),
              Text(
                widget.video ? "VIDEO QO'NG'IROQ" : "QO'NG'IROQ",
                style: TextStyle(
                  color: const Color(0xFFB8893B).withValues(alpha: 0.95),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 26),
              PulseRing(
                color: const Color(0xFF28B463),
                size: 136,
                child: UserAvatar(
                    uid: widget.fromId, size: 136, showOnline: false),
              ),
              const SizedBox(height: 26),
              Text(
                widget.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'sizga qo\'ng\'iroq qilmoqda...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 14.5,
                ),
              ),
              const Spacer(flex: 3),
              Padding(
                padding: const EdgeInsets.fromLTRB(44, 0, 44, 46),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CircleIconButton(
                      icon: Icons.call_end_rounded,
                      onTap: () => _pop(false),
                      bg: const Color(0xFFE23D3D),
                      size: 76,
                      glow: true,
                      label: 'Rad etish',
                    ),
                    CircleIconButton(
                      icon: widget.video
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      onTap: () => _pop(true),
                      bg: const Color(0xFF28B463),
                      size: 76,
                      glow: true,
                      label: 'Javob berish',
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
