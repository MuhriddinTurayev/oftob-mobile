# Oftob Building — iOS App Store uchun yo'riqnoma / Инструкция для публикации в App Store

Flutter ilovasi «Oftob Building» (qurilish kompaniyasi CRM: obyektlar, kassa, lidlar, davomat va h.k.).
Приложение на Flutter «Oftob Building» (CRM строительной компании: объекты, касса, лиды, посещаемость и т.д.).

Joriy versiya / Текущая версия: см. `pubspec.yaml` → `version: X.Y.Z+N`

## 1. Server / Сервер
Ilova tayyor serverga ulangan, sozlash shart emas / Приложение уже подключено к рабочему серверу:

    https://oftob.5-189-163-130.sslip.io

(`lib/session.dart` → `defaultServer`). Barcha ma'lumotlar (obyektlar, kassa, lidlar…) shu serverdan olinadi — ilovada alohida baza yo'q.
Boshqa serverga ulash / другой сервер: `--dart-define=OFTOB_SERVER=https://sizning-server.uz`

## 2. Kodni olish / Получить код
    git clone https://github.com/MuhriddinTurayev/oftob-mobile.git

Har doim `main` shoxidagi so'nggi kod — eng yangi versiya. / Последняя версия — всегда ветка `main`.

## 3. Variant A — Mac'siz, GitHub orqali (tavsiya) / Без Mac, через GitHub
Bir marta sozlanadi (ilova egasi yoki Apple hisobi egasi) / Настраивается один раз:

**Apple tomonida / На стороне Apple**
1. Apple Developer Program hisobi (99 USD/yil). / Аккаунт Apple Developer Program.
2. App Store Connect → My Apps → «+» → New App: Bundle ID `uz.oftob.oftobMobile` (yoki o'zingiznikini), nom «Oftob Building».
3. App Store Connect → Users and Access → Integrations → **App Store Connect API** → kalit yarating (rol: **Admin** tavsiya etiladi,
   chunki Apple bulutida imzo sertifikatini avtomatik yaratadi). `Key ID`, `Issuer ID` va `.p8` faylni saqlang (`.p8` bir marta yuklab olinadi).
4. Developer hisobidagi **Team ID** (10 belgi): developer.apple.com → Membership.

**GitHub tomonida / На стороне GitHub** (Fork yoki o'z repongiz → Settings → Secrets and variables → Actions):

| Nomi | Turi | Qiymat |
|---|---|---|
| `APPLE_TEAM_ID` | Secret | Team ID (10 belgi) |
| `APPSTORE_KEY_ID` | Secret | API kalit Key ID |
| `APPSTORE_ISSUER_ID` | Secret | Issuer ID |
| `APPSTORE_PRIVATE_KEY` | Secret | `.p8` faylning **butun matni** (-----BEGIN PRIVATE KEY----- bilan) |
| `IOS_BUNDLE_ID` | Variable (ixtiyoriy) | Bundle ID; bo'sh bo'lsa `uz.oftob.oftobMobile` |

**Yuklash / Загрузка:** GitHub → Actions → **«App Store Connect'ga yuklash (TestFlight)»** → Run workflow
(build raqamini kiriting yoki bo'sh qoldiring; har yuklashda u oldingisidan katta bo'lishi shart).
10–30 daqiqadan keyin build App Store Connect → TestFlight da ko'rinadi → App Store versiyasiga biriktirib, «Submit for Review».

> Diqqat: workflow Apple hisobisiz sinab ko'rilmagan. Birinchi ishga tushirishda log'ni kuzating; xato chiqsa (odatda imzo/ruxsat) — log matnini yuboring.
> Внимание: workflow не проверен с реальным Apple-аккаунтом; при первой ошибке (обычно подпись/права) смотрите лог.

## 4. Variant B — Mac + Xcode / Вариант B — Mac + Xcode
    flutter pub get
    flutter build ios --release --dart-define=BUILD_SHA=<ixtiyoriy>

Xcode → `ios/Runner.xcworkspace` → Runner → Signing & Capabilities → o'z **Team** va **Bundle Identifier**.
Product → Archive → Distribute App → App Store Connect.
Versiya: `pubspec.yaml` → `version: 1.0.15+16` (1.0.15 — versiya, 16 — build; har yuklashda build'ni oshiring).

## 5. App Review uchun / Для проверки Apple
- Ilovaga kirish uchun hisob kerak (kompaniya manzili + email + parol). **Demo-hisobni** ilova egasidan oling va
  App Store Connect → App Review Information → Sign-in required ga kiriting. / Demo-аккаунт получите у владельца.
- Ruxsatlar (`ios/Runner/Info.plist`): joylashuv (davomat), kamera/galereya (foto-hisobot, chek), mikrofon (ovozli yordamchi).
- Maxfiylik siyosati (Privacy Policy) havolasi va «App Privacy» anketasi kerak.
- iPhone skrinshotlari (Apple talab qiladigan o'lchamlarda).

## 6. Hozircha yo'q narsalar / Чего пока нет
- iOS'da push-bildirishnomalar (FCM) sozlanmagan: `lib/firebase_config.dart` faqat Android uchun. Ilova push'siz ishlaydi.
  Kerak bo'lsa — Firebase'da iOS ilova + APNs kaliti qo'shiladi.
- Android imzo kaliti repoda yo'q (maxfiy) — Android uchun kerak emas.

## 7. Tuzilma / Структура
- `lib/` — Dart kodi (ekranlar `lib/screens/`, API `lib/api.dart`, tarjimalar `lib/l10n_dict.dart` — uz/ru/tg)
- `ios/`, `android/`, `windows/` — platforma loyihalari
- `.github/workflows/ios.yml` — imzosiz IPA yig'ish (har push'da, sinov uchun)
- `.github/workflows/appstore.yml` — imzolab App Store Connect'ga yuklash (qo'lda ishga tushiriladi)
