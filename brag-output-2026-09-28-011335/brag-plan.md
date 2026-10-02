# Brag Plan: Jerox

## What is this app?
Jerox is a native macOS menu-bar clipboard manager — no Dock icon while you work — that opens history at the cursor and can rephrase selected text in place.

## The angle
Not another clipboard window. The claim is speed plus staying out of the way: ⌃⌥⌘V puts the real list on the cursor, 1–9 pastes, and ⌘⇧R rewrites selected text in the app you are already in. This video is built from `jerox-app.md` only. No hot-corner pie, no OCR, no on-device model, no “Clean up.” The otter and the Namaste welcome stay for the close.

## Hook (first 2-3 seconds)
Dark macOS desktop. Notes mid-sentence. Keycaps ⌃⌥⌘V depress. The 360×380 material picker **snaps** at the cursor (the app uses `animationBehavior = .none`). Super: **At the cursor.**

## Key moments (the middle)
- **The list, as it actually is:** Search, numbered 1–9 rows (text, `#2ec4d6` swatch, highlighted `func`, image preview, link), Pin / Plain, footer keycaps. Hit **3** — that row pastes into Notes.
- **Rephrase anywhere:** messy sentence selected in Notes; ⌘⇧R; a small loader at the mouse; the sentence rewrites in place. Jerox never comes forward. Super: **Without leaving the app.**

## Outro / punchline
First-launch welcome, once:
**Namaste 🙏, Welcome to Jerox Family**
Confetti. Teal otter. Small: *native · menu bar · on disk.*

## User flow worth showing
Show Jerox at the cursor → pick with 1–9 → paste into the previous app. Then: select text → Rephrase shortcut → rewritten text lands where you were.

## Tone
- Preset: polished (override slow crossfades — hard cuts on the key and the rewrite)
- Creative direction: precision tool for power users, fast and quietly confident
- Interpretation: built by someone annoyed that clipboard managers are slow and loud. Tight, diegetic motion. No SaaS cards.

## Format: landscape — 1920x1080
## Duration: 20.5 seconds

## Visual identity (from the project)
- Background: `#0E1114`
- Accent: otter teal `#2EC4D6`; clipboard orange `#F47B2A` on the mascot only
- Text: `#F2F4F5`; secondary `#C5CDD4`
- Selection: `rgba(10,132,255,0.22)`
- Display / body: system-ui (SF Pro on macOS)
- Strongest visual: borderless 12px material picker (Search, numbered rows, Rephrase menu, ↩ paste / ⇧↩ plain / ⌘P pin / 1–9)
- Brand: teal otter (`Jerox/jerox-icon.png`); menu-bar otter (`Jerox/jerox-icon-menu.png`)

## Share copy (draft)
Jerox: ⌃⌥⌘V and your clipboard history is already at the cursor. Paste with 1–9. Rephrase without leaving the app. Native macOS.

## Audio direction
- Role: sparse professional accents
- Music: `happy-beats-business-moves-vol-11-by-ende-dot-app.mp3` (~115 BPM, early strong cues)
- Music treatment: start 0; volume ~0.22; fade from ~18.6s
- Music cue guidance: bundled preset vol-11. Strong locks: **1.60s** picker snap; **8.96s** key 3; **12.65s** Rephrase; welcome settle near **17.91s**. Row ticks may use 5.80–7.91. Ignore a cue if it steals hold time.
- Audio-reactive treatment: subtle teal glow vs RMS. No visualizer.
- SFX posture: sparse, diegetic key/click, one soft snap, one warmer Namaste hit
- Audio-coupled moments: chord → snap; key 3; ⌘⇧R; confetti
- Restraint rule: no whooshes, no slide-in beds, no pie-chart ticks

## Storyboard

### Scene 1 — At the cursor — 3.5s
Menu-bar otter, no Dock. Notes window. Chord ⌃⌥⌘V. Picker snaps at the cursor with real chrome: Search, five rows, Rephrase, hints. Super: **At the cursor.**
Rows (fictional):
1. ship the picker at the cursor
2. `#2ec4d6` + swatch
3. `func paste(_ clip: Clip)`
4. Image
5. jxngrx.com
Sequential/interaction: yes — keys press, then instant panel.
Audio intent: coiled, then snap.
Audio-coupled idea: key ticks + soft impact at 1.60s.
Music: vol-11 under.
Transition mood: hard cut → Scene 2

### Scene 2 — Hit 3 — 7.0s
Same picker, already open. Hold long enough to read the formats. Keycap **3** depresses; row 3 selection-washes; `func paste(_ clip: Clip)` appears in Notes. Super: **1–9.**
Sequential/interaction: yes — key 3, paste.
Audio intent: dry keyboard.
Audio-coupled idea: one key at 8.96s.
Transition mood: hard cut → Scene 3

### Scene 3 — Rephrase — 6.0s
Picker gone. Notes shows: “hey can u send the build when u get a chance thx” (selected). Chord ⌘⇧R. Tiny loader at the mouse. Text becomes: “Could you send the build when you have a moment? Thank you.” Jerox stays out. Super: **Without leaving the app.**
Do not show Settings, API keys, or model names.
Sequential/interaction: yes — select, shortcut, loader, rewrite.
Audio intent: quieter confirmation.
Audio-coupled idea: keys on ⌘⇧R; soft tick when text lands (12.65s).
Transition mood: hard cut → Scene 4

### Scene 4 — Namaste — 4.0s
**Namaste 🙏, Welcome to Jerox Family**
Confetti. Otter last. Lockup: **native · menu bar · on disk**
Sequential/interaction: confetti only.
Audio intent: warmer, still quiet.
Audio-coupled idea: one soft hit near 17.91s; music fades.
Transition mood: hold, end.

**Scene duration sum: 3.5 + 7.0 + 6.0 + 4.0 = 20.5s**

**Music mood for this video:** tight / confident
**Audio summary:** A 115 BPM bed under diegetic keys, then a step back for Namaste.

## Music cue guidance
- Track: vol-11 @ 114.84 BPM
- Preset: `<skill-dir>/assets/music/cues/happy-beats-business-moves-vol-11-by-ende-dot-app.music-cues.md`
- Strong-cue locks: 1.60 / 8.96 / 12.65
- Restraint: readability wins

## Cut list (not in the app — do not shoot)
- Hot-corner / radial pie
- OCR / Vision
- On-device Foundation Models
- “Clean up”
- Type filters, Base64, case conversion, markdown strip
- OpenRouter fields, API keys, model picker
- Dock icon while working
