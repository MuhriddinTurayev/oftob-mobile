import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as w show Text;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'api.dart';
import 'format.dart';
import 'l10n.dart';
import 'session.dart';
import 'theme.dart';

/// Ilovaning asosiy tugmalariga ulanadigan ko'prik: ovozli buyruq bo'limni ochadi yoki «Ishga keldim / Ketdim» ni so'raydi.
class AppNav {
  /// Bo'lim nomi (pastki tab yoki «Xizmatlar» nomi) bo'yicha ochish — HomeScreen o'rnatadi
  static bool Function(String label)? open;

  /// Mavjud bo'limlar (rolga qarab) — buyruqni tanish uchun
  static List<String> sections = const [];

  /// 'start' | 'end' — ShiftCard tinglaydi
  static final ValueNotifier<String?> shift = ValueNotifier(null);
}

enum VoiceKind { open, shiftStart, shiftEnd }

class VoiceCmd {
  const VoiceCmd(this.kind, [this.label]);
  final VoiceKind kind;
  final String? label;
}

/// Ovozli (yoki yozma) buyruqni tanish. Savollar («Kassada qancha pul bor?») AI ga ketadi; faqat aniq buyruqlar bajariladi:
/// bo'limni ochish (qisqa gap yoki «och / открой / кушо» fe'li bilan) va «Ishga keldim / Ketdim».
VoiceCmd? parseCommand(String raw) {
  final t = raw.toLowerCase().replaceAll(RegExp('''[’'`ʻʼ‘´.,!?;:«»"]'''), '').replaceAll('ё', 'е').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return null;
  final words = t.split(' ');
  bool has(List<String> keys) => keys.any(t.contains);

  if (words.length <= 6) {
    // faqat «men» haqida: «Bobur ishga keldi» — boshqa odam, uni SI tushunadi va davomatda belgilaydi
    const startK = ['ishga keldim', 'ишга келдим', 'я пришел', 'я пришла', 'я на работе', 'ба кор омадам', 'кор омадам'];
    const endK = ['ketdim', 'ishdan ketdim', 'кетдим', 'ишдан кетдим', 'я ушел', 'ушел с работы', 'я ухожу', 'аз кор рафтам', 'рафтам'];
    if (has(endK)) return const VoiceCmd(VoiceKind.shiftEnd);
    if (has(startK)) return const VoiceCmd(VoiceKind.shiftStart);
  }

  const verbs = ['och', 'ochib', 'ochgin', 'otib', 'otgin', 'ot ', 'korsat', 'kir', 'bor ', 'откр', 'покаж', 'перейд', 'зайд', 'перейти', 'открыт', 'кушо', 'равед', 'нишон', 'очиш', 'ўт', 'кур', 'кўрсат'];
  final cmdy = words.length <= 2 || verbs.any((v) => ('$t ').contains(v));
  if (!cmdy) return null;
  // savol so'zlari bo'lsa — bu buyruq emas
  const asks = ['qancha', 'nechta', 'necha', 'qaysi', 'kim ', 'nima', 'сколько', 'какой', 'какие', 'кто ', 'что ', 'сколь', 'чанд', 'кадом'];
  if (asks.any((a) => ('$t ').contains(a))) return null;

  final map = <String, List<String>>{
    "To'lov so'rovlari": ['tolov sorov', 'заявки на оплату', 'заявка на оплату', 'дархости пардохт', 'tolov'],
    'Kontragentlar': ['kontragent', 'контрагент', 'тарафи шартнома'],
    'Prorab puli': ['prorab pul', 'деньги прораб', 'пули прораб'],
    'Davomat': ['davomat', 'давомат', 'посещаем', 'табель', 'кто пришел', 'ишга келган'],
    'Xodimlar': ['xodim', 'ходим', 'сотрудник', 'ishchi', 'рабочи', 'корманд', 'коргар'],
    'Vazifalar': ['vazifa', 'вазифа', 'задач'],
    'Obyektlar': ['obyekt', 'объект', 'xonadon', 'kvartira', 'квартир', 'хонадон'],
    'Sotuv': ['sotuv', 'сотув', 'продаж', 'фуруш'],
    'Lidlar': ['lidlar', 'lid ', 'лид', 'mijozlar arizasi'],
    'Ombor': ['ombor', 'омбор', 'склад', 'анбор'],
    'Hisobotlar': ['hisobot', 'ҳисобот', 'хисобот', 'отчет', 'отчёт'],
    'Valyutalar': ['valyuta', 'валют'],
    'Kassa': ['kassa', 'касса', 'кассу'],
    'Pul': ['pul ', 'деньги', 'пул '],
    'Yana': ['yana', 'ещё', 'еще', 'профиль', 'profil', 'sozlama', 'настройк'],
    'Bosh': ['bosh sahifa', 'bosh ekran', 'asosiy', 'главн', 'домой', 'бош'],
  };
  for (final e in map.entries) {
    if (e.value.any((k) => ('$t ').contains(k))) {
      // rolda yo'q bo'lim — mavjudini topishga urinamiz
      if (AppNav.sections.contains(e.key) || e.key == 'Bosh' || e.key == 'Yana') return VoiceCmd(VoiceKind.open, e.key);
      if (e.key == 'Pul' && AppNav.sections.contains('Prorab puli')) return const VoiceCmd(VoiceKind.open, 'Prorab puli');
      if (e.key == 'Prorab puli' && AppNav.sections.contains('Pul')) return const VoiceCmd(VoiceKind.open, 'Pul');
    }
  }
  return null;
}

class AiMsg {
  AiMsg(this.role, this.text, {this.pending = false, this.error = false, this.confirm, this.id, this.ask = false});
  final String role; // user | assistant
  String text;
  bool pending;
  bool error;
  VoiceCmd? confirm; // «Ha / Yo'q» kutilmoqda (telefondagi buyruq)
  int? id; // serverdagi javob raqami
  bool ask; // SI pulga oid amalni bajarishdan oldin tasdiq so'rayapti («Tasdiqlash / Bekor qilish»)

  static AiMsg fromServer(Map m) => AiMsg('${m['role']}', '${m['content']}', error: m['status'] == 'error', id: (m['id'] as num?)?.toInt(), ask: m['confirm'] == true, pending: m['status'] == 'streaming');
}

/// AI yordamchi holati: yozishma, ovoz yozish, gapirib berish. Bitta nusxa — yozishma panel yopilsa ham saqlanadi.
class AssistantController extends ChangeNotifier {
  AssistantController(this.session);

  final Session session;
  final List<AiMsg> messages = [];
  List<String> chips = const [];
  bool loaded = false;
  String conv = _newId(); // joriy suhbat
  List<Map<String, dynamic>> history = const [];
  bool historyLoading = false;
  bool busy = false;
  bool voiceReady = true;
  bool aiReady = true;
  String? limitLine; // «Osta 978 / 1000 so'rov · 01.12 da yangilanadi»
  bool recording = false;
  bool transcribing = false;
  int _listenGen = 0; // «Bekor» bosilsa — kelgan matn e'tiborsiz qoldiriladi
  bool speak = false;
  int recSeconds = 0;

  /// Yozishma oynasi ochiqmi — yopiq bo'lsa, javob kelganda ekranda xabar chiqadi ([onBackgroundReply])
  bool sheetOpen = false;

  /// Oyna yopiq paytda SI javob berdi: ilova xabar ko'rsatadi («Ochish» bilan)
  void Function(String text)? onBackgroundReply;

  /// Yozishma oynasini ochish so'rovi (xabardagi «Ochish» tugmasi) — suzuvchi tugma tinglaydi
  final ValueNotifier<int> openRequest = ValueNotifier(0);

  final AudioRecorder _rec = AudioRecorder();
  final FlutterTts _tts = FlutterTts();
  Timer? _recTimer;
  String? _recPath;
  StreamSubscription<Amplitude>? _ampSub;
  // jimlikni aniqlash: ovoz umuman bo'lmasa, serverga yubormaymiz (aks holda model matn «to'qib» chiqaradi)
  double _peak = 0;
  int _ampN = 0;

  /// Ovoz balandligi 0..1 (yozish tugmasi «nafas oladi», Telegram'dagidek)
  final ValueNotifier<double> level = ValueNotifier(0);

  /// Yozish 45 soniyaga yetib o'zi to'xtadi — tayyor matn (yozish maydoniga qo'yiladi)
  final ValueNotifier<String?> autoText = ValueNotifier(null);

  ApiClient? get _api => session.api;

  static String _newId() => 'c${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1296).toRadixString(36).padLeft(2, '0')}';

  String _loadedLang = '';

  Future<void> load() async {
    if (loaded) {
      // ilova tili almashgan: tayyor savollar va limit matni yangi tilda qayta olinadi (suhbat o'zgarmaydi)
      if (_loadedLang != L.code) await _refreshTexts();
      return;
    }
    _loadedLang = L.code;
    try {
      final d = await _api!.aiState();
      messages
        ..clear()
        ..addAll(((d['messages'] as List?) ?? const []).whereType<Map>().where((m) => '${m['content']}'.trim().isNotEmpty || m['status'] == 'streaming').map(AiMsg.fromServer));
      chips = ((d['chips'] as List?) ?? const []).map((e) => '$e').toList();
      _resumePending();
      voiceReady = d['voice'] != false;
      final lim = d['limit'];
      if (lim is Map && lim['line'] != null) limitLine = '${lim['line']}';
      aiReady = d['ai'] != false;
      loaded = true;
    } catch (e) {
      loaded = true;
      messages.add(AiMsg('assistant', e is ApiException ? e.message : '$e', error: true));
    }
    notifyListeners();
  }

  Future<void> _refreshTexts() async {
    final lang = L.code;
    try {
      final d = await _api!.aiState();
      chips = ((d['chips'] as List?) ?? const []).map((e) => '$e').toList();
      final lim = d['limit'];
      if (lim is Map && lim['line'] != null) limitLine = '${lim['line']}';
      _loadedLang = lang;
      notifyListeners();
    } catch (_) {}
  }

  /// Yangi (bo'sh) suhbat — eskisi tarixda qoladi
  void newChat() {
    stopSpeaking();
    conv = _newId();
    messages.clear();
    notifyListeners();
  }

  Future<void> loadHistory() async {
    historyLoading = true;
    notifyListeners();
    try {
      history = await _api!.aiChats();
    } catch (_) {}
    historyLoading = false;
    notifyListeners();
  }

  /// Tarixdan suhbatni ochish
  Future<bool> openChat(String id) async {
    stopSpeaking();
    try {
      final d = await _api!.aiState(conv: id);
      conv = id;
      messages
        ..clear()
        ..addAll(((d['messages'] as List?) ?? const []).whereType<Map>().where((m) => '${m['content']}'.trim().isNotEmpty || m['status'] == 'streaming').map(AiMsg.fromServer));
      notifyListeners();
      _resumePending();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteChat(String id) async {
    try {
      await _api!.aiClear(id);
    } catch (_) {}
    history = history.where((h) => '${h['id']}' != id).toList();
    if (id == conv) {
      newChat();
    } else {
      notifyListeners();
    }
  }

  /// Matn (yozilgan yoki ovozdan o'girilgan) — avval buyruq, bo'lmasa AI
  Future<void> submit(String text, {void Function()? closeSheet}) async {
    final q = text.trim();
    if (q.isEmpty || busy) return;
    stopSpeaking();
    messages.add(AiMsg('user', q));
    final cmd = parseCommand(q);
    if (cmd != null) {
      await _runCommand(cmd, closeSheet);
      return;
    }
    await _ask(q);
  }

  Future<void> _runCommand(VoiceCmd cmd, void Function()? closeSheet) async {
    final me = session.me;
    switch (cmd.kind) {
      case VoiceKind.open:
        final ok = AppNav.open?.call(cmd.label!) ?? false;
        if (ok) {
          messages.add(AiMsg('assistant', '«${tr(cmd.label!)}» ${tr('ochildi')}'));
          notifyListeners();
          closeSheet?.call();
        } else {
          messages.add(AiMsg('assistant', tr("Bu bo'lim sizda yo'q")));
          notifyListeners();
        }
      case VoiceKind.shiftStart:
      case VoiceKind.shiftEnd:
        if (me == null || !me.can('shift:write')) {
          messages.add(AiMsg('assistant', tr("«Ishga keldim / Ketdim» tugmasi sizning rolingizda yo'q. Davomat bo'limidan belgilang.")));
        } else {
          messages.add(AiMsg('assistant', cmd.kind == VoiceKind.shiftStart ? tr('Ishga keldim deb belgilansinmi? Joylashuvingiz ham yoziladi.') : tr('Ketdim deb belgilansinmi?'), confirm: cmd));
        }
        notifyListeners();
    }
  }

  void answerConfirm(AiMsg m, bool yes, {void Function()? closeSheet}) {
    final cmd = m.confirm;
    m.confirm = null;
    if (cmd == null) return;
    if (!yes) {
      messages.add(AiMsg('assistant', tr('Bekor qilindi')));
      notifyListeners();
      return;
    }
    AppNav.open?.call('Bosh');
    AppNav.shift.value = cmd.kind == VoiceKind.shiftStart ? 'start' : 'end';
    messages.add(AiMsg('assistant', tr('Bajarilmoqda — Bosh ekranda natijani ko\'rasiz')));
    notifyListeners();
    closeSheet?.call();
  }

  Future<void> _ask(String q) async {
    busy = true;
    final pending = AiMsg('assistant', '', pending: true);
    messages.add(pending);
    notifyListeners();
    try {
      final a = await _api!.aiSend(q, conv);
      pending.id = a.id;
      if (a.line != null) limitLine = a.line;
      if (a.text != null) {
        _finish(pending, a.text!, ask: a.confirm);
      } else if (a.id != null) {
        // javob serverda yozilyapti — oyna yopilsa ham kutamiz va tayyor bo'lgach xabar beramiz
        await _waitFor(pending);
      }
    } on ApiException catch (e) {
      pending
        ..pending = false
        ..error = true
        ..text = e.isNetwork ? tr("Internet yo'q — AI yordamchi internet bilan ishlaydi.") : e.message;
    } catch (e) {
      pending
        ..pending = false
        ..error = true
        ..text = '$e';
    }
    busy = false;
    notifyListeners();
  }

  /// Javob tayyor: matn, tasdiq tugmalari, ovoz bilan o'qish; oyna yopiq bo'lsa — ilovada xabar
  void _finish(AiMsg m, String text, {bool ask = false, bool error = false}) {
    m
      ..pending = false
      ..text = text
      ..ask = ask
      ..error = error;
    if (!error && speak) unawaited(_say(text));
    if (!sheetOpen && text.trim().isNotEmpty) onBackgroundReply?.call(text);
  }

  /// Serverda yozilayotgan javobni kutish (har 1,2 soniyada so'raladi; internet uzilsa — qayta urinadi, 4 daqiqagacha)
  Future<void> _waitFor(AiMsg m) async {
    final id = m.id;
    if (id == null) return;
    var fails = 0;
    final until = DateTime.now().add(const Duration(minutes: 4));
    while (DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (!messages.contains(m)) return; // suhbat almashtirildi
      try {
        final d = await _api!.aiMsg(id);
        fails = 0;
        final st = '${d['status']}';
        if (st == 'streaming') continue;
        if (d['limit_line'] != null) limitLine = '${d['limit_line']}';
        _finish(m, st == 'error' ? '${d['error'] ?? d['text'] ?? ''}' : '${d['text'] ?? ''}', ask: d['confirm'] == true, error: st == 'error');
        notifyListeners();
        return;
      } catch (_) {
        if (++fails > 60) break;
      }
    }
    _finish(m, tr("Javob kechikdi — suhbatni qayta oching, javob tayyor bo'lsa ko'rinadi."), error: true);
    notifyListeners();
  }

  /// Ochilgan suhbatda hali yozilayotgan javob bo'lsa — kutishni davom ettirish
  void _resumePending() {
    for (final m in messages.where((x) => x.pending && x.id != null).toList()) {
      busy = true;
      unawaited(_waitFor(m).whenComplete(() {
        busy = messages.any((x) => x.pending);
        notifyListeners();
      }));
    }
  }

  /// «Tasdiqlash» / «Bekor qilish» — SI taklif qilgan pulga oid amal
  Future<void> answerAsk(AiMsg m, bool yes) async {
    final id = m.id;
    if (id == null || !m.ask) return;
    m.ask = false;
    notifyListeners();
    try {
      final t = await _api!.aiAction(id, yes);
      m.text = t;
      HapticFeedback.mediumImpact();
      if (speak) unawaited(_say(t));
    } on ApiException catch (e) {
      messages.add(AiMsg('assistant', e.isNetwork ? tr("Internet yo'q") : e.message, error: true));
    }
    notifyListeners();
  }

  /// «Matnga o'girilmoqda» paytida «Bekor»: kutishni to'xtatamiz (server javobi kelsa ham e'tiborsiz)
  void cancelTranscribing() {
    if (!transcribing) return;
    _listenGen++;
    transcribing = false;
    notifyListeners();
  }

  /* ---------------- ovoz ---------------- */

  Future<String?> startRecording() async {
    if (recording || transcribing) return null;
    stopSpeaking();
    try {
      if (!await _rec.hasPermission()) return tr('Mikrofonga ruxsat berilmadi. Telefon sozlamalarida ruxsat bering.');
      final dir = await getTemporaryDirectory();
      _recPath = '${dir.path}/ai_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _rec.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: _recPath!);
      recording = true;
      recSeconds = 0;
      HapticFeedback.mediumImpact();
      await _ampSub?.cancel();
      _peak = 0;
      _ampN = 0;
      _ampSub = _rec.onAmplitudeChanged(const Duration(milliseconds: 90)).listen((a) {
        // dBFS (-60…0) → 0…1
        final v = ((a.current + 50) / 46).clamp(0.0, 1.0).toDouble();
        level.value = v;
        _ampN++;
        if (v > _peak) _peak = v;
      });
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        recSeconds++;
        notifyListeners();
        if (recSeconds >= 45) {
          unawaited(stopAndTranscribe().then((t) {
            if (t != null) autoText.value = t;
          }));
        }
      });
      notifyListeners();
      return null;
    } catch (e) {
      recording = false;
      notifyListeners();
      return tr('Mikrofonni ishga tushirib bo\'lmadi');
    }
  }

  Future<void> cancelRecording() async {
    _recTimer?.cancel();
    unawaited(_ampSub?.cancel());
    level.value = 0;
    if (!recording) return;
    recording = false;
    try {
      await _rec.stop();
    } catch (_) {}
    final p = _recPath;
    if (p != null) {
      try {
        await File(p).delete();
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Yozishni to'xtatib, matnga o'giradi va matnni qaytaradi (yubormaydi: matn yozish maydoniga tushadi,
  /// foydalanuvchi tekshirib, «Yuborish» ni bosadi). Xato bo'lsa — xabar chiqadi va null.
  Future<String?> stopAndTranscribe() async {
    String? out;
    await stopAndSend(onText: (t) => out = t);
    return out;
  }

  /// Yozishni to'xtatib, serverga yuboradi (nutq → matn), keyin [submit] (yoki [onText] — matnni qaytarish)
  Future<void> stopAndSend({void Function()? closeSheet, void Function(String text)? onText}) async {
    _recTimer?.cancel();
    unawaited(_ampSub?.cancel());
    level.value = 0;
    if (!recording) return;
    recording = false;
    transcribing = true;
    notifyListeners();
    final gen = ++_listenGen;
    String? path;
    try {
      // ba'zi telefonlarda yozuvni to'xtatish osilib qolishi mumkin — 5 soniyadan keyin saqlangan fayl bilan davom etamiz
      path = await _rec.stop().timeout(const Duration(seconds: 5));
    } catch (_) {}
    path ??= _recPath;
    String? text;
    String? err;
    try {
      if (path == null || !File(path).existsSync() || File(path).lengthSync() < 3000) {
        err = tr('Ovoz juda qisqa. Mikrofonni bosib turib gapiring.');
      } else if (_ampN >= 8 && _peak < 0.12) {
        err = tr("Ovoz eshitilmadi. Mikrofonga yaqinroq gapiring.");
      } else {
        text = await _api!.aiListen(path);
      }
    } on ApiException catch (e) {
      err = e.isNetwork ? tr("Internet yo'q yoki ovoz serveri javob bermadi — yana bir bor ayting.") : e.message;
    } catch (e) {
      err = '$e';
    }
    if (gen != _listenGen) return; // foydalanuvchi «Bekor» bosgan
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    transcribing = false;
    if (err != null || text == null) {
      messages.add(AiMsg('assistant', err ?? tr('Nutq tanilmadi'), error: true));
      notifyListeners();
      return;
    }
    notifyListeners();
    if (onText != null) {
      onText(text);
      return;
    }
    await submit(text, closeSheet: closeSheet);
  }

  Future<void> _say(String text) async {
    final clean = text.replaceAll(RegExp(r'[*_#`>]+'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.isEmpty) return;
    try {
      final lang = switch (L.code) { 'ru' => 'ru-RU', 'tg' => 'tg-TJ', _ => 'uz-UZ' };
      var ok = (await _tts.isLanguageAvailable(lang)) == true;
      if (!ok && L.code != 'ru') ok = false;
      await _tts.setLanguage(ok ? lang : 'ru-RU');
      await _tts.setSpeechRate(0.48);
      await _tts.speak(clean.length > 900 ? clean.substring(0, 900) : clean);
    } catch (_) {}
  }

  void toggleSpeak() {
    speak = !speak;
    if (!speak) stopSpeaking();
    notifyListeners();
  }

  void stopSpeaking() {
    try {
      _tts.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    _recTimer?.cancel();
    unawaited(_ampSub?.cancel());
    level.dispose();
    autoText.dispose();
    _rec.dispose();
    stopSpeaking();
    super.dispose();
  }
}

/// Ochiq oyna (varaq, dialog) bor-yo'qligini kuzatadi: oyna ochiqligida suzuvchi AI tugmasi yashirinadi.
class ModalWatcher extends NavigatorObserver {
  static final ValueNotifier<int> open = ValueNotifier(0);

  void _bump(int d) => WidgetsBinding.instance.addPostFrameCallback((_) => open.value = (open.value + d).clamp(0, 99));

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _bump(1);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _bump(-1);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PopupRoute) _bump(-1);
  }
}

/// Suzuvchi AI tugmasi: barmoq bilan istalgan joyga olib o'tiladi (chetga yopishadi, joyi eslab qolinadi);
/// bosilsa chat ochiladi, uzoq bosilsa — darhol tinglaydi.
class AiBubble extends StatefulWidget {
  const AiBubble({super.key, required this.controller, required this.navigatorKey});

  /// Ekran aylantirilmoqda — tugma chetga «yashirinadi» (kontentni yopmasin), to'xtagach qaytadi
  static final ValueNotifier<bool> scrolling = ValueNotifier(false);
  static Timer? _scrollTimer;

  static void onScroll(ScrollUpdateNotification n) {
    if (n.metrics.axis != Axis.vertical || (n.scrollDelta ?? 0).abs() < 1) return;
    if (!scrolling.value) scrolling.value = true;
    _scrollTimer?.cancel();
    _scrollTimer = Timer(const Duration(milliseconds: 1200), () => scrolling.value = false);
  }

  /// Pastdan xabar (SnackBar) chiqqanda tugma uni yopmasin: shu vaqtga chetga yashirinadi
  static void tuck(Duration d) {
    scrolling.value = true;
    _scrollTimer?.cancel();
    _scrollTimer = Timer(d, () => scrolling.value = false);
  }

  final AssistantController controller;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<AiBubble> createState() => _AiBubbleState();
}

class _AiBubbleState extends State<AiBubble> with SingleTickerProviderStateMixin {
  static const _size = 58.0;
  static const _gesture = MethodChannel('oftob/gesture');
  String _excluded = '';
  static const _tabW = 26.0, _tabH = 50.0; // chetdagi yorliq: kartochka chetidagi bo'sh joyga sig'adi (matn ~29dp dan boshlanadi)
  static const _store = FlutterSecureStorage();
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat(count: 2); // bir necha marta pulsatsiya qilib to'xtaydi: cheksiz animatsiya batareyani yeydi
  Offset? _pos; // yuqori-chap burchak (mantiqiy piksel)
  Offset _frac = const Offset(0, -1); // saqlangan joy: x: 0 chap / 1 o'ng; y: ekran balandligiga ulushi (-1 — standart: navigatsiya ustida)
  bool _dragging = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _loadPos();
    widget.controller.openRequest.addListener(_openReq);
  }

  void _openReq() => _show();

  Future<void> _loadPos() async {
    try {
      final v = await _store.read(key: 'ai_bubble');
      if (v != null) {
        final p = v.split(',');
        final x = double.tryParse(p[0]), y = double.tryParse(p[1]);
        if (x != null && y != null && mounted) setState(() => _frac = Offset(x, y));
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_excluded.isNotEmpty) _gesture.invokeMethod('exclude', null).catchError((_) => null);
    _pulse.dispose();
    widget.controller.openRequest.removeListener(_openReq);
    super.dispose();
  }

  Offset _clamp(Offset o, Size size, EdgeInsets pad) => Offset(o.dx.clamp(4.0, size.width - _size - 4), o.dy.clamp(pad.top + 4, size.height - pad.bottom - _size - 4));

  Offset _resolve(Size size, EdgeInsets pad) {
    if (_pos != null) return _clamp(_pos!, size, pad);
    final x = _frac.dx >= 0.5 ? size.width - _size - 4 : 4.0;
    final y = _frac.dy < 0 ? size.height - pad.bottom - 190 : _frac.dy * size.height;
    return _clamp(Offset(x, y), size, pad);
  }

  Future<void> _show({bool listen = false}) async {
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null || _opening) return;
    _opening = true;
    HapticFeedback.selectionClick();
    final c = widget.controller;
    unawaited(c.load());
    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (_) => AssistantSheet(controller: c, autoListen: listen),
    );
    _opening = false;
  }

  void _dragEnd(Size size, EdgeInsets pad) {
    final cur = _resolve(size, pad);
    final snapRight = cur.dx + _size / 2 > size.width / 2;
    final end = _clamp(Offset(snapRight ? size.width - _size - 4 : 4, cur.dy), size, pad);
    setState(() {
      _dragging = false;
      _pos = end;
      _frac = Offset(snapRight ? 1 : 0, end.dy / size.height);
    });
    HapticFeedback.lightImpact();
    _store.write(key: 'ai_bubble', value: '${_frac.dx},${_frac.dy}').catchError((_) {});
  }

  /// Yorliq turgan joyda Android «orqaga» imosi o'chadi — yorliqni chetdan sudrasa ilova yopilib qolmaydi
  void _exclude(Rect? r, double dpr) {
    if (!Platform.isAndroid) return;
    final v = r == null ? '' : [r.left, r.top, r.right, r.bottom].map((x) => (x * dpr).round()).join(',');
    if (v == _excluded) return;
    _excluded = v;
    _gesture.invokeMethod('exclude', r == null ? null : v.split(',').map(int.parse).toList()).catchError((_) => null);
  }

  /// Ekran chetidagi yorliq: tashqi tomoni ekran chetiga yopishgan, ichki tomoni yumaloq
  Widget _tab(bool right) {
    const r = Radius.circular(_tabH / 2);
    return Container(
      width: _tabW,
      height: _tabH,
      decoration: BoxDecoration(
        borderRadius: right ? const BorderRadius.only(topLeft: r, bottomLeft: r) : const BorderRadius.only(topRight: r, bottomRight: r),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Brand.green, Brand.teal]),
        boxShadow: [BoxShadow(color: Brand.green.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      alignment: right ? const Alignment(0.2, 0) : const Alignment(-0.2, 0),
      child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<int>(
      valueListenable: ModalWatcher.open,
      builder: (context, modals, _) {
        if (modals > 0 || mq.viewInsets.bottom > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _exclude(null, mq.devicePixelRatio));
          return const SizedBox.shrink();
        }
        final o = _resolve(size, mq.padding);
        {
          final right = o.dx + _size / 2 > size.width / 2;
          final top = o.dy + (_size - _tabH) / 2 - 8;
          final ex = right ? Rect.fromLTWH(size.width - _tabW - 14, top, _tabW + 14, _tabH + 16) : Rect.fromLTWH(0, top, _tabW + 14, _tabH + 16);
          WidgetsBinding.instance.addPostFrameCallback((_) => _exclude(_dragging ? null : ex, mq.devicePixelRatio));
        }
        return ValueListenableBuilder<bool>(
          valueListenable: AiBubble.scrolling,
          builder: (context, scrolling, _) {
        // dam olishda — ekran chetidagi ixcham yorliq (kartochkalardagi matn va summalarni yopmaydi);
        // bosilsa yordamchi ochiladi, sudralsa — to'liq tugma bo'lib joyi o'zgartiriladi; aylantirish paytida xira
        final docked = !_dragging;
        final faded = scrolling && !_dragging;
        final right = o.dx + _size / 2 > size.width / 2;
        return AnimatedPositioned(
          duration: _dragging ? Duration.zero : const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          left: docked ? (right ? size.width - _tabW : 0) : o.dx,
          top: docked ? o.dy + (_size - _tabH) / 2 : o.dy,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 220),
            opacity: faded ? 0.55 : 1,
            child: GestureDetector(
            onTap: _show,
            onLongPress: () => _show(listen: true),
            onPanStart: (_) {
              HapticFeedback.selectionClick();
              setState(() {
                _dragging = true;
                _pos = o;
              });
            },
            onPanUpdate: (d) => setState(() => _pos = _clamp((_pos ?? o) + d.delta, size, mq.padding)),
            onPanEnd: (_) => _dragEnd(size, mq.padding),
            onPanCancel: () => _dragEnd(size, mq.padding),
            child: docked
                ? _tab(right)
                : AnimatedScale(
              scale: _dragging ? 1.14 : 1,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final t = _pulse.value;
                  return SizedBox(
                    width: _size,
                    height: _size,
                    child: Stack(alignment: Alignment.center, children: [
                      Container(width: 46 + 12 * t, height: 46 + 12 * t, decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary.withValues(alpha: 0.18 * (1 - t)))),
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Brand.green, Brand.teal]),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.6),
                          boxShadow: [BoxShadow(color: Brand.green.withValues(alpha: _dragging ? 0.5 : 0.35), blurRadius: _dragging ? 24 : 16, offset: const Offset(0, 6))],
                        ),
                        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
                      ),
                    ]),
                  );
                },
              ),
            ),
          ),
          ),
        );
          },
        );
      },
    );
  }
}

/// Chat oynasi: shisha varaq, yozishma, tayyor savollar, mikrofon va yuborish
class AssistantSheet extends StatefulWidget {
  const AssistantSheet({super.key, required this.controller, this.autoListen = false});

  final AssistantController controller;
  final bool autoListen;

  @override
  State<AssistantSheet> createState() => _AssistantSheetState();
}

class _AssistantSheetState extends State<AssistantSheet> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  String? _note;
  String? _hint;
  Timer? _hintTimer;
  bool _history = false;

  /* Telegram'dagidek ovoz yozish: bosib turib gapiradi; tepaga suradi — qulflanadi (barmoqni qo'yib yuborsa
     ham yozaveradi); chapga suradi — bekor; qo'yib yuboradi — matnga o'girilib, yozish maydoniga tushadi.
     Yuborish — faqat «Yuborish» tugmasi bilan. */
  static const _lockDist = 80.0;
  static const _cancelDist = 120.0;
  String? _mode; // shu bosishda nima qilinadi: 'rec' | 'send' | 'stop'
  bool _pressing = false;
  bool _locked = false;
  Offset _start = Offset.zero;
  double _dx = 0, _dy = 0;
  DateTime _downAt = DateTime.now();
  DateTime _recStart = DateTime.now();

  AssistantController get c => widget.controller;
  bool get _hasText => _text.text.trim().isNotEmpty;
  bool get _recUi => _pressing || (c.recording && _locked) || (c.recording && _mode == 'rec');

  @override
  void initState() {
    super.initState();
    c.sheetOpen = true;
    c.addListener(_changed);
    c.autoText.addListener(_autoText);
    _text.addListener(_textChanged);
    if (widget.autoListen) WidgetsBinding.instance.addPostFrameCallback((_) => _startLocked());
  }

  @override
  void dispose() {
    c.sheetOpen = false;
    c.removeListener(_changed);
    c.autoText.removeListener(_autoText);
    _hintTimer?.cancel();
    if (c.recording) unawaited(c.cancelRecording());
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _hadText = false;
  String? _scrollSig;
  void _textChanged() {
    if (_hasText != _hadText && mounted) setState(() => _hadText = _hasText);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // faqat yangi xabar kelganda pastga suramiz. Har soniyadagi yangilanishda (yozish taymeri) emas: iPhone'da
      // chegaradan oshirib surish ro'yxatni «prujina»dek sakratardi
      final last = c.messages.isEmpty ? null : c.messages.last;
      final sig = '${c.messages.length}|${last?.pending}|${last?.text.length}|${last?.ask}';
      if (sig == _scrollSig) return;
      _scrollSig = sig;
      if (_scroll.hasClients && _scroll.position.maxScrollExtent > _scroll.offset) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _close() {
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _send([String? v]) async {
    final t = (v ?? _text.text).trim();
    if (t.isEmpty) return;
    _text.clear();
    await c.submit(t, closeSheet: _close);
  }

  void _showHint(String t) {
    _hintTimer?.cancel();
    setState(() => _hint = t);
    _hintTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _hint = null);
    });
  }

  /// Tayyor matn yozish maydoniga qo'shiladi (yuborilmaydi)
  void _insert(String t) {
    final cur = _text.text.trimRight();
    final v = cur.isEmpty ? t.trim() : '$cur ${t.trim()}';
    _text.value = TextEditingValue(text: v, selection: TextSelection.collapsed(offset: v.length));
    setState(() {});
  }

  /// 45 soniyaga yetib yozish o'zi to'xtadi
  void _autoText() {
    final t = c.autoText.value;
    if (t == null || !mounted) return;
    c.autoText.value = null;
    _pressing = false;
    _locked = false;
    _dx = _dy = 0;
    _insert(t);
  }

  /// AI pufakchasini uzoq bosib ochilganda — darhol qulflangan holda yozadi
  Future<void> _startLocked() async {
    if (c.recording || c.transcribing) return;
    setState(() {
      _locked = true;
      _note = null;
      _recStart = DateTime.now();
    });
    final err = await c.startRecording();
    if (!mounted) return;
    if (err != null || !c.recording) {
      setState(() {
        _locked = false;
        _note = err;
      });
    }
  }

  void _down(PointerDownEvent e) {
    _mode = null;
    if (c.transcribing) return;
    if (c.recording && _locked) {
      _mode = 'stop';
      return;
    }
    if (c.recording) return;
    if (_hasText) {
      _mode = 'send';
      return;
    }
    _mode = 'rec';
    _hintTimer?.cancel();
    setState(() {
      _pressing = true;
      _locked = false;
      _dx = _dy = 0;
      _start = e.position;
      _downAt = DateTime.now();
      _recStart = _downAt;
      _note = null;
      _hint = null;
    });
    HapticFeedback.lightImpact();
    c.startRecording().then((err) {
      if (!mounted) return;
      if (err != null) {
        setState(() {
          _pressing = false;
          _locked = false;
          _note = err;
        });
        return;
      }
      // barmoq yozish boshlanmasdan qo'yib yuborilgan (yoki ruxsat oynasi chiqib, bosish uzilgan)
      if (!_pressing && !_locked && c.recording) unawaited(c.cancelRecording());
    });
  }

  void _move(PointerMoveEvent e) {
    if (_mode != 'rec' || !_pressing || _locked) return;
    // yozish hali boshlanmagan (masalan, mikrofon ruxsati so'ralmoqda) — qulflash/bekor qilish yo'q
    if (!c.recording) return;
    final d = e.position - _start;
    final dx = d.dx.clamp(-_cancelDist - 20, 0.0).toDouble();
    final dy = d.dy.clamp(-_lockDist - 20, 0.0).toDouble();
    if (dy < -_lockDist) {
      HapticFeedback.mediumImpact();
      setState(() {
        _locked = true;
        _dx = _dy = 0;
      });
      return;
    }
    if (dx < -_cancelDist) {
      _cancel();
      return;
    }
    // bir vaqtda faqat bitta yo'nalish: qaysi tomonga ko'proq surilsa
    setState(() {
      if (-dx > -dy) {
        _dx = dx;
        _dy = 0;
      } else {
        _dy = dy;
        _dx = 0;
      }
    });
  }

  void _up(PointerEvent e, {bool cancelled = false}) {
    final m = _mode;
    _mode = null;
    switch (m) {
      case 'send':
        if (!cancelled && !c.busy) _send();
      case 'stop':
        if (!cancelled) _finish();
      case 'rec':
        if (_locked) {
          setState(() => _pressing = false); // qulflangan — barmoqsiz yozaveradi
          return;
        }
        if (!_pressing) return; // bekor qilingan yoki 45 soniyada o'zi to'xtagan
        final held = DateTime.now().difference(_downAt);
        if (cancelled || !c.recording || held < const Duration(milliseconds: 450)) {
          setState(() {
            _pressing = false;
            _dx = _dy = 0;
          });
          unawaited(c.cancelRecording());
          if (!cancelled) _showHint(tr('Yozish uchun bosib turing'));
          return;
        }
        _finish();
    }
  }

  void _cancel() {
    HapticFeedback.heavyImpact();
    setState(() {
      _pressing = false;
      _locked = false;
      _dx = _dy = 0;
    });
    unawaited(c.cancelRecording());
  }

  /// Yozishni tugatadi: ovoz matnga o'giriladi va maydonga tushadi
  Future<void> _finish() async {
    HapticFeedback.selectionClick();
    setState(() {
      _pressing = false;
      _locked = false;
      _dx = _dy = 0;
    });
    final t = await c.stopAndTranscribe();
    if (!mounted || t == null) return;
    _insert(t);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    final h = (mq.size.height * 0.84) - 0;
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SizedBox(
        height: h.clamp(320.0, mq.size.height - mq.viewInsets.bottom - mq.padding.top - 12),
        child: Glass(
          radius: 30,
          blur: true,
          tint: Theme.of(context).brightness == Brightness.dark ? const Color(0xB3101A15) : const Color(0xCCF4F9F6),
          child: Column(children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.outline.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(3))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              child: Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Brand.green, Brand.teal])),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(_history ? 'Suhbatlar tarixi' : 'AI yordamchi', maxLines: 1, softWrap: false, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  ),
                ),
                if (_history)
                  TextButton.icon(onPressed: () => setState(() => _history = false), icon: const Icon(Icons.arrow_back_rounded, size: 18), label: const Text('Suhbatga'))
                else ...[
                  IconButton(
                    tooltip: tr('Javobni ovozda aytish'),
                    onPressed: c.toggleSpeak,
                    icon: Icon(c.speak ? Icons.volume_up_rounded : Icons.volume_off_rounded, color: c.speak ? cs.primary : cs.outline),
                  ),
                  IconButton(
                    tooltip: tr('Tarix'),
                    onPressed: () {
                      setState(() => _history = true);
                      c.loadHistory();
                    },
                    icon: Icon(Icons.history_rounded, color: cs.onSurface),
                  ),
                  IconButton(
                    tooltip: tr('Yangi chat'),
                    onPressed: c.messages.isEmpty ? null : c.newChat,
                    icon: Icon(Icons.add_comment_outlined, color: c.messages.isEmpty ? cs.outline : cs.primary),
                  ),
                ],
                IconButton(onPressed: _close, icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Expanded(
              child: _history
                  ? _historyView(cs)
                  : !c.loaded
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
                      children: [
                        if (c.messages.isEmpty) _intro(cs),
                        for (final m in c.messages) _bubble(m, cs),
                      ],
                    ),
            ),
            if (!_history && _note != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 6), child: Text(_note!, style: TextStyle(color: cs.error, fontSize: 12.5))),
            if (!_history && _hint != null)
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 6), child: Align(alignment: Alignment.centerRight, child: _hintPill(_hint!, cs))),
            if (!_history && c.limitLine != null)
              Padding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 2), child: Align(alignment: Alignment.centerLeft, child: w.Text(c.limitLine!, style: TextStyle(color: cs.outline, fontSize: 11.5)))),
            if (!_history)
            Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 12 + (mq.viewInsets.bottom > 0 ? 0 : mq.padding.bottom)),
              child: _inputRow(cs),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _historyView(ColorScheme cs) {
    if (c.historyLoading && c.history.isEmpty) return const Center(child: CircularProgressIndicator());
    if (c.history.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(tr("Hozircha suhbat yo'q. Birinchi savolingizni bering."), textAlign: TextAlign.center, style: TextStyle(color: cs.outline))));
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(14, 6, 14, 16 + MediaQuery.paddingOf(context).bottom),
      children: [
        for (final h in c.history)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Glass(
              radius: 18,
              blur: false,
              shadow: false,
              tint: '${h['id']}' == c.conv ? cs.primary.withValues(alpha: 0.12) : null,
              onTap: () async {
                final ok = await c.openChat('${h['id']}');
                if (ok && mounted) setState(() => _history = false);
              },
              padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
              child: Row(children: [
                const IconTile(icon: Icons.chat_bubble_outline_rounded, color: Brand.teal, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    w.Text('${h['title']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    w.Text('${h['count']} ${tr('xabar')} · ${formatDate('${h['at']}')}', style: TextStyle(color: cs.outline, fontSize: 12)),
                  ]),
                ),
                IconButton(tooltip: tr("O'chirish"), onPressed: () => c.deleteChat('${h['id']}'), icon: Icon(Icons.delete_outline_rounded, color: cs.outline)),
              ]),
            ),
          ),
      ],
    );
  }

  Widget _inputRow(ColorScheme cs) {
    final rec = _recUi;
    Widget field;
    if (rec) {
      field = _recBar(cs);
    } else if (c.transcribing) {
      field = Glass(
        key: const ValueKey('tr'),
        radius: 24,
        shadow: false,
        padding: const EdgeInsets.only(left: 16, right: 4),
        child: SizedBox(
          height: 46,
          child: Row(children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2)),
            const SizedBox(width: 10),
            Expanded(child: w.Text(tr("Matnga o'girilmoqda…"), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
            TextButton(onPressed: c.cancelTranscribing, child: const Text('Bekor')),
          ]),
        ),
      );
    } else {
      field = Glass(
        key: const ValueKey('field'),
        radius: 24,
        shadow: false,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: TextField(
          controller: _text,
          minLines: 1,
          maxLines: 4,
          textInputAction: TextInputAction.send,
          onSubmitted: _send,
          decoration: InputDecoration(hintText: tr('Savol yoki buyruq yozing…'), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 13)),
        ),
      );
    }
    final lockP = (-_dy / _lockDist).clamp(0.0, 1.0);
    return Stack(clipBehavior: Clip.none, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (ch, a) => FadeTransition(opacity: a, child: SizeTransition(sizeFactor: a, axis: Axis.horizontal, alignment: Alignment.centerRight, child: ch)),
            child: field,
          ),
        ),
        const SizedBox(width: 8),
        const SizedBox(width: 46, height: 46),
      ]),
      // qulf: tepaga surilsa — qo'l qo'yib yuborilsa ham yozaveradi
      Positioned(
        key: const ValueKey('lock'),
        right: 3,
        bottom: 66,
        child: IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: rec && _pressing && !_locked ? 1 : 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              offset: rec && _pressing && !_locked ? Offset.zero : const Offset(0, 0.5),
              child: Transform.translate(offset: Offset(0, _dy * 0.45), child: _LockPill(progress: lockP)),
            ),
          ),
        ),
      ),
      Positioned(key: const ValueKey('mic'), right: 0, bottom: 0, child: _micButton(cs)),
    ]);
  }

  Widget _micButton(ColorScheme cs) {
    final rec = _recUi;
    final showSend = !rec && !c.transcribing && _hasText;
    final IconData icon = showSend
        ? Icons.send_rounded
        : rec && _locked
            ? Icons.arrow_upward_rounded
            : Icons.mic_rounded;
    final disabled = c.transcribing || (showSend && c.busy);
    final color = rec ? Brand.green : (disabled ? Brand.green.withValues(alpha: 0.4) : Brand.green);
    // tugma barmoq ketidan yuradi (Telegram'dagidek); qulflanganda joyida turadi
    final off = rec && !_locked ? Offset(_dx * 0.85, _dy * 0.85) : Offset.zero;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: (e) => _up(e, cancelled: true),
      // pastki oyna surilib ketmasin (barmoq tugma ustida suriladi)
      child: GestureDetector(
        onVerticalDragUpdate: (_) {},
        onHorizontalDragUpdate: (_) {},
        child: Semantics(
          button: true,
          label: showSend ? tr('Yuborish') : tr('Ovoz yozish'),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Transform.translate(
              offset: off,
              child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                // ovoz balandligiga qarab «nafas oladigan» halqa
                if (rec)
                  ValueListenableBuilder<double>(
                    valueListenable: c.level,
                    builder: (_, lv, _) => AnimatedScale(
                      duration: const Duration(milliseconds: 140),
                      scale: 1.65 + lv * 0.9,
                      child: Container(width: 46, height: 46, decoration: BoxDecoration(shape: BoxShape.circle, color: Brand.green.withValues(alpha: 0.18))),
                    ),
                  ),
                AnimatedScale(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  scale: rec ? 1.55 : 1,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: disabled ? null : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF5B9BFF), Color(0xFF1D4ED8)]),
                      color: disabled ? color : null,
                      boxShadow: [BoxShadow(color: Brand.green.withValues(alpha: rec ? 0.45 : 0.3), blurRadius: rec ? 18 : 12, offset: const Offset(0, 4))],
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      transitionBuilder: (ch, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: ch)),
                      child: Icon(icon, key: ValueKey(icon), color: Colors.white, size: rec ? 20 : 22),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _recBar(ColorScheme cs) {
    final cancelP = (-_dx / _cancelDist).clamp(0.0, 1.0);
    return Glass(
      key: const ValueKey('rec'),
      radius: 24,
      shadow: false,
      padding: const EdgeInsets.only(left: 16, right: 4),
      child: SizedBox(
        height: 46,
        child: Row(children: [
          const _RecDot(),
          const SizedBox(width: 9),
          _RecClock(start: _recStart),
          const SizedBox(width: 10),
          if (_locked) ...[
            Expanded(child: _Wave(level: c.level, color: cs.primary)),
            TextButton(
              onPressed: _cancel,
              child: w.Text(tr('Bekor qilish'), style: TextStyle(color: Colors.red.shade600, fontWeight: FontWeight.w800)),
            ),
          ] else ...[
            Expanded(
              child: ClipRect(
                child: Transform.translate(
                  offset: Offset(_dx * 0.55, 0),
                  child: Opacity(
                    opacity: 1 - cancelP * 0.9,
                    child: Align(alignment: Alignment.centerRight, child: _Shimmer(text: '‹  ${tr('Bekor qilish uchun suring')}')),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 30),
          ],
        ]),
      ),
    );
  }

  Widget _hintPill(String t, ColorScheme cs) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: context.isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A), borderRadius: BorderRadius.circular(12)),
        child: w.Text(t, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
      );

  Widget _intro(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Glass(
          radius: 20,
          shadow: false,
          padding: const EdgeInsets.all(14),
          child: Text(
            tr("Salom! Men savollarga javob beraman va ishni o'zim bajaraman — yozing yoki mikrofonni bosib ayting. Masalan: «Bobur ishga keldi, telefoni yo'q, belgilab qo'y», «Ertaga betonni tekshirish vazifasini qo'y», «Bugun kim ishda?», «Kassani och». Pulga oid ishlarni tasdiqlaganingizdan keyin bajaraman."),
            style: const TextStyle(fontSize: 14, height: 1.35),
          ),
        ),
        if (!c.voiceReady) Padding(padding: const EdgeInsets.only(top: 8), child: Text(tr("Ovoz uchun administrator platformada Gemini/ChatGPT kalitini ulashi kerak."), style: TextStyle(color: cs.outline, fontSize: 12.5))),
        if (c.chips.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final q in c.chips) ActionChip(label: w.Text(q, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)), onPressed: () => _send(q)),
          ]),
        ],
      ]),
    );
  }

  Widget _bubble(AiMsg m, ColorScheme cs) {
    final me = m.role == 'user';
    final child = m.pending
        ? const _TypingDots()
        : Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            SelectableText(m.error ? tr(m.text) : m.text, style: TextStyle(fontSize: 14.5, height: 1.35, color: m.error ? cs.error : (me ? Colors.white : cs.onSurface))),
            if (m.ask && m.id != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(spacing: 8, runSpacing: 6, children: [
                  FilledButton.icon(
                    onPressed: () => c.answerAsk(m, true),
                    style: FilledButton.styleFrom(minimumSize: const Size(70, 38)),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Tasdiqlash'),
                  ),
                  OutlinedButton(onPressed: () => c.answerAsk(m, false), style: OutlinedButton.styleFrom(minimumSize: const Size(70, 38)), child: const Text('Bekor qilish')),
                ]),
              ),
            if (m.confirm != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  FilledButton(onPressed: () => c.answerConfirm(m, true, closeSheet: _close), style: FilledButton.styleFrom(minimumSize: const Size(70, 38)), child: const Text('Ha')),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () => c.answerConfirm(m, false), style: OutlinedButton.styleFrom(minimumSize: const Size(70, 38)), child: const Text("Yo'q")),
                ]),
              ),
          ]);
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(topLeft: const Radius.circular(20), topRight: const Radius.circular(20), bottomLeft: Radius.circular(me ? 20 : 5), bottomRight: Radius.circular(me ? 5 : 20)),
          gradient: me ? const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)]) : null,
          color: me ? null : context.pill.withValues(alpha: context.isDark ? 0.12 : 0.72),
          border: me ? null : Border.all(color: context.pillBorder),
        ),
        child: child,
      ),
    );
  }
}

class _RecDot extends StatefulWidget {
  const _RecDot();

  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(opacity: Tween(begin: 0.3, end: 1.0).animate(_c), child: Container(width: 14, height: 14, decoration: BoxDecoration(color: Colors.red.shade600, shape: BoxShape.circle)));
}

/// Yozish vaqti: 0:07,3 (Telegram'dagidek o'ndan bir soniya bilan)
class _RecClock extends StatefulWidget {
  const _RecClock({required this.start});
  final DateTime start;

  @override
  State<_RecClock> createState() => _RecClockState();
}

class _RecClockState extends State<_RecClock> {
  late final Timer _t = Timer.periodic(const Duration(milliseconds: 100), (_) {
    if (mounted) setState(() {});
  });

  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ms = DateTime.now().difference(widget.start).inMilliseconds.clamp(0, 3600000);
    final sec = ms ~/ 1000;
    return w.Text('${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')},${(ms % 1000) ~/ 100}',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, fontFeatures: [FontFeature.tabularFigures()]));
  }
}

/// Qulf: tepaga surilgan sari yopiladi; ostida «tepaga» o'qi sakraydi
class _LockPill extends StatefulWidget {
  const _LockPill({required this.progress});
  final double progress;

  @override
  State<_LockPill> createState() => _LockPillState();
}

class _LockPillState extends State<_LockPill> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    final p = widget.progress;
    return Container(
      width: 40,
      height: 82 - 22 * p,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dark ? Colors.white12 : const Color(0x1A0F172A)),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(p > 0.75 ? Icons.lock_rounded : Icons.lock_open_rounded, size: 20, color: p > 0.75 ? Brand.green : (dark ? Colors.white70 : const Color(0xFF475569))),
        if (p < 0.6)
          AnimatedBuilder(
            animation: _c,
            builder: (_, _) => Transform.translate(
              offset: Offset(0, 3 - 6 * _c.value),
              child: Icon(Icons.keyboard_arrow_up_rounded, size: 20, color: (dark ? Colors.white : const Color(0xFF475569)).withValues(alpha: 0.7 * (1 - p))),
            ),
          ),
      ]),
    );
  }
}

/// Qulflangan yozishda — jonli ovoz to'lqini
class _Wave extends StatefulWidget {
  const _Wave({required this.level, required this.color});
  final ValueNotifier<double> level;
  final Color color;

  @override
  State<_Wave> createState() => _WaveState();
}

class _WaveState extends State<_Wave> {
  final List<double> _v = List.filled(40, 0.0, growable: true);

  @override
  void initState() {
    super.initState();
    widget.level.addListener(_tick);
  }

  @override
  void dispose() {
    widget.level.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    setState(() {
      _v.add(widget.level.value);
      if (_v.length > 40) _v.removeAt(0);
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(height: 26, child: CustomPaint(painter: _WavePainter(List.of(_v), widget.color)));
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.v, this.color);
  final List<double> v;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const step = 5.0;
    final n = (size.width / step).floor();
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final idx = v.length - n + i;
      final lv = idx >= 0 && idx < v.length ? v[idx] : 0.0;
      final h = 3 + (size.height - 4) * lv;
      final x = i * step + 2;
      canvas.drawLine(Offset(x, size.height / 2 - h / 2), Offset(x, size.height / 2 + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}

/// «‹ Bekor qilish uchun chapga suring» — yaltirab turadigan matn
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.text});
  final String text;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final x = 1.3 - _c.value * 1.6; // o'ngdan chapga yuradi
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => LinearGradient(
            colors: [cs.outline, cs.onSurface, cs.outline],
            stops: [(x - 0.2).clamp(0.0, 1.0), x.clamp(0.0, 1.0), (x + 0.2).clamp(0.0, 1.0)],
          ).createShader(r),
          child: w.Text(widget.text, maxLines: 1, overflow: TextOverflow.fade, softWrap: false, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.white)),
        );
      },
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary.withValues(alpha: 0.3 + 0.7 * ((((_c.value * 3) - i) % 3) < 1 ? 1 - (((_c.value * 3) - i) % 3) : 0.0))),
          ),
      ]),
    );
  }
}
