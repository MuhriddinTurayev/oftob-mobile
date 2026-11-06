import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../avatar.dart';
import '../format.dart';
import '../l10n.dart';
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final me = s.me!;
    final name = '${_p['name'] ?? (s.userName.isEmpty ? me.company : s.userName)}';
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          Glass(
            radius: 28,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Column(children: [
              GestureDetector(
                onTap: _uploading ? null : _photoMenu,
                child: Stack(clipBehavior: Clip.none, children: [
                  ListenableBuilder(listenable: s, builder: (_, _) => UserAvatar(session: s, name: name, size: 104)),
                  if (_uploading) const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0x66000000)), child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))))),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(width: 36, height: 36, decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary, border: Border.all(color: Colors.white, width: 3)), child: const Icon(Icons.photo_camera_rounded, size: 17, color: Colors.white)),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Text('${me.roleName} · ${me.company}', textAlign: TextAlign.center, style: TextStyle(color: cs.outline, fontSize: 13.5)),
              if ('${_p['phone'] ?? ''}'.isNotEmpty || '${_p['email'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 10),
                if ('${_p['phone'] ?? ''}'.isNotEmpty) Text('${_p['phone']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                if ('${_p['email'] ?? ''}'.isNotEmpty && !'${_p['email']}'.endsWith('.local')) Text('${_p['email']}', style: TextStyle(color: cs.outline, fontSize: 13)),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          Glass(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _pwOpen = !_pwOpen),
                child: Row(children: [
                  const IconTile(icon: Icons.lock_outline_rounded, color: Brand.purple, size: 40),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Parolni almashtirish', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
                  AnimatedRotation(turns: _pwOpen ? 0.5 : 0, duration: const Duration(milliseconds: 250), child: Icon(Icons.expand_more_rounded, color: cs.outline)),
                ]),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
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
                        const SizedBox(height: 4),
                        Text('Parol almashtirilgach, boshqa qurilmalar qayta kirishi kerak.', style: TextStyle(color: cs.outline, fontSize: 12)),
                      ]),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          Glass(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const IconTile(icon: Icons.devices_rounded, color: Brand.blue, size: 40),
                const SizedBox(width: 12),
                const Expanded(child: Text('Faol seanslar', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))),
                IconButton(onPressed: () {
                  setState(() => _sessionsLoading = true);
                  _loadSessions();
                }, icon: Icon(Icons.refresh_rounded, color: cs.outline)),
              ]),
              const SizedBox(height: 4),
              if (_sessionsLoading && _sessions.isEmpty)
                const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator()))
              else
                for (final x in _sessions)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      Icon(x['kind'] == 'web' ? Icons.language_rounded : Icons.smartphone_rounded, color: x['current'] == true ? cs.primary : cs.outline),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text('${x['title']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
                            if (x['current'] == true) ...[const SizedBox(width: 8), StatusChip(tr('Shu qurilma'), cs.primary)],
                          ]),
                          Text([if ('${x['ip'] ?? ''}'.isNotEmpty) '${x['ip']}', _ago('${x['at']}')].where((e) => e.isNotEmpty).join(' · '), style: TextStyle(color: cs.outline, fontSize: 12)),
                        ]),
                      ),
                      if (x['current'] != true) IconButton(tooltip: tr('Seansni yopish'), onPressed: () => _revoke(x), icon: Icon(Icons.logout_rounded, color: cs.error, size: 20)),
                    ]),
                  ),
              if (_sessions.where((e) => e['current'] != true).isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _revokeOthers, icon: const Icon(Icons.phonelink_erase_rounded, size: 18), label: const Text('Boshqa hammasidan chiqish'))),
              ],
            ]),
          ),
          const SizedBox(height: 14),
          Glass(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [const IconTile(icon: Icons.translate, color: Brand.teal, size: 40), const SizedBox(width: 12), const Text('Til', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5))]),
              const SizedBox(height: 12),
              const LangSwitch(),
            ]),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: cs.error, side: BorderSide(color: cs.error.withValues(alpha: 0.5))),
              onPressed: () async {
                Navigator.of(context).pop();
                await widget.onLogout();
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Chiqish'),
            ),
          ),
        ],
      ),
    );
  }
}
