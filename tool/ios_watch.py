#!/usr/bin/env python3
"""Watch of the iPhone builds sent to TestFlight (lot 28, card « iPhone :
aucune version TestFlight depuis le 3 novembre 2026 »).

Looks at the runs of the « iOS nightly » workflow on main over the last days
and finds the last job whose step « Archive, sign and send to TestFlight »
succeeded. If none finished in the last 48 hours, one GitHub issue
« Pas de version iPhone depuis 48 h » (label ``ci``) is opened (GitHub
e-mails the owner); it is closed with a comment as soon as a build gets
through again. Token: GITHUB_TOKEN only (actions: read, issues: write).
``--dry-run`` reads but prints what it would write.

Python standard library only.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.request

TITLE = "Pas de version iPhone depuis 48 h"
LABEL = "ci"
UPLOAD_STEP = "Archive, sign and send to TestFlight"
WORKFLOW = "ios-nightly.yml"
LIMIT = dt.timedelta(hours=48)
API = os.environ.get("GITHUB_API_URL", "https://api.github.com")


def parse_time(value: str | None) -> dt.datetime | None:
    if not value:
        return None
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def last_upload(jobs: list[dict]) -> dict | None:
    """The most recent job whose TestFlight upload step succeeded."""
    best = None
    for job in jobs:
        if job.get("conclusion") != "success":
            continue
        if not any(s.get("name") == UPLOAD_STEP and s.get("conclusion") == "success"
                   for s in job.get("steps") or []):
            continue
        end = parse_time(job.get("completed_at"))
        if end and (best is None or end > best[0]):
            best = (end, job)
    return best[1] if best else None


def is_late(last: dict | None, now: dt.datetime) -> bool:
    if last is None:
        return True
    return now - parse_time(last["completed_at"]) > LIMIT


def issue_body(last: dict | None, now: dt.datetime, run_url: str) -> str:
    if last:
        since = f"Dernière version envoyée à TestFlight : {last['completed_at']} ([job]({last.get('html_url', '')}))."
    else:
        since = "Aucune version envoyée à TestFlight trouvée dans les lancements « iOS nightly » récents."
    return "\n\n".join([
        f"Aucune construction iPhone n'a abouti depuis plus de 48 h (contrôle du {now:%Y-%m-%d %H:%M} UTC).",
        since,
        "À vérifier : le job iOS du dernier lancement (machine macOS non attribuée, "
        "« The job was not acquired by Runner of type hosted », signature, envoi App Store Connect). "
        "Relancer à la main : Actions › iOS nightly › Run workflow (branche main).",
        f"Contrôle : {run_url}" if run_url else "",
        "Ticket ouvert et fermé automatiquement par le workflow « iOS nightly ».",
    ]).strip()


class GitHub:
    def __init__(self, repo: str, token: str, dry_run: bool = False):
        self.repo, self.token, self.dry_run = repo, token, dry_run

    def call(self, method: str, path: str, data: dict | None = None):
        if self.dry_run and method != "GET":
            print(f"[dry-run] {method} {path} {json.dumps(data or {}, ensure_ascii=False)[:300]}")
            return {}
        headers = {"Accept": "application/vnd.github+json",
                   "X-GitHub-Api-Version": "2022-11-28",
                   "Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        req = urllib.request.Request(
            f"{API}{path}", method=method,
            data=json.dumps(data).encode() if data is not None else None,
            headers=headers)
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
        return json.loads(raw) if raw else {}

    def recent_jobs(self, now: dt.datetime, days: int = 7) -> list[dict]:
        since = (now - dt.timedelta(days=days)).strftime("%Y-%m-%d")
        try:
            runs = self.call("GET", f"/repos/{self.repo}/actions/workflows/{WORKFLOW}/runs"
                                    f"?branch=main&created=%3E%3D{since}&per_page=100")
        except urllib.error.HTTPError as e:
            if e.code != 404:  # workflow not yet on main
                raise
            return []
        jobs: list[dict] = []
        for run in runs.get("workflow_runs", []):
            data = self.call("GET", f"/repos/{self.repo}/actions/runs/{run['id']}/jobs?filter=all&per_page=100")
            jobs.extend(data.get("jobs", []))
        return jobs

    def ensure_label(self) -> None:
        try:
            self.call("GET", f"/repos/{self.repo}/labels/{LABEL}")
        except urllib.error.HTTPError as e:
            if e.code != 404:
                raise
            self.call("POST", f"/repos/{self.repo}/labels", {
                "name": LABEL, "color": "fbca04",
                "description": "Intégration continue"})

    def open_issue(self) -> dict | None:
        issues = self.call("GET", f"/repos/{self.repo}/issues?state=open&labels={LABEL}&per_page=100")
        mine = [i for i in issues if i.get("title") == TITLE and "pull_request" not in i]
        return min(mine, key=lambda i: i["number"]) if mine else None


def sync_issue(gh: GitHub, late: bool, body: str, last: dict | None) -> str:
    """Opens or closes the issue. Returns what was done."""
    current = gh.open_issue()
    if not late:
        if not current:
            return "build within 48 h, no open issue"
        gh.call("POST", f"/repos/{gh.repo}/issues/{current['number']}/comments",
                {"body": f"Version iPhone de nouveau envoyée à TestFlight ({last['completed_at']}). "
                         "Ticket fermé automatiquement."})
        gh.call("PATCH", f"/repos/{gh.repo}/issues/{current['number']}",
                {"state": "closed", "state_reason": "completed"})
        return f"issue #{current['number']} closed"
    if current:
        return f"issue #{current['number']} already open"
    gh.ensure_label()
    new = gh.call("POST", f"/repos/{gh.repo}/issues",
                  {"title": TITLE, "body": body, "labels": [LABEL]})
    return f"issue #{new.get('number', '?')} opened"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Alert when no iPhone build reached TestFlight for 48 h")
    p.add_argument("--repo", required=True)
    p.add_argument("--run-url", default="")
    p.add_argument("--dry-run", action="store_true")
    a = p.parse_args(argv)
    token = os.environ.get("GITHUB_TOKEN", "")
    if not token and not a.dry_run:
        print("::error::GITHUB_TOKEN missing")
        return 1
    now = dt.datetime.now(dt.timezone.utc)
    gh = GitHub(a.repo, token, a.dry_run)
    last = last_upload(gh.recent_jobs(now))
    late = is_late(last, now)
    done = sync_issue(gh, late, issue_body(last, now, a.run_url), last)
    when = last["completed_at"] if last else "none in the last 7 days"
    level = "warning" if late else "notice"
    print(f"::{level} title=iPhone::last TestFlight upload: {when}; {done}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
