# Product

<!-- impeccable:product-schema 1 -->

## Platform

macos

Native Mac app. Not web, iOS, or Android. The schema’s web / iOS / Android / adaptive values do not fit this product.

## Users

Someone at a Mac, already mid-task in another app, who needs a recent copy, a rewrite, dictation, or the text on screen without leaving that app.

## Product Purpose

Jerox brings clipboard history, rewrite, dictation, and screen-text reading to the app the person is already using. Success is finishing that job and landing back in the previous app.

## Positioning

It works where you already are. History opens at the cursor. Rewrite and dictation paste back. Text read from the screen appears on the thing you selected.

## Operating Context

Menu-bar app. No Dock icon while you work. The Dock icon appears only while Settings is open, then hides again.

The dictation bar stays at the bottom center of the screen that contains the pointer.

Paste-back into the previous app needs Accessibility access. Dictation needs the microphone and speech recognition. Screen-text reading needs Screen Recording.

## Capabilities and Constraints

Confirmed jobs: recall a recent copy, rewrite text, dictate, and read text from the screen you are looking at.

Dictation and screen-text reading stay on this Mac. Cloud AI is only for rephrase.

Dictation runs on Apple Speech (live text) or a downloaded Whisper model (offline, transcribes on stop). Models come from a pinned Hugging Face revision of `ggerganov/whisper.cpp`, are sha256-verified, and live in `~/Library/Application Support/Jerox/Models`. The catalog is `SpeechCatalog` in `Jerox/Models.swift`.

Minimum macOS 15.1. Existing app: Swift, SwiftUI, and AppKit.

A downloaded on-device rewrite (LLM) model is not in the product. Add it only when asked. Downloaded speech models are.

Undecided: pricing, distribution, and any audience beyond the person above.

## Brand Commitments

The name is Jerox. The menu-bar icon is the stacked-panels mark (silver over graphite). The one-time welcome stays:

🙏 Namaste, Welcome to Jerox Family — this is developed by jxngrx.com 🎉💚

## Evidence on Hand

The running app is the source of truth: `Jerox/JeroxApp.swift` and `Jerox/History.swift`.

`jerox-app.md` is behind the app. It still says screen-text reading is absent and that rephrase is OpenRouter-only. Do not treat that file as the current product.

No testimonials, pricing, press, or case studies. Do not invent them.

## Product Principles

- Come to the work. History, rewrite, dictation, and screen text happen in the app the person is already using.
- The Mac does the listening and the reading. The network is only for a rephrase they asked for.
- Stay in the menu bar. No Dock icon while they work.
- The dictation bar stays at the bottom center of the screen that contains the pointer.
- The name, the stacked-panels mark, and the one-time welcome stay.

## Accessibility & Inclusion

The confirmed jobs depend on system permission prompts: Accessibility for paste-back, microphone and speech recognition for dictation, and Screen Recording for reading text off the screen. No separate accessibility standard was set.
