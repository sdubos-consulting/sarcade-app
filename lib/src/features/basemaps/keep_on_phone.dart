/// « Garder sur ce téléphone » in the panel « Carte » (card « Cartes hors
/// connexion sur le téléphone », validated on 9 Nov 2026, choice 3): the
/// zone of the offline package of the base map in use is taken from the
/// SARCADE server and kept on the device; Wi-Fi only unless the person
/// accepts the mobile network; size shown before; « Supprimer » frees it.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../access/access_manager.dart';
import '../../l10n/strings.dart';
import 'basemap_models.dart';
import 'offline_tiles.dart';
import 'tile_files.dart';

/// « 512 Mo », « 1,2 Go ».
String sizeLabel(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1).replaceAll('.', S.lang == 'fr' ? ',' : '.')} ${S.t('size.gb')}';
  }
  return '${(bytes / (1024 * 1024)).round()} ${S.t('size.mb')}';
}

/// Shown only when the base map has a package with a known zone.
bool canKeepOnPhone(Basemap b) => !kIsWeb && b.package != null && b.package!.keepable && TileFiles.instance != null;

class KeepOnPhoneTile extends StatefulWidget {
  final Basemap basemap;
  final String serverUrl;
  /// Network type, replaceable in the tests.
  final Future<bool> Function()? onWifi;
  const KeepOnPhoneTile({super.key, required this.basemap, required this.serverUrl, this.onWifi});
  @override
  State<KeepOnPhoneTile> createState() => _KeepOnPhoneTileState();
}

class _KeepOnPhoneTileState extends State<KeepOnPhoneTile> {
  ({int files, int bytes})? _usage;
  final keeper = TileKeeper.instance;

  @override
  void initState() {
    super.initState();
    keeper.addListener(_changed);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    keeper.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (!keeper.busy) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final u = await keeper.files?.usage(TileShelf.kept, widget.basemap.id);
    if (mounted) setState(() => _usage = u);
  }

  Future<bool> _wifi() async {
    if (widget.onWifi != null) return widget.onWifi!();
    try {
      final r = await Connectivity().checkConnectivity();
      return r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return true;
    }
  }

  Future<void> _keep() async {
    final p = widget.basemap.package!;
    if (!await _wifi()) {
      if (!mounted) return;
      final go = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: Text(S.t('keep.noWifiTitle')),
        content: Text(S.t('keep.noWifiBody', {'size': sizeLabel(p.sizeBytes)})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(S.t('common.cancel'))),
          FilledButton(key: const ValueKey('keep-mobile-ok'), onPressed: () => Navigator.pop(c, true), child: Text(S.t('keep.anyway'))),
        ]));
      if (go != true) return;
    }
    final failed = await keeper.keep(widget.basemap, widget.serverUrl,
        headers: AccessManager.instance.headersFor(Uri.parse(widget.serverUrl)));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(
        failed > 0 ? S.t('keep.partial', {'n': '$failed'}) : S.t('keep.done'))));
  }

  Future<void> _delete() async {
    await keeper.files?.clear(TileShelf.kept, widget.basemap.id);
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.basemap.package!;
    final t = Theme.of(context), s = t.colorScheme;
    final total = packageTileCount(p);
    final running = keeper.running == widget.basemap.id;
    final u = _usage;
    final kept = u != null && u.files > 0;
    final complete = kept && u.files >= total;
    final String subtitle;
    if (running) {
      subtitle = S.t('keep.progress', {'done': '${keeper.done}', 'total': '${keeper.total}'});
    } else if (complete) {
      subtitle = S.t('keep.kept', {'size': sizeLabel(u.bytes), 'zoom': '${p.maxZoom}'});
    } else if (kept) {
      subtitle = S.t('keep.incomplete', {'pct': '${(u.files * 100 / total).floor()}', 'size': sizeLabel(u.bytes)});
    } else {
      subtitle = S.t('keep.offer', {'size': sizeLabel(p.sizeBytes), 'zoom': '${p.maxZoom}'});
    }
    return Padding(key: const ValueKey('keep-on-phone'), padding: const EdgeInsets.fromLTRB(16, 4, 8, 4), child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(complete ? Icons.offline_pin : Icons.download_for_offline_outlined, color: complete ? s.primary : s.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(S.t(complete ? 'keep.titleKept' : 'keep.title'), style: t.textTheme.bodyLarge),
            Text(subtitle, key: const ValueKey('keep-status'), style: t.textTheme.bodySmall?.copyWith(color: s.onSurfaceVariant)),
          ])),
          if (running)
            TextButton(key: const ValueKey('keep-cancel'), onPressed: keeper.cancel, child: Text(S.t('common.cancel')))
          else ...[
            if (!complete)
              TextButton(key: const ValueKey('keep-start'), onPressed: keeper.busy ? null : _keep,
                  child: Text(S.t(kept ? 'keep.resume' : 'keep.start'))),
            if (kept)
              IconButton(key: const ValueKey('keep-delete'), tooltip: S.t('keep.delete'), onPressed: _delete,
                  icon: const Icon(Icons.delete_outline)),
          ],
        ]),
        if (running) Padding(padding: const EdgeInsets.only(top: 6, right: 8),
            child: LinearProgressIndicator(value: keeper.total == 0 ? null : keeper.done / keeper.total)),
      ]));
  }
}
