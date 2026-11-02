# SBOM and vulnerability watch — application

Card « SBOM : produire et exploiter l'inventaire des composants » (lot 22,
2 Nov 2026). Same register format as `sarcade-server` (OSV-Scanner
`osv-scanner.toml`). Goal: know in a few minutes whether an announced
vulnerability affects a version in service.

## 1. Inventory (SBOM) of each build

`tool/sbom.py` (Python standard library, no network) writes a CycloneDX 1.5
JSON file from what the build already produced. The CI runs it in the jobs
that build, as a step with `continue-on-error`: an SBOM problem never fails
a build, it only gives a warning.

| File | Content | Where |
|---|---|---|
| `sarcade-app.cdx.json` | Dart packages of `pubspec.lock` (pub.dev packages with version, `pkg:pub` purl and SHA-256; local plugins of `third_party/`; packages of the Flutter SDK), Flutter SDK and Dart SDK versions | artifact `sbom` of every run (pull requests included); attached to the `web-dev`, `windows-dev` and `android-dev` / `android-<branch>` pre-releases |
| `sarcade-app-android.cdx.json` | the above, plus the Maven libraries packaged in the APK (`:app` `releaseRuntimeClasspath`, plugins included: AndroidX, Firebase, Flutter embedding…) | artifact `sbom-android`; attached to `android-dev` / `android-<branch>` |
| `sarcade-app-ios.cdx.json` | the above, plus the pods of `ios/Podfile.lock` (Firebase, GoogleUtilities…) | artifact `sbom-ios` (TestFlight builds have no GitHub release) |

Covered for every platform: all Dart code (`pubspec.lock` is the same for
Android, iOS, Windows, Linux and web; the web build is that Dart code compiled
to JavaScript plus the Flutter engine, CanvasKit and skwasm, listed as the
Flutter SDK component).

Not covered:
- Windows: native libraries brought by plugins through CMake (for example the
  Firebase C++ SDK downloaded by `firebase_core`) and the Visual C++ runtime;
- Linux: system libraries (GTK, libsecret…) taken from the distribution;
- the Flutter engine is one component (version and engine revision), not its
  own third-party libraries (Skia, ICU…);
- local plugins of `third_party/` have no purl on purpose (an advisory on the
  pub.dev package of the same name must not match); their native code is
  covered through the Gradle and CocoaPods lists only.

Generate by hand (after `flutter pub get`):

```bash
python3 tool/sbom.py --out sbom/sarcade-app.cdx.json
```

## 2. Nightly check (`.github/workflows/sbom-nightly.yml`)

Every night at 02:41 UTC, and by hand (Actions › SBOM nightly check › Run
workflow, on any branch):

1. downloads the SBOMs attached to `web-dev`, `windows-dev` and `android-dev`
   (the versions in service);
2. builds the SBOM of the checked-out branch (`main` at night) and keeps its
   `pubspec.lock`, which OSV-Scanner also reads directly;
3. runs OSV-Scanner (Docker image `ghcr.io/google/osv-scanner`, version pinned
   in the workflow) on each file, with `--config osv-scanner.toml`;
4. `tool/osv_nightly.py issue` keeps **one** issue « Faille dans un
   composant » (label `security`) up to date:
   - a vulnerability not dismissed and no open issue: the issue is opened
     (GitHub e-mails those who watch the repository, the owner included);
   - the list changed: the issue text is replaced and a comment lists the new
     and the vanished vulnerabilities (another e-mail);
   - same list: nothing (no e-mail every night);
   - nothing left: a comment, then the issue is closed.

Token: the `GITHUB_TOKEN` of the workflow (`issues: write`); no secret. Pull
requests are never blocked by a vulnerability already present: the scan only
runs in this workflow.

Test (validation criterion of the card): Run workflow with « Essai : ajouter un
composant à faille connue » ticked adds a test SBOM with `log4j-core 2.14.1`
(Log4Shell): the issue opens, with `essai--sbom-test.cdx.json` in « Vue
dans ». The next run without the box closes it (if nothing else is found).

## 3. Register of dismissed vulnerabilities (`osv-scanner.toml`)

A vulnerability that does not affect SARCADE (« pas concerné, parce que… ») is
dismissed in `osv-scanner.toml` at the root of the repository, by a pull
request:

```toml
[[IgnoredVulns]]
id = "GHSA-xxxx-xxxx-xxxx"
ignoreUntil = 2027-05-01
reason = "Only the server part of the package is affected; SARCADE uses its client. Stéphane, 2 Nov 2026"
```

- `id`: as written in the issue (OSV, GHSA or CVE identifier);
- `reason`: required, why SARCADE is not affected, who decided, when;
- `ignoreUntil`: required, re-examination date. After it, OSV-Scanner reports
  the vulnerability again and the issue reopens.

The job `sbom-tools` of the CI and the nightly check refuse an entry without
`reason` or `ignoreUntil` (`python3 tool/osv_nightly.py check-config
osv-scanner.toml`); a date passed or due within 14 days gives a warning.

## Tests

```bash
python3 -m unittest discover -s tool -p "test_*.py"
```
