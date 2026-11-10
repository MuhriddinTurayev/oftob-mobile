import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' as w show Text;

import 'l10n.dart';
import 'theme.dart';

/// Tanlash maydoni (DropdownButtonFormField o'rniga): bosilganda oddiy ochiladigan ro'yxat emas —
/// pastdan chiroyli varaq chiqadi (kartochkali qatorlar, tanlangani ✓, ko'p bo'lsa qidiruv).
/// API DropdownButtonFormField bilan bir xil: initialValue, items, onChanged, decoration.
class SheetDropdown<T> extends StatefulWidget {
  const SheetDropdown({
    super.key,
    this.initialValue,
    required this.items,
    this.onChanged,
    this.decoration = const InputDecoration(),
    this.isExpanded = true,
    this.isDense = false,
  });

  final T? initialValue;
  final List<DropdownMenuItem<T>>? items;
  final ValueChanged<T?>? onChanged;
  final InputDecoration decoration;
  final bool isExpanded;
  final bool isDense;

  @override
  State<SheetDropdown<T>> createState() => _SheetDropdownState<T>();
}

/// Qator matnini olish (qidiruv uchun): Text / w.Text / ichma-ich Row, Padding va h.k.
String _labelOf(Widget? w0) {
  if (w0 == null) return '';
  if (w0 is Text) return tr(w0.data);
  if (w0 is w.Text) return w0.data ?? w0.textSpan?.toPlainText() ?? '';
  if (w0 is Row) return w0.children.map(_labelOf).where((s) => s.isNotEmpty).join(' ');
  if (w0 is Column) return w0.children.map(_labelOf).where((s) => s.isNotEmpty).join(' ');
  if (w0 is Padding) return _labelOf(w0.child);
  if (w0 is Expanded) return _labelOf(w0.child);
  if (w0 is Flexible) return _labelOf(w0.child);
  if (w0 is SizedBox) return _labelOf(w0.child);
  if (w0 is Align) return _labelOf(w0.child);
  if (w0 is FittedBox) return _labelOf(w0.child);
  return '';
}

class _SheetDropdownState<T> extends State<SheetDropdown<T>> {
  late T? _v = widget.initialValue;

  @override
  void didUpdateWidget(covariant SheetDropdown<T> old) {
    super.didUpdateWidget(old);
    if (old.initialValue != widget.initialValue) _v = widget.initialValue;
  }

  List<DropdownMenuItem<T>> get _items => widget.items ?? const [];

  DropdownMenuItem<T>? get _selected => _items.where((i) => i.value == _v).firstOrNull;

  Future<void> _open() async {
    FocusScope.of(context).unfocus();
    final r = await showModalBottomSheet<_Pick<T>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _PickSheet<T>(title: widget.decoration.labelText ?? widget.decoration.hintText ?? '', items: _items, current: _v),
    );
    if (r == null || !mounted) return;
    HapticFeedback.selectionClick();
    setState(() => _v = r.value);
    widget.onChanged?.call(r.value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onChanged != null && _items.isNotEmpty;
    final sel = _selected;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: enabled ? _open : null,
      child: InputDecorator(
        isEmpty: sel == null,
        isFocused: false,
        decoration: widget.decoration.copyWith(
          enabled: enabled,
          isDense: widget.isDense || (widget.decoration.isDense ?? false),
          suffixIcon: widget.decoration.suffixIcon ?? Icon(Icons.unfold_more_rounded, color: enabled ? cs.primary : cs.outline),
        ),
        child: sel == null
            ? const SizedBox(height: 20)
            : DefaultTextStyle.merge(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
                child: Align(alignment: Alignment.centerLeft, child: sel.child),
              ),
      ),
    );
  }
}

class _Pick<T> {
  const _Pick(this.value);
  final T? value;
}

class _PickSheet<T> extends StatefulWidget {
  const _PickSheet({required this.title, required this.items, required this.current});

  final String title;
  final List<DropdownMenuItem<T>> items;
  final T? current;

  @override
  State<_PickSheet<T>> createState() => _PickSheetState<T>();
}

class _PickSheetState<T> extends State<_PickSheet<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    final search = widget.items.length > 8;
    final q = _q.trim().toLowerCase();
    final shown = q.isEmpty ? widget.items : widget.items.where((i) => _labelOf(i.child).toLowerCase().contains(q)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.82),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: w.Text(tr(widget.title), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            ),
          if (search)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(hintText: tr('Qidirish'), prefixIcon: const Icon(Icons.search_rounded), isDense: true),
              ),
            ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + mq.padding.bottom),
              itemCount: shown.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final it = shown[i];
                final on = it.value == widget.current;
                return Opacity(
                  opacity: it.enabled ? 1 : 0.45,
                  child: Glass(
                    radius: 16,
                    blur: false,
                    shadow: false,
                    tint: on ? cs.primary.withValues(alpha: 0.13) : null,
                    onTap: it.enabled ? () => Navigator.of(context).pop(_Pick<T>(it.value)) : null,
                    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                    child: Row(children: [
                      Expanded(
                        child: DefaultTextStyle.merge(
                          style: TextStyle(fontWeight: on ? FontWeight.w900 : FontWeight.w700, fontSize: 15, color: on ? cs.primary : cs.onSurface),
                          child: it.child,
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: on ? Icon(Icons.check_circle_rounded, key: const ValueKey(1), color: cs.primary) : Icon(Icons.circle_outlined, key: const ValueKey(0), color: cs.outline.withValues(alpha: 0.5)),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
