#!/usr/bin/env python3
"""Offline self-test for ghsafe - locks the pure invariants (no network).

Covers the two real-world corruptions: CRLF doubling and the normalize/compose
paths that feed every PATCH. Run: python test_ghsafe.py
"""
import json
import sys

import ghsafe

fails = []


def check(name, cond):
    print(("ok  " if cond else "FAIL") + " - " + name)
    if not cond:
        fails.append(name)


# --- normalize() collapses every line-ending variant to a single \n ---
check("normalize CRLF -> LF", ghsafe.normalize("a\r\nb") == "a\nb")
check("normalize double-CR (\\r\\r\\n) -> single LF",
      ghsafe.normalize("a\r\r\nb") == "a\nb")          # THE bug that shattered code blocks
check("normalize lone CR -> LF", ghsafe.normalize("a\rb") == "a\nb")
check("normalize is idempotent",
      ghsafe.normalize(ghsafe.normalize("a\r\r\nb\r\n")) == ghsafe.normalize("a\r\r\nb\r\n"))
check("normalize leaves clean LF untouched", ghsafe.normalize("a\nb\nc") == "a\nb\nc")

# --- a normalized body carries ZERO carriage returns (the verify invariant) ---
crlf_fenced = "intro\r\n```\r\nline1\r\nline2\r\n```\r\ntail"
clean = ghsafe.normalize(crlf_fenced)
check("normalized body has 0 CR", clean.count("\r") == 0)
check("fence count preserved by normalize", clean.count("```") == 2)

# --- the JSON payload we send is valid utf-8 and CR-free ---
note = "header with em-dash — and smart quote “"
payload = json.dumps({"body": ghsafe.normalize(note + "\r\n")}).encode("utf-8")
decoded = json.loads(payload.decode("utf-8"))["body"]
check("payload round-trips utf-8 (em-dash intact)", "—" in decoded)
check("payload body is CR-free", decoded.count("\r") == 0)

# --- prepend composition is CR-free even from CRLF inputs (compose without network) ---
composed = ghsafe.normalize("EDIT NOTE\r\n") + "\n\n---\n\n" + ghsafe.normalize("orig\r\r\nbody")
check("composed prepend has 0 CR", composed.count("\r") == 0)
check("composed prepend keeps note + body", "EDIT NOTE" in composed and "orig" in composed)

# --- verify's content comparison tolerates trailing-newline diffs (GitHub strips them) ---
def cmp(a, b):  # mirrors _verify's interior-content comparison
    return ghsafe.normalize(a).strip("\n") == ghsafe.normalize(b).strip("\n")
check("verify tolerates a stripped trailing newline", cmp("body text\n", "body text"))
check("verify still rejects a real interior diff", not cmp("line A\nline B", "line A\nline X"))

print()
if fails:
    print("FAILED: " + ", ".join(fails))
    sys.exit(1)
print("ALL %d ghsafe tests passed." % 13)
