# Hyperframes Composition Brief: Jerox

## Objective
Create a short launch-style brag video for Jerox, a native macOS clipboard manager.

## Output
- Composition directory: `brag-output/composition/`
- Rendered video: `brag-output/brag.mp4`
- Format: landscape — 1920x1080
- Duration: 21 seconds

## Source Material
- Project root: `/Users/shubhamjangra/Work/Jerox`
- Primary files read: `jerox-app.md`, `Jerox/JeroxApp.swift`, `Jerox/History.swift`, `Jerox/jerox-icon.png`, `Jerox/jerox-icon-menu.png`
- Product name: Jerox
- Tagline / strongest claim: History at the cursor. A hot-corner pie you scroll.
- Key UI or visual moment to recreate:
  1. Borderless material picker (360×380, 12px radius, Search, numbered 1–9 rows, pin, Plain, Clean up / Rephrase, keycap hints)
  2. Hot-corner radial pie (standout — most screen time)
  3. First-launch welcome + teal otter mascot
- Copy that must appear verbatim:
  - Search
  - Plain
  - Clean up
  - Rephrase
  - Friendly chat
  - Professional chat
  - Professional mail
  - 1–9
  - Namaste 🙏, Welcome to Jerox Family
  - At the cursor.
  - Scroll. Click. Recopy.
  - On device.
- Fictional clipboard rows (no personal data):
  - ship the picker at the cursor
  - `#2ec4d6`
  - `func paste(_ clip: Clip)`
  - screenshot + OCR overlay becoming searchable
  - jxngrx.com

## Creative Direction
- Tone preset: polished
- Creative direction: precision tool for power users, fast and quietly confident
- Interpretation: diegetic cuts on the hotkey and the click. Override polished's slow crossfades. Four tight beats. Cut scope before polish.
- Angle: not another clipboard list. Speed + a new interaction (hot-corner pie). Otter/Namaste only at the close.
- Hook: ⌃⌥⌘V → picker snaps at the cursor. Super: At the cursor.
- Outro / punchline: Namaste 🙏, Welcome to Jerox Family + confetti + otter
- Avoid:
  - Generic SaaS language
  - Abstract filler visuals
  - Unrelated visual redesign
  - Stock slide-ins / whooshes
  - Showing the otter before the tool has proven itself
  - Dock icon (the app has none)
  - Cloud/OpenRouter chrome

## Visual Identity
- Background: `#0E1114`
- Text: `#F5F5F7`
- Accent: `#2EC4D6` (otter teal); orange `#F47B2A` only on the mascot clipboard
- Selection wash: `rgba(10,132,255,0.18)`
- Display font: SF Pro Display, `-apple-system`, `system-ui`
- Body font: SF Pro Text, `-apple-system`, `system-ui`
- Visual references from the project:
  - `.regularMaterial` frost picker, 12px continuous radius, 1px separator stroke
  - KeyCap: 10px semibold rounded, quaternary fill, 5px radius
  - Menu-bar otter 18px in the status item
  - Full otter icon for the close
  - Code highlight: purple keywords (`func`)

## Storyboard
Use the storyboard in `brag-output/brag-plan.md` as the creative contract.

Scene summary:
1. At the cursor — 3.6s — keycaps ⌃⌥⌘V, picker snaps at cursor, "At the cursor."
2. Hot corner — 8.2s — cursor to top-right, pie blooms, 5 slices scroll, click to recopy, "Scroll. Click. Recopy."
3. Hit 3 — 5.2s — number 3 pastes code row; Rephrase menu with three tones; "On device."
4. Namaste — 4.0s — welcome line, confetti, otter, Jerox lockup

## Audio
- Audio role: sparse professional accents
- Audio arc: coiled snap → mechanical pie ticks → dry key → warmer human close
- Music: `happy-beats-business-moves-vol-11-by-ende-dot-app.mp3`
- Music treatment: start 0; volume ~0.22; fade from ~19.2s
- Music cue guidance: bundled preset `/Users/shubhamjangra/.agents/skills/brag/assets/music/cues/happy-beats-business-moves-vol-11-by-ende-dot-app.music-cues.md` — lock 1.60 / 6.34 / 17.91; slice ticks 8.96–12.12
- Audio-reactive treatment: subtle; teal glow / pie presence vs RMS. No visualizer.
- Audio-coupled moments:
  - Scene 1 — key chord + picker snap
  - Scene 2 — pie bloom + slice ticks + click
  - Scene 3 — key 3
  - Scene 4 — confetti / welcome
- SFX selection guidance: low HF-risk clicks and soft impacts; one warmer close hit
- SFX analysis guidance: `/Users/shubhamjangra/.agents/skills/brag/assets/sfx/sfx-analysis.md`
- Exact SFX choice: Hyperframes should choose filenames, timestamps, density, and volume based on the implemented animation.
- Audio files: copy the chosen music and any Hyperframes-selected SFX into `brag-output/composition/assets/`

## Hyperframes Instructions
Load the composition-building Hyperframes domain skills — `hyperframes-core` (composition contract + `data-*` timing), `hyperframes-animation` (motion), `hyperframes-creative` (design spec, beats, audio-reactive), `hyperframes-keyframes` (seek-safe keyframes), and `hyperframes-cli` (lint/check/render). /brag is its own workflow: do not enter the `hyperframes` entry-point intent interview and do not route into its generic promo / launch-video workflow. Prefer native Hyperframes conventions over anything in `/brag`.

Requirements:
- Show at least one real UI, copy, or visual element from the source project.
- Keep all text readable in the final render.
- Keep the video within 15-25 seconds.
- Include the planned music/SFX layer.
- Treat `/brag` audio notes as guidance, not a fixed cue sheet.
- Treat music cue metadata as optional timing hints.
- Major reveals may move toward nearby strong cues within about 0.15s. Use only 1-3 strong cue locks.
- Honor diegetic motion: picker appears instantly (no fade/slide); pie blooms from the corner; cuts land on hotkey/click.
- Copy `Jerox/jerox-icon.png` and `Jerox/jerox-icon-menu.png` into composition assets.
- Run `hyperframes check` before render — it is brag's single gate.
