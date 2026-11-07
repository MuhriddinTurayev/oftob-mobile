import 'dart:io';

import 'package:flutter/material.dart' hide Text;

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'upload.dart';
import 'session.dart';
import 'l10n.dart';

/// Shartnoma yoki chek PDF'ini serverdan (shaxsiy kalit bilan) yuklab, telefondagi PDF ko'rgichda ochadi
/// yoki ulashish oynasini ko'rsatadi (Telegram, pochta va h.k. orqali xaridorga yuborish uchun).
/// [kind]: 'contract' | 'receipt' ([id] — to'lov raqami).
Future<void> openDocument(
  BuildContext context,
  Session session, {
  required String objectId,
  required String apartmentId,
  required String kind,
  String? id,
  required String fileName,
  bool share = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  try {
    final bytes = await runUpload(context, title: tr('Hujjat yuklanmoqda'), download: true, task: (p) => session.api!.downloadDocument(objectId, apartmentId, kind, id: id, onProgress: p));
    final dir = await getTemporaryDirectory();
    final safe = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File('${dir.path}/$safe.pdf');
    await file.writeAsBytes(bytes, flush: true);
    if (share) {
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')], text: fileName));
      return;
    }
    final res = await OpenFilex.open(file.path, type: 'application/pdf');
    if (res.type != ResultType.done) {
      // PDF ko'rgich yo'q bo'lsa — ulashish oynasi orqali ochiladi / saqlanadi
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')], text: fileName));
    }
  } catch (e) {
    await session.handleError(e);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$e')));
  }
}
