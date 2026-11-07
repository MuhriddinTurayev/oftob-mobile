import 'package:flutter/material.dart' hide Text;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../format.dart';
import '../l10n.dart';
import '../theme.dart';

/// Belgi nuqtasi: «Keldim» yoki «Ketdim» bosilgan joy
class CheckPoint {
  const CheckPoint({required this.label, required this.time, required this.lat, required this.lng, this.dist, this.acc});
  final String label;
  final String time;
  final double lat;
  final double lng;
  final num? dist;
  final num? acc;

  static CheckPoint? from(Map w, String pre, String label) {
    final lat = (w['${pre}_lat'] as num?)?.toDouble();
    final lng = (w['${pre}_lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return CheckPoint(label: label, time: '${w[pre] ?? ''}', lat: lat, lng: lng, dist: w['${pre}_dist'] as num?, acc: w['${pre}_acc'] as num?);
  }
}

/// Xodim qayerda belgilagani: xaritada nuqta(lar) va obyekt doirasi; Google xaritada ochish ham mumkin
Future<void> showCheckinMap(BuildContext context, {required String name, required List<CheckPoint> points, Map? site}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CheckinMap(name: name, points: points, site: site),
  );
}

class _CheckinMap extends StatelessWidget {
  const _CheckinMap({required this.name, required this.points, this.site});
  final String name;
  final List<CheckPoint> points;
  final Map? site;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sLat = (site?['lat'] as num?)?.toDouble();
    final sLng = (site?['lng'] as num?)?.toDouble();
    final radius = ((site?['radius'] as num?) ?? 150).toDouble();
    final sitePt = sLat != null && sLng != null ? LatLng(sLat, sLng) : null;
    final all = [for (final p in points) LatLng(p.lat, p.lng), ?sitePt];
    final h = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
        Text(tr('Qayerda belgilagani'), style: TextStyle(color: cs.outline)),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            height: (h * 0.42).clamp(240, 420),
            child: FlutterMap(
              options: MapOptions(
                initialCameraFit: all.length > 1 ? CameraFit.coordinates(coordinates: all, padding: const EdgeInsets.all(48), maxZoom: 17) : null,
                initialCenter: all.first,
                initialZoom: 16,
                maxZoom: 19,
              ),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'uz.oftob.oftob_mobile', maxZoom: 19),
                if (sitePt != null)
                  CircleLayer(circles: [
                    CircleMarker(point: sitePt, radius: radius, useRadiusInMeter: true, color: Brand.green.withValues(alpha: 0.18), borderColor: Brand.green, borderStrokeWidth: 2),
                  ]),
                MarkerLayer(markers: [
                  if (sitePt != null) Marker(point: sitePt, width: 30, height: 30, child: const Icon(Icons.apartment_rounded, color: Brand.green, size: 26)),
                  for (var i = 0; i < points.length; i++)
                    Marker(
                      point: LatLng(points[i].lat, points[i].lng),
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: Icon(Icons.location_on_rounded, size: 44, color: i == 0 ? cs.error : Colors.indigo, shadows: const [Shadow(blurRadius: 6, color: Colors.black38)]),
                    ),
                ]),
                const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap')]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < points.length; i++) _row(context, points[i], i == 0 ? cs.error : Colors.indigo, sitePt != null),
        if (sitePt == null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr("Obyekt joylashuvi belgilanmagan — masofa hisoblanmaydi. «Ish vaqti va joylashuv» bo'limida belgilang."), style: TextStyle(color: Colors.orange.shade800, fontSize: 12.5)),
          ),
      ]),
    );
  }

  Widget _row(BuildContext context, CheckPoint p, Color color, bool hasSite) {
    final cs = Theme.of(context).colorScheme;
    final d = p.dist;
    final r = ((site?['radius'] as num?) ?? 150);
    final on = d != null && d <= r + (p.acc ?? 0).clamp(0, 100);
    final where = d == null ? (hasSite ? '' : tr('masofa noma\'lum')) : (on ? '${tr('Obyektda')} · ${distLabel(d)}' : tr('Obyektdan :d uzoqda').replaceAll(':d', distLabel(d)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(Icons.location_on_rounded, color: color, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p.label}${p.time.isEmpty ? '' : ' · ${p.time}'}', style: const TextStyle(fontWeight: FontWeight.w800)),
            Text([if (where.isNotEmpty) where, if (p.acc != null) '± ${distLabel(p.acc!)}'].join(' · '),
                style: TextStyle(color: d != null && !on ? Colors.orange.shade800 : cs.outline, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
        TextButton.icon(
          onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${p.lat},${p.lng}'), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: const Text('Google xarita'),
        ),
      ]),
    );
  }
}
