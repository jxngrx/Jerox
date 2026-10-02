# Brag Plan: Jerox

## What is this app?
Jerox is a native macOS clipboard manager — menu-bar only, near-zero RAM — that summons history at the cursor and scrolls it as a radial pie from a hot corner.

## The angle
Clipboard managers are usually another list in another window. Jerox's claim is speed plus a genuinely new interaction: history appears where you already are, and the standout move is a hot-corner pie you scroll through. This video is a precision-tool demo, not a feature catalog. Four beats only. Cuts land on the hotkey and the click — diegetic motion, not stock slide-ins. The otter mascot and the Namaste welcome stay for the close, after the tool has already proven itself.

## Hook (first 2-3 seconds)
A dark macOS desktop. No logo. A cursor sits mid-Notes. The chord ⌃⌥⌘V hits as physical keycaps — then the real 360×380 material picker snaps into existence at the cursor, no fade, no slide (`animationBehavior = .none`). Super: **At the cursor.**

## Key moments (the middle)
- **Hot-corner pie (hero, most screen time):** cursor slams the top-right corner; a radial pie blooms; scroll ticks through recent copies (text, teal swatch, code, screenshot with OCR text, link); click a slice to re-copy.
- **Number-key paste:** picker already open, numbered 1–9; key `3` fires and that row pastes. Keyboard-only flex.
- Folded, not standalone scenes: formats live as pie slices; "Clean up" / "Rephrase" (Friendly chat · Professional chat · Professional mail) is a one-breath footer on the picker; OCR is the screenshot slice becoming searchable text.

## Outro / punchline
First-launch welcome, warm and human — not the opener:
**Namaste 🙏, Welcome to Jerox Family**
Confetti. The teal otter (clipboard in paw) lands. Small: *native · menu bar · on device.*

## User flow worth showing
Hotkey (or hot corner) → history appears where you are → pick by scroll/click or by number → paste. Centerpiece is the working picker and the pie, not a landing page (there isn't one).

## Tone
- Preset: polished (nearest: restraint, 4 scenes, confidence through hold — but override polished's slow crossfades)
- Creative direction: precision tool for power users, fast and quietly confident
- Interpretation: built by someone personally annoyed that clipboard managers are slow. Tight, diegetic cuts on the action itself. Quiet type. No corporate SaaS language. Humor only from the Namaste close.

## Format: landscape — 1920x1080
## Duration: 21.0 seconds

## Visual identity (from the project)
- Background: `#0E1114` desktop; picker uses macOS `.regularMaterial` frost (`rgba(40,42,46,0.72)` over blur)
- Accent: otter teal `#2EC4D6`; clipboard orange `#F47B2A` (icon only, used sparingly)
- Text: `#F5F5F7` primary; `rgba(255,255,255,0.55)` secondary
- Selection: system accent wash `rgba(10,132,255,0.18)` (SwiftUI `Color.accentColor.opacity(0.18)`)
- Display font: SF Pro Display / `-apple-system`
- Body font: SF Pro Text / `-apple-system`
- Strongest visual element: borderless 12px-radius material picker (search + numbered rows + pin + Plain + Clean up / Rephrase + keycap hints) and the hot-corner radial pie
- Brand mark: teal otter holding an orange clipboard (`Jerox/jerox-icon.png`); menu-bar otter (`Jerox/jerox-icon-menu.png`)

## Share copy (draft)
Jerox: hit a hotkey and your clipboard history is already at the cursor. Scroll the hot-corner pie. Paste with 1–9. Native macOS. On device.

## Audio direction
- Role: sparse professional accents under a tight, confident bed
- Music: `happy-beats-business-moves-vol-11-by-ende-dot-app.mp3` — clean 115 BPM pulse, early strong cues that match action landings (not the chirpier vol-1 opener)
- Music treatment: start at 0.00s; sit under UI at ~0.22; fade from ~19.2s so the welcome can breathe; no late drop
- Music cue guidance: bundled preset `<skill-dir>/assets/music/cues/happy-beats-business-moves-vol-11-by-ende-dot-app.music-cues.md` (114.84 BPM). Strong-cue targets: **1.60s** (picker snap), **6.34s** (pie bloom), **17.91s** (Namaste). Beat-grid window 8.96–12.12s for pie-slice ticks. Ignore a cue if it steals hold time from readable type.
- Audio-reactive treatment: subtle; teal edge glow / pie-slice presence breathe with RMS. No waveform, no EQ bars.
- SFX posture: sparse, motion-matched, professional restraint. Clicks on key/click. Soft impact on picker snap and pie bloom. One warmer hit on confetti — not a casino fanfare.
- Audio-coupled moments: keycap chord → picker snap; pie scroll ticks; number-key `3`; welcome confetti
- Restraint rule: no whooshes, no slide-in beds, no repeated bright clicks. Diegetic first.

## Storyboard

### Scene 1 — At the cursor — 3.6s
Dark macOS desktop (menu-bar otter already in the status bar — dock empty). A Notes-like window, cursor mid-sentence. Keycaps ⌃ ⌥ ⌘ V assemble and depress. The real picker (360×380, 12px continuous radius, material, 1px separator stroke) **snaps on at the cursor** — search "Search", numbered rows, pin glyphs, Plain, footer keycaps (`↩ paste` · `⇧↩ plain` · `⌘P pin` · `1–9`). Super, small, settled 0.9s+: **At the cursor.**
Rows (fictional, no personal data):
1. ship the picker at the cursor
2. `#2ec4d6` + teal swatch
3. `func paste(_ clip: Clip)` (purple `func`, blue none, secondary comment if needed)
Copy that must appear: Search, Plain, 1–9, the keycap hint labels.
Sequential/interaction: yes — keycaps press, then picker appears as one instant (not a list building).
Audio intent: coiled, then a clean snap.
Audio-coupled idea: key ticks on the chord; soft impact the instant the panel exists.
Music: vol-11 under, low.
Transition mood: hard cut on the next action (cursor already moving) → Scene 2

### Scene 2 — Hot corner — 8.2s
Same desktop. Cursor travels to the **top-right hot corner** and docks. A **radial pie** blooms from that corner — this is the standout visual, give it the hold. Scroll wheel ticks rotate selection through slices (most screen time of the video):
1. text: ship the picker at the cursor
2. color: `#2ec4d6` swatch
3. code: `func paste(_ clip: Clip)`
4. screenshot thumb + OCR overlay text "Clean up / Rephrase" becoming **searchable**
5. link: jxngrx.com (public site from the welcome — no private URLs)
Click the selected slice; it flashes copied. Super, small: **Scroll. Click. Recopy.**
Sequential/interaction: yes — cursor to corner, pie bloom, 5 slice ticks, click.
Audio intent: confident, mechanical, no carnival.
Audio-coupled idea: soft bloom on appear; low ticks on each slice (every other beat if text must be read; ticks may hit the grid); click on recopy.
Music: vol-11; lock bloom near **6.34s** (scene-absolute ~5.8–6.5). Slice ticks in the 8.96–12.12 beat-grid window.
Transition mood: hard cut on the click's resolution → Scene 3

### Scene 3 — Hit 3 — 5.2s
Picker already open (same chrome as Scene 1). Number column 1–9 visible. Keycap **3** depresses; row 3 (`func paste(_ clip: Clip)`) selection-washes and pastes into the Notes window. Immediate after: footer **Clean up** and **Rephrase** — Rephrase menu opens with the three real tones: Friendly chat / Professional chat / Professional mail. Tiny settled label: **On device.**
Do not narrate "AI features." Show the buttons and the three tones. Hold the menu long enough to read (~1.2s+).
Sequential/interaction: yes — key 3, paste, Rephrase menu items.
Audio intent: dry keyboard flex, then a quieter confirmation.
Audio-coupled idea: one key click on 3; no extra sting on the menu.
Music: continue under.
Transition mood: hard cut → Scene 4

### Scene 4 — Namaste — 4.0s
The first-launch welcome, treated as a human sign-off — not a settings alert clone for its own sake. Centered line, **Jerox** bold:
**Namaste 🙏, Welcome to Jerox Family**
Confetti (warm, brief — the 🎉 from the real welcome). Teal otter with orange clipboard enters last, not first. Small lockup under: **Jerox** and `native · menu bar · on device`.
Verbatim welcome from the app (allowed to shorten the "developed by jxngrx.com 🎉💚" clause into the lockup if the full sentence crowds; prefer the user-specified closer).
Sequential/interaction: none required; confetti is the motion.
Audio intent: warmer, still quiet. Let the last chord ring.
Audio-coupled idea: one soft success/confetti hit near **17.91s**; music fades from ~19.2s.
Transition mood: hold, then end.

**Scene duration sum: 3.6 + 8.2 + 5.2 + 4.0 = 21.0s**

**Music mood for this video:** tight / confident / not chirpy
**Audio summary:** A 115 BPM bed sits under diegetic UI hits — chord, snap, pie ticks, number key — then steps back so the Namaste close can feel human.

## Music cue guidance
- Track: `happy-beats-business-moves-vol-11-by-ende-dot-app.mp3` @ ~114.84 BPM
- Preset: `<skill-dir>/assets/music/cues/happy-beats-business-moves-vol-11-by-ende-dot-app.music-cues.md`
- Strong-cue locks (1–3): 1.60s picker snap; 6.34s pie bloom; 17.91s Namaste
- Beat-grid: pie slices in 8.96 / 9.50 / 10.54 / 11.06 / 11.60 (skip a beat if a label needs a full read)
- Restraint: polished-adjacent — do not decorate every beat. Story and readability win.

## Cut list (scope we will not shoot)
- Settings window, retention steppers, OpenRouter fields
- Dock icon (the app has none)
- Generic "fast / powerful / streamlined" cards
- Separate AI or OCR scenes
- Series of 6+ feature title cards
