# Djigarlar

Android uchun shaxsiy messenger (Flutter + Firebase).

## v0.7.0
- Username: ro'yxatdan o'tishda tanlanadi (noyob, a-z 0-9 _), profilda o'zgartiriladi. Username'i yo'q eski foydalanuvchilarga kirganda so'raladi
- Qidiruv: chatlar va kontaktlar qidiruvida ism yoki @username yozilsa, odam topiladi (suhbat hali bo'lmasa ham)
- Kontaktlar: topilgan odamni saqlash (+), kontaktlar ro'yxati faqat saqlanganlardan iborat, profildan saqlash/o'chirish
- Guruh: a'zolar kontaktlardan yoki @username qidirib tanlanadi, yaratilgach guruh chati darrov ochiladi
- firestore.rules yangilandi (`usernames` to'plami): Rules bo'limiga qayta qo'ying!

## v0.6.4
- Yangi dizayn: yanada jonli ranglar, chuqur qorong'i rejim, yumshoq soyali kartalar, yumaloq dialog va menyular, 3 rangli gradient sarlavha, yangi 4 ta chat foni

## v0.6.3
- Build tuzatishlari: plaginlar uchun compileSdk 36, `record_linux` mosligi, logotip fayllari yo'q bo'lsa ham build o'tadi
- Firebase sozlanmagan bo'lsa ilova yiqilmaydi, tushuntirish ekrani ko'rsatadi
- Firebase qiymatlarini GitHub Secrets orqali berish mumkin (kodga yozmasdan)
- Eskirgan `withOpacity` o'rniga `withValues`; workflow: kesh, taymaut, takroriy ishga tushishni bekor qilish

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
4. Firebase qiymatlarini kiriting (ikki yo'ldan biri):
   - `lib/firebase_config.dart` ga 4 ta qiymatni yozing, yoki
   - GitHub -> Settings -> Secrets and variables -> Actions da `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID` nomli 4 ta secret yarating (build paytida avtomatik yoziladi).
5. `git push` qiling, GitHub -> Actions -> Build APK -> Artifacts dan `djigarlar-apk` ni yuklab oling.

## Cheklovlar
- Kiruvchi qo'ng'iroq faqat ilova ochiq bo'lganda ko'rinadi (push bildirishnoma keyingi versiyada).
- Ba'zi tarmoqlarda (mobil operatorlar) qo'ng'iroq ulanmasligi mumkin: TURN server kerak bo'ladi.
- Guruh qo'ng'iroqlari hali yo'q.
