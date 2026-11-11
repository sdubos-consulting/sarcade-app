/// « Garder sur ce téléphone » in the panel « Carte » (card « Cartes hors
/// connexion sur le téléphone », validated on 9 Nov 2026, choice 3): the
/// zone of the offline package of the base map in use is taken from the
/// SARCADE server and kept on the device; Wi-Fi only unless the person
/// accepts the mobile network; size shown before; « Supprimer » frees it.
///
/// Card « Cartes hors connexion : téléchargement trop long, choisir la
/// finesse, voir la place prise, purger » (10 and 11 Nov 2026): the level
/// (Aperçu … Expert, Terrain by default) and the zone are chosen first,
/// with the estimated size of each level ([KeepPlan]); the room taken is
/// shown for this base map and for all; « Effacer » and « Tout effacer »
/// ask first.
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../access/access_manager.dart';
import '../../l10n/strings.dart';
import 'basemap_models.dart';
import 'keep_plan.dart';
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

/// Preferences of the device where the plan of each base map is kept.
typedef KeepPrefs = ({String? Function(String key) read, Future<void> Function(String key, String? value) save});

String keepPlanKey(String basemap) => 'keep_plan:$basemap';

class KeepOnPhoneTile extends StatefulWidget {
  final Basemap basemap;
  final String serverUrl;
  /// Network type, replaceable in the tests.
  final Future<bool> Function()? onWifi;
  /// Plan kept per base map; without it, the plan lives as long as the
  /// panel.
  final KeepPrefs? prefs;
  /// Zone of the map on screen (west, south, east, north), my position and
  /// the centre of the map, for the zones and the « détail local ».
  final List<double>? Function()? view;
  final ({double lat, double lon})? me, centre;
  /// Every base map, for the room taken by all and « Tout effacer ».
  final List<Basemap> all;
  /// Replaceable in the tests.
  final TileKeeper? keeper;
  const KeepOnPhoneTile({super.key, required this.basemap, required this.serverUrl, this.onWifi, this.prefs, this.view,
    this.me, this.centre, this.all = const [], this.keeper});
  @override
  State<KeepOnPhoneTile> createState() => _KeepOnPhoneTileState();
}

class _KeepOnPhoneTileState extends State<KeepOnPhoneTile> {
  ({int files, int bytes})? _usage;
  int _allBytes = 0;
  KeepPlan? _plan;
  late final keeper = widget.keeper ?? TileKeeper.instance;

  @override
  void initState() {
    super.initState();
    _plan = KeepPlan.decode(widget.prefs?.read(keepPlanKey(widget.basemap.id)));
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

  List<Basemap> get _others => [for (final b in widget.all) if (b.id != widget.basemap.id) b];

  Future<void> _refresh() async {
    final f = keeper.files;
    final u = await f?.usage(TileShelf.kept, widget.basemap.id);
    var all = u?.bytes ?? 0;
    for (final b in _others) {
      all += (await f?.usage(TileShelf.kept, b.id))?.bytes ?? 0;
    }
    if (mounted) setState(() {_usage = u; _allBytes = all;});
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

  /// Images of the plan, or of the whole package (kept before the levels).
  int _total(OfflinePackage p) => _plan == null ? packageTileCount(p) : partsTileCount(_plan!.parts(p));

  Future<void> _choose() async {
    final plan = await showKeepPlanSheet(context, package: widget.basemap.package!, current: _plan,
        view: widget.view?.call(), me: widget.me, centre: widget.centre);
    if (plan == null || !mounted) return;
    // Another plan: what was kept before is freed first, so that a lighter
    // level really takes less room.
    if (_plan?.encode() != plan.encode() && (_usage?.files ?? 0) > 0) {
      await keeper.files?.clear(TileShelf.kept, widget.basemap.id);
    }
    _plan = plan;
    await widget.prefs?.save(keepPlanKey(widget.basemap.id), plan.encode());
    await _keep();
  }

  Future<void> _keep() async {
    final p = widget.basemap.package!;
    final plan = _plan;
    final count = _total(p);
    if (!await _wifi()) {
      if (!mounted) return;
      final go = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
        title: Text(S.t('keep.noWifiTitle')),
        content: Text(S.t('keep.noWifiBody', {'size': sizeLabel(estimatedBytes(p, count))})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(S.t('common.cancel'))),
          FilledButton(key: const ValueKey('keep-mobile-ok'), onPressed: () => Navigator.pop(c, true), child: Text(S.t('keep.anyway'))),
        ]));
      if (go != true) return;
    }
    final failed = await keeper.keep(widget.basemap, widget.serverUrl,
        headers: AccessManager.instance.headersFor(Uri.parse(widget.serverUrl)),
        tiles: plan == null ? null : partsTiles(plan.parts(p)), count: count);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(
        failed > 0 ? S.t('keep.partial', {'n': '$failed'}) : S.t('keep.done'))));
  }

  Future<bool> _confirm(String title, String body) async => await showDialog<bool>(context: context, builder: (c) => AlertDialog(
    title: Text(title), content: Text(body),
    actions: [
      TextButton(onPressed: () => Navigator.pop(c, false), child: Text(S.t('common.cancel'))),
      FilledButton(key: const ValueKey('keep-erase-ok'), onPressed: () => Navigator.pop(c, true), child: Text(S.t('keep.erase'))),
    ])) == true;

  Future<void> _delete() async {
    if (!await _confirm(S.t('keep.eraseTitle'), S.t('keep.eraseBody', {'name': widget.basemap.name, 'size': sizeLabel(_usage?.bytes ?? 0)}))) return;
    await keeper.files?.clear(TileShelf.kept, widget.basemap.id);
    await _refresh();
  }

  Future<void> _deleteAll() async {
    if (!await _confirm(S.t('keep.eraseAllTitle'), S.t('keep.eraseAllBody', {'size': sizeLabel(_allBytes)}))) return;
    for (final b in [widget.basemap, ..._others]) {
      await keeper.files?.clear(TileShelf.kept, b.id);
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.basemap.package!;
    final t = Theme.of(context), s = t.colorScheme;
    final total = _total(p);
    final running = keeper.running == widget.basemap.id;
    final u = _usage;
    final kept = u != null && u.files > 0;
    final complete = kept && u.files >= total;
    final level = _plan?.level;
    final String subtitle;
    if (running) {
      subtitle = S.t('keep.progress', {'done': '${keeper.done}', 'total': '${keeper.total}'});
    } else if (complete) {
      subtitle = level == null
          ? S.t('keep.kept', {'size': sizeLabel(u.bytes), 'zoom': '${p.maxZoom}'})
          : S.t('keep.keptLevel', {'size': sizeLabel(u.bytes), 'level': S.t('keep.level.${level.name}')});
    } else if (kept) {
      subtitle = S.t('keep.incomplete', {'pct': '${(u.files * 100 / total).floor().clamp(0, 99)}', 'size': sizeLabel(u.bytes)});
    } else {
      subtitle = S.t('keep.chooseOffer');
    }
    final others = _allBytes - (u?.bytes ?? 0);
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
            if (kept && !complete)
              TextButton(key: const ValueKey('keep-start'), onPressed: keeper.busy ? null : _keep, child: Text(S.t('keep.resume')))
            else
              TextButton(key: const ValueKey('keep-choose'), onPressed: keeper.busy ? null : _choose,
                  child: Text(S.t(kept ? 'keep.change' : 'keep.start'))),
            if (kept)
              IconButton(key: const ValueKey('keep-delete'), tooltip: S.t('keep.delete'), onPressed: _delete,
                  icon: const Icon(Icons.delete_outline)),
          ],
        ]),
        if (running) Padding(padding: const EdgeInsets.only(top: 6, right: 8),
            child: LinearProgressIndicator(value: keeper.total == 0 ? null : keeper.done / keeper.total)),
        // Room taken (choice 3): this base map, and all of them when others
        // are kept too, with « Tout effacer » (choice 4).
        if (!running && others > 0) Padding(padding: const EdgeInsets.only(left: 36), child: Row(children: [
          Expanded(child: Text(S.t('keep.usedAll', {'size': sizeLabel(_allBytes)}), key: const ValueKey('keep-used-all'),
              style: t.textTheme.bodySmall?.copyWith(color: s.onSurfaceVariant))),
          TextButton(key: const ValueKey('keep-delete-all'), onPressed: _deleteAll, child: Text(S.t('keep.eraseAll'))),
        ])),
      ]));
  }
}

/// Choice of the level and of the zone, with the estimated size of each
/// level for the zone chosen (complement of 11 Nov 2026). Returns the plan,
/// or null when cancelled.
Future<KeepPlan?> showKeepPlanSheet(BuildContext context, {required OfflinePackage package, KeepPlan? current,
    List<double>? view, ({double lat, double lon})? me, ({double lat, double lon})? centre}) {
  var level = keepLevelFor(current?.level ?? KeepLevel.fallback, package);
  var zone = current?.zone ?? KeepZoneKind.server;
  var detail = current?.detailAt != null;
  final detailAt = me ?? centre;
  KeepPlan? planOf(KeepLevel l, KeepZoneKind z) =>
      KeepPlan.of(package, level: l, zone: z, view: view, me: me, detailAt: detail ? detailAt : null);
  bool zoneOk(KeepZoneKind z) => planOf(level, z) != null;
  if (!zoneOk(zone)) zone = KeepZoneKind.server;
  return showModalBottomSheet<KeepPlan>(context: context, isScrollControlled: true, builder: (c) => StatefulBuilder(builder: (c, set) {
    final t = Theme.of(c);
    String size(KeepLevel l) {
      final plan = planOf(l, zone);
      return plan == null ? '—' : sizeLabel(estimatedBytes(package, partsTileCount(plan.parts(package))));
    }
    final chosen = planOf(level, zone);
    final canDetail = detailAt != null && level.zoom < localDetailZoom && package.maxZoom > level.zoom;
    return SafeArea(child: ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.85),
      child: ListView(shrinkWrap: true, key: const ValueKey('keep-plan'), children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text(S.t('keep.title'), style: t.textTheme.titleLarge)),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: Text(S.t('keep.levelTitle'), style: t.textTheme.titleSmall)),
        RadioGroup<KeepLevel>(groupValue: level, onChanged: (v) {if (v != null) set(() => level = v);}, child: Column(children: [
          for (final l in KeepLevel.values)
            RadioListTile<KeepLevel>(key: ValueKey('keep-level-${l.name}'), dense: true, value: l,
              enabled: keepLevelAvailable(l, package),
              title: Text(S.t('keep.level.${l.name}')),
              subtitle: Text(!keepLevelAvailable(l, package) ? S.t('keep.levelUnavailable')
                  : '${S.t('keep.levelHelp.${l.name}')} · ≈ ${size(l)}')),
        ])),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Text(S.t('keep.zoneTitle'), style: t.textTheme.titleSmall)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Wrap(spacing: 8, runSpacing: 4, children: [
          for (final z in KeepZoneKind.values)
            if (zoneOk(z) || z == KeepZoneKind.server)
              ChoiceChip(key: ValueKey('keep-zone-${z.name}'), label: Text(S.t('keep.zone.${z.name}')), selected: zone == z,
                onSelected: (_) => set(() => zone = z)),
        ])),
        if (canDetail)
          SwitchListTile(key: const ValueKey('keep-detail'), value: detail, onChanged: (v) => set(() => detail = v),
            title: Text(S.t('keep.localDetail')),
            subtitle: Text(S.t(me != null ? 'keep.localDetailMe' : 'keep.localDetailCentre'))),
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(S.t('common.cancel'))),
          const SizedBox(width: 8),
          FilledButton(key: const ValueKey('keep-go'), onPressed: chosen == null ? null : () => Navigator.pop(c, chosen),
            child: Text(S.t('keep.go', {'size': size(level)}))),
        ])),
      ])));
  }));
}
