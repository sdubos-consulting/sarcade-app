#!/usr/bin/env python3
"""CycloneDX SBOM of the SARCADE application (card « SBOM : produire et
exploiter l'inventaire des composants », lot 22, point 1).

Python standard library only, no network: it reads what the build already
produced and writes a CycloneDX 1.5 JSON file.

- Dart packages: pubspec.lock (pub.dev packages with their SHA-256, the
  local plugins of third_party/, the packages of the Flutter SDK);
- Flutter and Dart SDK: ``flutter --version --machine`` (file);
- Android: ``gradlew :app:dependencies --configuration releaseRuntimeClasspath``
  (text output, file), the Maven libraries really packaged in the APK;
- iOS: ios/Podfile.lock (CocoaPods).

Never fails a build on its own: the CI steps run it with continue-on-error,
and an unreadable optional input only gives a warning.

    python3 tool/sbom.py --out sbom/sarcade-app.cdx.json \
        [--lock pubspec.lock] [--pubspec pubspec.yaml] [--platform web] \
        [--build main@abc1234] [--build-number 560] [--flutter-json flutter.json] \
        [--gradle-deps deps.txt] [--podfile-lock ios/Podfile.lock]
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
import uuid
from pathlib import Path

SPEC_VERSION = "1.5"
TOOL_NAME = "sarcade-sbom"
TOOL_VERSION = "1"
PUB_DEV = ("https://pub.dev", "https://pub.dartlang.org")


def warn(msg: str) -> None:
    print(f"::warning title=SBOM::{msg}", file=sys.stderr)


def _unquote(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def parse_pubspec_lock(text: str) -> dict[str, dict]:
    """Packages of a pubspec.lock (the file is generated: fixed layout).

    Returns {name: {"dependency", "source", "version", "description"}};
    ``description`` is a dict (hosted, git, path) or a string (sdk).
    """
    packages: dict[str, dict] = {}
    in_packages = False
    current: dict | None = None
    in_description = False
    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        line = raw.strip()
        if indent == 0:
            in_packages = line == "packages:"
            current = None
            continue
        if not in_packages:
            continue
        key, _, value = line.partition(":")
        key = _unquote(key)
        if indent == 2:
            current = {"description": {}}
            packages[key] = current
            in_description = False
        elif indent == 4 and current is not None:
            in_description = False
            if key == "description":
                if value.strip():
                    current["description"] = _unquote(value)
                else:
                    in_description = True
            else:
                current[key] = _unquote(value)
        elif indent >= 6 and current is not None and in_description:
            current["description"][key] = _unquote(value)
    return packages


def pubspec_version(text: str) -> str:
    m = re.search(r"^version:\s*([^\s#]+)", text, re.M)
    return _unquote(m.group(1)) if m else "0.0.0"


def parse_flutter_json(text: str) -> dict:
    """``flutter --version --machine`` (any banner before the JSON ignored)."""
    start = text.find("{")
    if start < 0:
        return {}
    try:
        return json.loads(text[start:text.rfind("}") + 1])
    except ValueError:
        return {}


# One line of the Gradle dependency tree, e.g.
#   +--- androidx.core:core:1.13.1 -> 1.15.0 (*)
#   |    \--- org.jetbrains.kotlin:kotlin-stdlib:{strictly 1.9.0} -> 1.9.0 (c)
#   +--- androidx.lifecycle:lifecycle-runtime -> 2.6.1
_GRADLE_LINE = re.compile(
    r"^[\s|+\\-]*---\s+"
    r"(?P<group>[\w.\-]+):(?P<artifact>[\w.\-]+)"
    r"(?::(?P<declared>\{[^}]*\}|[^\s]+))?"
    r"(?:\s+->\s+(?P<resolved>[^\s]+))?"
    r"(?:\s+\((?P<flag>[*cn])\))?\s*$")


def parse_gradle_deps(text: str) -> list[tuple[str, str, str]]:
    """Resolved Maven coordinates (group, artifact, version) of a Gradle tree.

    Constraints « (c) » and unresolved « (n) » entries are not dependencies.
    """
    seen: dict[tuple[str, str], str] = {}
    for raw in text.splitlines():
        m = _GRADLE_LINE.match(raw.rstrip())
        if not m or m.group("flag") in ("c", "n"):
            continue
        version = m.group("resolved") or m.group("declared") or ""
        if version.startswith("{"):
            inner = re.search(r"([\w.\-+]+)\s*\}$", version)
            version = inner.group(1) if inner else ""
        if not version:
            continue
        seen.setdefault((m.group("group"), m.group("artifact")), version)
    return sorted((g, a, v) for (g, a), v in seen.items())


def parse_podfile_lock(text: str) -> tuple[list[tuple[str, str]], set[str]]:
    """Pods (name, version) of a Podfile.lock and the names of local pods
    (« EXTERNAL SOURCES » with a :path:, i.e. Flutter and its plugins)."""
    pods: dict[str, str] = {}
    local: set[str] = set()
    section = ""
    external_name = ""
    for raw in text.splitlines():
        if not raw.strip():
            continue
        if not raw.startswith(" "):
            section = raw.strip().rstrip(":")
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        line = raw.strip()
        if section == "PODS" and indent == 2 and line.startswith("- "):
            entry = _unquote(line[2:].rstrip(":"))
            m = re.match(r"^(\S+)\s+\(([^)]+)\)$", entry)
            if m:
                name = m.group(1).split("/")[0]
                pods.setdefault(name, m.group(2))
        elif section == "EXTERNAL SOURCES":
            if indent == 2:
                external_name = _unquote(line.rstrip(":"))
            elif indent == 4 and line.startswith(":path:") and external_name:
                local.add(external_name.split("/")[0])
    return sorted(pods.items()), local


def _dart_component(name: str, pkg: dict, flutter_version: str) -> dict:
    source = pkg.get("source", "")
    version = pkg.get("version", "")
    desc = pkg.get("description")
    comp: dict = {"type": "library", "name": name, "version": version}
    props = [{"name": "sarcade:ecosystem", "value": "pub"},
             {"name": "sarcade:source", "value": source or "unknown"},
             {"name": "sarcade:dependency", "value": pkg.get("dependency", "")}]
    if source == "hosted" and isinstance(desc, dict):
        url = desc.get("url", "https://pub.dev").rstrip("/")
        purl = f"pkg:pub/{name}@{version}"
        if url not in PUB_DEV:
            purl += f"?repository_url={url}"
        comp["purl"] = purl
        if re.fullmatch(r"[0-9a-fA-F]{64}", desc.get("sha256", "")):
            comp["hashes"] = [{"alg": "SHA-256", "content": desc["sha256"]}]
        comp["externalReferences"] = [
            {"type": "distribution", "url": f"{url}/packages/{name}/versions/{version}"}]
    elif source == "path" and isinstance(desc, dict):
        # Local plugin (third_party/): part of this repository. No purl, so
        # an advisory on a pub.dev package of the same name never matches.
        props.append({"name": "sarcade:path", "value": desc.get("path", "")})
        comp["description"] = "Local package of this repository"
    elif source == "git" and isinstance(desc, dict):
        props.append({"name": "sarcade:git", "value":
                      f"{desc.get('url', '')}#{desc.get('resolved-ref', desc.get('ref', ''))}"})
    elif source == "sdk":
        comp["description"] = "Package of the Flutter SDK"
        if flutter_version and version in ("", "0.0.0"):
            comp["version"] = flutter_version
    if pkg.get("dependency") == "direct dev":
        comp["scope"] = "excluded"  # tests and lints: not in the application
    comp["bom-ref"] = comp.get("purl") or f"pub:{name}@{comp['version']}"
    comp["properties"] = props
    return comp


def build_sbom(*, lock_text: str, pubspec_text: str, platform: str = "",
               build: str = "", build_number: str = "", flutter: dict | None = None,
               gradle_text: str = "", podfile_text: str = "",
               now: dt.datetime | None = None, serial: str | None = None) -> dict:
    flutter = flutter or {}
    flutter_version = flutter.get("frameworkVersion", "")
    app_version = pubspec_version(pubspec_text)
    if build_number:  # same as the build: --build-number = CI run number
        app_version = app_version.split("+")[0] + "+" + build_number
    root_ref = "sarcade_app"
    root = {"type": "application", "bom-ref": root_ref, "name": "sarcade_app",
            "version": app_version,
            "description": "SARCADE application (Flutter)",
            "licenses": [{"license": {"id": "AGPL-3.0-only"}}],
            "externalReferences": [
                {"type": "vcs", "url": "https://github.com/sdubos-consulting/sarcade-app"}]}
    props = []
    if platform:
        props.append({"name": "sarcade:platform", "value": platform})
    if build:
        props.append({"name": "sarcade:build", "value": build})
    if props:
        root["properties"] = props

    components: list[dict] = []
    direct: list[str] = []
    for name, pkg in sorted(parse_pubspec_lock(lock_text).items()):
        comp = _dart_component(name, pkg, flutter_version)
        components.append(comp)
        if pkg.get("dependency", "").startswith("direct"):
            direct.append(comp["bom-ref"])

    if flutter_version:
        components.append({
            "type": "framework", "bom-ref": f"flutter-sdk@{flutter_version}",
            "name": "flutter", "group": "dev.flutter", "version": flutter_version,
            "description": "Flutter SDK (framework, engine; web: CanvasKit and skwasm)",
            "properties": [
                {"name": "sarcade:channel", "value": flutter.get("channel", "")},
                {"name": "sarcade:frameworkRevision", "value": flutter.get("frameworkRevision", "")},
                {"name": "sarcade:engineRevision", "value": flutter.get("engineRevision", "")}],
            "externalReferences": [{"type": "vcs", "url": "https://github.com/flutter/flutter"}]})
        direct.append(f"flutter-sdk@{flutter_version}")
    dart_version = (flutter.get("dartSdkVersion") or "").split(" ")[0]
    if dart_version:
        components.append({
            "type": "framework", "bom-ref": f"dart-sdk@{dart_version}",
            "name": "dart-sdk", "group": "dev.dart", "version": dart_version,
            "description": "Dart SDK (runtime and core libraries)",
            "externalReferences": [{"type": "vcs", "url": "https://github.com/dart-lang/sdk"}]})
        direct.append(f"dart-sdk@{dart_version}")

    for group, artifact, version in parse_gradle_deps(gradle_text):
        purl = f"pkg:maven/{group}/{artifact}@{version}"
        components.append({
            "type": "library", "bom-ref": purl, "group": group, "name": artifact,
            "version": version, "purl": purl,
            "properties": [{"name": "sarcade:ecosystem", "value": "maven"},
                           {"name": "sarcade:origin", "value": "android releaseRuntimeClasspath"}]})
        direct.append(purl)

    pods, local_pods = parse_podfile_lock(podfile_text)
    for name, version in pods:
        comp = {"type": "library", "name": name, "version": version,
                "properties": [{"name": "sarcade:ecosystem", "value": "cocoapods"}]}
        if name in local_pods:
            comp["bom-ref"] = f"pod:{name}@{version}"
            comp["description"] = "Native part of Flutter or of a Flutter plugin"
        else:
            comp["purl"] = comp["bom-ref"] = f"pkg:cocoapods/{name}@{version}"
        components.append(comp)
        direct.append(comp["bom-ref"])

    now = now or dt.datetime.now(dt.timezone.utc)
    return {
        "bomFormat": "CycloneDX",
        "specVersion": SPEC_VERSION,
        "serialNumber": f"urn:uuid:{serial or uuid.uuid4()}",
        "version": 1,
        "metadata": {
            "timestamp": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "tools": {"components": [{"type": "application", "name": TOOL_NAME,
                                      "version": TOOL_VERSION,
                                      "description": "tool/sbom.py of sarcade-app"}]},
            "component": root,
        },
        "components": components,
        "dependencies": [{"ref": root_ref, "dependsOn": sorted(set(direct))}],
    }


def _read(path: str | None, what: str, required: bool = False) -> str:
    if not path:
        return ""
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace")
    except OSError as e:
        if required:
            raise
        warn(f"{what} unreadable ({path}): {e}; left out of the SBOM")
        return ""


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--out", required=True)
    p.add_argument("--lock", default="pubspec.lock")
    p.add_argument("--pubspec", default="pubspec.yaml")
    p.add_argument("--platform", default="")
    p.add_argument("--build", default="")
    p.add_argument("--build-number", default="")
    p.add_argument("--flutter-json")
    p.add_argument("--gradle-deps")
    p.add_argument("--podfile-lock")
    a = p.parse_args(argv)
    sbom = build_sbom(
        lock_text=_read(a.lock, "pubspec.lock", required=True),
        pubspec_text=_read(a.pubspec, "pubspec.yaml"),
        platform=a.platform, build=a.build, build_number=a.build_number,
        flutter=parse_flutter_json(_read(a.flutter_json, "flutter --version")),
        gradle_text=_read(a.gradle_deps, "Gradle dependencies"),
        podfile_text=_read(a.podfile_lock, "Podfile.lock"))
    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(sbom, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    counts: dict[str, int] = {}
    for c in sbom["components"]:
        eco = next((x["value"] for x in c.get("properties", [])
                    if x["name"] == "sarcade:ecosystem"), "sdk")
        counts[eco] = counts.get(eco, 0) + 1
    summary = ", ".join(f"{k} {v}" for k, v in sorted(counts.items()))
    print(f"::notice title=SBOM {out.name}::{len(sbom['components'])} components ({summary})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
