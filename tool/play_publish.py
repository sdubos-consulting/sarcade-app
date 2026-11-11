# /// script
# requires-python = ">=3.12"
# dependencies = [
#   "google-api-python-client>=2.150",
#   "google-auth>=2.35",
#   "google-auth-httplib2>=0.2",
# ]
# ///
"""Google Play, from the i9 (card « Android : publication automatique sur
Google Play, reprise depuis l'i9 », validated on 8 Nov 2026).

Replaces the step `r0adkll/upload-google-play` of the GitHub CI, suspended
since 6 Nov 2026. Run with `uv run --script tool/play_publish.py`.

    next-version --key KEY.json [--floor N]
        Prints the next versionCode: highest one known by Google Play (every
        bundle and every track) plus one, at least --floor.
    upload --key KEY.json --aab APP.aab --version N [--track internal]
           [--status auto|draft|completed] [--name TEXT]
        Sends the bundle and puts it on the track, in one edit; « auto »
        publishes at once and falls back to a draft while the app is one.

The key file (service account `sarcade-ci`) is never printed.

Sending (card « Publication Android : envoi à Google Play qui échoue par
délai dépassé », validated on 9 Nov 2026): the bundle goes in pieces of
8 MB with resumption, each request tried again up to 5 times, a wait of
5 minutes at most per request; if the whole sending still fails on the
network, it is sent again once after 1 minute (the bundle is not built
again).
"""
from __future__ import annotations

import argparse
import sys
import time

PACKAGE = "org.sarcade.sarcade_app"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"
CHUNK = 8 * 1024 * 1024
RETRIES = 5
TIMEOUT_S = 300
RESEND_AFTER_S = 60


def highest_version(bundles: list[dict], tracks: list[dict]) -> int:
    """Highest versionCode among the uploaded bundles and the track releases."""
    codes = [int(b["versionCode"]) for b in bundles if "versionCode" in b]
    for track in tracks:
        for release in track.get("releases", []):
            codes += [int(c) for c in release.get("versionCodes", [])]
    return max(codes, default=0)


def release_name(version: int, label: str) -> str:
    """Release name shown in the Play Console; Google allows 50 characters."""
    return f"{version} {label}".strip()[:50]


def _service(key: str):
    from google.oauth2 import service_account
    from googleapiclient.discovery import build

    import google_auth_httplib2

    creds = service_account.Credentials.from_service_account_file(key, scopes=[SCOPE])
    return build("androidpublisher", "v3", http=google_auth_httplib2.AuthorizedHttp(creds, http=plain_http()),
                 cache_discovery=False)


def plain_http():
    """The client of the Google library (308 « Resume Incomplete » of the
    resumable upload not taken for a redirect), with a longer wait."""
    from googleapiclient.http import build_http

    http = build_http()
    http.timeout = TIMEOUT_S
    return http


def send_in_chunks(request, retries: int = RETRIES, say=print) -> dict:
    """Resumable upload, one piece after the other; each piece is tried
    again by the client library on a cut or a 5xx (up to [retries])."""
    response = None
    last = -1
    while response is None:
        status, response = request.next_chunk(num_retries=retries)
        if status is not None:
            pct = int(status.progress() * 100)
            if pct // 25 != last // 25:
                say(f"Google Play: {pct} % sent")
            last = pct
    return response


def network_failure(error) -> bool:
    """A cut or a timeout of the network, or Google unavailable (5xx)."""
    if isinstance(error, (TimeoutError, ConnectionError, OSError)):
        return True
    status = getattr(getattr(error, "resp", None), "status", None)
    return isinstance(status, int) and status >= 500


def with_one_resend(send, wait_s: int = RESEND_AFTER_S, say=print, sleep=time.sleep):
    """[send]() and, after a network failure, once more after [wait_s]."""
    try:
        return send()
    except Exception as e:  # noqa: BLE001
        if not network_failure(e):
            raise
        say(f"Google Play did not answer ({type(e).__name__}): sent again in {wait_s} s (2/2)")
        sleep(wait_s)
        return send()


def cmd_next_version(args) -> int:
    edits = _service(args.key).edits()
    edit = edits.insert(packageName=PACKAGE, body={}).execute()
    try:
        bundles = edits.bundles().list(packageName=PACKAGE, editId=edit["id"]).execute().get("bundles", [])
        tracks = edits.tracks().list(packageName=PACKAGE, editId=edit["id"]).execute().get("tracks", [])
    finally:
        edits.delete(packageName=PACKAGE, editId=edit["id"]).execute()
    print(max(highest_version(bundles, tracks) + 1, args.floor))
    return 0


def _upload_once(args, status: str) -> None:
    from googleapiclient.http import MediaFileUpload

    edits = _service(args.key).edits()
    edit = edits.insert(packageName=PACKAGE, body={}).execute(num_retries=RETRIES)
    try:
        media = MediaFileUpload(args.aab, mimetype="application/octet-stream", resumable=True, chunksize=CHUNK)
        bundle = send_in_chunks(edits.bundles().upload(packageName=PACKAGE, editId=edit["id"], media_body=media))
        if int(bundle["versionCode"]) != args.version:
            raise SystemExit(f"error: Google Play read versionCode {bundle['versionCode']}, expected {args.version}")
        body = {"track": args.track, "releases": [{
            "name": release_name(args.version, args.name),
            "versionCodes": [str(args.version)],
            "status": status,
        }]}
        edits.tracks().update(packageName=PACKAGE, editId=edit["id"], track=args.track, body=body).execute(num_retries=RETRIES)
        edits.commit(packageName=PACKAGE, editId=edit["id"]).execute(num_retries=RETRIES)
    except BaseException:
        try:
            edits.delete(packageName=PACKAGE, editId=edit["id"]).execute()
        except Exception:
            pass
        raise


def refused_because_draft(error) -> bool:
    """Google refuses a published release while the app is a draft."""
    text = str(getattr(error, "content", b"") or error).lower()
    return getattr(getattr(error, "resp", None), "status", None) == 400 and "draft" in text


def cmd_upload(args) -> int:
    from googleapiclient.errors import HttpError

    status = "completed" if args.status == "auto" else args.status
    try:
        with_one_resend(lambda: _upload_once(args, status))
    except HttpError as e:
        if args.status != "auto" or not refused_because_draft(e):
            raise
        print("Google Play: published release refused (app still a draft), sent as draft")
        status = "draft"
        with_one_resend(lambda: _upload_once(args, status))
    print(f"Google Play: versionCode {args.version} on track « {args.track} », status {status}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    nv = sub.add_parser("next-version")
    nv.add_argument("--key", required=True)
    nv.add_argument("--floor", type=int, default=1)
    nv.set_defaults(func=cmd_next_version)
    up = sub.add_parser("upload")
    up.add_argument("--key", required=True)
    up.add_argument("--aab", required=True)
    up.add_argument("--version", type=int, required=True)
    up.add_argument("--track", default="internal")
    # « auto » (default): published at once (« completed »); sent again as
    # « draft » only if Google refuses because the app is still a draft.
    up.add_argument("--status", default="auto", choices=["auto", "draft", "completed"])
    up.add_argument("--name", default="main")
    up.set_defaults(func=cmd_upload)
    args = parser.parse_args(argv)
    # Each new try of the client library said in the log (« Sleeping … before
    # retry 2 of 5 »).
    import logging
    logging.basicConfig(level=logging.WARNING, format="Google Play: %(message)s")
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
