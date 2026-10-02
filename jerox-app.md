# Jerox

Native macOS clipboard manager. Swift and SwiftUI/AppKit. Minimum macOS 15.1. Menu-bar app: no Dock icon while you work, small footprint, history kept on disk.

Bundle id `com.jxngrx.jerox`.

## How you open it

- **Show Jerox** (default ⌃⌥⌘V) opens the clipboard list at the cursor. Press it again to close.
- **Menu bar** left click opens the same list under the menu-bar icon. Right click is Settings… and Quit.
- Escape, a click outside, or the show shortcut again dismisses the list and returns you to the app you were in.

The menu-bar icon is the stacked-panels mark. The Dock and Command-Tab icon is the squircle Jerox logo, and it only appears while Settings is open.

## Clipboard list

- History of what you copy, newest first. Pins sit above everything else.
- Search box filters the list. A typed phrase that appears in the text ranks above a looser character-by-character match.
- Arrow keys move the selection. **1–9** paste that row.
- **Paste** (default Return) pastes the selected row into the previous app, in its original format.
- **Paste plain** (default ⇧Return) pastes the same row as plain text.
- **Pin** (default ⌘P) pins or unpins the selected row. Pins are kept until you unpin them.
- Copying the same thing again moves the existing row to the top instead of adding a duplicate.
- Code rows are lightly colored (keywords, strings, numbers, comments). Image rows show a small preview.

## What it captures

Polled from the system clipboard. Nothing already on the clipboard at launch is imported.

- **Text**
- **Rich text** (RTF, RTFD, HTML). Paste puts the original formatting back.
- **Images** on the clipboard, with a preview.
- **A single image file** under 8 MB is stored as bytes (PNG, TIFF, and JPEG kept; HEIC, WebP, GIF, and BMP become PNG), so the preview and paste still work after the file moves. Larger files stay as a path, with no preview.
- **Other files** are stored as paths.
- **Links.** A web URL is captured even when the clipboard text is a page title. Paste writes both the text and the URL.
- **Colors** (`#hex` and `rgb()`) are stored as a canonical hex value and pasted as a color.
- **Code**, detected from the text and shown with simple highlighting.
- **Screenshots** saved to the Desktop (or the folder set in the screenshot location) whose English name starts with `Screenshot` or `Screen Shot` and whose type is PNG or TIFF are added as images.
- **JSON.** If the whole clipboard is a JSON object or array, it is pretty-printed immediately and that pretty text is what history keeps. Fragments (`true`, a number) and JSON buried inside other text are left alone.

## Settings

Sidebar window titled Jerox Settings. Opening it shows Jerox in the Dock. Closing it hides the Dock icon again.

- **Paste.** JSON pretty-print toggle. When on, pasting pretty-prints JSON. The saved history row is not changed by this toggle.
- **History.** Keep up to N items (1–5000, default 200) and up to N days (1–3650, default 14). Pins are exempt.
- **Shortcuts.** Show Jerox, Paste, Paste plain, Pin, and Rephrase. Click Edit and press the keys. Escape cancels. Show Jerox and Rephrase need a modifier.
- **AI.** OpenRouter API key (stored in the Keychain), model name (default `openai/gpt-4o-mini`), and the default rephrase tone.

## Rephrase

Uses OpenRouter only. Nothing runs until you ask. The rewrite is meant to sound like a person: no em dashes, en dashes, bullet lists, or AI phrasing. The reply is only the rewritten text.

Tones: Friendly chat, Professional chat, Professional mail. The default is chosen in Settings. The list also has a Rephrase menu for the selected row.

- **In the list.** The rephrase shortcut rewrites the selected row in place and shows a loader above that line.
- **Anywhere else.** Select text in another app and press the shortcut (default ⌘⇧R). A small loader appears at the mouse. Jerox copies the selection, rewrites it, and pastes the result back without bringing itself forward. That temporary copy is not added as its own history row; the rewritten text is. Accessibility access is required. If it is missing, paste still writes the clipboard and macOS is asked for permission once per launch.

## First launch

Shown once:

> 🙏 Namaste, Welcome to **Jerox** Family — this is developed by [jxngrx.com](http://jxngrx.com) 🎉💚

## Not in the app

Hot corner, type filter, trim, markdown stripping, case conversion, Base64, OCR, on-device Foundation Models, a “clean this up” action, per-app exclusions, contextual paste, a clipboard stack, auto-categorization, and snippets or templates.
