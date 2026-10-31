# Djigarlar

Android uchun shaxsiy messenger (Flutter + Firebase).

## v0.6.2
- Pastki panel iOS Telegram uslubida: tekis panel, to'ldirilgan/konturli ikonkalar, bounce animatsiya, tebranish, o'qilmagan xabarlar nishoni, sahifalar orasida silliq o'tish

## v0.6
- Yangi dizayn: gradient sarlavhalar, yumshoq kartalar, yangi kirish ekrani, sanalar chatda, yangi xabar maydoni, profil sarlavhasi, qo'ng'iroq ekrani foni

## v0.5
- Ovozli xabarlar (mikrofon tugmasi, 60 soniyagacha)
- So'rovnomalar (skrepka tugmasi)
- Xabarni uzatish, "Saqlangan xabarlarga" qo'shish, xabarni qadash, chat ichida qidirish
- Guruh boshqaruvi: nom o'zgartirish, a'zo qo'shish/chiqarish, guruhdan chiqish
- Foydalanuvchi profili (ismga bosing), chat fonlari, arxiv
- Matn formati: **qalin**, __kursiv__, `kod`, ~~chiziq~~; faqat emoji bo'lsa katta ko'rinadi
- Ilova ochiq paytida yangi xabar bildirishnomasi

## v0.4
- Yangi dizayn: logotip, rangli mavzular (8 rang), kun/tun rejimi
- Chat ro'yxati: oxirgi xabar, o'qilmaganlar soni, qadash, papkalar (Hammasi/Shaxsiy/Guruhlar), qidiruv
- Saqlangan xabarlar
- Reaksiyalar, javob berish, tahrirlash, o'chirish, stikerlar
- O'qildi belgilari, "yozmoqda...", onlayn / oxirgi marta
- Profil: rasm, bio, emoji holat

## v0.3
- Galereyadan rasm yuborish (rasm kichraytirilib Firestore'da saqlanadi, Storage kerak emas)

## v0.2
- Email/parol bilan kirish va ro'yxatdan o'tish
- 1-1 real vaqtdagi chat
- Guruh chatlar (yaratish, a'zolarni tanlash, yuboruvchi ismi)
- Audio va video qo'ng'iroq (WebRTC, 1-1)

## Sozlash
1. console.firebase.google.com da loyiha oching, Android ilova qo'shing (package: `uz.djigarlar.djigarlar`).
2. Authentication -> Email/Password ni yoqing.
3. Firestore Database yarating, so'ng Rules bo'limiga `firestore.rules` faylidagi matnni qo'ying va Publish bosing (har yangilanishda qayta qo'ying).
4. `lib/firebase_config.dart` ga 4 ta qiymatni yozing.
5. `git push` qiling, GitHub -> Actions -> Build APK -> Artifacts dan `djigarlar-apk` ni yuklab oling.

## Cheklovlar
- Kiruvchi qo'ng'iroq faqat ilova ochiq bo'lganda ko'rinadi (push bildirishnoma keyingi versiyada).
- Ba'zi tarmoqlarda (mobil operatorlar) qo'ng'iroq ulanmasligi mumkin: TURN server kerak bo'ladi.
- Guruh qo'ng'iroqlari hali yo'q.
