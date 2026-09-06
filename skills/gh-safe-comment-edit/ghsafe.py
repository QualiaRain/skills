#!/usr/bin/env python3
"""ghsafe - safe programmatic edits to GitHub comment / PR / issue bodies from Windows.

Closes the two traps that have each corrupted LIVE upstream content from this machine:

  1. cp1252 mojibake - capturing gh's UTF-8 output with the Windows locale codec
     turns an em-dash into `a-eur-"` and publishes it. (Now also backstopped by
     PYTHONUTF8=1 in ~/.claude/settings.json - but this tool NEVER relies on that;
     it always decodes UTF-8 explicitly, so it is correct even outside Claude Code.)

  2. CRLF doubling - writing an already-CRLF body through a Windows text-mode file
     (`open(p,"w")` without newline="") turns every `\\r\\n` into `\\r\\r\\n`. GitHub
     renders the double-CR as a paragraph break, SHATTERING fenced code blocks into
     one box per line. The fence COUNT stays the same, so content-only checks miss it.

Invariants enforced on every write:
  - fetch body as BYTES, decode utf-8 (never the locale codec)
  - normalize to `\\n`-only (strip every `\\r`) before posting
  - PATCH/POST via `gh api --input -` with a JSON payload on stdin
    (no text-mode temp file - that is exactly what doubled the CRs)
  - round-trip verify: re-fetch and assert 0 carriage returns + content matches

CLI:
  python ghsafe.py get     --repo O/R --kind comment|review-comment|issue|pr --id N
  python ghsafe.py set     --repo O/R --kind ...           --id N --body-file F
  python ghsafe.py prepend --repo O/R --kind ...           --id N --note-file F [--if-absent MARK]
  python ghsafe.py append  --repo O/R --kind ...           --id N --text-file F [--sep S]
  python ghsafe.py post    --repo O/R --issue N --body-file F     # new issue/PR comment

`--kind` maps to the GitHub API object:
  comment        = a conversation comment   -> /repos/{repo}/issues/comments/{id}
  review-comment = an inline code comment   -> /repos/{repo}/pulls/comments/{id}
  issue          = an issue body            -> /repos/{repo}/issues/{id}
  pr             = a pull-request body       -> /repos/{repo}/pulls/{id}

Body files are read as BYTES + utf-8 (text-mode reads would re-introduce trap #2).
Run `python test_ghsafe.py` for the offline self-test of the pure invariants.
"""
import argparse
import json
import re
import subprocess
import sys

ENDPOINTS = {
    "comment":        "repos/{repo}/issues/comments/{id}",
    "review-comment": "repos/{repo}/pulls/comments/{id}",
    "issue":          "repos/{repo}/issues/{id}",
    "pr":             "repos/{repo}/pulls/{id}",
}


def normalize(body):
    """Collapse every line ending to a single `\\n`. Idempotent.

    A run of one-or-more `\\r` before a `\\n` (covers `\\r\\n` AND the doubled
    `\\r\\r\\n` that shattered live code blocks) collapses to one `\\n`; any
    remaining lone-`\\r` run (old-Mac endings) also becomes a single `\\n`.
    A naive `.replace` chain would turn `\\r\\r\\n` into a blank line instead.
    """
    body = re.sub(r"\r+\n", "\n", body)
    return re.sub(r"\r+", "\n", body)


def _gh(args, input_bytes=None):
    """Run `gh <args>`; return stdout BYTES. Raises on non-zero with utf-8 stderr."""
    r = subprocess.run(["gh"] + args, input=input_bytes, capture_output=True)
    if r.returncode != 0:
        raise RuntimeError("gh failed (%d): %s" % (r.returncode, r.stderr.decode("utf-8", "replace")))
    return r.stdout


def _path(repo, kind, ident):
    if kind not in ENDPOINTS:
        raise ValueError("unknown --kind %r (choose from %s)" % (kind, ", ".join(ENDPOINTS)))
    return ENDPOINTS[kind].format(repo=repo, id=ident)


def get_body(repo, kind, ident):
    """Fetch the body as a clean utf-8 str (bytes-decoded, not locale)."""
    raw = _gh(["api", _path(repo, kind, ident)])
    obj = json.loads(raw.decode("utf-8"))
    return obj.get("body") or ""


def _verify(repo, kind, ident, expected_clean):
    back = get_body(repo, kind, ident)
    crs = back.count("\r")
    if crs:  # the primary guarantee: no CRs -> no shattered code blocks
        raise AssertionError("post-write verify FAILED: %d carriage return(s) stored" % crs)
    # Content match tolerates leading/trailing newline diffs: GitHub strips/normalizes
    # surrounding blank lines on storage, which is not corruption. Interior content must match.
    if normalize(back).strip("\n") != expected_clean.strip("\n"):
        raise AssertionError("post-write verify FAILED: stored body does not match what we sent")
    return back


def set_body(repo, kind, ident, body, verify=True):
    """Replace the body. Normalizes to `\\n`, PATCHes via stdin JSON, verifies."""
    clean = normalize(body)
    payload = json.dumps({"body": clean}).encode("utf-8")
    _gh(["api", "-X", "PATCH", _path(repo, kind, ident), "--input", "-"], input_bytes=payload)
    if verify:
        _verify(repo, kind, ident, clean)
    return clean


def prepend(repo, kind, ident, note, sep="\n\n---\n\n", if_absent=None):
    """Prepend `note` (+ separator) to the existing body.

    If `if_absent` is given and already present in the body, do nothing (idempotent).
    """
    body = get_body(repo, kind, ident)
    if if_absent is not None and if_absent in body:
        return None  # already prepended; no-op
    new = normalize(note) + sep + normalize(body)
    return set_body(repo, kind, ident, new)


def append(repo, kind, ident, text, sep="\n\n"):
    body = get_body(repo, kind, ident)
    new = normalize(body) + sep + normalize(text)
    return set_body(repo, kind, ident, new)


def post_comment(repo, issue_number, body, verify=True):
    """Create a new conversation comment on an issue/PR. Returns the new comment id."""
    clean = normalize(body)
    payload = json.dumps({"body": clean}).encode("utf-8")
    raw = _gh(["api", "-X", "POST", "repos/%s/issues/%s/comments" % (repo, issue_number),
               "--input", "-"], input_bytes=payload)
    obj = json.loads(raw.decode("utf-8"))
    cid = obj["id"]
    if verify:
        _verify(repo, "comment", cid, clean)
    return cid


def _read(path):
    """Read a body/note file as BYTES + utf-8 (text-mode reads would re-add CRs)."""
    with open(path, "rb") as f:
        return f.read().decode("utf-8")


def main(argv=None):
    p = argparse.ArgumentParser(description="Safe GitHub body edits (UTF-8 + LF, verified).")
    sub = p.add_subparsers(dest="cmd", required=True)

    def common(sp, need_kind=True):
        sp.add_argument("--repo", required=True, help="owner/name")
        if need_kind:
            sp.add_argument("--kind", required=True, choices=list(ENDPOINTS))
            sp.add_argument("--id", required=True, dest="ident")

    g = sub.add_parser("get"); common(g)
    s = sub.add_parser("set"); common(s); s.add_argument("--body-file", required=True)
    pr = sub.add_parser("prepend"); common(pr)
    pr.add_argument("--note-file", required=True)
    pr.add_argument("--sep", default="\n\n---\n\n")
    pr.add_argument("--if-absent", default=None)
    ap = sub.add_parser("append"); common(ap)
    ap.add_argument("--text-file", required=True)
    ap.add_argument("--sep", default="\n\n")
    po = sub.add_parser("post"); common(po, need_kind=False)
    po.add_argument("--issue", required=True)
    po.add_argument("--body-file", required=True)

    a = p.parse_args(argv)
    if a.cmd == "get":
        sys.stdout.buffer.write(get_body(a.repo, a.kind, a.ident).encode("utf-8"))
    elif a.cmd == "set":
        set_body(a.repo, a.kind, a.ident, _read(a.body_file))
        print("set OK (verified: 0 CR, content matches)")
    elif a.cmd == "prepend":
        r = prepend(a.repo, a.kind, a.ident, _read(a.note_file), sep=a.sep, if_absent=a.if_absent)
        print("prepend skipped (marker already present)" if r is None
              else "prepend OK (verified: 0 CR, content matches)")
    elif a.cmd == "append":
        append(a.repo, a.kind, a.ident, _read(a.text_file), sep=a.sep)
        print("append OK (verified: 0 CR, content matches)")
    elif a.cmd == "post":
        cid = post_comment(a.repo, a.issue, _read(a.body_file))
        print("posted comment id=%s (verified: 0 CR)" % cid)


if __name__ == "__main__":
    main()
