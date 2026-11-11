import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as w show Text;
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'l10n.dart';
import 'push.dart';
import 'session.dart';
import 'theme.dart';

/// Xodimning Telegram botga ulanishi (ilovaning o'zidan, bitta bosishda): `t.me/BOT?start=KOD`.
/// Ulangandan keyin pul so'rovlari, hisobotlar, vazifalar ilova yopiq bo'lsa ham darhol Telegram'ga keladi.
class TgLink {
  /// Oxirgi ma'lum holat: {enabled, linked, bot, code, link}; null — hali so'ralmagan
  static final ValueNotifier<Map<String, dynamic>?> state = ValueNotifier(null);

  static Future<Map<String, dynamic>?> load(Session s) async {
    final api = s.api;
    if (api == null) return null;
    try {
      final d = Map<String, dynamic>.from(await api.aGet('/me/telegram') as Map);
      state.value = d;
      return d;
    } catch (_) {
      return state.value;
    }
  }
}

class TelegramConnectScreen extends StatefulWidget {
  const TelegramConnectScreen({super.key, required this.session});

  final Session session;

  @override
  State<TelegramConnectScreen> createState() => _TelegramConnectScreenState();
}

class _TelegramConnectScreenState extends State<TelegramConnectScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _d;
  bool _busy = false, _opened = false, _push = true;
  String? _err;

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    Push.enabled().then((v) {
      if (mounted) setState(() => _push = v);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Telegram'dan qaytganda — ulanganini o'zi tekshiradi
  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.resumed && _opened && _d?['linked'] != true) _check();
  }

  Future<void> _load() async {
    final d = await TgLink.load(s);
    if (mounted) setState(() => _d = d ?? {'enabled': false});
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final d = Map<String, dynamic>.from(await s.api!.aSend('POST', '/me/telegram/check') as Map);
      TgLink.state.value = d;
      if (!mounted) return;
      setState(() => _d = d);
      if (d['linked'] == true) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Telegram ulandi — xabarlar endi Telegram\'ga ham keladi'))));
      } else {
        setState(() => _err = tr("Bot hali kodni olmadi. Telegram'da «Start» (Boshlash) tugmasini bosing, keyin qayta tekshiring."));
      }
    } catch (e) {
      await s.handleError(e);
      if (mounted) setState(() => _err = e is ApiException ? e.message : '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _open() async {
    final link = '${_d?['link'] ?? ''}';
    if (link.isEmpty) return;
    _opened = true;
    final ok = await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      setState(() => _err = tr("Telegram ochilmadi. Telegram ilovasi o'rnatilganini tekshiring."));
    }
  }

  Future<void> _unlink() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Telegram'ni uzasizmi?"),
        content: const Text("Xabarlar Telegram'ga kelmay qoladi. Keyin qayta ulash mumkin."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Bekor qilish')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error), onPressed: () => Navigator.pop(c, true), child: const Text('Uzish')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final d = Map<String, dynamic>.from(await s.api!.aSend('POST', '/me/telegram/unlink') as Map);
      TgLink.state.value = d;
      _opened = false;
      if (mounted) setState(() => _d = d);
    } catch (e) {
      await s.handleError(e);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _askPush() async {
    final v = await Push.askPermission();
    if (mounted) setState(() => _push = v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = _d;
    final linked = d?['linked'] == true;
    final bot = '${d?['bot'] ?? ''}';
    Widget step(int n, String t) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Brand.green, shape: BoxShape.circle),
              child: w.Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Padding(padding: const EdgeInsets.only(top: 3), child: Text(t, style: const TextStyle(fontSize: 14.5)))),
          ]),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Telegram bot')),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom), children: [
              Glass(
                radius: 24,
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    IconTile(icon: Icons.send_rounded, color: linked ? Brand.green : Brand.teal, size: 48),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(linked ? 'Telegram ulangan' : 'Telegram ulanmagan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: context.ink)),
                        if (bot.isNotEmpty) w.Text('@$bot', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    if (linked) const Icon(Icons.check_circle_rounded, color: Brand.green, size: 28),
                  ]),
                  const SizedBox(height: 12),
                  Text(
                    linked
                        ? "Ilova yopiq bo'lsa ham xabarlar darhol Telegram'ga keladi. Botdan foydalanish: hisobot, xarajat yozish, davomat va boshqalar."
                        : "Ulansangiz, pul so'rovlari, xarid hisobotlari, vazifalar va kunlik hisobot ilova yopiq bo'lsa ham darhol Telegram'ga keladi.",
                    style: TextStyle(color: context.inkSoft, fontSize: 13.5, height: 1.35),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              if (d['enabled'] != true)
                Glass(
                  radius: 20,
                  padding: const EdgeInsets.all(16),
                  child: Text("Telegram bot hali sozlanmagan. Platforma administratoriga murojaat qiling.", style: TextStyle(color: cs.error)),
                )
              else if (!linked) ...[
                Glass(
                  radius: 20,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    step(1, "«Telegram'da ochish» tugmasini bosing"),
                    step(2, "Telegram'da «Start» (Boshlash) tugmasini bosing"),
                    step(3, "Ilovaga qayting — ulanganini o'zi tekshiradi"),
                  ]),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy ? null : _open,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text("Telegram'da ochish"),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _check,
                  icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded),
                  label: const Text('Ulanganini tekshirish'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
                if ('${d['code'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text("Tugma ishlamasa — botga shu kodni yozing:", textAlign: TextAlign.center, style: TextStyle(color: cs.outline, fontSize: 12.5)),
                  const SizedBox(height: 6),
                  Center(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: '${d['code']}'));
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Nusxa olindi'))));
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          w.Text('${d['code']}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 3, color: cs.primary)),
                          const SizedBox(width: 8),
                          Icon(Icons.copy_rounded, size: 18, color: cs.outline),
                        ]),
                      ),
                    ),
                  ),
                ],
              ] else ...[
                FilledButton.icon(
                  onPressed: _open,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Botni ochish'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _unlink,
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text("Telegram'ni uzish"),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), foregroundColor: cs.error),
                ),
              ],
              if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: w.Text(_err!, textAlign: TextAlign.center, style: TextStyle(color: cs.error))),
              if (Push.supported) ...[
                const SizedBox(height: 22),
                Glass(
                  radius: 20,
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(children: [
                    IconTile(icon: Icons.notifications_active_rounded, color: _push ? Brand.green : Brand.amber, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Telefon bildirishnomalari', style: TextStyle(fontWeight: FontWeight.w800, color: context.ink)),
                        Text(_push ? "Yoqilgan — ilova yopiq bo'lsa ham telefon tepasida chiqadi" : "O'chirilgan — ruxsat bering", style: TextStyle(color: context.inkSoft, fontSize: 12.5)),
                      ]),
                    ),
                    if (!_push) TextButton(onPressed: _askPush, child: const Text('Yoqish')),
                  ]),
                ),
              ],
            ]),
    );
  }
}

/// «Yana» va bosh sahifa uchun: Telegram ulanmagan bo'lsa — eslatma kartochka
class TgConnectBanner extends StatelessWidget {
  const TgConnectBanner({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: TgLink.state,
      builder: (context, d, _) {
        if (d == null || d['enabled'] != true || d['linked'] == true) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Glass(
            radius: 22,
            tint: Brand.teal.withValues(alpha: 0.12),
            onTap: () => Navigator.of(context).push(DeskRoute<void>(builder: (_) => TelegramConnectScreen(session: session))),
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(children: [
              const IconTile(icon: Icons.send_rounded, color: Brand.teal, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("Telegram botga ulaning", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: context.ink)),
                  Text("Pul so'rovlari va hisobotlar ilova yopiq bo'lsa ham darhol keladi", style: TextStyle(color: context.inkSoft, fontSize: 12.5)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: context.inkSoft),
            ]),
          ),
        );
      },
    );
  }
}
