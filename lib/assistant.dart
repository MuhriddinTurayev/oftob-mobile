import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as w show Text;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'api.dart';
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
    const startK = ['ishga keldim', 'ishga keldi', 'ишга келдим', 'я пришел', 'пришел на работу', 'я на работе', 'ба кор омадам', 'кор омадам'];
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
  AiMsg(this.role, this.text, {this.pending = false, this.error = false, this.confirm});
  final String role; // user | assistant
  String text;
  bool pending;
  bool error;
  VoiceCmd? confirm; // «Ha / Yo'q» kutilmoqda
}

/// AI yordamchi holati: yozishma, ovoz yozish, gapirib berish. Bitta nusxa — yozishma panel yopilsa ham saqlanadi.
class AssistantController extends ChangeNotifier {
  AssistantController(this.session);

  final Session session;
  final List<AiMsg> messages = [];
  List<String> chips = const [];
  bool loaded = false;
  bool busy = false;
  bool voiceReady = true;
  bool aiReady = true;
  bool recording = false;
  bool transcribing = false;
  bool speak = false;
  int recSeconds = 0;

  final AudioRecorder _rec = AudioRecorder();
  final FlutterTts _tts = FlutterTts();
  Timer? _recTimer;
  String? _recPath;

  ApiClient? get _api => session.api;

  Future<void> load() async {
    if (loaded) return;
    try {
      final d = await _api!.aiState();
      messages
        ..clear()
        ..addAll(((d['messages'] as List?) ?? const []).whereType<Map>().where((m) => '${m['content']}'.trim().isNotEmpty).map((m) => AiMsg('${m['role']}', '${m['content']}', error: m['status'] == 'error')));
      chips = ((d['chips'] as List?) ?? const []).map((e) => '$e').toList();
      voiceReady = d['voice'] != false;
      aiReady = d['ai'] != false;
      loaded = true;
    } catch (e) {
      loaded = true;
      messages.add(AiMsg('assistant', e is ApiException ? e.message : '$e', error: true));
    }
    notifyListeners();
  }

  Future<void> clear() async {
    stopSpeaking();
    try {
      await _api!.aiClear();
    } catch (_) {}
    messages.clear();
    notifyListeners();
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
      final a = await _api!.aiSend(q);
      pending
        ..pending = false
        ..text = a;
      if (speak) unawaited(_say(a));
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

  /* ---------------- ovoz ---------------- */

  Future<String?> startRecording() async {
    if (recording || busy || transcribing) return null;
    stopSpeaking();
    try {
      if (!await _rec.hasPermission()) return tr('Mikrofonga ruxsat berilmadi. Telefon sozlamalarida ruxsat bering.');
      final dir = await getTemporaryDirectory();
      _recPath = '${dir.path}/ai_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _rec.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: _recPath!);
      recording = true;
      recSeconds = 0;
      HapticFeedback.mediumImpact();
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        recSeconds++;
        notifyListeners();
        if (recSeconds >= 45) unawaited(stopAndSend());
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

  /// Yozishni to'xtatib, serverga yuboradi (nutq → matn), keyin [submit]
  Future<void> stopAndSend({void Function()? closeSheet}) async {
    _recTimer?.cancel();
    if (!recording) return;
    recording = false;
    transcribing = true;
    notifyListeners();
    String? path;
    try {
      path = await _rec.stop();
    } catch (_) {}
    path ??= _recPath;
    String? text;
    String? err;
    try {
      if (path == null || !File(path).existsSync() || File(path).lengthSync() < 3000) {
        err = tr('Ovoz juda qisqa. Mikrofonni bosib, gapirib, yana bosing.');
      } else {
        text = await _api!.aiListen(path);
      }
    } on ApiException catch (e) {
      err = e.isNetwork ? tr("Internet yo'q") : e.message;
    } catch (e) {
      err = '$e';
    }
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
    _rec.dispose();
    stopSpeaking();
    super.dispose();
  }
}

/// Chap tomonda kichkina suzuvchi AI tugmasi: bosilsa chat ochiladi, uzoq bosilsa — darhol tinglaydi.
class AiBubble extends StatefulWidget {
  const AiBubble({super.key, required this.controller, required this.navigatorKey});

  final AssistantController controller;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<AiBubble> createState() => _AiBubbleState();
}

class _AiBubbleState extends State<AiBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();
  bool _open = false;
  double _up = 0; // tugmani yuqoriga/pastga surish

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _show({bool listen = false}) async {
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null || _open) return;
    setState(() => _open = true);
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
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (_open || mq.viewInsets.bottom > 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Positioned(
      left: 12,
      bottom: mq.padding.bottom + 104 + _up,
      child: GestureDetector(
        onVerticalDragUpdate: (d) => setState(() => _up = (_up - d.delta.dy).clamp(-60.0, 420.0)),
        onTap: _show,
        onLongPress: () => _show(listen: true),
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final t = _pulse.value;
            return SizedBox(
              width: 58,
              height: 58,
              child: Stack(alignment: Alignment.center, children: [
                Container(
                  width: 46 + 12 * t,
                  height: 46 + 12 * t,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary.withValues(alpha: 0.18 * (1 - t))),
                ),
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Brand.green, Brand.teal]),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.6),
                    boxShadow: [BoxShadow(color: Brand.green.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 22),
                ),
              ]),
            );
          },
        ),
      ),
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

  AssistantController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_changed);
    if (widget.autoListen) WidgetsBinding.instance.addPostFrameCallback((_) => _mic());
  }

  @override
  void dispose() {
    c.removeListener(_changed);
    if (c.recording) unawaited(c.cancelRecording());
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent + 80, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
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

  Future<void> _mic() async {
    if (c.recording) {
      await c.stopAndSend(closeSheet: _close);
      return;
    }
    final err = await c.startRecording();
    if (mounted) setState(() => _note = err);
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
                const Expanded(child: Text('AI yordamchi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                IconButton(
                  tooltip: tr('Javobni ovozda aytish'),
                  onPressed: c.toggleSpeak,
                  icon: Icon(c.speak ? Icons.volume_up_rounded : Icons.volume_off_rounded, color: c.speak ? cs.primary : cs.outline),
                ),
                IconButton(tooltip: tr('Tozalash'), onPressed: c.messages.isEmpty ? null : c.clear, icon: Icon(Icons.delete_outline_rounded, color: cs.outline)),
                IconButton(onPressed: _close, icon: const Icon(Icons.close_rounded)),
              ]),
            ),
            Expanded(
              child: !c.loaded
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
            if (_note != null) Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 6), child: Text(_note!, style: TextStyle(color: cs.error, fontSize: 12.5))),
            if (c.recording || c.transcribing) _listening(cs),
            Padding(
              padding: EdgeInsets.fromLTRB(12, 4, 12, 12 + (mq.viewInsets.bottom > 0 ? 0 : mq.padding.bottom)),
              child: Row(children: [
                Expanded(
                  child: Glass(
                    radius: 24,
                    shadow: false,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 3,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: InputDecoration(hintText: tr('Savol yoki buyruq yozing…'), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 13)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _roundBtn(
                  icon: c.recording ? Icons.stop_rounded : Icons.mic_rounded,
                  color: c.recording ? Colors.red.shade600 : Brand.teal,
                  onTap: c.transcribing ? null : _mic,
                ),
                const SizedBox(width: 8),
                _roundBtn(icon: Icons.send_rounded, color: Brand.green, onTap: c.busy ? null : () => _send()),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _roundBtn({required IconData icon, required Color color, VoidCallback? onTap}) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 46,
          height: 46,
          decoration: BoxDecoration(shape: BoxShape.circle, color: onTap == null ? color.withValues(alpha: 0.35) : color, boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))]),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      );

  Widget _listening(ColorScheme cs) {
    final s = c.recSeconds;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Glass(
        radius: 16,
        shadow: false,
        tint: (c.recording ? Colors.red : Brand.teal).withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          if (c.recording) const _RecDot() else const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2)),
          const SizedBox(width: 10),
          Expanded(child: Text(c.recording ? '${tr('Tinglayapman…')} ${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}' : tr("Matnga o'girilmoqda…"), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
          if (c.recording) TextButton(onPressed: c.cancelRecording, child: const Text('Bekor')),
        ]),
      ),
    );
  }

  Widget _intro(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Glass(
          radius: 20,
          shadow: false,
          padding: const EdgeInsets.all(14),
          child: Text(
            tr("Salom! Men ma'lumotlaringiz bo'yicha savollarga javob beraman (kassa, xodimlar, vazifalar…). Ovoz bilan ham ishlayman: mikrofonni bosing va ayting — masalan «Kassani och», «Ishga keldim», «Bugun kim ishda?»."),
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
            SelectableText(m.text, style: TextStyle(fontSize: 14.5, height: 1.35, color: m.error ? cs.error : (me ? Colors.white : cs.onSurface))),
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
          gradient: me ? const LinearGradient(colors: [Brand.green, Color(0xFF0F9460)]) : null,
          color: me ? null : Colors.white.withValues(alpha: 0.7),
          border: me ? null : Border.all(color: Colors.white.withValues(alpha: 0.9)),
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
