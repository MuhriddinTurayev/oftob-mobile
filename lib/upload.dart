import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'l10n.dart';
import 'theme.dart';

/// Yuklash jarayoni: [sent] bayt yuborildi, jami [total] bayt
typedef UploadProgress = void Function(int sent, int total);

/// Multipart so'rov, fayl tarmoqqa ketayotganda necha bayt yuborilganini xabar qiladi
class ProgressMultipartRequest extends http.MultipartRequest {
  ProgressMultipartRequest(super.method, super.url, {this.onProgress});

  final UploadProgress? onProgress;

  @override
  http.ByteStream finalize() {
    final stream = super.finalize();
    final cb = onProgress;
    if (cb == null) return stream;
    final total = contentLength;
    var sent = 0;
    cb(0, total);
    return http.ByteStream(stream.transform(StreamTransformer<List<int>, List<int>>.fromHandlers(handleData: (data, sink) {
      sent += data.length;
      cb(sent, total);
      sink.add(data);
    })));
  }
}

class _UploadState {
  const _UploadState(this.sent, this.total, {this.done = false});
  final int sent;
  final int total;
  final bool done;
  double get fraction => total <= 0 ? 0 : (sent / total).clamp(0.0, 1.0);
}

/// Fayl yuklanayotganda ekranda oyna: aylana, foiz, necha MB ketdi. Muvaffaqiyatli tugasa — bir lahza yashil belgi.
/// Xato bo'lsa oyna yopiladi va xato chaqiruvchiga qaytadi.
///
/// Foiz qanday hisoblanadi: telefon faylni tarmoq buferiga bir zumda «yuborib» qo'yadi, haqiqiy jo'nash esa sekinroq bo'ladi.
/// Shuning uchun foiz vaqt bo'yicha silliq o'sadi (o'rtacha mobil internet tezligi taxmini bilan), lekin hech qachon
/// buferga berilgan baytlardan oshmaydi; 100% — faqat server «qabul qildim» deganda.
/// [download] — yuklab olish: qabul qilingan baytlar aniq, shuning uchun foiz to'g'ridan-to'g'ri baytlardan olinadi.
Future<T> runUpload<T>(BuildContext context, {required String title, required Future<T> Function(UploadProgress onProgress) task, bool download = false}) async {
  final state = ValueNotifier(const _UploadState(0, 0));
  final nav = Navigator.of(context, rootNavigator: true);
  var open = true;
  unawaited(showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => PopScope(canPop: false, child: _UploadDialog(title: title, state: state, download: download)),
  ).then((_) => open = false));
  var sent = 0, total = 0, shownPct = -1;
  final sw = Stopwatch()..start();
  final tick = Timer.periodic(const Duration(milliseconds: 150), (_) {
    if (total <= 0) {
      if (sent > 0 && sent != state.value.sent) state.value = _UploadState(sent, 0); // hajmi noma'lum: necha KB kelgani
      return;
    }
    final byBytes = sent / total;
    final tau = math.max(1.2, total / (80 * 1024)); // ~80 KB/s mobil yuklash
    final byTime = 0.97 * (1 - math.exp(-sw.elapsedMilliseconds / 1000 / tau));
    final f = (download ? byBytes : math.min(byBytes, byTime)).clamp(0.0, 0.97);
    final pct = (f * 100).floor();
    if (pct != shownPct) {
      shownPct = pct;
      state.value = _UploadState((f * total).round(), total);
    }
  });
  try {
    final r = await task((s, t) {
      sent = s;
      total = t;
    });
    tick.cancel();
    state.value = _UploadState(total, total, done: true);
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return r;
  } finally {
    tick.cancel();
    if (open) nav.pop();
  }
}

String _mb(int b) => b < 1024 * 1024 ? '${(b / 1024).round()} KB' : '${(b / 1024 / 1024).toStringAsFixed(1)} MB';

class _UploadDialog extends StatelessWidget {
  const _UploadDialog({required this.title, required this.state, this.download = false});

  final bool download;
  final String title;
  final ValueNotifier<_UploadState> state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: ValueListenableBuilder<_UploadState>(
          valueListenable: state,
          builder: (context, st, _) {
            final waiting = !st.done && st.total > 0 && st.fraction >= 0.95; // deyarli ketdi, server javobini kutyapmiz
            return Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: 104,
                height: 104,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: st.fraction),
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOut,
                  builder: (context, v, _) => Stack(alignment: Alignment.center, children: [
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        value: st.total > 0 || st.done ? v : null, // hajmi noma'lum bo'lsa — aylanib turadi
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        color: st.done ? Brand.green : cs.primary,
                        backgroundColor: cs.primary.withValues(alpha: 0.12),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: st.done
                          ? Icon(Icons.check_rounded, key: const ValueKey('ok'), size: 52, color: Brand.green)
                          : st.total > 0
                              ? Text('${(v * 100).round()}%', key: const ValueKey('pct'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: context.ink))
                              : Icon(download ? Icons.download_rounded : Icons.upload_rounded, key: const ValueKey('ic'), size: 34, color: cs.primary),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 18),
              Text(st.done ? tr('Yuklandi') : title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                st.done
                    ? tr('Muvaffaqiyatli yuborildi')
                    : waiting
                        ? tr('Server qabul qilyapti…')
                        : st.total > 0
                            ? '${_mb(st.sent)} / ${_mb(st.total)}'
                            : st.sent > 0
                                ? _mb(st.sent)
                                : tr('Tayyorlanmoqda…'),
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.outline, fontSize: 13.5),
              ),
              if (!st.done) ...[
                const SizedBox(height: 10),
                Text(tr('Iltimos, ilovani yopmang'), textAlign: TextAlign.center, style: TextStyle(color: cs.outline, fontSize: 12)),
              ],
            ]);
          },
        ),
      ),
    );
  }
}

/// Joyida (rasm ustida, tugma ichida) ko'rsatiladigan yuklash foizi: [progress] 0..1 silliq o'sadi
/// (telefon buferi faylni bir zumda «yutib» yuboradi — shuning uchun tezlik taxmini bilan), 1 — server qabul qildi.
class UploadTracker {
  final ValueNotifier<double> progress = ValueNotifier(0);
  int _sent = 0, _total = 0;
  final _sw = Stopwatch();
  Timer? _t;

  void start() {
    _sent = _total = 0;
    progress.value = 0;
    _sw
      ..reset()
      ..start();
    _t?.cancel();
    _t = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (_total <= 0) return;
      final tau = math.max(1.2, _total / (80 * 1024));
      final byTime = 0.97 * (1 - math.exp(-_sw.elapsedMilliseconds / 1000 / tau));
      final f = math.min(_sent / _total, byTime).clamp(0.0, 0.97);
      if ((f - progress.value).abs() >= 0.01) progress.value = f;
    });
  }

  void onBytes(int sent, int total) {
    _sent = sent;
    _total = total;
  }

  void finish() {
    _t?.cancel();
    progress.value = 1;
  }

  void stop() => _t?.cancel();

  void dispose() {
    _t?.cancel();
    progress.dispose();
  }
}
