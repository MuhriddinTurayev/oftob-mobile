/// Firebase loyihasi «Oftob Building» (oftob-building) — Android ilova sozlamalari.
/// Bu qiymatlar maxfiy emas (har bir APK ichida bo'ladi); serverdagi maxfiy kalit — platforma sozlamalarida.
/// Bo'sh bo'lsa — Firebase push o'chiq, ilova avvalgidek fondagi tekshiruv bilan ishlaydi.
class FirebaseConfig {
  static const apiKey = 'AIzaSyD_S9bRN-dox07C4xGmsM29tOrjozcqTm0';
  static const appId = '1:114323522041:android:a386e1fe717d8bc7a87d28';
  static const messagingSenderId = '114323522041';
  static const projectId = 'oftob-building';

  static bool get ready => apiKey.isNotEmpty && appId.isNotEmpty && messagingSenderId.isNotEmpty;
}
