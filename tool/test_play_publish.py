"""Tests of tool/play_publish.py (no network): `python -m unittest tool/test_play_publish.py`."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from play_publish import highest_version, network_failure, refused_because_draft, release_name, send_in_chunks, with_one_resend  # noqa: E402


class HighestVersion(unittest.TestCase):
    def test_bundles_and_tracks(self):
        bundles = [{"versionCode": 338}, {"versionCode": 402}]
        tracks = [{"track": "internal", "releases": [{"versionCodes": ["405"]}]},
                  {"track": "production"}]
        self.assertEqual(highest_version(bundles, tracks), 405)

    def test_nothing_published(self):
        self.assertEqual(highest_version([], []), 0)


class ReleaseName(unittest.TestCase):
    def test_short(self):
        self.assertEqual(release_name(406, "main@adcd135"), "406 main@adcd135")

    def test_cut_at_50(self):
        self.assertEqual(len(release_name(406, "x" * 80)), 50)


class _Resp:
    def __init__(self, status):
        self.status = status


class _Err(Exception):
    def __init__(self, status, content):
        super().__init__("http error")
        self.resp = _Resp(status)
        self.content = content


class RefusedBecauseDraft(unittest.TestCase):
    def test_draft_app(self):
        err = _Err(400, b'{"error": {"message": "Only releases with status draft may be created on draft app."}}')
        self.assertTrue(refused_because_draft(err))

    def test_other_error(self):
        self.assertFalse(refused_because_draft(_Err(403, b'{"error": {"message": "The caller does not have permission"}}')))
        self.assertFalse(refused_because_draft(_Err(400, b'{"error": {"message": "APK specifies a version code that has already been used."}}')))


class _Status:
    def __init__(self, p):
        self.p = p

    def progress(self):
        return self.p


class _Request:
    """Resumable upload: three pieces, the client library's retries asked."""
    def __init__(self):
        self.steps = [(_Status(0.3), None), (_Status(0.6), None), (None, {"versionCode": "7"})]
        self.retries = []

    def next_chunk(self, num_retries=0):
        self.retries.append(num_retries)
        return self.steps.pop(0)


class SendInChunks(unittest.TestCase):
    def test_pieces_until_the_answer(self):
        r, said = _Request(), []
        self.assertEqual(send_in_chunks(r, say=said.append), {"versionCode": "7"})
        self.assertEqual(r.retries, [5, 5, 5])
        self.assertTrue(any("%" in s for s in said))


class OneResend(unittest.TestCase):
    def test_timeout_then_success(self):
        calls, said, slept = [], [], []

        def send():
            calls.append(1)
            if len(calls) == 1:
                raise TimeoutError("The read operation timed out")
            return "ok"
        self.assertEqual(with_one_resend(send, wait_s=60, say=said.append, sleep=slept.append), "ok")
        self.assertEqual(len(calls), 2)
        self.assertEqual(slept, [60])
        self.assertIn("2/2", said[0])

    def test_two_timeouts_fail(self):
        def send():
            raise TimeoutError("cut")
        with self.assertRaises(TimeoutError):
            with_one_resend(send, say=lambda _: None, sleep=lambda _: None)

    def test_refusal_not_sent_again(self):
        calls = []

        def send():
            calls.append(1)
            raise _Err(400, b"version code already used")
        with self.assertRaises(_Err):
            with_one_resend(send, say=lambda _: None, sleep=lambda _: None)
        self.assertEqual(len(calls), 1)

    def test_network_failure(self):
        self.assertTrue(network_failure(TimeoutError()))
        self.assertTrue(network_failure(_Err(503, b"")))
        self.assertFalse(network_failure(_Err(403, b"")))


class PlainHttp(unittest.TestCase):
    """9 Nov 2026: a plain httplib2.Http took the 308 of the resumable
    upload for a redirect (« RedirectMissingLocation »)."""
    def test_308_is_not_a_redirect(self):
        try:
            from play_publish import plain_http
            http = plain_http()
        except ImportError:
            self.skipTest("google-api-python-client absent (uv run --script installs it)")
        self.assertNotIn(308, http.redirect_codes)
        self.assertEqual(http.timeout, 300)


if __name__ == "__main__":
    unittest.main()
