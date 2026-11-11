import 'package:flutter/material.dart';
// Flutter now has its own appBuildNumber: only the clipboard from here.
import 'package:flutter/services.dart' show Clipboard, ClipboardData, rootBundle;
import 'package:url_launcher/url_launcher.dart';
import '../../config/version.dart';
import '../../l10n/strings.dart';
import '../basemaps/basemap_models.dart';
import '../basemaps/basemap_sheet.dart' show basemapNotices;
import '../../operations/event_settings.dart' show StoreRelease;
import '../../operations/version_state.dart';
import 'notifications_panel.dart' show VersionStatus;
import 'windows_update_box.dart';
import '../../ui/link_status.dart';

class SarcadeAboutPage extends StatelessWidget {
  const SarcadeAboutPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: LinkedAppBar(title: Text(S.t('about.title'))),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: ListView(padding: const EdgeInsets.all(20), children: const [SarcadeAboutContent()]),
    ))),
  );
}

/// Address that receives « Signaler un problème » (already public on the
/// Play listing; card « Téléchargements servis par le serveur SARCADE »).
const aboutFeedbackEmail = 'github@sdubos.com';
/// Privacy policy of the GitHub pages, frozen since 6 Nov 2026: used only
/// without a SARCADE server (its /confidentialite otherwise).
const aboutPrivacyFallback = 'https://sdubos-consulting.github.io/sarcade-app/confidentialite/';

/// « https://sarcade.example/telechargements » for the server of the
/// session, null without a valid http(s) server.
String? serverPageUrl(String? serverUrl, String page) {
  final u = Uri.tryParse((serverUrl ?? '').trim());
  if (u == null || u.host.isEmpty || !(u.scheme == 'http' || u.scheme == 'https')) return null;
  final base = u.toString().replaceFirst(RegExp(r'/+$'), '');
  return '$base/$page';
}

/// E-mail of « Signaler un problème », with the version and the build.
String aboutFeedbackMailto({String version = appVersion, String build = appBuild, String number = appBuildNumber}) {
  final v = number.isEmpty ? version : '$version ($number)';
  final subject = 'SARCADE $v : problème ou suggestion';
  final body = '\n\n---\nSARCADE $v${build.isEmpty ? '' : ' · $build'}';
  return Uri(scheme: 'mailto', path: aboutFeedbackEmail,
      query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}').toString();
}

/// Text of the licence of the application (file LICENSE, in the assets),
/// shown in the application (no link to GitHub any more).
class AboutLicencePage extends StatelessWidget {
  const AboutLicencePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(S.t('about.licenseShort'))),
    body: SafeArea(child: FutureBuilder<String>(
      future: rootBundle.loadString('LICENSE'),
      builder: (context, snap) => snap.hasData
          ? SingleChildScrollView(padding: const EdgeInsets.all(16), child: SelectableText(snap.data!,
              key: const ValueKey('about-licence-text'), style: const TextStyle(fontFamily: 'monospace', fontSize: 12)))
          : Center(child: snap.hasError ? Text(S.t('about.licenceMissing')) : const CircularProgressIndicator()),
    )),
  );
}

/// Content of « À propos », shown in its page and in the Settings tab.
class SarcadeAboutContent extends StatelessWidget {
  /// Server of the session: « Télécharger et code source » and the privacy
  /// policy are its pages (/telechargements, /confidentialite).
  final String? serverUrl;
  const SarcadeAboutContent({super.key, this.serverUrl});

  Future<void> _open(BuildContext context, String url) async {
    bool opened;
    try {
      opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('about.linkFailed'))));
    }
  }

  /// One link (card « À propos : liens avec chevron et adresse », lot
  /// 29.4): the whole line touchable, the site in small grey under the
  /// title, « › »; no square « external link » icon any more.
  Widget _link(BuildContext context, IconData icon, String label, String url, {String? site, VoidCallback? onTap, Key? key}) {
    final s = Theme.of(context).colorScheme;
    return ListTile(
      key: key,
      dense: true, visualDensity: const VisualDensity(vertical: -2), contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(S.t(label), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(site ?? linkSite(url), style: TextStyle(color: s.onSurfaceVariant)),
      trailing: Icon(Icons.chevron_right, color: s.onSurfaceVariant),
      onTap: onTap ?? () => _open(context, url),
    );
  }

  /// « Version 0.1.0 (2003) · À jour », copied with the build and the
  /// reference version on a touch.
  Widget _versionLine(BuildContext context) {
    final t = Theme.of(context);
    final version = aboutVersionLine();
    final details = [
      S.t('about.version', {'version': appVersion}),
      if (appBuild.isNotEmpty) S.t('about.build', {'build': appBuild}),
      S.t('version.referenceLine', {'ref': appReference()}),
      S.t('about.publisher'),
    ].join('\n');
    return InkWell(key: const ValueKey('about-version'), borderRadius: BorderRadius.circular(8), onTap: () async {
      await Clipboard.setData(ClipboardData(text: details));
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.t('common.copied'))));
    }, child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: ValueListenableBuilder<StoreRelease?>(
      valueListenable: latestRelease, builder: (context, r, _) {
        final upToDate = VersionStatus.shown && r != null && !r.newerThan(appVersion, appBuildNumber);
        return Text(upToDate ? '$version · ${S.t('version.upToDate')}' : version, textAlign: TextAlign.center,
          style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant));
      })));
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Windows: « Mise à jour » box first (card « Windows : menu Mise à
        // jour », lot 25; SARCADE has no « Aide » menu bar).
        if (WindowsUpdateBox.shown) const Padding(padding: EdgeInsets.only(bottom: 16), child: WindowsUpdateBox()),
        // Top of the page (lot 29.4): logo of about 96 px, name and
        // description centred, one line for the version.
        Center(child: Image.asset(
          Theme.of(context).brightness == Brightness.dark ? 'assets/logo/sarcade-logo-dark.png' : 'assets/logo/sarcade-logo-light.png',
          height: 96, semanticLabel: 'SARCADE',
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        )),
        const SizedBox(height: 8),
        Text('SARCADE', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(S.t('about.descriptionShort'), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        _versionLine(context),
        // An update available: the line and its button (store).
        if (VersionStatus.shown) Center(child: ValueListenableBuilder<StoreRelease?>(valueListenable: latestRelease,
          builder: (context, r, _) => r != null && r.newerThan(appVersion, appBuildNumber) ? const VersionStatus() : const SizedBox.shrink())),
        const Divider(height: 24),
        _link(context, Icons.business_outlined, 'about.publisherShort', 'https://www.sdubos.com/'),
        // Card « Téléchargements servis par le serveur SARCADE » (9 Nov
        // 2026): no GitHub link any more (account suspended).
        if (serverPageUrl(serverUrl, 'telechargements') case final downloads?)
          _link(context, Icons.download_outlined, 'about.downloadsShort', downloads, key: const ValueKey('about-downloads')),
        _link(context, Icons.feedback_outlined, 'about.feedbackShort', aboutFeedbackMailto(), site: aboutFeedbackEmail,
            key: const ValueKey('about-feedback')),
        _link(context, Icons.privacy_tip_outlined, 'about.privacy', serverPageUrl(serverUrl, 'confidentialite') ?? aboutPrivacyFallback),
        _link(context, Icons.description_outlined, 'about.licenseShort', '', site: S.t('about.inApp'), key: const ValueKey('about-licence'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AboutLicencePage()))),
        ListTile(
          dense: true, visualDensity: const VisualDensity(vertical: -2), contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.favorite_outline),
          title: Text(S.t('about.creditsShort')),
          subtitle: Text(S.t('about.inApp'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
          onTap: () => showLicensePage(context: context, applicationName: 'SARCADE', applicationVersion: appVersion),
        ),
        // Licence notices of the base maps, also behind the ⓘ of the map
        // (card « Panneau Fond de carte », 30 Oct 2026, 1 h 35).
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.map_outlined),
          title: Text(S.t('about.mapNotices')),
          subtitle: Text(basemapNotices(builtInBasemaps).join('\n')),
        ),
      ]);
}

/// « github.com », « sdubos.com »: the site of a link, without « www. ».
String linkSite(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// « Version 0.1.0 (2003) »; the build number only when there is one.
String aboutVersionLine({String version = appVersion, String build = appBuildNumber}) =>
    build.isEmpty ? S.t('about.versionLine', {'version': version}) : S.t('about.versionLineBuild', {'version': version, 'build': build});
