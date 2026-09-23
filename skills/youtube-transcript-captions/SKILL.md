---
name: youtube-transcript-captions
description: "Get the text of a YouTube video - yt-dlp caption download in seconds, no media download, no GPU, no browser - falling back to downloading audio plus a Whisper-based diarized transcript when captions are missing or speakers must be separated. Use on any YouTube URL - transcribe this video, summarize this link, what do they say in, I need to quote from this, analyze this video. Not for transcribing local audio/video files."
---

# YouTube transcript via captions

Captions beat GPU transcription for YouTube sources: ~75 KB download vs. media download + WhisperX run. Needs `yt-dlp` on PATH (`yt-dlp --version`; install with `pip install -U yt-dlp` if missing).

## Steps

1. If you only have a title/description, find the video ID and VERIFY it's the right one (channel + duration), don't trust the first hit:

```
yt-dlp "ytsearch5:SEARCH TERMS" --print "%(id)s | %(title)s | %(channel)s | %(duration)s | %(view_count)s" --no-download
```

2. Download captions only (into the session scratchpad; `OUTNAME` is any base name you pick):

```
yt-dlp --skip-download --write-subs --write-auto-subs --sub-langs "en.*" --sub-format vtt -o "OUTNAME" "https://www.youtube.com/watch?v=VIDEO_ID"
```

   Done when at least one `OUTNAME.*.vtt` file exists. Several can appear (`OUTNAME.en.vtt`, `OUTNAME.en-orig.vtt`, `OUTNAME.en-US.vtt`); prefer `OUTNAME.en.vtt`, else use whichever exists, and put that name in the scripts below. No `.vtt` at all = no English captions: go to the fallback.

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

   In the 170–280 band, don't guess — the word-level timestamps settle it in one command. They count each spoken word once, so duplicated text cannot inflate this rate. If it is close to the step-4 rate, the speech is genuinely fast; if the step-4 rate is well above it, the text is duplicated:

```python
import re
raw = open('OUTNAME.en.vtt', encoding='utf-8').read()
st = sorted({int(h)*3600+int(m)*60+float(s) for h,m,s in re.findall(r'<(\d\d):(\d\d):(\d\d\.\d\d\d)>', raw)})
gaps = [b-a for a, b in zip(st, st[1:]) if 0 < b-a <= 2.0]   # >2s = cut point, not a pause
if not gaps:
    print('no word-level timestamps (manual captions carry none) - use the auto-caption file, e.g. OUTNAME.en-orig.vtt')
else:
    print('%.0f wpm actual speaking rate' % (60/(sum(gaps)/len(gaps))))
```

   Example: a fast jump-cut tutorial channel measured 226 wpm and a narration channel 135 wpm — both transcripts clean. The old 120–170 band false-alarmed on five of six videos and cost several turns chasing a non-existent dedup bug.

## Fallback: audio download + diarized transcript

Use when there are no captions, or you need speakers separated (interviews, panels) - captions carry no speaker labels.

The author used `whispr`, a private WhisperX wrapper that is not public. Use a public equivalent instead: **WhisperX** (bundles faster-whisper + pyannote diarization), or faster-whisper plus pyannote yourself. Diarization needs a free Hugging Face token with the pyannote model terms accepted. Check the installed version's flags with `whisperx --help` before running; do not guess them.

1. **Download audio only:** `yt-dlp -f bestaudio -x --audio-format mp3 -o "downloads/%(title)s.%(ext)s" "<YOUTUBE_URL>"`. Done when an `.mp3` appears in `downloads/`.
2. **Transcribe + diarize**, e.g. `whisperx "downloads/<file>.mp3" --diarize --hf_token <HF_TOKEN> --output_dir transcripts --output_format txt` (confirm each flag in `--help`). Skip diarization for single-speaker content; it is the slow part. On Windows, set `PYTHONIOENCODING=utf-8` first or Unicode output can crash the run.
3. **Read the `.txt`, not the JSON** (word-level JSON is huge). Summarize in 300-500 words:
   - **What it's about** - one-sentence lede
   - **Key concepts** - 3-5 main ideas
   - **Specifics** - examples, timestamps, notable quotes
   - **Takeaway** - conclusion or call to action

   With multiple speakers (`SPEAKER_00`, `SPEAKER_01`), name them from self-intros or direct address in the first few minutes.
4. **Present:** the summary, plus the path to the full transcript file. Keep the audio in `downloads/` in case you need to re-run with different options.

### Edge cases

| Situation | What to do |
|-----------|-----------|
| Download timeout | Retry once with `--socket-timeout 30` |
| Invalid / unavailable URL | Report yt-dlp's error message; don't retry |
| Video >2 hours | Warn the user transcription will take several minutes (longer without a GPU) |
| Non-English or no speech | Whisper still attempts; note in summary if output is sparse |
| **`Sign in to confirm you're not a bot`** (429 + this error on plain download) | **Don't reach for `--cookies-from-browser` first** - Chrome's cookie DB locks while it's running, and even closed, modern Chrome's app-bound cookie encryption makes yt-dlp's decrypt fail on Windows (open upstream, [yt-dlp#10927](https://github.com/yt-dlp/yt-dlp/issues/10927)). What worked: install the `bgutil-ytdlp-pot-provider` pip plugin + its companion `generate_once.js` script (needs Node.js - confirm with `node --version`), then pass `--js-runtimes node --extractor-args "youtube:player_client=mweb" --extractor-args "youtubepot-bgutilscript:script_path=<path to generate_once.js>" --remote-components ejs:github`. This uses PO tokens instead of cookies - no browser credential access. `mweb`/`web_embedded` clients worked; `tv`/`ios`/`web_safari` hit DRM or PO-token gaps, avoid those. |

## Landmines

- yt-dlp may print a loud "No supported JavaScript runtime" deprecation WARNING — ignorable, captions still download fine (seen on yt-dlp 2026.06.09).
- Official channels retitle uploads (e.g. a channel that prefixes "Article:"); a mirror/response video's duration can confirm which upload is canonical.
- **A watch page returning HTTP 429 does NOT mean the transcript is unobtainable — the captions endpoint is a separate path and often still works.** Never record "no transcript available" on the strength of a watch-page/oEmbed failure; run step 2 first. (A video once written off as unretrievable after days of 429s returned its full transcript on the first `yt-dlp --write-auto-subs` try. The 429 was a property of one retrieval path, not of the video.)
- No captions at all, or you need speaker labels → use the fallback above.

## Feedback (optional)

If this skill misfires or breaks for you, a short report helps everyone who installs it:
https://github.com/QualiaRain/skills/issues/new?template=skill-report.yml (which skill, which surface -
Claude Code / claude.ai / Cowork - your OS, what you asked, what happened). This is optional. If the person
agrees, Claude can file it with `gh issue create`; one report per distinct problem, and say it was
AI-assisted. Posting from Windows? `gh-safe-comment-edit` (in this pack) keeps the text from being mangled,
and `gh-comment-watch` (in this pack) can follow the thread for replies.
