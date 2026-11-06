import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../avatar.dart';
import '../format.dart';
import '../l10n.dart';
import '../motion.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';

/// Profil: rasm (kamera/galereya), parolni almashtirish, faol seanslar (qurilmalar), til, chiqish.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.session, required this.onLogout});

  final Session session;
  final Future<void> Function() onLogout;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Session get s => widget.session;
  Map<String, dynamic> _p = const {};
  List<Map<String, dynamic>> _sessions = const [];
  bool _uploading = false;
  bool _sessionsLoading = true;

  // parol
  bool _pwOpen = false, _pwBusy = false, _show = false;
  final _cur = TextEditingController(), _new = TextEditingController(), _rep = TextEditingController();
  String? _pwErr;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cur.dispose();
    _new.dispose();
    _rep.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await s.api!.profile();
      if ((p['photo_url'] ?? '') != (s.photoUrl ?? '')) s.setPhoto(p['photo_url'] as String?);
      if (mounted) setState(() => _p = p);
    } catch (e) {
      await s.handleError(e);
    }
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      final l = await s.api!.profileSessions();
      if (mounted) {
        setState(() {
          _sessions = l;
          _sessionsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _sessionsLoading = false);
    }
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _pick(ImageSource src) async {
    XFile? x;
    try {
      x = await ImagePicker().pickImage(source: src, maxWidth: 1200, imageQuality: 85);
    } catch (e) {
      _snack(tr("Rasmni ochib bo'lmadi"));
      return;
    }
    if (x == null) return;
    setState(() => _uploading = true);
    try {
      final url = await s.api!.profilePhotoUpload(x.path);
      s.setPhoto(url);
      HapticFeedback.mediumImpact();
      _snack(tr('Rasm saqlandi'));
    } on ApiException catch (e) {
      _snack(e.message);
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _removePhoto() async {
    setState(() => _uploading = true);
    try {
      await s.api!.profilePhotoDelete();
      s.setPhoto(null);
    } on ApiException catch (e) {
      _snack(e.message);
    }
    if (mounted) setState(() => _uploading = false);
  }

  void _photoMenu() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Kamera'), onTap: () {
            Navigator.pop(ctx);
            _pick(ImageSource.camera);
          }),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Galereyadan tanlash'), onTap: () {
            Navigator.pop(ctx);
            _pick(ImageSource.gallery);
          }),
          if (s.photoUrl != null)
            ListTile(leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error), title: Text("Rasmni o'chirish", style: TextStyle(color: Theme.of(ctx).colorScheme.error)), onTap: () {
              Navigator.pop(ctx);
              _removePhoto();
            }),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Future<void> _savePassword() async {
    if (_pwBusy) return;
    if (_cur.text.isEmpty || _new.text.isEmpty) {
      setState(() => _pwErr = tr('Hamma maydonni to\'ldiring'));
      return;
    }
    if (_new.text != _rep.text) {
      setState(() => _pwErr = tr('Yangi parollar bir xil emas'));
      return;
    }
    setState(() {
      _pwBusy = true;
      _pwErr = null;
    });
    try {
      await s.api!.profilePassword(_cur.text, _new.text, _rep.text);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      _cur.clear();
      _new.clear();
      _rep.clear();
      setState(() {
        _pwOpen = false;
        _pwBusy = false;
      });
      _snack(tr('Parol almashtirildi. Boshqa qurilmalar qayta kiradi.'));
      _loadSessions();
    } on ApiException catch (e) {
      setState(() {
        _pwBusy = false;
        _pwErr = e.message;
      });
    }
  }

  Future<void> _revoke(Map<String, dynamic> x) async {
    try {
      await s.api!.profileSessionRevoke('${x['id']}');
      HapticFeedback.selectionClick();
      _loadSessions();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _revokeOthers() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Boshqa qurilmalardan chiqish'),
        content: const Text("Shu telefondan tashqari hamma qurilma va brauzer seanslari yopiladi. Davom etasizmi?"),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Yo'q")), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ha, chiqarish'))],
      ),
    );
    if (ok != true) return;
    try {
      final n = await s.api!.profileRevokeOthers();
      _snack('${tr('Yopildi')}: $n');
      _loadSessions();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  String _ago(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    final m = DateTime.now().difference(d).inMinutes;
    if (m < 2) return tr('hozirgina');
    if (m < 60) return '$m ${tr('daqiqa oldin')}';
    if (m < 1440) return '${m ~/ 60} ${tr('soat oldin')}';
    return formatDate(iso);
  }

  Widget _field(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: TextField(
          controller: c,
          obscureText: !_show,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: tr(label), suffixIcon: IconButton(icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => _show = !_show))),
        ),
      );

  Widget _title(String t, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 4, 10),
        child: Row(children: [Expanded(child: Text(t, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: -0.2))), if (trailing != null) trailing]),
      );

  /// Bo'lim: ketma-ket yumshoq paydo bo'ladi va keyingisidan masofa bilan ajraladi
  Widget _sec(int i, Widget w) => Reveal(index: i, child: Padding(padding: const EdgeInsets.only(bottom: 20), child: w));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final me = s.me!;
    final name = '${_p['name'] ?? (s.userName.isEmpty ? me.company : s.userName)}';
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 48),
        children: [
          _sec(
            0,
            Glass(
              radius: 30,
              blur: true,
              padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
              child: Column(children: [
                Tappable(
                  onTap: _uploading ? null : _photoMenu,
                  scale: 0.94,
                  child: Stack(clipBehavior: Clip.none, children: [
                    ListenableBuilder(listenable: s, builder: (_, _) => UserAvatar(session: s, name: name, size: 108)),
                    if (_uploading) const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0x66000000)), child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))))),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(width: 38, height: 38, decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Brand.green, Brand.teal]), border: Border.all(color: Colors.white, width: 3)), child: const Icon(Icons.photo_camera_rounded, size: 18, color: Colors.white)),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                const SizedBox(height: 4),
                Text('${me.roleName} · ${me.company}', textAlign: TextAlign.center, style: TextStyle(color: cs.outline, fontSize: 13.5)),
                if ('${_p['phone'] ?? ''}'.isNotEmpty || ('${_p['email'] ?? ''}'.isNotEmpty && !'${_p['email']}'.endsWith('.local'))) ...[
                  const SizedBox(height: 14),
                  Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.center, children: [
                    if ('${_p['phone'] ?? ''}'.isNotEmpty) _contact(Icons.phone_rounded, '${_p['phone']}'),
                    if ('${_p['email'] ?? ''}'.isNotEmpty && !'${_p['email']}'.endsWith('.local')) _contact(Icons.mail_rounded, '${_p['email']}'),
                  ]),
                ],
              ]),
            ),
          ),
          _sec(
            1,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _title('Xavfsizlik'),
              Glass(
                radius: 24,
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Tappable(
                    scale: 0.98,
                    onTap: () => setState(() => _pwOpen = !_pwOpen),
                    child: Row(children: [
                      const IconTile(icon: Icons.lock_outline_rounded, color: Brand.purple, size: 42),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('Parolni almashtirish', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
                      AnimatedRotation(turns: _pwOpen ? 0.5 : 0, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic, child: Icon(Icons.expand_more_rounded, color: cs.outline)),
                    ]),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 340),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: !_pwOpen
                        ? const SizedBox(width: double.infinity)
                        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _field(_cur, 'Joriy parol'),
                            _field(_new, 'Yangi parol (kamida 8 belgi, harf va raqam)'),
                            _field(_rep, 'Yangi parolni takrorlang'),
                            if (_pwErr != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_pwErr!, style: TextStyle(color: cs.error, fontSize: 13))),
                            const SizedBox(height: 14),
                            SizedBox(width: double.infinity, child: FilledButton(onPressed: _pwBusy ? null : _savePassword, child: Text(_pwBusy ? 'Saqlanmoqda…' : 'Parolni saqlash'))),
                            const SizedBox(height: 6),
                            Text('Parol almashtirilgach, boshqa qurilmalar qayta kirishi kerak.', style: TextStyle(color: cs.outline, fontSize: 12)),
                          ]),
                  ),
                ]),
              ),
            ]),
          ),
          _sec(
            2,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _title('Faol seanslar', trailing: IconButton(visualDensity: VisualDensity.compact, onPressed: () {
                setState(() => _sessionsLoading = true);
                _loadSessions();
              }, icon: Icon(Icons.refresh_rounded, color: cs.outline))),
              if (_sessionsLoading && _sessions.isEmpty)
                const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator()))
              else
                for (var i = 0; i < _sessions.length; i++)
                  Reveal(
                    index: i.clamp(0, 8),
                    child: GlassRow(
                      margin: const EdgeInsets.only(bottom: 10),
                      tint: _sessions[i]['current'] == true ? cs.primary.withValues(alpha: 0.12) : null,
                      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                      child: Row(children: [
                        IconTile(icon: _sessions[i]['kind'] == 'web' ? Icons.language_rounded : Icons.smartphone_rounded, color: _sessions[i]['current'] == true ? Brand.green : Brand.blue, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text('${_sessions[i]['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5))),
                              if (_sessions[i]['current'] == true) ...[const SizedBox(width: 8), StatusChip(tr('Shu qurilma'), cs.primary)],
                            ]),
                            const SizedBox(height: 2),
                            Text([if ('${_sessions[i]['ip'] ?? ''}'.isNotEmpty) '${_sessions[i]['ip']}', _ago('${_sessions[i]['at']}')].where((e) => e.isNotEmpty).join(' · '), style: TextStyle(color: cs.outline, fontSize: 12)),
                          ]),
                        ),
                        if (_sessions[i]['current'] != true) IconButton(tooltip: tr('Seansni yopish'), onPressed: () => _revoke(_sessions[i]), icon: Icon(Icons.logout_rounded, color: cs.error, size: 20)),
                      ]),
                    ),
                  ),
              if (_sessions.where((e) => e['current'] != true).isNotEmpty) ...[
                const SizedBox(height: 4),
                SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _revokeOthers, icon: const Icon(Icons.phonelink_erase_rounded, size: 18), label: const Text('Boshqa hammasidan chiqish'))),
              ],
            ]),
          ),
          _sec(
            3,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _title('Til'),
              Glass(
                radius: 24,
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const IconTile(icon: Icons.translate, color: Brand.teal, size: 42),
                  const SizedBox(width: 12),
                  const Expanded(child: LangSwitch()),
                ]),
              ),
            ]),
          ),
          _sec(
            4,
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _title('Ko\'rinish'),
              Glass(
                radius: 24,
                padding: const EdgeInsets.all(16),
                child: ValueListenableBuilder<ThemeMode>(
                  valueListenable: ThemeController.mode,
                  builder: (context, tm, _) => Row(children: [
                    const IconTile(icon: Icons.dark_mode_outlined, color: Brand.purple, size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded, size: 18), label: Text('Avto')),
                          ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded, size: 18), label: Text('Kun')),
                          ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded, size: 18), label: Text('Tun')),
                        ],
                        selected: {tm},
                        onSelectionChanged: (v) {
                          HapticFeedback.selectionClick();
                          ThemeController.set(v.first);
                        },
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
          _sec(
            5,
            GlassRow(
              margin: EdgeInsets.zero,
              tint: Colors.red.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              onTap: () async {
                Navigator.of(context).pop();
                await widget.onLogout();
              },
              child: Row(children: [
                IconTile(icon: Icons.logout_rounded, color: cs.error, size: 42),
                const SizedBox(width: 12),
                Expanded(child: Text('Hisobdan chiqish', style: TextStyle(color: cs.error, fontWeight: FontWeight.w800, fontSize: 15.5))),
                Icon(Icons.chevron_right, color: cs.error.withValues(alpha: 0.6)),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contact(IconData icon, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: context.pill, borderRadius: BorderRadius.circular(14), border: Border.all(color: context.pillBorder)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 15, color: Theme.of(context).colorScheme.primary), const SizedBox(width: 7), Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))]),
      );
}
