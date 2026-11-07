import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../l10n.dart';
import '../location.dart';
import '../theme.dart';

/// Tanlangan nuqta va radius
class PickedSite {
  const PickedSite(this.lat, this.lng, this.radius);
  final double lat;
  final double lng;
  final int radius;
}

/// «41.2775, 69.2177», Google/Yandex xarita havolasi (…@41.27,69.21… yoki ?q=41.27,69.21 yoki ll=69.21,41.27) → nuqta
LatLng? parseCoords(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  try {
    s = Uri.decodeFull(s);
  } catch (_) {}
  bool ok(double a, double b) => a.abs() <= 90 && b.abs() <= 180 && !(a == 0 && b == 0);
  // gradus-daqiqa-soniya: 41°16'39.2"N 69°13'03.9"E
  final d = RegExp(r'''(\d{1,3})\s*[°º:\s]\s*(\d{1,2})\s*['′:\s]\s*(\d{1,2}(?:[.,]\d+)?)\s*(?:"|″|'')?\s*([NSnsСЮсю])[\s,;]*(\d{1,3})\s*[°º:\s]\s*(\d{1,2})\s*['′:\s]\s*(\d{1,2}(?:[.,]\d+)?)\s*(?:"|″|'')?\s*([EWewВЗвз])''').firstMatch(s);
  if (d != null) {
    double v(int i) => double.parse(d.group(i)!) + double.parse(d.group(i + 1)!) / 60 + double.parse(d.group(i + 2)!.replaceAll(',', '.')) / 3600;
    final lat = v(1) * (RegExp('[SsЮю]').hasMatch(d.group(4)!) ? -1 : 1), lng = v(5) * (RegExp('[WwЗз]').hasMatch(d.group(8)!) ? -1 : 1);
    if (ok(lat, lng)) return LatLng(lat, lng);
  }
  // Google: belgining aniq nuqtasi (!3d…!4d…) ekran markazidan (@…) muhimroq
  final g = RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)').firstMatch(s);
  if (g != null) {
    final lat = double.parse(g.group(1)!), lng = double.parse(g.group(2)!);
    if (ok(lat, lng)) return LatLng(lat, lng);
  }
  // Yandex: ll=uzunlik,kenglik
  final y = RegExp(r'[?&]ll=(-?\d+(?:\.\d+)?)(?:%2C|,)(-?\d+(?:\.\d+)?)').firstMatch(s);
  if (y != null) {
    final lng = double.parse(y.group(1)!), lat = double.parse(y.group(2)!);
    if (ok(lat, lng)) return LatLng(lat, lng);
  }
  for (final re in [
    RegExp(r'@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)'),
    RegExp(r'[?&](?:q|query|daddr|destination)=(-?\d+(?:\.\d+)?)(?:%2C|,)\s*(-?\d+(?:\.\d+)?)'),
    RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)'),
    RegExp(r'^\s*(-?\d+(?:[.,]\d+)?)\s*[,; ]\s*(-?\d+(?:[.,]\d+)?)\s*$'),
  ]) {
    final m = re.firstMatch(s);
    if (m != null) {
      final lat = double.tryParse(m.group(1)!.replaceAll(',', '.')), lng = double.tryParse(m.group(2)!.replaceAll(',', '.'));
      if (lat != null && lng != null && ok(lat, lng)) return LatLng(lat, lng);
    }
  }
  return null;
}

/// Obyektni xaritada belgilash: xaritani suring — markazdagi nuqta obyekt bo'ladi; radius doira bilan ko'rinadi.
/// «Mening joyim» — telefon joylashuvi; «Koordinata» — raqam yoki xarita havolasi.
class MapPickerScreen extends StatefulWidget {
  const MapPickerScreen({super.key, required this.title, this.lat, this.lng, this.radius = 150});
  final String title;
  final double? lat;
  final double? lng;
  final int radius;

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _map = MapController();
  late LatLng _center = widget.lat != null && widget.lng != null ? LatLng(widget.lat!, widget.lng!) : const LatLng(41.311081, 69.240562);
  late double _radius = widget.radius.toDouble().clamp(30, 1000);
  bool _sat = false, _busy = false;

  void _go(LatLng p, {double zoom = 17}) {
    setState(() => _center = p);
    _map.move(p, zoom);
  }

  Future<void> _mine() async {
    setState(() => _busy = true);
    final r = await currentFix();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.fix == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.error ?? '')));
      return;
    }
    _go(LatLng(r.fix!.lat, r.fix!.lng));
  }

  Future<void> _enter() async {
    final c = TextEditingController(text: '${_center.latitude.toStringAsFixed(6)}, ${_center.longitude.toStringAsFixed(6)}');
    String? err;
    final p = await showDialog<LatLng>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Koordinata yoki havola'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("Masalan: 41.277548, 69.217751 yoki 41°16'39.2\"N 69°13'03.9\"E — yoki Google/Yandex xaritadagi joy havolasini qo'ying.", style: TextStyle(color: Theme.of(ctx).colorScheme.outline, fontSize: 13)),
            const SizedBox(height: 10),
            TextField(controller: c, autofocus: true, minLines: 1, maxLines: 3, decoration: InputDecoration(hintText: '41.277548, 69.217751', errorText: err)),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final d = await Clipboard.getData('text/plain');
                  if (d?.text != null) set(() => c.text = d!.text!);
                },
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: const Text("Qo'yish"),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Bekor qilish')),
            FilledButton(
              onPressed: () {
                final v = parseCoords(c.text);
                if (v == null) {
                  set(() => err = tr('Koordinata topilmadi'));
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: const Text("Ko'rsatish"),
            ),
          ],
        ),
      ),
    );
    if (p != null) _go(p);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: tr('Sun\'iy yo\'ldosh'), onPressed: () => setState(() => _sat = !_sat), icon: Icon(_sat ? Icons.map_rounded : Icons.satellite_alt_rounded)),
        ],
      ),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _center,
            initialZoom: widget.lat != null ? 17 : 12,
            maxZoom: 19,
            onPositionChanged: (pos, _) => setState(() => _center = pos.center),
          ),
          children: [
            TileLayer(
              urlTemplate: _sat
                  ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'uz.oftob.oftob_mobile',
              maxZoom: 19,
            ),
            CircleLayer(circles: [
              CircleMarker(point: _center, radius: _radius, useRadiusInMeter: true, color: Brand.green.withValues(alpha: 0.18), borderColor: Brand.green, borderStrokeWidth: 2),
            ]),
            RichAttributionWidget(attributions: [TextSourceAttribution(_sat ? 'Esri' : 'OpenStreetMap')]),
          ],
        ),
        // markazdagi nuqta — xaritani suring
        IgnorePointer(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 44),
              child: Icon(Icons.location_on_rounded, size: 48, color: cs.error, shadows: const [Shadow(blurRadius: 8, color: Colors.black38)]),
            ),
          ),
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Column(children: [
            FloatingActionButton.small(heroTag: 'mine', onPressed: _busy ? null : _mine, child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location_rounded)),
            const SizedBox(height: 8),
            FloatingActionButton.small(heroTag: 'coords', onPressed: _enter, child: const Icon(Icons.edit_location_alt_rounded)),
          ]),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 16,
          child: SafeArea(
            top: false,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(20),
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1C2421) : Colors.white,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("Xaritani suring — qizil nuqta obyekt joyi bo'ladi", style: TextStyle(color: cs.outline, fontSize: 12.5)),
                  const SizedBox(height: 2),
                  Text('${_center.latitude.toStringAsFixed(6)}, ${_center.longitude.toStringAsFixed(6)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Row(children: [
                    Text('${tr('Radius')}: ${_radius.round()} m', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Expanded(child: Slider(value: _radius, min: 30, max: 1000, divisions: 97, onChanged: (v) => setState(() => _radius = v))),
                  ]),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        Navigator.pop(context, PickedSite(_center.latitude, _center.longitude, _radius.round()));
                      },
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Shu joyni saqlash'),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
