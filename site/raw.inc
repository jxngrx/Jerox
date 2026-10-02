<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Jerox — Everything you copy. Right where you left it.</title>
  <meta name="description" content="Jerox is a native macOS menu-bar clipboard. History opens at the cursor. Pins stay on top. Rephrase pastes back. Requires macOS 15.1+.">
  <meta property="og:title" content="Jerox — Everything you copy. Right where you left it.">
  <meta property="og:description" content="Native macOS clipboard manager. Opens at the cursor. Pins, search, and a rewrite that pastes back. Menu-bar otter. macOS 15.1+.">
  <meta property="og:type" content="website">
  <meta name="theme-color" content="#07090c">
  <link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Ccircle cx='16' cy='16' r='16' fill='%23070a0c'/%3E%3Cellipse cx='16' cy='17' rx='10' ry='11' fill='%232ec8c4'/%3E%3Cellipse cx='16' cy='21' rx='6.2' ry='6.5' fill='%23f3ead8'/%3E%3Ccircle cx='12.2' cy='15' r='2.1' fill='%23111416'/%3E%3Ccircle cx='19.6' cy='15' r='2.1' fill='%23111416'/%3E%3Ccircle cx='12.7' cy='14.5' r='.7' fill='%23fff'/%3E%3Ccircle cx='20.1' cy='14.5' r='.7' fill='%23fff'/%3E%3Crect x='12' y='22.2' width='8' height='6.2' rx='1' fill='%23f08a3a'/%3E%3Crect x='14.2' y='21.2' width='3.6' height='1.6' rx='.4' fill='%23c5c8cc'/%3E%3C/svg%3E">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Azeret+Mono:wght@500;600&family=Bricolage+Grotesque:opsz,wght@12..96,400;12..96,700;12..96,800&family=Sora:wght@400;500;600&display=swap" rel="stylesheet">
  <script src="https://cdnjs.cloudflare.com/ajax/libs/gsap/3.12.5/gsap.min.js" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/gsap/3.12.5/ScrollTrigger.min.js" crossorigin="anonymous" referrerpolicy="no-referrer"></script>
  <style>
    :root {
      --ink: #07090c;
      --ink-2: #12181c;
      --ink-3: #1b2328;
      --teal: #2ec8c4;
      --orange: #f08a3a;
      --cream: #f3ead8;
      --cream-dim: #d2c7b0;
      --line: rgba(243, 234, 216, .16);
      --display: "Bricolage Grotesque", "Trebuchet MS", sans-serif;
      --sans: Sora, "Segoe UI", sans-serif;
      --mono: "Azeret Mono", ui-monospace, monospace;
    }
    *, *::before, *::after { box-sizing: border-box; }
    html { scroll-behavior: smooth; }
    html, body { margin: 0; background: var(--ink); color: var(--cream); }
    body {
      font-family: var(--sans);
      font-size: 1.0625rem;
      line-height: 1.55;
    }
    img { max-width: 100%; display: block; }
    a { color: inherit; }
    button { font: inherit; }
    ::selection { background: var(--teal); color: var(--ink); }
    :focus-visible { outline: 2px solid var(--teal); outline-offset: 3px; }
    .skip { position: absolute; left: -999px; }
    .skip:focus { left: 12px; top: 12px; z-index: 80; background: var(--teal); color: var(--ink); padding: .65rem 1rem; }
    .mesh, .grain { position: fixed; inset: 0; pointer-events: none; z-index: 0; }
    .mesh {
      background:
        radial-gradient(48% 38% at 82% 18%, rgba(46, 200, 196, .16), transparent 62%),
        radial-gradient(38% 48% at 12% 82%, rgba(240, 138, 58, .1), transparent 58%);
    }
    .grain {
      z-index: 1; opacity: .2; mix-blend-mode: overlay;
      background-image: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='140' height='140'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='.8' numOctaves='4' stitchTiles='stitch'/></filter><rect width='100%' height='100%' filter='url(%23n)'/></svg>");
    }
    .blob {
      position: fixed; width: 240px; height: 240px; border-radius: 50%;
      background: rgba(46, 200, 196, .22);
      mix-blend-mode: screen; pointer-events: none; z-index: 2;
      transform: translate(-50%, -50%); opacity: 0;
    }
    body.has-pointer .blob { opacity: .85; }
    header, main, footer { position: relative; z-index: 3; }
    .nav {
      position: sticky; top: 0; z-index: 20;
      display: flex; align-items: center; justify-content: space-between;
      padding: .85rem 4vw; gap: 1rem;
      background: rgba(7, 9, 12, .8);
      backdrop-filter: blur(18px);
      border-bottom: 1px solid var(--line);
    }
    .brand {
      display: flex; align-items: center; gap: .7rem;
      text-decoration: none; font-family: var(--display); font-weight: 800;
      letter-spacing: -.03em; font-size: 1.15rem;
    }
    .brand img { width: 36px; height: 36px; border-radius: 50%; }
    .nav-links { display: flex; gap: 1.5rem; font-size: .95rem; }
    .nav-links a { text-decoration: none; color: var(--cream-dim); }
    .nav-links a:hover, .nav-links a:focus-visible { color: var(--cream); }
    .btn {
      display: inline-flex; align-items: center; justify-content: center;
      background: var(--orange); color: #1a0e04; text-decoration: none;
      font-weight: 600; padding: .95rem 1.35rem; border-radius: 999px;
      border: 0; cursor: pointer;
      box-shadow: 0 12px 28px rgba(0, 0, 0, .35);
      will-change: transform;
    }
    .btn .note { font-size: .72rem; font-weight: 500; margin-left: .55rem; }
    .hero {
      min-height: 100svh; display: grid; grid-template-columns: 1.05fr .95fr;
      align-items: end; padding: 8vh 5vw 8vh; gap: 2.5rem;
    }
    .hero h1 {
      font-family: var(--display); font-weight: 800; letter-spacing: -.04em;
      font-size: clamp(3.2rem, 8vw, 6rem); line-height: .94; margin: 0 0 1.1rem;
      max-width: 12ch;
    }
    .hero h1 .word { display: inline-block; overflow: hidden; vertical-align: bottom; }
    .hero h1 .char { display: inline-block; }
    .lede { font-size: clamp(1.15rem, 2vw, 1.4rem); color: var(--cream-dim); max-width: 36ch; margin: 0 0 2rem; }
    .hero-actions { display: flex; align-items: center; gap: 1.2rem; flex-wrap: wrap; }
    .req { font-size: .88rem; color: var(--cream-dim); }
    .hero-visual { position: relative; min-height: 52vh; }
    .otter-float { width: min(640px, 100%); margin-left: auto; }
    .menubar {
      display: flex; align-items: center; justify-content: space-between;
      margin: 0 5vw; padding: .5rem 1rem;
      background: #161a1e; border: 1px solid var(--line);
      border-radius: 10px 10px 0 0; font-family: var(--mono); font-size: .875rem;
      color: var(--cream-dim);
    }
    .menubar-left, .menubar-right { display: flex; align-items: center; gap: .75rem; }
    .menubar img { width: 16px; height: 16px; }
    .marquee { border-block: 1px solid var(--line); background: #0b1013; overflow: hidden; padding: 1.15rem 1.5rem; }
    .marquee-track {
      display: flex; gap: 2.5rem; width: max-content;
      animation: ticker 28s linear infinite;
      font-family: var(--display); font-weight: 800; letter-spacing: -.02em;
      font-size: clamp(1.4rem, 3vw, 2.2rem); text-transform: uppercase;
    }
    .marquee-track span { color: var(--teal); }
    @keyframes ticker { from { transform: translateX(0); } to { transform: translateX(-50%); } }
    section { padding: 7.5rem 5vw; }
    .how { padding: 0; }
    .how-pin { height: 320vh; }
    .how-sticky {
      position: sticky; top: 0; height: 100vh;
      display: grid; grid-template-columns: .9fr 1.1fr; gap: 3rem;
      align-items: center; padding: 0 5vw;
    }
    h2 {
      font-family: var(--display); font-weight: 800; letter-spacing: -.04em;
      font-size: clamp(2.3rem, 5vw, 4.2rem); line-height: .96; margin: 0 0 1.15rem;
    }
    .copy p { color: var(--cream-dim); max-width: 38ch; }
    .bento { display: grid; grid-template-columns: 1.3fr .7fr; gap: .85rem; margin-top: 1.8rem; }
    .tile {
      background: var(--ink-2); border: 1px solid var(--line); border-radius: 16px;
      padding: 1.25rem 1.35rem;
    }
    .tile h3 { margin: 0 0 .45rem; font-size: 1.05rem; font-family: var(--display); }
    .tile p { margin: 0; font-size: .92rem; color: var(--cream-dim); }
    .tile.wide { grid-column: 1 / -1; display: flex; gap: 1.1rem; align-items: center; }
    .tile.wide img { width: 96px; border-radius: 12px; }
    .stage { position: relative; height: min(72vh, 640px); }
    .mac {
      position: absolute; inset: 8% 4% 4% 10%;
      background: #22262b; border-radius: 14px; border: 1px solid rgba(255,255,255,.12);
      box-shadow: 0 22px 50px rgba(0,0,0,.45); overflow: hidden;
    }
    .traffic { display: flex; gap: 6px; padding: 12px 14px; }
    .traffic span { width: 10px; height: 10px; border-radius: 50%; display: block; }
    .traffic span:nth-child(1) { background: #ff5f57; }
    .traffic span:nth-child(2) { background: #febc2e; }
    .traffic span:nth-child(3) { background: #28c840; }
    .doc { padding: 1.6rem 1.9rem; font-family: var(--display); font-size: 1.65rem; color: #d7d3c8; }
    .caret { display: inline-block; width: 2px; height: 1.1em; background: var(--teal); vertical-align: text-bottom; animation: blink 1s steps(2) infinite; }
    @keyframes blink { 50% { opacity: 0; } }
    .chord { display: flex; gap: .45rem; margin: 1.1rem 0 0; }
    .key {
      font-family: var(--mono); font-size: .875rem; background: #16181c; color: var(--cream);
      border: 1px solid #3a3f46; border-bottom-width: 3px; border-radius: 7px;
      padding: .45rem .6rem; min-width: 2.1rem; text-align: center; display: inline-block;
    }
    .key.is-down { transform: translateY(2px); border-bottom-width: 1px; background: var(--teal); color: var(--ink); }
    .panel {
      position: absolute; left: 26%; top: 26%; width: min(340px, 78%);
      background: rgba(22, 26, 30, .82); backdrop-filter: blur(22px);
      border: 1px solid rgba(255,255,255,.16); border-radius: 14px;
      box-shadow: 0 18px 48px rgba(0,0,0,.42); opacity: 0; transform: translateY(16px);
      padding: .35rem;
    }
    .search {
      margin: 8px; background: rgba(0,0,0,.3); border: 1px solid var(--line);
      border-radius: 8px; padding: .55rem .75rem; color: var(--cream-dim); font-size: .86rem;
    }
    .rows { padding: 4px 8px 12px; }
    .row {
      display: grid; grid-template-columns: 18px 1fr auto; gap: .55rem; align-items: center;
      padding: .55rem .65rem; border-radius: 8px; font-size: .84rem; opacity: 0; transform: translateX(-12px);
    }
    .row.on { background: rgba(46, 200, 196, .14); }
    .swatch { width: 14px; height: 14px; border-radius: 4px; background: var(--orange); }
    .pin-mark { width: 8px; height: 8px; border-radius: 50%; background: var(--orange); opacity: 0; }
    .json { font-family: var(--mono); font-size: .875rem; white-space: pre; color: #9ad9d6; }
    .draw-label { position: absolute; bottom: 6%; left: 10%; font-size: .875rem; color: var(--cream-dim); }
    .types { padding-right: 0; padding-left: 0; }
    .types-head { padding: 0 5vw 2.2rem; }
    .hscroll { overflow: hidden; }
    .htrack { display: flex; gap: 1.3rem; padding: 0 5vw 2rem; width: max-content; }
    .type-card {
      width: min(72vw, 380px); min-height: 440px; border-radius: 22px;
      border: 1px solid var(--line); background: var(--ink-2); padding: 1.5rem 1.45rem;
      transform-style: preserve-3d;
    }
    .type-card:hover, .type-card:focus-within { transform: rotateX(5deg) rotateY(-6deg) translateY(-6px); }
    .type-card h3 { font-family: var(--display); font-size: 1.8rem; margin: .35rem 0 .7rem; }
    .type-card p { color: var(--cream-dim); margin: 0; }
    .viz { height: 188px; border-radius: 14px; margin-bottom: 1.1rem; overflow: hidden; background: var(--ink-3); display: grid; place-items: center; padding: 1rem; }
    .rich { font-family: Georgia, serif; }
    .rich em { color: var(--orange); font-style: italic; }
    .codeviz { font-family: var(--mono); font-size: .875rem; color: #9ad9d6; }
    .kw { color: #c792ea; } .str { color: #c3e88d; }
    .rephrase { display: grid; grid-template-columns: 1fr 1fr; gap: 3rem; align-items: center; }
    .tones { display: flex; gap: .5rem; flex-wrap: wrap; margin: 1.1rem 0 1.3rem; }
    .tones button {
      background: transparent; color: var(--cream); border: 1px solid var(--line);
      border-radius: 999px; padding: .55rem .95rem; cursor: pointer;
    }
    .tones button[aria-pressed="true"] { background: var(--teal); color: var(--ink); border-color: var(--teal); }
    .demo { background: var(--ink-2); border: 1px solid var(--line); border-radius: 18px; padding: 1.4rem 1.45rem; }
    .demo .before { color: var(--cream-dim); text-decoration: line-through; text-decoration-color: #8a5a32; margin-bottom: 1.1rem; }
    .demo .after { min-height: 6.5rem; font-size: 1.15rem; }
    .neon-wrap { display: grid; place-items: center; }
    .neon-otter { width: min(100%, 420px); }
    .neon-otter path, .neon-otter ellipse, .neon-otter circle {
      fill: none; stroke: var(--teal); stroke-width: 2.2; stroke-linecap: round; stroke-linejoin: round;
    }
    .clip-stroke { stroke: var(--orange); }
    .keys-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(230px, 1fr)); gap: .9rem; margin-top: 2.1rem; }
    .key-card { border: 1px solid var(--line); border-radius: 16px; padding: 1.2rem 1.25rem; background: var(--ink-2); }
    .key-card:hover, .key-card:focus-within { border-color: var(--teal); }
    .key-card p { margin: .65rem 0 0; color: var(--cream-dim); }
    .privacy, .focused { display: grid; grid-template-columns: 1fr 1fr; gap: 3rem; align-items: center; }
    .iso-otter { width: min(100%, 420px); border-radius: 24px; }
    .nope { list-style: none; padding: 0; margin: 0; }
    .nope li { padding: .85rem 0; border-bottom: 1px solid var(--line); display: flex; justify-content: space-between; gap: 1rem; }
    .nope small { color: var(--teal); font-family: var(--mono); }
    .faq { max-width: 760px; }
    details { border-top: 1px solid var(--line); padding: 1.15rem 0; }
    details:last-of-type { border-bottom: 1px solid var(--line); }
    summary { cursor: pointer; font-family: var(--display); font-size: 1.3rem; list-style: none; padding: .15rem 0; }
    summary::-webkit-details-marker { display: none; }
    details p { color: var(--cream-dim); margin: .7rem 0 0; }
    .cta { min-height: 86vh; display: grid; place-items: center; text-align: center; padding: 6rem 5vw; overflow: hidden; }
    .wordmark-wrap { overflow: hidden; width: 100%; }
    .wordmark {
      font-family: var(--display); font-weight: 800; font-size: 6rem;
      letter-spacing: -.04em; line-height: .85; margin: 0; white-space: nowrap;
      transform-origin: center;
      animation: drift 28s linear infinite;
    }
    @keyframes drift { from { transform: translateX(6%) scale(1.35); } to { transform: translateX(-6%) scale(1.35); } }
    .cta-otter { width: min(400px, 68vw); margin: 0 auto 1.5rem; }
    .foot {
      display: flex; justify-content: space-between; align-items: flex-end; gap: 2rem;
      padding: 2.2rem 5vw 2.6rem; border-top: 1px solid var(--line); flex-wrap: wrap;
    }
    .pixel { width: 96px; image-rendering: pixelated; cursor: pointer; transform-origin: bottom center; }
    .preload {
      position: fixed; inset: 0; z-index: 50; background: var(--ink);
      display: grid; place-items: center;
    }
    .preload-inner { text-align: center; position: relative; padding: 2rem; }
    .ring { width: 120px; height: 120px; transform: rotate(-90deg); }
    .ring circle { fill: none; stroke-width: 3; }
    .ring .bg { stroke: var(--line); }
    .ring .fg { stroke: var(--teal); stroke-dasharray: 339; stroke-dashoffset: 339; }
    .preload img { width: 64px; height: 64px; border-radius: 50%; position: absolute; left: 50%; top: 38%; transform: translate(-50%, -50%); }
    .count { font-variant-numeric: tabular-nums; color: var(--teal); font-family: var(--display); font-size: 2.4rem; }
    @media (max-width: 900px) {
      .hero, .how-sticky, .rephrase, .privacy, .focused { grid-template-columns: 1fr; }
      .nav-links { display: none; }
      .how-pin { height: auto; }
      .how-sticky { position: relative; height: auto; padding: 4.5rem 5vw; }
      .hero { min-height: auto; padding-top: 4rem; }
      .bento { grid-template-columns: 1fr; }
      .type-card { width: 78vw; }
    }
    @media (prefers-reduced-motion: reduce) {
      *, *::before, *::after { animation: none !important; transition: none !important; }
      .hero h1 .char { transform: none !important; opacity: 1 !important; }
      .panel, .row { opacity: 1 !important; transform: none !important; }
      html { scroll-behavior: auto; }
    }
  </style>
</head>
<body>
  <a class="skip" href="#main">Skip to content</a>
  <div class="mesh" aria-hidden="true"></div>
  <div class="grain" aria-hidden="true"></div>
  <div class="blob" aria-hidden="true"></div>
  <div class="preload" id="preload" role="status">
    <div class="preload-inner">
      <svg class="ring" viewBox="0 0 120 120" aria-hidden="true">
        <circle class="bg" cx="60" cy="60" r="54"></circle>
        <circle class="fg" cx="60" cy="60" r="54" id="ring"></circle>
      </svg>
      <img src="media/logo-round.png" width="64" height="64" alt="">
      <p>Holding your copies</p>
    </div>
  </div>
  <header class="nav">
    <a class="brand" href="#top"><img src="media/logo-round.png" width="36" height="36" alt="">Jerox</a>
    <nav class="nav-links" aria-label="Page">
      <a href="#how">How it works</a>
      <a href="#types">Clipboard</a>
      <a href="#rephrase">Rephrase</a>
      <a href="#shortcuts">Shortcuts</a>
    </nav>
    <a class="btn magnetic" href="#download">Download for macOS</a>
  </header>
  <div class="menubar" aria-hidden="true">
    <div class="menubar-left"><strong>Finder</strong><span>File</span><span>Edit</span><span>View</span><img src="media/otter-menu.png" width="16" height="16" alt=""></div>
    <div class="menubar-right"><span>Wed 30</span><span>1:33 PM</span></div>
  </div>
  <main id="main">
    <section class="hero" id="top">
      <div>
        <h1 data-split>Everything you copy.</h1>
        <p class="lede">Right where you left it. A menu-bar otter keeps history on disk and opens it at the cursor, then gets out of the way.</p>
        <div class="hero-actions">
          <a class="btn magnetic" href="#download">Download for macOS <span class="note">15.1+</span></a>
          <p class="req">Native Swift. No Dock icon while you work.</p>
        </div>
      </div>
      <div class="hero-visual">
        <img class="otter-float" src="media/otter-float.jpg" width="960" height="540" alt="Teal otter floating on its back, holding a glowing orange clipboard.">
      </div>
    </section>
    <div class="marquee" aria-hidden="true">
      <div class="marquee-track">
        <b>Text</b><span>·</span><b>Rich text</b><span>·</span><b>Images</b><span>·</span><b>Links</b><span>·</span><b>Colors</b><span>·</span><b>Code</b><span>·</span><b>JSON</b><span>·</span><b>Files</b><span>·</span><b>Screenshots</b><span>·</span>
        <b>Text</b><span>·</span><b>Rich text</b><span>·</span><b>Images</b><span>·</span><b>Links</b><span>·</span><b>Colors</b><span>·</span><b>Code</b><span>·</span><b>JSON</b><span>·</span><b>Files</b><span>·</span><b>Screenshots</b><span>·</span>
      </div>
    </div>
    <section class="how" id="how">
      <div class="how-pin">
        <div class="how-sticky">
          <div class="copy">
            <h2>Open it where you already are.</h2>
            <p>Control-Option-Command-V pops the list at the cursor. Escape, a click outside, or the shortcut again puts you back in the app you never left.</p>
            <div class="chord" aria-hidden="true">
              <span class="key" data-k="1">⌃</span>
              <span class="key" data-k="2">⌥</span>
              <span class="key" data-k="3">⌘</span>
              <span class="key" data-k="4">V</span>
            </div>
            <div class="bento">
              <article class="tile"><h3>Newest first</h3><p>Copy the same thing again and the old row moves up. Duplicates do not pile.</p></article>
              <article class="tile"><h3>1–9 paste</h3><p>A number pastes that row. Return pastes. Shift-Return pastes plain.</p></article>
              <article class="tile wide">
                <img src="media/otter-papercut.jpg" width="160" height="160" alt="Paper-cut otter with a pin through its clipboard.">
                <div><h3>Pins stay on top</h3><p>Command-P keeps a row above history until you unpin it. Pins ignore the item and day limits.</p></div>
              </article>
            </div>
          </div>
          <div class="stage">
            <div class="mac">
              <div class="traffic"><span></span><span></span><span></span></div>
              <div class="doc">Dear team,<br>The numbers from last week are <span class="caret"></span></div>
            </div>
            <div class="panel" id="clip-panel">
              <div class="search" id="live-search">Search</div>
              <div class="rows">
                <div class="row" data-row="0"><span class="pin-mark"></span><span>Meeting notes — Thu</span><span>⌘P</span></div>
                <div class="row" data-row="1"><span class="swatch"></span><span>#E08A3A  rgb(224, 138, 58)</span><span></span></div>
                <div class="row json" data-row="2">{ "ok": true }</div>
                <div class="row" data-row="3"><span></span><span>https://jxngrx.com</span><span></span></div>
                <div class="row" data-row="4"><span></span><span>Screenshot 2026-09-30.png</span><span></span></div>
              </div>
            </div>
            <p class="draw-label">A drawing of the real list. Not a screenshot.</p>
          </div>
        </div>
      </div>
    </section>
    <section class="types" id="types">
      <div class="types-head">
        <h2>What it actually keeps.</h2>
        <p class="lede">Polled from the system clipboard. Nothing already there at launch is imported.</p>
      </div>
      <div class="hscroll">
        <div class="htrack">
          <article class="type-card"><div class="viz"><p>Grocery: tomato, potato, ladyfingers, Amit.</p></div><h3>Text</h3><p>Plain copies land as rows. Search ranks an exact phrase above a fuzzy match.</p></article>
          <article class="type-card"><div class="viz rich"><p>Paste puts the <em>original formatting</em> back. RTF, RTFD, HTML.</p></div><h3>Rich text</h3><p>Formatting is preserved until you ask for plain with Shift-Return.</p></article>
          <article class="type-card"><div class="viz"><img src="media/otter-sticker.jpg" alt="Sticker-style teal otter holding a clipboard." width="200" height="200" style="width:70%;border-radius:12px"></div><h3>Images</h3><p>Clipboard images show a preview. A single image file under 8 MB is stored as bytes so paste still works after the file moves.</p></article>
          <article class="type-card"><div class="viz"><p style="color:var(--teal);text-decoration:underline">jxngrx.com</p></div><h3>Links</h3><p>A web URL is captured even when the clipboard text is a page title. Paste writes both.</p></article>
          <article class="type-card"><div class="viz"><span class="swatch" style="width:72px;height:72px;border-radius:16px"></span></div><h3>Colors</h3><p>#hex and rgb() become a real swatch, stored as canonical hex, pasted as a color.</p></article>
          <article class="type-card"><div class="viz codeviz"><span class="kw">func</span> paste() {<br>&nbsp;&nbsp;<span class="str">"held"</span><br>}</div><h3>Code</h3><p>Detected from the text. Keywords, strings, numbers, and comments get a light tint.</p></article>
          <article class="type-card"><div class="viz json">{<br>&nbsp;&nbsp;"ok": true,<br>&nbsp;&nbsp;"items": 12<br>}</div><h3>JSON</h3><p>A whole object or array is pretty-printed immediately. That pretty text is what history keeps.</p></article>
          <article class="type-card"><div class="viz"><p>~/Desktop/Screenshot 2026-09-30.png</p></div><h3>Files and shots</h3><p>Other files stay as paths. Desktop screenshots named Screenshot or Screen Shot join as images.</p></article>
        </div>
      </div>
    </section>
    <section class="rephrase" id="rephrase">
      <div>
        <h2>Rewrite it so it sounds like you.</h2>
        <p class="lede">Rephrase uses your OpenRouter key, stored in the Keychain. Nothing runs until you ask. The reply is only the rewritten text: no em dashes, no bullet lists, no machine voice.</p>
        <div class="tones" role="tablist" aria-label="Rephrase tone">
          <button type="button" aria-pressed="true" data-tone="friendly">Friendly chat</button>
          <button type="button" aria-pressed="false" data-tone="chat">Professional chat</button>
          <button type="button" aria-pressed="false" data-tone="mail">Professional mail</button>
        </div>
        <div class="demo">
          <p class="before">hey so like i was wondering if we could maybe push the deadline?? the client is kinda freaking out and i dont have the latest numbers</p>
          <p class="after" id="typed"></p>
        </div>
        <p class="req" style="margin-top:1.1rem">In the list it rewrites the selected row. Anywhere else, select text and press Command-Shift-R. The result pastes back in place.</p>
      </div>
      <div class="neon-wrap" aria-hidden="true">
        <svg class="neon-otter" viewBox="0 0 280 300">
          <path d="M128 46c10-24 34-32 42-14"/>
          <ellipse cx="150" cy="118" rx="62" ry="70"/>
          <path d="M96 108c-10-18-8-38 8-42"/>
          <path d="M204 108c12-18 22-34 8-44"/>
          <ellipse cx="150" cy="210" rx="58" ry="62"/>
          <ellipse class="clip-stroke" cx="150" cy="228" rx="28" ry="36"/>
          <path class="clip-stroke" d="M136 196h28v10h-28z"/>
          <circle cx="128" cy="108" r="7"/>
          <circle cx="172" cy="108" r="7"/>
          <path d="M138 138c8 10 18 10 26 0"/>
          <path d="M92 200c-28 10-40 38-22 54"/>
          <path d="M208 198c30 8 40 40 18 58"/>
        </svg>
      </div>
    </section>
    <section id="shortcuts">
      <h2>The keys that matter.</h2>
      <p class="lede">Hover a chord. Customizable in Settings. Show Jerox and Rephrase need a modifier.</p>
      <div class="keys-grid">
        <article class="key-card"><div><span class="key">⌃</span> <span class="key">⌥</span> <span class="key">⌘</span> <span class="key">V</span></div><p>Show Jerox at the cursor. Press again to close.</p></article>
        <article class="key-card"><div><span class="key">esc</span></div><p>Dismiss. Click outside does the same. You land back in the previous app.</p></article>
        <article class="key-card"><div><span class="key">↩</span></div><p>Paste the selected row in its original format.</p></article>
        <article class="key-card"><div><span class="key">⇧</span> <span class="key">↩</span></div><p>Paste as plain text.</p></article>
        <article class="key-card"><div><span class="key">⌘</span> <span class="key">P</span></div><p>Pin or unpin. Pins sit above everything else.</p></article>
        <article class="key-card"><div><span class="key">1</span> … <span class="key">9</span></div><p>Paste that numbered row.</p></article>
        <article class="key-card"><div><span class="key">⌘</span> <span class="key">⇧</span> <span class="key">R</span></div><p>Rephrase the selected row, or selected text in any app.</p></article>
      </div>
    </section>
    <section class="privacy" id="privacy">
      <div>
        <h2>Local first. Cloud only when you ask.</h2>
        <p class="lede">History lives on disk. The OpenRouter key lives in the Keychain. Rephrase does not run in the background. A duplicate is not a new row; it moves to the top.</p>
        <p>Keep up to <span class="count" data-count="5000">0</span> items and <span class="count" data-count="3650">0</span> days. Pins are exempt.</p>
      </div>
      <img class="iso-otter" src="media/otter-iso.jpg" width="720" height="720" alt="Isometric otter sitting on a stack of clipboard cards.">
    </section>
    <section class="focused" id="focused">
      <div>
        <h2>Focused by design.</h2>
        <p class="lede">Jerox is a clipboard that shows up at the cursor. It is not a text workshop. These absences are the product.</p>
      </div>
      <ul class="nope">
        <li>OCR <small>not in the app</small></li>
        <li>Snippets and templates <small>not in the app</small></li>
        <li>Hot corners <small>not in the app</small></li>
        <li>Markdown stripping, trim, case, Base64 <small>not in the app</small></li>
        <li>Per-app exclusions, clipboard stacks <small>not in the app</small></li>
        <li>On-device Foundation Models <small>not in the app</small></li>
      </ul>
    </section>
    <section class="faq" id="faq">
      <h2>Before you ask.</h2>
      <details open>
        <summary>Where does history live?</summary>
        <p>On disk, on this Mac. Pins stay until you unpin them. Limits are yours: 1–5000 items, 1–3650 days.</p>
      </details>
      <details>
        <summary>Does it sit in the Dock?</summary>
        <p>No, not while you work. The circular logo appears in the Dock only while Settings is open, then hides again. The menu-bar otter is the everyday icon.</p>
      </details>
      <details>
        <summary>What does Rephrase send?</summary>
        <p>Only the text you asked to rewrite, through OpenRouter, with your key. Friendly chat, Professional chat, or Professional mail. Default tone is set in Settings.</p>
      </details>
      <details>
        <summary>What if Accessibility is off?</summary>
        <p>Paste-back into the previous app needs it. If it is missing, paste still writes the clipboard and macOS is asked for permission once per launch.</p>
      </details>
    </section>
    <section class="cta" id="download">
      <div class="wordmark-wrap"><p class="wordmark" aria-hidden="true">JEROX JEROX JEROX</p></div>
      <img class="cta-otter" src="media/otter-hero.jpg" width="800" height="800" alt="Otter holding an orange clipboard and waving.">
      <h2>Hold on to it.</h2>
      <p class="lede" style="margin-inline:auto">Native macOS 15.1+. Tiny footprint. History on disk. The otter never drops a copy.</p>
      <a class="btn magnetic" href="#download">Download for macOS <span class="note">Requires macOS 15.1+</span></a>
    </section>
  </main>
  <footer class="foot">
    <div>
      <p>Developed by <a href="https://jxngrx.com">jxngrx.com</a></p>
      <p class="req">Namaste, Welcome to Jerox Family.</p>
    </div>
    <button type="button" class="pixel-btn" aria-label="Pixel otter hops when clicked" style="background:none;border:0;padding:0;cursor:pointer">
      <img class="pixel" src="media/otter-pixel.jpg" width="96" height="96" alt="">
    </button>
  </footer>
  <script>
    gsap.registerPlugin(ScrollTrigger);
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const fine = window.matchMedia("(pointer: fine)").matches;
    (function preloader() {
      const el = document.getElementById("preload");
      const ring = document.getElementById("ring");
      if (reduced) { el.remove(); reveal(); return; }
      const tl = gsap.timeline({ onComplete() {
        gsap.to(el, { clipPath: "circle(0% at 50% 50%)", duration: .9, ease: "power3.inOut", onComplete: () => el.remove() });
        reveal();
      }});
      tl.to(ring, { strokeDashoffset: 0, duration: 1.1, ease: "power2.inOut" })
        .to(el.querySelector("img"), { scale: 1.08, duration: .4, yoyo: true, repeat: 1 }, 0);
    })();
    function splitHead() {
      document.querySelectorAll("[data-split]").forEach((h) => {
        const words = h.textContent.trim().split(/\s+/);
        h.textContent = "";
        words.forEach((w, i) => {
          const word = document.createElement("span");
          word.className = "word";
          [...w].forEach((ch) => {
            const s = document.createElement("span");
            s.className = "char";
            s.textContent = ch;
            word.appendChild(s);
          });
          h.appendChild(word);
          if (i < words.length - 1) h.appendChild(document.createTextNode(" "));
        });
      });
    }
    function reveal() {
      splitHead();
      if (!reduced) {
        gsap.from(".hero h1 .char", { yPercent: 110, duration: 1, stagger: 0.03, ease: "power4.out" });
        gsap.from(".lede, .hero-actions", { y: 24, opacity: 0, duration: .8, delay: .35, ease: "power3.out" });
        gsap.to(".otter-float", { y: 12, duration: 3.2, yoyo: true, repeat: -1, ease: "sine.inOut" });
      }
      if (fine && !reduced) {
        document.body.classList.add("has-pointer");
        const blob = document.querySelector(".blob");
        const otter = document.querySelector(".otter-float");
        window.addEventListener("pointermove", (e) => {
          gsap.to(blob, { x: e.clientX, y: e.clientY, duration: .6, ease: "power3.out" });
          const rx = (e.clientX / innerWidth - .5) * 24;
          const ry = (e.clientY / innerHeight - .5) * 16;
          gsap.to(otter, { x: rx, y: ry, duration: .8, ease: "power3.out" });
        }, { passive: true });
        document.querySelectorAll(".magnetic").forEach((btn) => {
          btn.addEventListener("pointermove", (e) => {
            const r = btn.getBoundingClientRect();
            gsap.to(btn, { x: (e.clientX - r.left - r.width / 2) * .28, y: (e.clientY - r.top - r.height / 2) * .28, duration: .3 });
          });
          btn.addEventListener("pointerleave", () => gsap.to(btn, { x: 0, y: 0, duration: .5, ease: "power3.out" }));
        });
      }
      setupHow(); setupTypes(); setupRephrase(); setupCounts();
    }
    function setupHow() {
      const keys = gsap.utils.toArray(".chord .key");
      const panel = document.getElementById("clip-panel");
      const rows = gsap.utils.toArray("[data-row]");
      const search = document.getElementById("live-search");
      const pin = document.querySelector(".pin-mark");
      const json = document.querySelector(".row.json");
      if (reduced || matchMedia("(max-width: 900px)").matches) {
        gsap.set([panel, rows, pin], { opacity: 1, x: 0, y: 0 });
        rows[0].classList.add("on");
        search.textContent = "json";
        json.textContent = "{\\n  \\"ok\\": true,\\n  \\"items\\": 12\\n}";
        keys.forEach((k) => k.classList.add("is-down"));
        return;
      }
      const tl = gsap.timeline({ scrollTrigger: { trigger: ".how-pin", start: "top top", end: "bottom bottom", scrub: 1 } });
      keys.forEach((k, i) => {
        tl.to(k, { onStart: () => k.classList.add("is-down"), onReverseComplete: () => k.classList.remove("is-down"), duration: 0.08 }, i * 0.08);
      });
      tl.to(panel, { opacity: 1, y: 0, duration: .25 }, 0.35);
      rows.forEach((r, i) => tl.to(r, { opacity: 1, x: 0, duration: .18 }, 0.45 + i * 0.08));
      tl.to({}, { duration: .12, onUpdate() { search.textContent = "json".slice(0, Math.ceil(this.progress() * 4)); } }, 0.95);
      tl.to(rows.filter((_, i) => i !== 2), { opacity: .22, duration: .15 }, 1.05);
      tl.to(json, { onStart() { json.textContent = "{\\n  \\"ok\\": true,\\n  \\"items\\": 12\\n}"; json.classList.add("on"); }, duration: .2 }, 1.1);
      tl.to(pin, { opacity: 1, y: 4, duration: .15 }, 1.25);
      tl.to(rows[0], { onStart() { rows[0].classList.add("on"); json.classList.remove("on"); } }, 1.25);
    }
    function setupTypes() {
      const track = document.querySelector(".htrack");
      if (!track || reduced || matchMedia("(max-width: 900px)").matches) return;
      const dist = () => Math.max(0, track.scrollWidth - innerWidth + 80);
      gsap.to(track, {
        x: () => -dist(), ease: "none",
        scrollTrigger: { trigger: ".types", start: "top top", end: () => "+=" + dist(), scrub: 1, pin: true, anticipatePin: 1 }
      });
    }
    function setupRephrase() {
      const copy = {
        friendly: "Hey, any chance we can push the deadline? The client is pretty stressed and I still don't have the latest numbers.",
        chat: "Could we move the deadline? The client is anxious, and I don't have the latest numbers yet.",
        mail: "Hi, could we move the deadline? The client is anxious, and I do not have the latest numbers yet. Thank you."
      };
      const out = document.getElementById("typed");
      let timer;
      function type(text) {
        clearInterval(timer);
        out.textContent = "";
        if (reduced) { out.textContent = text; return; }
        let i = 0;
        timer = setInterval(() => {
          out.textContent = text.slice(0, ++i);
          if (i >= text.length) clearInterval(timer);
        }, 16);
      }
      type(copy.friendly);
      document.querySelectorAll(".tones button").forEach((b) => {
        b.addEventListener("click", () => {
          document.querySelectorAll(".tones button").forEach((x) => x.setAttribute("aria-pressed", "false"));
          b.setAttribute("aria-pressed", "true");
          type(copy[b.dataset.tone]);
        });
      });
      if (!reduced) {
        gsap.set(".neon-otter path, .neon-otter ellipse, .neon-otter circle", { strokeDasharray: 600, strokeDashoffset: 600 });
        ScrollTrigger.create({
          trigger: "#rephrase", start: "top 70%",
          onEnter: () => gsap.to(".neon-otter path, .neon-otter ellipse, .neon-otter circle", { strokeDashoffset: 0, duration: 1.6, stagger: 0.06, ease: "power2.out" })
        });
      }
    }
    function setupCounts() {
      document.querySelectorAll("[data-count]").forEach((el) => {
        const end = +el.dataset.count;
        if (reduced) { el.textContent = end.toLocaleString(); return; }
        ScrollTrigger.create({
          trigger: el, start: "top 85%", once: true,
          onEnter() {
            const obj = { n: 0 };
            gsap.to(obj, { n: end, duration: 1.4, ease: "power2.out", onUpdate: () => { el.textContent = Math.floor(obj.n).toLocaleString(); } });
          }
        });
      });
    }
    document.querySelector(".pixel-btn").addEventListener("click", () => {
      const img = document.querySelector(".pixel");
      gsap.fromTo(img, { y: 0 }, { y: -16, duration: .22, yoyo: true, repeat: 1, ease: "power2.out" });
    });
  </script>
</body>
</html>
