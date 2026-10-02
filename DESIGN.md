---
name: Jerox
description: A true-black framed product stage where the Mac app's real panels run live and one blue dot carries the brand.
colors:
  jerox-blue: "#0a84ff"
  jerox-blue-bright: "#3d9dff"
  button-blue: "#0068d6"
  button-blue-hover: "#0071e3"
  true-black: "#000000"
  stage-black: "#0c0c0e"
  frame-black: "#0a0a0c"
  inner-graphite: "#131316"
  hairline: "rgba(255, 255, 255, .08)"
  hairline-strong: "rgba(255, 255, 255, .14)"
  text-primary: "#f4f4f5"
  text-muted: "#a1a1aa"
  text-faint: "#80808a"
  silver: "#eef0f4"
  silver-shadow: "#9ea5b4"
  graphite: "#212328"
typography:
  display:
    fontFamily: "Inter, system-ui, sans-serif"
    fontSize: "clamp(46px, 7vw, 96px)"
    fontWeight: 600
    lineHeight: 1
    letterSpacing: "-0.035em"
    fontVariation: "font-optical-sizing: auto (opsz 14-32)"
  headline:
    fontFamily: "Inter, system-ui, sans-serif"
    fontSize: "clamp(36px, 4.6vw, 60px)"
    fontWeight: 600
    lineHeight: 1.04
    letterSpacing: "-0.035em"
  wordmark:
    fontFamily: "Inter, system-ui, sans-serif"
    fontSize: "clamp(120px, 24vw, 360px)"
    fontWeight: 700
    lineHeight: 0.78
    letterSpacing: "-0.035em"
  caption:
    fontFamily: "Inter, system-ui, sans-serif"
    fontSize: "clamp(20px, 2vw, 26px)"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "-0.02em"
  title:
    fontFamily: "Inter, system-ui, -apple-system, sans-serif"
    fontSize: "18px"
    fontWeight: 600
    letterSpacing: "-0.01em"
  lede:
    fontFamily: "Inter, system-ui, -apple-system, sans-serif"
    fontSize: "clamp(17px, 1.5vw, 20px)"
    fontWeight: 400
    lineHeight: 1.55
  body:
    fontFamily: "Inter, system-ui, -apple-system, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.55
  label-mono:
    fontFamily: "JetBrains Mono, ui-monospace, SF Mono, Menlo, monospace"
    fontSize: "12.5px"
    fontWeight: 500
    letterSpacing: "0.02em"
  keycap:
    fontFamily: "JetBrains Mono, ui-monospace, SF Mono, Menlo, monospace"
    fontSize: "12px"
    fontWeight: 500
rounded:
  stage: "28px"
  card: "24px"
  inner: "17px"
  popover: "13px"
  keycap: "7px"
  pill: "999px"
spacing:
  frame-gap: "8px"
  stage-inset: "12px"
  grid-gap: "14px"
  head-gap: "16px"
  pane: "30px"
  head-bottom: "52px"
  section: "clamp(110px, 14vw, 180px)"
components:
  button-primary:
    backgroundColor: "{colors.button-blue}"
    textColor: "#ffffff"
    typography: "{typography.title}"
    rounded: "{rounded.pill}"
    padding: "0 22px"
    height: "46px"
  button-primary-hover:
    backgroundColor: "{colors.button-blue-hover}"
  waitlist-field:
    backgroundColor: "rgba(255, 255, 255, .04)"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.pill}"
    padding: "6px"
    width: "min(480px, 100%)"
  nav-pill:
    backgroundColor: "rgba(16, 16, 19, .78)"
    textColor: "{colors.text-muted}"
    rounded: "{rounded.pill}"
    padding: "0 6px"
    height: "46px"
  card-frame:
    backgroundColor: "{colors.frame-black}"
    rounded: "{rounded.card}"
    padding: "{spacing.frame-gap}"
  card-inner:
    backgroundColor: "{colors.inner-graphite}"
    textColor: "{colors.text-primary}"
    rounded: "{rounded.inner}"
    padding: "{spacing.pane}"
  keycap:
    backgroundColor: "#1c1c21"
    textColor: "#d9d9de"
    typography: "{typography.keycap}"
    rounded: "{rounded.keycap}"
    height: "24px"
  status-chip:
    backgroundColor: "rgba(255, 255, 255, .04)"
    textColor: "#d4d4d8"
    rounded: "{rounded.pill}"
    padding: "7px 14px"
---

# Design System: Jerox

## Overview

**Creative North Star: "The Lit Stage"**

A true-black room with one framed stage in it. Everything the visitor needs to believe is on that stage: the Mac app's own panels, rebuilt in the page and running, and a film that plays as they scroll. The page itself stays quiet so the product can perform. Surfaces are graphite on black, separated by hairlines rather than shadows; the only colour with a voice is one blue, and it is almost always a dot.

The grammar is a modern component showcase: floating pill nav, a rounded hairline stage, double-framed bento cards (an outer frame, an 8px gap, an inner panel). The stacked-panels mark lives as a vast, barely-lit silhouette behind the hero headline, and the footer ends on a giant wordmark whose period is the blue dot over a blue haze. The dot is the system's signature: hero period, film cursor, live-state indicator, recording chip, wordmark period.

The world rejects the cream editorial page, the otter mascot, and the centered gradient SaaS hero. It carries no price, logos, testimonials, or invented numbers; proof is the working product.

**Key Characteristics:**
- True black page; one framed, rounded stage per act (hero, close).
- One accent, Jerox blue, rationed to the action, the dot, and live state.
- Double frames: outer frame, 8px gap, inner panel.
- Hairline borders (8% and 14% white), never heavy rules.
- Inter with optical sizing for everything human; JetBrains Mono only for keys, sizes, and system notes.
- Real product panels as illustration; no stock imagery, no invented UI.

## Colors

A near-monochrome graphite ladder on true black, with one saturated blue that does all the talking.

### Primary
- **Jerox Blue** (`jerox-blue`): the dot. Hero headline period, film rail progress, live-state dots in the privacy ledger and dictation chip, the footer wordmark period, focus outlines, caret colour, and the base of the closing haze. Also the alpha base for selections (16 to 38%).
- **Jerox Blue Bright** (`jerox-blue-bright`): lit highlights only, the rephrase sparkle and the second haze bloom.
- **Button Blue** (`button-blue`, hover `button-blue-hover`): every filled button. It is Jerox Blue taken darker so white button text stays legible; the brighter blue would not hold white text.

### Neutral
- **True Black** (`true-black`): the page itself, scrollbar track, theme colour.
- **Stage Black** (`stage-black`): the hero stage, as the top of a vertical gradient (#121215 to #09090b); the closing stage sits darker at #050506.
- **Frame Black** (`frame-black`): outer frame of every card and of the film.
- **Inner Graphite** (`inner-graphite`): inner panels inside a frame.
- **Hairline** / **Hairline Strong** (`hairline`, `hairline-strong`): all borders and dividers; strong is for hover, inputs, and nav separators.
- **Text Primary / Muted / Faint** (`text-primary`, `text-muted`, `text-faint`): headings and key terms; ledes and body copy; table headers, placeholders, and mono notes.
- **Silver / Silver Shadow / Graphite** (`silver`, `silver-shadow`, `graphite`): the logo's materials. Silver-to-silver-shadow fills the dictation level bars; graphite is the dictation bar body.

Product-panel replicas carry the app's own palettes (the light clipboard panel on #eceef2 paper with #1b1d22 ink and #0060df link blue; the dark rephrase popover on #1d1e22). Those belong to the replica, not to page chrome.

### Named Rules
**The One Dot Rule.** Jerox Blue appears only on the primary action, the dot, and live state. If a blue element is not one of those three, it is wrong.

**The Legible Button Rule.** Filled buttons use Button Blue, never Jerox Blue, so white text reads.

## Typography

**Display Font:** Inter variable (opsz 14 to 32, wght 400 to 700), self-hosted, with system-ui fallback
**Body Font:** Inter (same file)
**Label/Mono Font:** JetBrains Mono 500, self-hosted, with ui-monospace / SF Mono / Menlo fallback

**Character:** One family doing two jobs. Optical sizing gives headlines the tighter Display cut automatically, so there is no second display face; mono appears only where a Mac would show machine text.

### Hierarchy
- **Display** (600, clamp(46px, 7vw, 96px), 1.0, -0.035em): the hero headline only, max 12ch, balanced, ending in the blue dot.
- **Headline** (600, clamp(36px, 4.6vw, 60px), 1.04, -0.035em): one per section, short declarative sentences with a period.
- **Wordmark** (700, clamp(120px, 24vw, 360px), 0.78): the footer "Jerox." only, bleeding off the bottom of the close stage.
- **Caption** (600, clamp(20px, 2vw, 26px), 1.3): film captions under the scrubbed frame.
- **Title** (600, 18px, -0.01em): card and pane titles.
- **Lede** (400, clamp(17px, 1.5vw, 20px), muted, max 56ch): the one sentence under each headline.
- **Body** (400, 17px, 1.55): base; card descriptions run 15px muted at max 44ch.
- **Label Mono** (500, 12.5px, +0.02em, faint): the "macOS 15.1" note and form status. Model sizes use mono 13.5px tabular.
- **Keycap** (mono 500, 12px; 14px in the keymap): macOS modifier glyphs and keys.

### Named Rules
**The Sentence Headline Rule.** Headlines are plain sentences ending in a period, sentence case, no labels above them.

**The Machine Text Rule.** Mono is for keys, file sizes, system notes, and (user-pinned, 2026-10-02) the uppercase nav links, pill buttons, and hero aside. Never for headlines or prose.

## Layout

Content sits in a 1200px wrap (`min(1200px, 100% - 40px)`, 32px gutters under 560px). Acts are full-bleed framed stages inset 12px from the viewport (8px on small screens), each at least one viewport tall. Sections open with a left-aligned head block (16px gap, 52px below) and are separated by a fluid section gap (`clamp(110px, 14vw, 180px)`).

Features use a 12-column bento with a 14px gap, pairing 7+5 and 5+7 spans so widths alternate down the page; the privacy ledger is a 1:1 pair; the keymap is a three-column row (keys, action, note). Under 900px everything collapses to one column and the nav drops to brand plus CTA pills.

The film is a 560vh scroll track with a sticky viewport: frame sized to the smaller of 1180px, 94vw, or the 16:9 width that fits the viewport height, caption and a seven-segment progress rail beneath.

## Elevation & Depth

Flat by default, separated by tone and hairline. Depth comes from the black ladder (page, stage, frame, inner panel) and the 8px gap between frame and panel. Shadows appear only on things that float: the nav pills, the film frame, and the product-panel popovers, where they are soft and large.

### Shadow Vocabulary
- **Float** (`box-shadow: 0 10px 30px rgba(0, 0, 0, .35)`): nav pills, with a 16px backdrop blur.
- **Stage lift** (`box-shadow: 0 40px 120px rgba(0, 0, 0, .6)`): the film frame.
- **Popover** (`box-shadow: 0 24px 60px rgba(0, 0, 0, .5)`): panel replicas on dark; the light replica uses ink-tinted shadows.
- **Dot glow** (`box-shadow: 0 6px 18px rgba(10, 132, 255, .45)`): the hero period only.

### Named Rules
**The Hairline Not Shadow Rule.** Cards separate by border and tone; a card never gets a drop shadow at rest.

## Shapes

Generous, nested rounding: stage 28px, card frame 24px, inner panel 17px (frame radius minus the 8px gap, so curves stay concentric). Everything interactive is a full pill (999px): nav, buttons, waitlist field, chips, focus rings. Small replica parts step down to 13px popovers, 7 to 9px keycaps and selection rows. Dots are perfect circles. The mark silhouette is two rounded parallelograms, the stacked-panels geometry.

## Components

### Buttons
- **Shape:** full pill (999px).
- **Primary:** Button Blue fill, white 600 text at 15px, 46px tall, 22px side padding (36px tall in the nav).
- **Hover / Focus / Active:** fill shifts to Button Blue Hover over 0.2s; focus is a 2px Jerox Blue outline offset 3px; press scales to 0.97.
- There is no secondary button; nav links are text.

### Inputs / Fields
- **Style:** the waitlist field is one pill holding the input and the button: 4% white fill, strong hairline, 6px inner padding, max 480px. Under 560px it stacks into a 22px-radius block.
- **Focus:** the whole pill's border turns Jerox Blue at 70%; caret is Jerox Blue.
- **Error / Success:** shown in the mono note below, #ff8a80 for error, #8cc8ff for success.

### Navigation
- Three separate floating pills, centered and fixed 22px from the top: brand (mark plus wordmark), section links (14px muted, hairline separators, brighten on hover), and the CTA. 78% black glass with blur and the Float shadow. Under 900px the links pill hides.

### Cards / Containers
- **Corner Style:** 24px frame, 17px inner panel.
- **Background:** Frame Black outer, Inner Graphite inner (or the light paper panel when the replica is light).
- **Shadow Strategy:** none; see Elevation.
- **Border:** hairline, strong on hover.
- **Internal Padding:** 8px frame gap; 30px in text panes; 18px/14px card footers.

### Keycaps
- Mono glyph on #1c1c21, #2c2c33 border with a 2px bottom edge for a physical key, 7px radius, 24px tall (32px in the keymap). Uses the real macOS modifier glyphs.

### Live Product Panels (signature)
- The app's actual panels rebuilt in HTML and animated: clipboard history at the cursor, rephrase popover, dictation bar, screen-text capture. Shortcuts and model data match the shipping app. Selection highlights are Jerox Blue at 16 to 20%; a pressed key flashes Jerox Blue.

### Dot and Haze (signature)
- The blue dot (0.19em circle) closes the hero headline and the footer wordmark. The close stage ends in three blurred radial blue blooms (48px blur) rising from the bottom under the giant wordmark.

### Motion
- One ease everywhere, `cubic-bezier(.16, 1, .3, 1)`. Reveals rise 28px out of a 6px blur over 0.9 to 1s, staggered 70ms. Captions crossfade the same way. Everything settles to static under reduced motion.

## Do's and Don'ts

### Do:
- **Do** keep the page true black (#000000) and put content on framed stages and double-framed cards.
- **Do** ration Jerox Blue to the primary action, the dot, and live state.
- **Do** use Button Blue for filled buttons so white text stays legible.
- **Do** nest radii concentrically: 28px stage, 24px frame, 17px inner panel, pills for anything you press.
- **Do** separate surfaces with 8% and 14% white hairlines and the black tonal ladder.
- **Do** show the product with rebuilt, working panels whose shortcuts and data match the app.
- **Do** write headlines as short sentences ending in a period.
- **Do** use JetBrains Mono only for keys, sizes, and system notes.

### Don't:
- **Don't** use a cream or paper page background, an otter or mascot, or a centered gradient hero.
- **Don't** add a second accent colour or use blue as decoration.
- **Don't** put drop shadows on cards at rest.
- **Don't** add a second display typeface; Inter's optical sizing is the display cut.
- **Don't** put small uppercase labels above headlines.
- **Don't** invent prices, logos, testimonials, or numbers.
