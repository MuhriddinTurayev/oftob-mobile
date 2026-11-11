import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../keyboard.dart';
import '../api.dart';
import '../format.dart';
import '../l10n.dart';
import '../sheet_select.dart';
import '../session.dart';
import '../theme.dart';
import '../upload.dart';
import '../widgets.dart';

/// Ish jurnali va fotohisobotlar — saytdagi «Журнал и фотоотчёты» bilan bir xil yozuvlar
/// (prorab ilovadan, saytdan yoki Telegram-botdan yuboradi; rahbar shu yerda ham, saytda ham ko'radi).
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key, required this.session});

  final Session session;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final _list = GlobalKey<PagedListState>();
  List<Map<String, dynamic>> _objects = const [];
  String? _object; // filtr: null — hamma obyektlar

  Session get s => widget.session;
  bool get _canWrite => s.me!.can('journal:write');

  @override
  void initState() {
    super.initState();
    s.api!.objects().then((o) {
      if (mounted) setState(() => _objects = o);
    }).catchError((Object e) async {
      await s.handleError(e);
    });
  }

  Future<void> _new() async {
    if (_objects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Obyektlar yuklanmoqda — biroz kuting'))));
      return;
    }
    final ok = await Navigator.of(context).push<bool>(DeskRoute(builder: (_) => _NewReport(session: s, objects: _objects, initial: _object)));
    if (ok == true) _list.currentState?.reload();
  }

  Future<void> _delete(Map<String, dynamic> x) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Yozuvni o'chirish"),
        content: const Text("Yozuv suratlari bilan birga o'chiriladi."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Bekor qilish')),
          FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error), child: const Text("O'chirish")),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await s.api!.journalDelete(x['id'] as int);
      _list.currentState?.reload();
    } catch (e) {
      await s.handleError(e);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : '$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(children: [
      Column(children: [
        if (_objects.length > 1)
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: Text(tr('Hamma obyektlar')), selected: _object == null, showCheckmark: false, onSelected: (_) {
                    setState(() => _object = null);
                    WidgetsBinding.instance.addPostFrameCallback((_) => _list.currentState?.reload());
                  }),
                ),
                for (final o in _objects)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(label: Text('${o['name']}'), selected: _object == '${o['id']}', showCheckmark: false, onSelected: (_) {
                      setState(() => _object = '${o['id']}');
                      WidgetsBinding.instance.addPostFrameCallback((_) => _list.currentState?.reload());
                    }),
                  ),
              ],
            ),
          ),
        Expanded(
          child: PagedList(
            key: _list,
            session: s,
            emptyText: "Fotohisobotlar hali yo'q",
            fetch: (p) => s.api!.journal(page: p, object: _object),
            itemBuilder: (context, x) {
              final n = (x['photos'] as num?)?.toInt() ?? 0;
              final author = (x['author'] as Map?)?['name'];
              final when = '${x['created_at'] ?? ''}';
              final t = DateTime.tryParse(when)?.toLocal();
              final hm = t == null ? '' : ' ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Glass(
                  radius: 20,
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      CircleAvatar(radius: 18, backgroundColor: Brand.green.withValues(alpha: 0.14), foregroundColor: Brand.green, child: Text('$author'.isEmpty ? '?' : '$author'[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${author ?? '—'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(
                            [formatDate('${x['date']}') + hm, if (x['object'] != null) '${x['object']}', if (x['place'] != null) '📍 ${x['place']}'].join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: cs.outline, fontSize: 12.5),
                          ),
                        ]),
                      ),
                      if (x['can_edit'] == true && _canWrite)
                        IconButton(tooltip: tr("O'chirish"), visualDensity: VisualDensity.compact, onPressed: () => _delete(x), icon: Icon(Icons.delete_outline_rounded, color: cs.outline)),
                    ]),
                    if ('${x['text'] ?? ''}'.trim().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('${x['text']}', style: const TextStyle(fontSize: 14.5))),
                    if (n > 0) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 110,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: n,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, i) => GestureDetector(
                            onTap: () => Navigator.of(context).push(DeskRoute<void>(builder: (_) => _PhotoView(api: s.api!, id: x['id'] as int, count: n, start: i))),
                            child: ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(width: 110, height: 110, child: _Pic(api: s.api!, id: x['id'] as int, i: i, fit: BoxFit.cover))),
                          ),
                        ),
                      ),
                    ],
                  ]),
                ),
              );
            },
          ),
        ),
      ]),
      if (_canWrite)
        Positioned(
          right: 16,
          bottom: NavInset.listBottom(context) - 40,
          child: FloatingActionButton.extended(
            heroTag: 'journal-new',
            onPressed: _new,
            icon: const Icon(Icons.add_a_photo_rounded),
            label: const Text('Fotohisobot'),
          ),
        ),
    ]);
  }
}

class _Pic extends StatelessWidget {
  const _Pic({required this.api, required this.id, required this.i, this.fit});
  final ApiClient api;
  final int id;
  final int i;
  final BoxFit? fit;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>?>(
      future: api.journalBytes(id, i),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
        final b = snap.data;
        if (b == null) return Container(color: Colors.black12, child: const Icon(Icons.broken_image_outlined, color: Colors.grey));
        return Image.memory(Uint8List.fromList(b), fit: fit ?? BoxFit.contain, width: double.infinity, height: double.infinity);
      },
    );
  }
}

class _PhotoView extends StatelessWidget {
  const _PhotoView({required this.api, required this.id, required this.count, required this.start});
  final ApiClient api;
  final int id;
  final int count;
  final int start;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Fotohisobot')),
      body: PageView.builder(
        controller: PageController(initialPage: start),
        itemCount: count,
        itemBuilder: (_, i) => InteractiveViewer(maxScale: 6, child: Center(child: _Pic(api: api, id: id, i: i))),
      ),
    );
  }
}

/// Yangi fotohisobot: obyekt, qavat (ixtiyoriy), nima qilindi, suratlar (1..10)
class _NewReport extends StatefulWidget {
  const _NewReport({required this.session, required this.objects, this.initial});
  final Session session;
  final List<Map<String, dynamic>> objects;
  final String? initial;

  @override
  State<_NewReport> createState() => _NewReportState();
}

class _NewReportState extends State<_NewReport> {
  late String _object = widget.initial ?? '${widget.objects.first['id']}';
  final _text = TextEditingController();
  final _floor = TextEditingController();
  final _photos = <XFile>[];
  bool _busy = false;
  String? _err;

  @override
  void dispose() {
    _text.dispose();
    _floor.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource src) async {
    try {
      if (src == ImageSource.camera) {
        final f = await ImagePicker().pickImage(source: src, maxWidth: 1900, imageQuality: 80);
        if (f != null) setState(() => _photos.add(f));
      } else {
        final l = await ImagePicker().pickMultiImage(maxWidth: 1900, imageQuality: 80);
        setState(() => _photos.addAll(l.take(10 - _photos.length)));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr("Suratni ochib bo'lmadi. Ilovaga kamera/galereya ruxsatini bering."))));
    }
  }

  Future<void> _send() async {
    if (_photos.isEmpty) return setState(() => _err = tr("Kamida bitta surat qo'shing"));
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await runUpload<Map<String, dynamic>>(context,
          title: tr('Fotohisobot yuborilmoqda'),
          task: (p) => widget.session.api!.journalAdd(object: _object, text: _text.text, floor: int.tryParse(_floor.text.trim()), photos: [for (final f in _photos) f.path], onProgress: p));
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Fotohisobot yuborildi — rahbar ko\'radi'))));
      Navigator.pop(context, true);
    } catch (e) {
      await widget.session.handleError(e);
      if (mounted) setState(() => _err = e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Fotohisobot')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          if (widget.objects.length > 1)
            SheetDropdown<String>(
              initialValue: _object,
              isExpanded: true,
              decoration: InputDecoration(labelText: tr('Qaysi obyekt')),
              items: [for (final o in widget.objects) DropdownMenuItem(value: '${o['id']}', child: Text('${o['name']}', maxLines: 1, overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _object = v ?? _object),
            )
          else
            Text('${tr('Obyekt')}: ${widget.objects.first['name']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(controller: _floor, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: InputDecoration(labelText: tr('Qavat (ixtiyoriy)'))),
          const SizedBox(height: 12),
          TextField(controller: _text, minLines: 2, maxLines: 6, maxLength: 2000, decoration: InputDecoration(labelText: tr('Nima qilindi'), hintText: tr("masalan: 3-qavat devorlari terildi, armatura bog'landi"))),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: Text('Suratlar', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            Text('${_photos.length}/10', style: TextStyle(color: cs.outline, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          if (_photos.isNotEmpty)
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (var i = 0; i < _photos.length; i++)
                  Stack(fit: StackFit.expand, children: [
                    ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(_photos[i].path), fit: BoxFit.cover)),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: GestureDetector(
                        onTap: () => setState(() => _photos.removeAt(i)),
                        child: Container(decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), padding: const EdgeInsets.all(4), child: const Icon(Icons.close, color: Colors.white, size: 16)),
                      ),
                    ),
                  ]),
              ],
            ),
          if (_photos.length < 10) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera), label: const Text('Kamera'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(onPressed: () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('Galereya'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)))),
            ]),
          ],
        ],
      ),
      bottomNavigationBar: KeyboardLift(child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_err != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_err!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w700))),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _busy ? null : _send,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4)) : const Icon(Icons.send_rounded),
                label: const Text('Rahbarga yuborish'),
              ),
            ),
          ]),
        ),
      )),
    );
  }
}
