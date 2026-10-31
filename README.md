# Djigarlar

Android uchun shaxsiy messenger (Flutter + Firebase).

## v0.8.0 — yangi dizayn va qo'ng'iroq tuzatishlari

**Dizayn ("Ivory & Ink")**
- Butunlay yangi ko'rinish: iliq oq (fil suyagi) fon, qora siyoh matn, oltin urg'u
- Suzuvchi pastki panel (markazda yangi suhbat tugmasi), 4 bo'lim: Chatlar / Kontaktlar / Qo'ng'iroqlar / Profil
- Animatsiyalar: sahifa o'tishlari, ro'yxat elementlari pastdan chiqishi, bosilganda kichrayish,
  "yozmoqda" nuqtalari, qo'ng'iroqda tarqaluvchi halqalar, yuklanish effekti (shimmer)
- Xabar pufaklari qayta ishlangan, oq/qora kontrast, yumshoq soyalar

**Tuzatilgan xatolar**
- **Chat pastda qolib ketishi**: `lastTime` serverdan kelguncha bo'sh bo'lgani uchun yangi xabar
  vaqtsiz va ro'yxat oxirida turardi. Endi mijoz vaqti (`lastTimeMs`, `timeMs`) ham yoziladi —
  xabar darrov tepaga chiqadi va vaqti ko'rinadi
- **Sekinlik**: chat ekrani har soniyada qayta chizilardi (rasm har safar qaytadan dekod qilinardi).
  Endi taymer faqat ovoz yozishda ishlaydi, rasmlar keshlanadi, xabar va chat bitta `batch` bilan
  yoziladi, Firestore oflayn keshi yoqildi
- **Video callda kamera tugmasi qo'ng'iroqni uzib yuborishi**: tugmalar bir-birining ustiga tushib
  qolgan edi va ulanish "disconnected" bo'lishi bilanoq qo'ng'iroq yopilardi. Endi har bir tugma
  o'z maydoniga ega, kamerani o'chirish faqat trekni o'chiradi, uzilishda 20 soniya qayta ulanish kutiladi
- **Qizil tugma**: katta (74 px), aniq qizil, yorqin halqali; bosilganda ekran darrov yopiladi
- **Rasmlar ochilmasligi**: hujjat 1 MB dan oshib ketgani uchun yuborilmay qolardi. Endi rasm
  kichraytiriladi (1080 px, 55%), chegara 700 KB, xato bo'lsa xabar beriladi; pufakda o'lcham
  oldindan egallanadi (silkinmaydi), to'liq ekranda zum, ikki marta bosish va pastga surib yopish

**Yangi imkoniyatlar**
- **Guruh video chat** (mesh): guruh chatida kamera tugmasi — hamma bir-birini ko'radi,
  qo'ng'iroq ketayotganda chatda "Qo'shilish" tasmasi chiqadi
- **Orqa/old kamerani almashtirish** video qo'ng'iroqda
- Kiruvchi qo'ng'iroq endi butun ekranli (katta yashil/qizil tugmalar)
- Qo'ng'iroqlar tarixi bo'limi
- Kameradan to'g'ridan-to'g'ri rasm yuborish
- `firestore.rules` yangilandi (`groupCalls`) — **Rules bo'limiga qayta qo'ying!**

## v0.7.2
- Firebase qiymatlari (`lib/firebase_config.dart`) yozildi
- firestore.rules: yangi suhbatning birinchi xabari darrov ko'rinadi (`usernames` qoidalari saqlangan). Rules'ga qayta qo'ying!

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
