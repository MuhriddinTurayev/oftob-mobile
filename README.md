# Oftob CRM — mobil ilova (Flutter)

`C:\backend\OSPanel\home\erm` (Laravel CRM) uchun Android ilova.

## Ikki rejim

| Rejim | Nima ochiladi | Kirish |
|---|---|---|
| **Platforma** (asosiy) | Veb-dasturning o'zi ilova ichida: **hamma bo'lim** (jurnal, tasdiqlar, davomat+GPS, prorab pullari, hisobotlar, AI, 3D, sotuv, kassa…), rollar va huquqlar saytdagidek | Email + parol (xodimlar uchun «Kompaniya manzili» ham) |
| **API kalit** (tezkor) | Mahalliy ekranlar: obyektlar, lidlar, kassa, ombor, vazifalar | `oft_…` kalit |

Platforma rejimida API kalit **kerak emas**: sayt qanday kirsangiz, ilovada ham shunday kirasiz.
Kirish saqlanadi (cookie), keyingi safar to'g'ridan-to'g'ri ochiladi. Menyu (⋮): Bosh sahifa, Yangilash, Brauzerda ochish, Chiqish.

Platforma rejimining hozirgi cheklovlari:
- Google bilan kirish ilova ichida ishlamaydi (Google WebView'ni bloklaydi) — email/parol bilan kiring.
- Fayl yuklab olish (PDF shartnoma, chek) hozircha ilova ichida ishlamaydi — Menyu → «Brauzerda ochish».
- Rasm yuklashda galereyadan tanlanadi (to'g'ridan-to'g'ri kamera hozircha yo'q).
- GPS (davomat belgisi) ishlaydi: birinchi marta joylashuv ruxsatini bering.

## iPhone (iOS)

Kod Android bilan **bitta** (Flutter), `ios/` papkasi to'liq sozlangan (iOS 15+, ruxsatlar, orqaga surish).
Apple qoidasi: iPhone ilovasini yig'ish uchun Xcode kerak, u faqat macOS'da ishlaydi — Windows'da yig'ib bo'lmaydi.
Mac'siz yo'l — GitHub'ning macOS serverida yig'ish (`.github/workflows/ios.yml` tayyor):

1. `oftob_mobile` papkasini GitHub'ga yuklang (**private** repo): `git init`, `git add .`, `git commit`, `git push`.
2. GitHub → **Actions** → «iPhone (iOS) yig'ish» → **Run workflow**. ~15 daqiqa.
3. Tugagach **Artifacts → oftob-ios** dan `Oftob.ipa` ni yuklab oling (imzosiz IPA).

IPA'ni iPhone'ga o'rnatish (uchta yo'l):

| Yo'l | Narx | Muddat | Qanday |
|---|---|---|---|
| **Sideloadly** / AltStore (Windows'da ishlaydi) | bepul (oddiy Apple ID) | har 7 kunda qayta o'rnatish | iPhone'ni USB bilan ulang, Sideloadly'ga IPA'ni tashlang |
| **TestFlight** | 99$/yil Apple Developer | 90 kun, 10 000 gacha tester | IPA'ni imzolab App Store Connect'ga yuklash (Codemagic buni osonlashtiradi) |
| **App Store** | 99$/yil | doimiy | Apple tekshiruvidan o'tadi |

Mac bor bo'lsa: `flutter pub get` → `flutter build ios --release` yoki Xcode'da `ios/Runner.xcworkspace` → Run.

## Baza bilan qanday ulanadi (API kalit rejimi)

```
Telefon (Flutter)  ──HTTPS──▶  Laravel  /api/v1  ──▶  MySQL (erm_app)
     API kalit (oft_…)          ruxsatlarni tekshiradi     ma'lumotlar
```

Ilova MySQL'ga **to'g'ridan-to'g'ri ulanmaydi** — bu xavfli (baza paroli telefonda qoladi, hamma ma'lumot ochiladi).
U Laravel'ning tayyor ochiq API'si (`/api/v1`) orqali ishlaydi. Har bir so'rovda `Authorization: Bearer oft_…` yuboriladi,
server kalitning roli va ruxsatlariga qarab ma'lumot beradi. Kalit faqat o'z kompaniyangiz va ruxsat etilgan obyektlarni ko'radi.

Serverda **hech narsa o'zgartirish shart emas**.

## 1. API kalit olish

1. Veb-dasturga kiring → **Kompaniya → API va integratsiyalar** (`/company/api`) → kalit so'rang.
2. Super admin (`/admin`) kalitni beradi: `oft_…` bilan boshlanadi. Rolni tanlang (masalan «Rahbar»).
3. Kalitni ilovada **Kirish** oynasiga kiriting. U telefonning xavfsiz xotirasida saqlanadi.

Ilovada faqat kalitga ruxsat berilgan bo'limlar ko'rinadi:

| Bo'lim | Kerakli ruxsat | Nima qiladi |
|---|---|---|
| Obyektlar | `objects:read` | obyektlar, tayyorlik %, kvartiralar ro'yxati |
| (kvartira) | `sales:write` | bron qilish / sotish / bo'shatish |
| Lidlar | `leads:read`, `leads:write` | arizalar, yangi ariza qo'shish |
| Kassa | `cash:read` | kassalar qoldig'i, operatsiyalar |
| Ombor | `stock:read` | materiallar va qoldiqlar |
| Vazifalar | `tasks:read`, `tasks:write` | vazifalar, holatini o'zgartirish |

## 2. Server manzili

| Holat | Manzil |
|---|---|
| Ishlab turgan server | `https://oftob.37-60-247-120.sslip.io` (standart) |
| Kompyuteringizdagi Laravel, telefon (Wi-Fi) | `http://192.168.1.55:8000` — faqat **debug** build |
| Android emulyator → kompyuter | `http://10.0.2.2:8000` — faqat **debug** build |

Kompyuterdagi Laravel'ni telefonga ochish (OSPanel `https://erp` faqat kompyuterning o'zida ishlaydi):

```bash
cd C:\backend\OSPanel\home\erm
php artisan serve --host=0.0.0.0 --port=8000
```

Windows xavfsizlik devori so'rasa — «Private network» uchun ruxsat bering. Telefon va kompyuter bitta Wi-Fi'da bo'lsin.

## 3. Ishga tushirish

Barcha buyruqlar shu papkada (`oftob_mobile`):

```bash
flutter pub get          # paketlarni yuklash (birinchi marta)
flutter devices          # ulangan qurilmalar ro'yxati
flutter run              # telefon / emulyatorda ishga tushirish
```

**Haqiqiy telefonda:** Sozlamalar → Telefon haqida → «Build raqami»ni 7 marta bosing → Dasturchi parametrlari →
**USB debugging** yoqing → USB bilan ulang → telefonda «Ruxsat berish» → `flutter run`.

**Emulyatorda:** Android Studio → Device Manager → Create device → ishga tushiring → `flutter run`.

## 4. APK yig'ish (telefonga o'rnatish uchun)

```bash
flutter build apk --release
```

Tayyor fayl: `build\app\outputs\flutter-apk\app-release.apk` — telefonga yuboring va o'rnating.
Release build faqat **HTTPS** serverga ulanadi (http — faqat debug'da).
Play Market uchun alohida imzo kaliti (keystore) kerak: https://docs.flutter.dev/deployment/android

## 5. Kod tuzilmasi

| Fayl | Vazifasi |
|---|---|
| `lib/api.dart` | `/api/v1` bilan ishlash, xatolarni o'zbekchaga o'girish |
| `lib/session.dart` | server + kalitni saqlash, kirish/chiqish |
| `lib/screens/login.dart` | kirish oynasi |
| `lib/screens/home.dart` | pastki menyu (ruxsatga qarab) |
| `lib/screens/objects.dart` | obyektlar → kvartiralar → bron/sotuv |
| `lib/screens/leads.dart`, `cash.dart`, `stock.dart`, `tasks.dart` | qolgan bo'limlar |
| `test/widget_test.dart` | testlar (`flutter test`) |

Yangi bo'lim qo'shish: `C:\backend\OSPanel\home\erm\app\Services\Api\Spec.php` da barcha endpointlar tavsifi bor
(yoki veb-saytda `/developers`), `lib/api.dart` ga metod qo'shing va `home.dart` ga tab qo'shing.

## Tez-tez uchraydigan muammolar

- **«Serverga ulanib bo'lmadi»** — manzil xato, internet yo'q yoki (http bo'lsa) release build. Brauzerda manzilni oching: `…/api/v1` JSON qaytarishi kerak.
- **«API kalit noto'g'ri / bekor qilingan»** — yangi kalit so'rang.
- **«Bu bo'lim uchun kalitda ruxsat yo'q»** — kalit rolida shu bo'limga huquq yo'q.
- **`flutter` topilmadi** — terminalni yoping va qayta oching (PATH yangilanadi).
