# Hyperframes Composition Brief: Jerox

## Objective
Create a short launch-style brag video for Jerox, a native macOS clipboard manager. Source of truth: `jerox-app.md` (current product — not the older spec).

## Output
- Composition directory: `brag-output-2026-09-28-011335/composition/`
- Rendered video: `brag-output-2026-09-28-011335/brag.mp4`
- Format: landscape — 1920x1080
- Duration: 20.5 seconds

## Source Material
- Project root: `/Users/shubhamjangra/Work/Jerox`
- Primary files: `jerox-app.md`, `Jerox/JeroxApp.swift`, `Jerox/History.swift`, `Jerox/jerox-icon.png`, `Jerox/jerox-icon-menu.png`
- Product name: Jerox
- Tagline / strongest claim: History at the cursor. Rephrase without leaving the app.
- Key UI to recreate: material picker (360×380, 12px radius, Search, 1–9, Pin, Plain, Rephrase menu, keycap hints); in-place Rephrase loader at the mouse
- Copy that must appear verbatim:
  - Search
  - Rephrase
  - Friendly chat
  - Professional chat
  - Professional mail
  - Plain
  - 1–9
  - At the cursor.
  - Without leaving the app.
  - Namaste 🙏, Welcome to Jerox Family

## Creative Direction
- Tone preset: polished
- Creative direction: precision tool for power users, fast and quietly confident
- Interpretation: diegetic cuts on the hotkey and the rewrite. No stock slide-ins.
- Angle: speed + staying out of the way. Otter/Namaste only at the close.
- Hook: ⌃⌥⌘V → picker snaps at the cursor
- Outro: Namaste 🙏, Welcome to Jerox Family
- Avoid:
  - Generic SaaS language
  - Hot-corner pie, OCR, on-device AI, Clean up (not in the app)
  - API keys / OpenRouter chrome
  - Dock icon while working
  - Abstract filler

## Visual Identity
- Background: `#0E1114`
- Text: `#F2F4F5`
- Accent: `#2EC4D6`
- Display/body: `system-ui, sans-serif` (no named font without @font-face)
- Visual references: `.regularMaterial` picker, KeyCap 10px rounded, menu-bar otter, code keyword purple (AA contrast)

## Storyboard
Use `brag-output-2026-09-28-011335/brag-plan.md`.

1. At the cursor — 3.5s — chord + picker snap
2. Hit 3 — 7.0s — formats visible, number-key paste
3. Rephrase — 6.0s — ⌘⇧R in Notes, loader, rewrite in place
4. Namaste — 4.0s — welcome + otter + confetti

## Audio
- Audio role: sparse professional accents
- Audio arc: snap → key → rewrite → human close
- Music: `happy-beats-business-moves-vol-11-by-ende-dot-app.mp3`
- Music treatment: ~0.22; fade from ~18.6s
- Music cue guidance: vol-11 preset; locks 1.60 / 8.96 / 12.65
- Audio-reactive treatment: subtle glow vs RMS
- Audio-coupled moments: chord, snap, key 3, Rephrase, confetti
- SFX analysis: `/Users/shubhamjangra/.agents/skills/brag/assets/sfx/sfx-analysis.md`
- Exact SFX: Hyperframes chooses after motion exists
- Audio files: copy into `composition/assets/`

## Hyperframes Instructions
Use hyperframes-core / animation / creative / keyframes / cli. Do not enter the generic `/hyperframes` interview. Picker appears instantly. Check must pass with zero errors before render.
