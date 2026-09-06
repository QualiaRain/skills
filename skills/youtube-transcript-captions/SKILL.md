---
name: youtube-transcript-captions
description: "Get the text of a YouTube video - yt-dlp caption download in seconds, no media download, no GPU, no browser - falling back to downloading audio plus whispr for a word-for-word DIARIZED transcript when captions are missing or speakers must be separated. Use on any YouTube URL - transcribe this video, summarize this link, what does he say in, I need to quote from this, analyze this video. Not for local files (whispr-transcribe)."
---

# YouTube transcript via captions

Captions beat GPU transcription for YouTube sources: ~75 KB download vs. media download + WhisperX run. Verified 2026-07-08 (Peterson Analysis project).

## Steps

1. If you only have a title/description, find the video ID and VERIFY it's the right one (channel + duration), don't trust the first hit:

```
yt-dlp "ytsearch5:SEARCH TERMS" --print "%(id)s | %(title)s | %(channel)s | %(duration)s | %(view_count)s" --no-download
```

2. Download captions only (into the session scratchpad):

```
yt-dlp --skip-download --write-subs --write-auto-subs --sub-langs "en.*" --sub-format vtt -o "OUTNAME" "https://www.youtube.com/watch?v=VIDEO_ID"
```

3. Strip VTT markup to plain text (handles rolling auto-captions, which repeat each line — the consecutive-dedup is load-bearing):

```python
import re
lines = open('OUTNAME.en.vtt', encoding='utf-8').read().splitlines()
out = []
for l in lines:
    l = re.sub(r'<[^>]+>', '', l).strip()
    if not l or '-->' in l or l in ('WEBVTT','Kind: captions','Language: en') or re.match(r'^\d+$', l):
        continue
    if l != (out[-1] if out else None):
        out.append(l)
text = re.sub(r'\s+', ' ', ' '.join(out))
open('transcript.txt', 'w', encoding='utf-8').write(text)
```

4. Sanity-check: word count ÷ duration. **Do NOT treat a high rate as a bug.** Real ranges: 120–170 wpm unedited speech, 200–270 wpm for jump-cut tutorial/YouTube content (every pause removed in the edit). Under ~110 → dedup ate real content or captions are partial. Over ~280 → probably duplicated text.

   In the 170–280 band, don't guess — the word-level timestamps settle it in one command. Median inter-word gap ≥0.30s means genuine fast speech; a much smaller gap than the apparent rate implies means the text is duplicated:

```python
import re
raw = open('OUTNAME.en.vtt', encoding='utf-8').read()
st = sorted({int(h)*3600+int(m)*60+float(s) for h,m,s in re.findall(r'<(\d\d):(\d\d):(\d\d\.\d\d\d)>', raw)})
gaps = [b-a for a, b in zip(st, st[1:]) if 0 < b-a <= 2.0]   # >2s = cut point, not a pause
print('%.0f wpm actual speaking rate' % (60/(sum(gaps)/len(gaps))))
```

   Measured 2026-07-26: Nate Herk 226 wpm (0.24s median gap) vs a narration channel at 135 wpm (0.36s) — both transcripts clean. The old 120–170 band false-alarmed on five of six videos and cost several turns chasing a non-existent dedup bug.

## Fallback: full download + diarized transcript (whispr)

Download any YouTube video → diarized transcript → summary. Minimum tool calls.

### Setup constants

```powershell
$env:PYTHONIOENCODING = 'utf-8'   # mandatory — whispr prints Unicode; Windows errors without this
$W = "$HOME\Claude\Whispr"
$CWD = (Get-Location).Path        # save so you can restore after cd'ing into $W if needed
```

Always invoke whispr via `uv run --project $W whispr …` — `whispr` is not on PATH.

---

### Workflow (2–3 tool calls)

#### Tool call 1 — Download

```powershell
$env:PYTHONIOENCODING = 'utf-8'
$W = "$HOME\Claude\Whispr"
$url = "<YOUTUBE_URL>"
$outDir = "downloads"

# Create dirs if needed
"downloads","transcripts" | ForEach-Object { if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ | Out-Null } }

# Download (--no-update suppresses version warning; -f best gets a pre-merged file)
uv run --project $W yt-dlp --no-update -f b -o "$outDir\%(title)s.%(ext)s" "$url"

# Capture the freshly-downloaded file
$videoFile = (Get-ChildItem $outDir -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
$baseName  = [System.IO.Path]::GetFileNameWithoutExtension($videoFile)
Write-Host "Downloaded: $videoFile"
```

#### Tool call 2 — Transcribe + render text

```powershell
$env:PYTHONIOENCODING = 'utf-8'
$W = "$HOME\Claude\Whispr"
# (Set $videoFile and $baseName from Tool call 1 output, or re-derive with Get-ChildItem)

$jsonOut = "transcripts\$baseName-transcript.json"
$txtOut  = "transcripts\$baseName-transcript.txt"

# Transcribe + diarize (--fold-traces merges stray trace labels into real speakers).
# For solo-speaker content, add --no-diarize to save ~22s per 17-min of video
# (skips the EBU R128 re-prep + pyannote inference entirely — see edit-pipeline.md §15.17).
# Rule: use --no-diarize when the content is known to be one speaker AND you don't need
# speaker labels. If in doubt, keep the default (diarization).
uv run --project $W whispr transcribe "$videoFile" -o "$jsonOut" --fold-traces

# Render readable timecoded text
uv run --project $W whispr transcript "$jsonOut" -o "$txtOut" --format hms --consolidate-speakers
Write-Host "Transcript: $txtOut"
```

#### No tool call — Read + summarize

Read the `.txt` file (not the JSON — it's word-level and huge). Synthesize a summary:

- **What it's about** — one sentence lede
- **Key concepts** — 3–5 main ideas
- **Specifics** — examples, timestamps, notable quotes
- **Takeaway** — conclusion or call to action
- Target: **300–500 words**

If there are multiple speakers (`SPEAKER_00`, `SPEAKER_01`), identify them from self-intros or direct address in the first few minutes and mention them in the summary.

#### Present to user

1. Your written summary
2. `transcripts/<name>-transcript.txt` — full timecoded transcript

---

### Edge cases

| Situation | What to do |
|-----------|-----------|
| Download timeout | Retry once with `--socket-timeout 30` |
| Invalid / unavailable URL | Report yt-dlp's error message; don't retry |
| Video >2 hours | Warn the user: "This will take several minutes to transcribe" |
| Non-English or no speech | Whisper still attempts; note in summary if output is sparse |
| Single speaker | Use `--no-diarize` to save ~22s per 17-min (skips loudnorm re-prep + pyannote). If multi-speaker is possible, keep default. |
| **`Sign in to confirm you're not a bot`** (429 + this error on plain download) | **Don't reach for `--cookies-from-browser` first** — Chrome's cookie DB locks while it's running, and even closed, modern Chrome's app-bound cookie encryption makes yt-dlp's DPAPI decrypt fail outright (open upstream, [yt-dlp#10927](https://github.com/yt-dlp/yt-dlp/issues/10927)); Edge cookies are also unreachable (blocked by this machine's AppData deny-list). The real fix, proven 2026-07-15 on two live downloads: install the `bgutil-ytdlp-pot-provider` pip plugin + its companion `generate_once.js` server (needs Node.js as the JS-challenge-solver runtime — confirm with `node --version`; install if absent), then pass `--js-runtimes node --extractor-args "youtube:player_client=mweb" --extractor-args "youtubepot-bgutilscript:script_path=<path to generate_once.js>" --remote-components ejs:github`. This sidesteps cookies entirely via PO tokens — no browser credential access needed at all. `mweb`/`web_embedded` clients worked; `tv`/`ios`/`web_safari` hit DRM or PO-token gaps, avoid those. |

---

### Notes

- **Never** use `uv run whispr` without `--project $W` — it's not on PATH and will fail from any other working directory.
- `--format hms` is mandatory on the `transcript` command — the default SMPTE format errors on audio without `--fps`/`--video`.
- `--consolidate-speakers` groups each speaker's runs into readable blocks rather than word-by-word labels.
- The JSON transcript is large (~0.5 MB for a 15-min video); read the `.txt` for summarization, not the JSON.
- Downloaded video stays in `downloads/` — reuse it if you need to re-transcribe with different flags.

## Landmines

- yt-dlp prints a loud "No supported JavaScript runtime" deprecation WARNING — ignorable, captions still download fine (observed 2026-07-08, yt-dlp 2026.06.09).
- Official channels retitle uploads (e.g. Peterson's channel prefixes "Article:"); a mirror/response video's duration can confirm which upload is canonical.
- `OUTNAME.en.vtt` (manual or best) and `OUTNAME.en-orig.vtt` (auto) may both appear; prefer `en.vtt`.
- **A watch page returning HTTP 429 does NOT mean the transcript is unobtainable — the captions endpoint is a separate path and often still works.** Never record "no transcript available" on the strength of a watch-page/oEmbed failure; run step 2 first. (2026-07-26: a source had been filed for days as permanently unretrievable after persistent 429s and "not indexed in any secondary source"; `yt-dlp --write-auto-subs` returned the full transcript first try. The 429 was a property of one retrieval path, not of the video.)
- No captions at all → fall back: `yt-dlp -f bestaudio -x` then the `whispr-transcribe` (not included in this pack) skill. Also fall back when you need speaker diarization (interviews/panels) — captions carry no speaker labels.
