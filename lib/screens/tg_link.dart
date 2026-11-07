import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../l10n.dart';
import '../session.dart';
import '../theme.dart';

/// Ishchini Telegram-botga ulash: shaxsiy kod (K1234567), bot havolasi, ulanganmi, yangi kod.
/// Ishchi havolani bosadi yoki botga kodni yozadi — Telegram avtomatik ulanadi va «Keldim» tugmasi chiqadi.
Future<void> showTelegramLink(BuildContext context, Session s, {required String objectId, required String staffId, required String name, String? code, bool linked = false, String bot = ''}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TgSheet(session: s, objectId: objectId, staffId: staffId, name: name, code: code, linked: linked, bot: bot),
  );
}

class _TgSheet extends StatefulWidget {
  const _TgSheet({required this.session, required this.objectId, required this.staffId, required this.name, this.code, this.linked = false, this.bot = ''});
  final Session session;
  final String objectId;
  final String staffId;
  final String name;
  final String? code;
  final bool linked;
  final String bot;

  @override
  State<_TgSheet> createState() => _TgSheetState();
}

class _TgSheetState extends State<_TgSheet> {
  late String? _code = widget.code;
  late bool _linked = widget.linked;
  late String _bot = widget.bot;
  bool _busy = false;
  String? _err;

  String? get _url => _bot.isNotEmpty && _code != null ? 'https://t.me/$_bot?start=$_code' : null;

  @override
  void initState() {
    super.initState();
    if (_code == null || _code!.isEmpty) _load();
  }

  Future<void> _load({bool renew = false}) async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final d = await widget.session.api!.aSend('POST', '/attendance/code', {'object': widget.objectId, 'staff': widget.staffId, 'renew': renew}) as Map;
      setState(() {
        _code = '${d['code'] ?? ''}';
        _linked = d['linked'] == true;
        _bot = '${d['bot'] ?? ''}';
      });
      if (renew) HapticFeedback.mediumImpact();
    } catch (e) {
      await widget.session.handleError(e);
      if (mounted) setState(() => _err = e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _message() {
    final u = _url;
    return [
      '${tr('Salom')}, ${widget.name}!',
      tr("Ishga kelganingizni Telegram orqali belgilash uchun:"),
      if (u != null) '1) ${tr('Shu havolani oching')}: $u' else '1) ${tr('Kompaniya Telegram-botini oching')}${_bot.isNotEmpty ? ' @$_bot' : ''}',
      '2) ${tr("«Start» ni bosing yoki kodni yuboring")}: $_code',
      '3) ${tr("Obyektga kelganda «Keldim» tugmasini bosing")}',
    ].join('\n');
  }

  Future<void> _renew() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Yangi kod'),
        content: Text(tr("Eski kod ishlamay qoladi va ulangan Telegram uziladi (telefon yo'qolsa yoki kod boshqaga tushsa). Ishchi yangi kod bilan qayta ulanadi.")),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Bekor qilish')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yangi kod'))],
      ),
    );
    if (ok == true) await _load(renew: true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final code = _code ?? '';
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const IconTile(icon: Icons.telegram, color: Color(0xFF229ED9), size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
              Text(tr('Telegram-botga ulash'), style: TextStyle(color: cs.outline)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: (_linked ? Colors.green : Colors.orange).withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
            child: Text(_linked ? tr('Ulangan') : tr('Ulanmagan'), style: TextStyle(color: _linked ? Colors.green.shade700 : Colors.orange.shade800, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 16),
        if (_busy && code.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
        else if (_err != null && code.isEmpty)
          Text(_err!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w700))
        else ...[
          // katta kod — bosilsa nusxa olinadi
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              Clipboard.setData(ClipboardData(text: code));
              HapticFeedback.selectionClick();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Kod nusxalandi'))));
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(color: const Color(0xFF229ED9).withValues(alpha: 0.10), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF229ED9).withValues(alpha: 0.35))),
              child: Column(children: [
                Text(code, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 4, color: Color(0xFF1B7FB0))),
                const SizedBox(height: 2),
                Text(tr('bosing — nusxa olinadi'), style: TextStyle(color: cs.outline, fontSize: 12)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _bot.isNotEmpty
                ? tr("Ishchi havolani ochib «Start» ni bossa yoki @:b botiga kodni yuborsa — Telegram avtomatik ulanadi. Keyin obyektda «Keldim» tugmasini bosadi.").replaceAll(':b', _bot)
                : tr("Ishchi kompaniya Telegram-botiga shu kodni yuborsa — avtomatik ulanadi. Keyin obyektda «Keldim» tugmasini bosadi."),
            style: TextStyle(color: cs.outline, fontSize: 13),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: code.isEmpty ? null : () => SharePlus.instance.share(ShareParams(text: _message())),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), backgroundColor: const Color(0xFF229ED9), foregroundColor: Colors.white),
              icon: const Icon(Icons.send_rounded, color: Colors.white),
              label: const Text('Ishchiga yuborish (Telegram, SMS…)'),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            if (_url != null)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(_url!), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Botni ochish'),
                ),
              ),
            if (_url != null) const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _renew,
                icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.autorenew_rounded, size: 18),
                label: const Text('Yangi kod'),
              ),
            ),
          ]),
          if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, style: TextStyle(color: cs.error))),
        ],
      ]),
    );
  }
}
