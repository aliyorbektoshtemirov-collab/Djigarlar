import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

// Firebase loyihasi: djigarlar
// Android ilova: uz.djigarlar.djigarlar

const _android = FirebaseOptions(
  apiKey: 'AIzaSyA1QbsBy0nhssfI3M9v-NI-BMk1_yiCrNU',
  appId: '1:187349473371:android:ab3357408d570908ff477e',
  messagingSenderId: '187349473371',
  projectId: 'djigarlar',
);

// iOS ilova: uz.djigarlar.djigarlar
// (GoogleService-Info.plist dagi qiymatlar)
const _ios = FirebaseOptions(
  apiKey: 'AIzaSyC_IzpJ31B8UgfPb5q56JNUrnPAv4o7cXw',
  appId: '1:187349473371:ios:3648660037b8ae90ff477e',
  messagingSenderId: '187349473371',
  projectId: 'djigarlar',
  storageBucket: 'djigarlar.firebasestorage.app',
  iosBundleId: 'uz.djigarlar.djigarlar',
);

FirebaseOptions get firebaseOptions =>
    defaultTargetPlatform == TargetPlatform.iOS ? _ios : _android;
