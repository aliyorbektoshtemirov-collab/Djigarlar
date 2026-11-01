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

// ---------------------------------------------------------------------------
// iOS uchun: Firebase Console -> loyiha sozlamalari -> "Ilova qo'shish" -> iOS
// Bundle ID: uz.djigarlar.djigarlar
// So'ng GoogleService-Info.plist dagi qiymatlarni shu yerga ko'chiring:
//   API_KEY      -> apiKey
//   GOOGLE_APP_ID-> appId   (1:187349473371:ios:...)
// Yoki GitHub Secrets: IOS_FIREBASE_API_KEY, IOS_FIREBASE_APP_ID
// ---------------------------------------------------------------------------
const _ios = FirebaseOptions(
  apiKey: 'SHU_YERGA_IOS_API_KEY',
  appId: 'SHU_YERGA_IOS_APP_ID',
  messagingSenderId: '187349473371',
  projectId: 'djigarlar',
  iosBundleId: 'uz.djigarlar.djigarlar',
);

FirebaseOptions get firebaseOptions =>
    defaultTargetPlatform == TargetPlatform.iOS ? _ios : _android;
