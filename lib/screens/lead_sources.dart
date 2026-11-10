import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import '../l10n.dart';

/// Lid manbalari: qayerdan arizalar keladi (sayt, Facebook/Instagram, WhatsApp, Telegram bot, shaxmatka, API),
/// har biri ulanganmi, oxirgi 30 kunda nechta lid keldi va qanday ulanadi — qadam-baqadam. Sinov lidi yuborish mumkin.
class LeadSourcesScreen extends StatefulWidget {
  const LeadSourcesScreen({super.key, required this.session});

  final Session session;

  @override
  State<LeadSourcesScreen> createState() => _LeadSourcesScreenState();
}

class _LeadSourcesScreenState extends State<LeadSourcesScreen> {
  Key _key = UniqueKey();
  String? _busy;

  Session get s => widget.session;

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  void _copy(String v) {
    Clipboard.setData(ClipboardData(text: v));
    HapticFeedback.selectionClick();
    _snack(tr('Nusxa olindi'));
  }

  Future<void> _test(String ch) async {
    setState(() => _busy = ch);
    try {
      await s.api!.leadSourceTest(ch);
      _snack(tr("Sinov lidi yuborildi — «Lidlar» ro'yxatida ko'rinadi"));
      setState(() => _key = UniqueKey());
    } catch (e) {
      await s.handleError(e);
      _snack(e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _metaKeys() async {
    final token = TextEditingController();
    final secret = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(c).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Facebook / Instagram kalitlari', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text("Meta for Developers → ilovangiz → sahifa (Page) uchun uzoq muddatli Page Access Token va App Secret.", style: TextStyle(color: Theme.of(c).colorScheme.outline, fontSize: 13)),
          const SizedBox(height: 14),
          TextField(controller: token, minLines: 2, maxLines: 4, decoration: InputDecoration(labelText: tr('Page Access Token'))),
          const SizedBox(height: 10),
          TextField(controller: secret, decoration: InputDecoration(labelText: tr('App Secret (ixtiyoriy)'))),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Saqlash va tekshirish'))),
        ]),
      ),
    );
    if (ok != true || (token.text.trim().isEmpty && secret.text.trim().isEmpty)) return;
    setState(() => _busy = 'meta');
    try {
      final r = await s.api!.leadSourceMeta(pageToken: token.text.trim(), appSecret: secret.text.trim());
      final chk = (r['check'] as Map?) ?? const {};
      _snack(chk['ok'] == true ? '${tr('Ulandi')}: ${chk['page'] ?? ''}${chk['ig'] != null ? ' · Instagram @${chk['ig']}' : ''}' : '${tr('Ulanmadi')}: ${chk['error'] ?? ''}');
      setState(() => _key = UniqueKey());
    } catch (e) {
      await s.handleError(e);
      _snack(e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  static const _look = {
    'site': (Icons.language_rounded, Color(0xFF2F6FDE)),
    'meta': (Icons.facebook_rounded, Color(0xFF1877F2)),
    'whatsapp': (Icons.chat_rounded, Color(0xFF25D366)),
    'telegram': (Icons.send_rounded, Color(0xFF229ED9)),
    'chess': (Icons.grid_view_rounded, Color(0xFF7B5CE0)),
    'api': (Icons.code_rounded, Color(0xFF14A39A)),
    'manual': (Icons.edit_note_rounded, Color(0xFFF27A1A)),
  };

  /// Har bir manba uchun qanday ulash — qisqa qadamlar
  List<String> _steps(String id) => switch (id) {
        'site' => [
            "Saytingiz formasini (yoki Tilda / Make / Zapier) quyidagi manzilga POST qilib yuboring.",
            "Maydonlar: name (ism), phone (telefon), message (izoh), ixtiyoriy: rooms, budget, src.",
            "Tilda: Sozlamalar → Formalar → Webhook → manzilni qo'ying.",
          ],
        'meta' => [
            "Meta for Developers'da ilova yarating, «Webhooks» ga quyidagi manzil va Verify token ni kiriting.",
            "Sahifa (Page) obunalari: leadgen va messages. Instagram — biznes akkaunt sahifaga ulangan bo'lsin.",
            "Page Access Token ni shu yerga kiriting — obuna avtomatik yoqiladi.",
          ],
        'whatsapp' => [
            "WhatsApp Business Platform (Cloud API) da Webhook manzili va Verify token — Facebook bilan bir xil.",
            "Webhook maydonlari: messages. Mijoz yozgan har bir xabar lid bo'lib tushadi.",
          ],
        'telegram' => [
            "@BotFather da bot yarating va tokenni oling.",
            "Saytda: Sozlamalar → Telegram bot → tokenni qo'ying. Botga yozganlar va bron qilganlar lid bo'ladi.",
          ],
        'chess' => [
            "Bu sahifa — xonadonlar shaxmatkasi va ariza formasi. Havolani saytingizga, Instagram bio yoki reklamaga qo'ying.",
            "Mijoz ariza qoldirsa — darhol shu yerga lid bo'lib tushadi.",
          ],
        'api' => [
            "Boshqa dasturlar uchun: POST /api/v1/leads (Bearer kalit bilan). Kalitni saytda «API» bo'limida oling.",
          ],
        _ => [
            "Ilovada «Ariza» tugmasi yoki saytdagi «Lidlar» bo'limidan qo'lda qo'shiladi.",
          ],
      };

  Widget _field(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: cs.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _copy(value),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: TextStyle(color: cs.outline, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  SelectableText(value, maxLines: 2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ),
              Icon(Icons.copy_rounded, size: 18, color: cs.primary),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _source(Map<String, dynamic> x, bool canEdit, bool https) {
    final cs = Theme.of(context).colorScheme;
    final id = '${x['id']}';
    final (icon, color) = _look[id] ?? (Icons.inbox_rounded, cs.primary);
    final on = x['connected'] == true;
    final count = x['count'] as num?;
    final test = switch (id) { 'site' => 'site', 'meta' => 'facebook', 'whatsapp' => 'whatsapp', _ => null };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(
        padding: const EdgeInsets.all(14),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            leading: IconTile(icon: icon, color: color, size: 44),
            title: Text('${x['title']}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Row(children: [
              Icon(on ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 15, color: on ? Brand.green : cs.outline),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '${on ? tr('Ulangan') : tr('Ulanmagan')}${count != null ? ' · ${tr('30 kunda')}: $count' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: on ? Brand.green : cs.outline, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
            children: [
              const SizedBox(height: 6),
              for (final (i, st) in _steps(id).indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                      child: Text('${i + 1}', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(st, style: const TextStyle(fontSize: 13))),
                  ]),
                ),
              if ((id == 'meta' || id == 'whatsapp') && !https)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text("Diqqat: Meta faqat https manzilni qabul qiladi — sayt https bilan ishlashi kerak.", style: TextStyle(color: Colors.orange.shade700, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              if (x['url'] != null) _field(id == 'chess' ? tr('Sahifa havolasi') : tr('Manzil (URL)'), '${x['url']}'),
              if (x['hook_url'] != null) _field(tr('Webhook manzili'), '${x['hook_url']}'),
              if (x['verify_token'] != null) _field(tr('Verify token'), '${x['verify_token']}'),
              if (x['bot'] != null) _field(tr('Bot'), '@${x['bot']}'),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                if (test != null)
                  OutlinedButton.icon(
                    onPressed: _busy != null ? null : () => _test(test),
                    icon: _busy == test ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.science_outlined, size: 18),
                    label: const Text('Sinov lidi'),
                  ),
                if (id == 'meta' && canEdit)
                  FilledButton.icon(
                    onPressed: _busy != null ? null : _metaKeys,
                    icon: _busy == 'meta' ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.key_rounded, size: 18),
                    label: Text(on ? tr('Kalitni yangilash') : tr('Kalitni kiritish')),
                  ),
              ]),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Lid manbalari')),
      body: FutureBody<Map<String, dynamic>>(
        key: _key,
        session: s,
        load: () => s.api!.leadSources(),
        builder: (context, d, reload) {
          final src = ((d['sources'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          final errors = ((d['errors'] as List?) ?? const []).whereType<Map>().toList();
          final canEdit = d['can_edit'] == true;
          final https = d['https'] == true;
          final on = src.where((x) => x['connected'] == true).length;
          return ListView(
            padding: EdgeInsets.fromLTRB(16, 8, 16, NavInset.listBottom(context)),
            children: [
              HeroGlass(
                tint: Brand.blue,
                child: Row(children: [
                  const IconTile(icon: Icons.hub_rounded, color: Brand.blue, size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('$on / ${src.length} ${tr('manba ulangan')}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 2),
                      Text("Har bir manbani oching: qanday ulash, manzil va sinov lidi.", style: TextStyle(color: cs.outline, fontSize: 13)),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              for (final x in src) _source(x, canEdit, https),
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Oxirgi xatolar', style: TextStyle(color: cs.error, fontWeight: FontWeight.w800)),
                for (final e in errors) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${e['msg']}', style: TextStyle(color: cs.outline, fontSize: 12))),
              ],
            ],
          );
        },
      ),
    );
  }
}
