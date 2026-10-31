import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallScreen extends StatefulWidget {
  final String callId;
  final bool isCaller;
  final bool video;
  final String peerName;
  final String peerId;
  final String myName;
  const CallScreen(
      {super.key,
      required this.callId,
      required this.isCaller,
      required this.video,
      required this.peerName,
      required this.peerId,
      required this.myName});
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
  Timer? _timeout;
  bool _muted = false,
      _camOff = false,
      _speaker = false,
      _connected = false,
      _closing = false,
      _answerSet = false;
  late String _status = widget.isCaller ? "Qo'ng'iroq qilinmoqda..." : 'Ulanmoqda...';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _localR.initialize();
      await _remoteR.initialize();
      _stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.video ? {'facingMode': 'user'} : false,
      });
      _localR.srcObject = _stream;
      _speaker = widget.video;
      await Helper.setSpeakerphoneOn(_speaker);
      if (mounted) setState(() {});

      _pc = await createPeerConnection({
        'iceServers': [
          {
            'urls': [
              'stun:stun.l.google.com:19302',
              'stun:stun1.l.google.com:19302'
            ]
          }
        ],
        'sdpSemantics': 'unified-plan',
      });
      for (final t in _stream!.getTracks()) {
        await _pc!.addTrack(t, _stream!);
      }
      _pc!.onTrack = (e) {
        if (e.streams.isNotEmpty) {
          _remoteR.srcObject = e.streams[0];
          if (mounted) setState(() {});
        }
      };
      _pc!.onIceCandidate = (c) {
        if (c.candidate == null) return;
        _doc
            .collection(widget.isCaller ? 'callerCandidates' : 'calleeCandidates')
            .add(Map<String, dynamic>.from(c.toMap()));
      };
      _pc!.onConnectionState = (s) {
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _timeout?.cancel();
          if (mounted) {
            setState(() {
              _connected = true;
              _status = 'Ulandi';
            });
          }
        } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _hangup();
        }
      };

      _subs.add(_doc.snapshots().listen((s) async {
        final d = s.data();
        if (d == null) return;
        final st = d['status'];
        if (st == 'ended' || st == 'declined') {
          _close();
          return;
        }
        if (widget.isCaller && d['answer'] != null && !_answerSet) {
          _answerSet = true;
          final a = d['answer'] as Map;
          await _pc!.setRemoteDescription(
              RTCSessionDescription(a['sdp'] as String, a['type'] as String));
          _listenCandidates();
        }
      }));

      if (widget.isCaller) {
        final offer = await _pc!.createOffer();
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
        _timeout = Timer(const Duration(seconds: 40), () {
          if (!_connected) _hangup();
        });
      } else {
        final snap = await _doc.get();
        final o = snap.data()!['offer'] as Map;
        await _pc!.setRemoteDescription(
            RTCSessionDescription(o['sdp'] as String, o['type'] as String));
        final ans = await _pc!.createAnswer();
        await _pc!.setLocalDescription(ans);
        await _doc.update({
          'answer': {'sdp': ans.sdp, 'type': ans.type},
          'status': 'accepted',
        });
        _listenCandidates();
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Xato: $e');
      await Future.delayed(const Duration(seconds: 3));
      _hangup();
    }
  }

  void _listenCandidates() {
    _subs.add(_doc
        .collection(widget.isCaller ? 'calleeCandidates' : 'callerCandidates')
        .snapshots()
        .listen((s) {
      for (final ch in s.docChanges) {
        if (ch.type == DocumentChangeType.added) {
          final d = ch.doc.data()!;
          _pc?.addCandidate(RTCIceCandidate(
              d['candidate'] as String?,
              d['sdpMid'] as String?,
              d['sdpMLineIndex'] as int?));
        }
      }
    }));
  }

  Future<void> _hangup() async {
    try {
      await _doc.update({'status': 'ended'});
    } catch (_) {}
    _close();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timeout?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _stream?.getTracks().forEach((t) => t.stop());
    _stream?.dispose();
    _pc?.close();
    _localR.dispose();
    _remoteR.dispose();
    super.dispose();
  }

  Widget _btn(IconData icon, VoidCallback onTap,
          {Color? bg, Color? fg = Colors.white}) =>
      CircleAvatar(
        radius: 28,
        backgroundColor: bg ?? Colors.white24,
        child: IconButton(
            icon: Icon(icon, color: fg), iconSize: 28, onPressed: onTap),
      );

  @override
  Widget build(BuildContext context) {
    final showRemoteVideo = widget.video && _remoteR.srcObject != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _hangup();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          if (showRemoteVideo)
            Positioned.fill(
                child: RTCVideoView(_remoteR,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))
          else
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircleAvatar(
                    radius: 54,
                    child: Text(
                        widget.peerName.isEmpty
                            ? '?'
                            : widget.peerName[0].toUpperCase(),
                        style: const TextStyle(fontSize: 40))),
                const SizedBox(height: 16),
                Text(widget.peerName,
                    style: const TextStyle(color: Colors.white, fontSize: 26)),
                const SizedBox(height: 8),
                Text(_status, style: const TextStyle(color: Colors.white70)),
              ]),
            ),
          if (widget.video)
            Positioned(
              top: 48,
              right: 16,
              width: 100,
              height: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RTCVideoView(_localR,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _btn(_muted ? Icons.mic_off : Icons.mic, () {
                setState(() => _muted = !_muted);
                for (final t in _stream?.getAudioTracks() ?? []) {
                  t.enabled = !_muted;
                }
              }),
              if (widget.video)
                _btn(_camOff ? Icons.videocam_off : Icons.videocam, () {
                  setState(() => _camOff = !_camOff);
                  for (final t in _stream?.getVideoTracks() ?? []) {
                    t.enabled = !_camOff;
                  }
                }),
              _btn(_speaker ? Icons.volume_up : Icons.hearing, () {
                setState(() => _speaker = !_speaker);
                Helper.setSpeakerphoneOn(_speaker);
              }),
              _btn(Icons.call_end, _hangup, bg: Colors.red),
            ]),
          ),
        ]),
      ),
    );
  }
}
