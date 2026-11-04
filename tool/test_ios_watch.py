"""Tests of tool/ios_watch.py (lot 28, iPhone builds watch).

    python3 -m unittest discover -s tool -p "test_*.py"
"""
import datetime as dt
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import ios_watch  # noqa: E402

NOW = dt.datetime(2026, 11, 6, 4, 30, tzinfo=dt.timezone.utc)


def job(end, conclusion="success", upload="success", jid=1):
    steps = [{"name": "Set up job", "conclusion": "success"},
             {"name": "Build iOS (no code signing)", "conclusion": "skipped"}]
    if upload:
        steps.append({"name": ios_watch.UPLOAD_STEP, "conclusion": upload})
    return {"id": jid, "conclusion": conclusion, "completed_at": end, "steps": steps,
            "html_url": f"https://example.invalid/job/{jid}"}


class FakeGitHub(ios_watch.GitHub):
    def __init__(self, issues):
        super().__init__("o/r", "t")
        self.issues, self.calls = issues, []

    def call(self, method, path, data=None):
        self.calls.append((method, path, data))
        if method == "GET" and "/issues?" in path:
            return self.issues
        if method == "GET" and "/labels/" in path:
            return {"name": "ci"}
        if method == "POST" and path.endswith("/issues"):
            return {"number": 42}
        return {}


class LastUpload(unittest.TestCase):
    def test_most_recent_successful_upload(self):
        jobs = [job("2026-11-05T04:40:00Z", jid=1), job("2026-11-06T04:20:00Z", jid=2),
                job("2026-11-06T04:25:00Z", conclusion="failure", upload="failure", jid=3)]
        self.assertEqual(ios_watch.last_upload(jobs)["id"], 2)

    def test_unsigned_or_cancelled_jobs_do_not_count(self):
        jobs = [job("2026-11-06T04:20:00Z", upload=None, jid=1),
                job("2026-11-06T04:25:00Z", conclusion="cancelled", upload=None, jid=2),
                job("2026-11-06T04:26:00Z", upload="skipped", jid=3)]
        self.assertIsNone(ios_watch.last_upload(jobs))

    def test_late_after_48_hours(self):
        self.assertTrue(ios_watch.is_late(None, NOW))
        self.assertTrue(ios_watch.is_late(job("2026-11-04T04:29:00Z"), NOW))
        self.assertFalse(ios_watch.is_late(job("2026-11-04T04:31:00Z"), NOW))


class SyncIssue(unittest.TestCase):
    def test_opens_one_issue_when_late(self):
        gh = FakeGitHub([])
        self.assertEqual(ios_watch.sync_issue(gh, True, "corps", None), "issue #42 opened")
        post = [c for c in gh.calls if c[0] == "POST" and c[1].endswith("/issues")]
        self.assertEqual(post[0][2]["title"], ios_watch.TITLE)
        self.assertEqual(post[0][2]["labels"], ["ci"])

    def test_no_duplicate(self):
        gh = FakeGitHub([{"number": 7, "title": ios_watch.TITLE}])
        self.assertEqual(ios_watch.sync_issue(gh, True, "corps", None), "issue #7 already open")
        self.assertFalse([c for c in gh.calls if c[0] != "GET"])

    def test_closes_when_a_build_got_through(self):
        gh = FakeGitHub([{"number": 7, "title": ios_watch.TITLE}])
        last = job("2026-11-06T04:20:00Z")
        self.assertEqual(ios_watch.sync_issue(gh, False, "", last), "issue #7 closed")
        self.assertIn(("PATCH", "/repos/o/r/issues/7", {"state": "closed", "state_reason": "completed"}), gh.calls)

    def test_other_ci_issues_untouched(self):
        gh = FakeGitHub([{"number": 9, "title": "Autre"}, {"number": 10, "title": ios_watch.TITLE, "pull_request": {}}])
        self.assertEqual(ios_watch.sync_issue(gh, False, "", job("2026-11-06T04:20:00Z")),
                         "build within 48 h, no open issue")

    def test_body_mentions_last_build(self):
        body = ios_watch.issue_body(job("2026-11-03T09:02:53Z"), NOW, "https://run")
        self.assertIn("2026-11-03T09:02:53Z", body)
        self.assertIn("https://run", body)


if __name__ == "__main__":
    unittest.main()
