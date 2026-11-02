#!/usr/bin/env python3
"""Nightly OSV check of the SARCADE application SBOMs (card « SBOM : produire
et exploiter l'inventaire des composants », lot 22, points 3 and 4).

Subcommands (Python standard library only):

- ``check-config osv-scanner.toml``: the register of dismissed vulnerabilities
  ([[IgnoredVulns]]) must give, for each entry, an ``id``, a non-empty
  ``reason`` and an ``ignoreUntil`` date (re-examination). Exit 1 otherwise.
- ``issue --repo owner/name results/*.json``: reads the JSON reports of
  OSV-Scanner (dismissed vulnerabilities already left out by its --config)
  and keeps one GitHub issue « Faille dans un composant » (label
  ``security``) up to date: opened when a vulnerability is found, updated
  without duplicate (a comment when the list changes, so the owner gets an
  e-mail), closed when nothing is left. Token: GITHUB_TOKEN. ``--dry-run``
  prints what it would do.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

TITLE = "Faille dans un composant"
LABEL = "security"
MARKER = "sarcade-osv"
API = os.environ.get("GITHUB_API_URL", "https://api.github.com")


# --- point 4: register of dismissed vulnerabilities ------------------------

def check_config(text: str, today: dt.date | None = None) -> tuple[list[str], list[str]]:
    """(errors, notes) of the [[IgnoredVulns]] of an osv-scanner.toml."""
    import tomllib  # Python 3.11+

    today = today or dt.date.today()
    errors: list[str] = []
    notes: list[str] = []
    try:
        data = tomllib.loads(text)
    except tomllib.TOMLDecodeError as e:
        return [f"osv-scanner.toml unreadable: {e}"], []
    entries = data.get("IgnoredVulns", [])
    if not isinstance(entries, list):
        return ["IgnoredVulns must be a list ([[IgnoredVulns]])"], []
    for i, entry in enumerate(entries, 1):
        vid = str(entry.get("id", "")).strip()
        where = f"[[IgnoredVulns]] n° {i} ({vid or 'no id'})"
        if not vid:
            errors.append(f"{where}: id missing")
        if not str(entry.get("reason", "")).strip():
            errors.append(f"{where}: reason missing (why SARCADE is not affected)")
        until = entry.get("ignoreUntil")
        if until is None:
            errors.append(f"{where}: ignoreUntil missing (re-examination date)")
            continue
        day = until.date() if isinstance(until, dt.datetime) else until
        if not isinstance(day, dt.date):
            errors.append(f"{where}: ignoreUntil is not a date")
        elif day < today:
            notes.append(f"{where}: re-examination date {day} passed, reported again")
        elif (day - today).days <= 14:
            notes.append(f"{where}: re-examination due on {day}")
    return errors, notes


# --- point 3: OSV-Scanner reports -> findings -------------------------------

def _fixed_versions(vuln: dict, name: str) -> list[str]:
    fixed: set[str] = set()
    for aff in vuln.get("affected", []) or []:
        if (aff.get("package") or {}).get("name") not in (name, None):
            continue
        for rng in aff.get("ranges", []) or []:
            for ev in rng.get("events", []) or []:
                if ev.get("fixed"):
                    fixed.add(ev["fixed"])
    return sorted(fixed)


def findings_from_reports(reports: dict[str, dict]) -> list[dict]:
    """One finding per (vulnerability group, package, version), with the
    SBOMs or lock files where it was seen. ``reports``: {label: OSV json}."""
    found: dict[tuple, dict] = {}
    for label, report in reports.items():
        for result in report.get("results", []) or []:
            for pkg in result.get("packages", []) or []:
                info = pkg.get("package", {}) or {}
                vulns = {v.get("id"): v for v in pkg.get("vulnerabilities", []) or []}
                if not vulns:
                    continue
                groups = pkg.get("groups") or [{"ids": [i]} for i in vulns]
                for group in groups:
                    ids = sorted(i for i in group.get("ids", []) if i)
                    if not ids:
                        continue
                    aliases = sorted(set(group.get("aliases", []) or []) | set(ids))
                    main_id = next((i for i in ids if i.startswith("GHSA-")), ids[0])
                    key = (info.get("ecosystem", ""), info.get("name", ""),
                           info.get("version", ""), main_id)
                    v = vulns.get(main_id) or next(iter(vulns.values()))
                    f = found.setdefault(key, {
                        "id": main_id, "aliases": aliases,
                        "ecosystem": key[0], "package": key[1], "version": key[2],
                        "summary": (v.get("summary") or v.get("details") or "").strip().splitlines()[0:1],
                        "severity": group.get("max_severity", ""),
                        "fixed": _fixed_versions(v, key[1]),
                        "seen_in": []})
                    if label not in f["seen_in"]:
                        f["seen_in"].append(label)
    out = list(found.values())
    for f in out:
        f["summary"] = f["summary"][0] if f["summary"] else ""
    return sorted(out, key=lambda f: (f["package"], f["id"], f["version"]))


def finding_key(f: dict) -> str:
    return f"{f['id']}|{f['ecosystem']}/{f['package']}@{f['version']}"


def issue_body(findings: list[dict], scanned: list[str], run_url: str,
               today: dt.date | None = None) -> str:
    today = today or dt.date.today()
    lines = [
        f"Contrôle de nuit OSV du {today.isoformat()} : **{len(findings)} faille(s)** "
        "non écartée(s) dans les composants de l'application.",
        "",
        "| Faille | Composant | Version | Gravité | Corrigée en | Vue dans |",
        "|---|---|---|---|---|---|",
    ]
    for f in findings:
        link = f"[{f['id']}](https://osv.dev/vulnerability/{f['id']})"
        others = [a for a in f["aliases"] if a != f["id"]]
        if others:
            link += " (" + ", ".join(others[:3]) + ")"
        summary = f["summary"].replace("|", "/")
        comp = f"{f['ecosystem']} `{f['package']}`" + (f"<br>{summary}" if summary else "")
        lines.append(f"| {link} | {comp} | {f['version']} | {f['severity'] or '?'} | "
                     f"{', '.join(f['fixed']) or 'pas encore'} | {', '.join(f['seen_in'])} |")
    lines += [
        "",
        "**Que faire** : mettre à jour le composant (ou la dépendance qui l'amène) "
        "dans une PR ; si SARCADE n'est pas concerné, l'écarter dans `osv-scanner.toml` "
        "avec la raison et une date de réexamen (`docs/sbom.md`).",
        "",
        "Inventaires contrôlés : " + ", ".join(f"`{s}`" for s in scanned) + ".",
        f"Exécution : {run_url}" if run_url else "",
        "",
        f"<!-- {MARKER}: " + " ".join(sorted(finding_key(f) for f in findings)) + " -->",
    ]
    return "\n".join(lines).rstrip() + "\n"


def keys_in_body(body: str) -> set[str]:
    m = re.search(rf"<!-- {MARKER}: (.*?) -->", body or "", re.S)
    return set(m.group(1).split()) if m else set()


# --- GitHub REST -------------------------------------------------------------

class GitHub:
    def __init__(self, repo: str, token: str, dry_run: bool = False):
        self.repo, self.token, self.dry_run = repo, token, dry_run

    def call(self, method: str, path: str, data: dict | None = None):
        if self.dry_run and (method != "GET" or not self.token):
            print(f"[dry-run] {method} {path} {json.dumps(data or {}, ensure_ascii=False)[:300]}")
            return [] if method == "GET" else {}
        req = urllib.request.Request(
            f"{API}{path}", method=method,
            data=json.dumps(data).encode() if data is not None else None,
            headers={"Authorization": f"Bearer {self.token}",
                     "Accept": "application/vnd.github+json",
                     "X-GitHub-Api-Version": "2022-11-28",
                     "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
        return json.loads(raw) if raw else {}

    def ensure_label(self) -> None:
        try:
            self.call("GET", f"/repos/{self.repo}/labels/{LABEL}")
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise
            self.call("POST", f"/repos/{self.repo}/labels", {
                "name": LABEL, "color": "b60205",
                "description": "Faille de sécurité dans un composant"})

    def open_issue(self) -> dict | None:
        issues = self.call("GET", f"/repos/{self.repo}/issues?state=open&labels={LABEL}&per_page=100")
        mine = [i for i in issues if i.get("title") == TITLE and "pull_request" not in i]
        return min(mine, key=lambda i: i["number"]) if mine else None


def sync_issue(gh: GitHub, findings: list[dict], body: str) -> str:
    """Opens, updates or closes the issue. Returns what was done."""
    current = gh.open_issue()
    if not findings:
        if not current:
            return "nothing found, no open issue"
        gh.call("POST", f"/repos/{gh.repo}/issues/{current['number']}/comments",
                {"body": "Contrôle de nuit : plus aucune faille non écartée. Ticket fermé automatiquement."})
        gh.call("PATCH", f"/repos/{gh.repo}/issues/{current['number']}",
                {"state": "closed", "state_reason": "completed"})
        return f"issue #{current['number']} closed"
    keys = {finding_key(f) for f in findings}
    if not current:
        gh.ensure_label()
        new = gh.call("POST", f"/repos/{gh.repo}/issues",
                      {"title": TITLE, "body": body, "labels": [LABEL]})
        return f"issue #{new.get('number', '?')} opened"
    before = keys_in_body(current.get("body", ""))
    if before == keys:
        return f"issue #{current['number']} unchanged"
    gh.call("PATCH", f"/repos/{gh.repo}/issues/{current['number']}", {"body": body})
    added = sorted(keys - before)
    gone = sorted(before - keys)
    note = ["Contrôle de nuit : liste mise à jour."]
    if added:
        note.append("Nouvelles : " + ", ".join(f"`{k}`" for k in added))
    if gone:
        note.append("Disparues : " + ", ".join(f"`{k}`" for k in gone))
    gh.call("POST", f"/repos/{gh.repo}/issues/{current['number']}/comments",
            {"body": "\n\n".join(note)})
    return f"issue #{current['number']} updated"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Nightly OSV check of the SARCADE SBOMs")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check-config")
    c.add_argument("config")
    i = sub.add_parser("issue")
    i.add_argument("--repo", required=True)
    i.add_argument("--run-url", default="")
    i.add_argument("--dry-run", action="store_true")
    i.add_argument("reports", nargs="+", help="label=path of an OSV-Scanner JSON report")
    a = p.parse_args(argv)

    if a.cmd == "check-config":
        path = Path(a.config)
        errors, notes = check_config(path.read_text(encoding="utf-8") if path.exists() else "")
        for n in notes:
            print(f"::warning title=osv-scanner.toml::{n}")
        for e in errors:
            print(f"::error title=osv-scanner.toml::{e}")
        if not errors:
            print("osv-scanner.toml: register valid")
        return 1 if errors else 0

    reports: dict[str, dict] = {}
    for spec in a.reports:
        label, _, path = spec.partition("=")
        if not path:
            label, path = Path(spec).stem, spec
        reports[label] = json.loads(Path(path).read_text(encoding="utf-8") or "{}")
    findings = findings_from_reports(reports)
    body = issue_body(findings, list(reports), a.run_url)
    print(body)
    token = os.environ.get("GITHUB_TOKEN", "")
    if not token and not a.dry_run:
        print("::error::GITHUB_TOKEN missing")
        return 1
    done = sync_issue(GitHub(a.repo, token, a.dry_run), findings, body)
    level = "warning" if findings else "notice"
    print(f"::{level} title=OSV::{len(findings)} vulnerability(ies) not dismissed; {done}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
