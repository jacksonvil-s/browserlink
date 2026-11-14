# Version 1.5.0
Biggest update yet, bringing many improvements and fixes.

The update is so big, we thought to give you a few highlights:

**Highlights:**
- **Remembered sites:** pick a browser (or Quick Preview) once and that site opens there automatically, with a toast to change it. Links with safety warnings still show the chooser.
- **Faster, keyboard-friendly chooser:** navigate with the arrow keys and press Return, and it now has a copy-link button.
- **A fuller Quick Preview:** find in page, zoom, JavaScript dialogs and file uploads.
- **Cleaner links:** tracking parameters and redirect pages are removed before you open anything.
- **Smarter safety checks:** better look-alike, IP address and international-domain detection.
- **More browsers:** other installed browsers are found automatically, plus DuckDuckGo and Dia support.
- **Menu bar extras:** Open Link from Clipboard, Recent Links (off by default), and Pause Remembered Sites. All are also in Preferences if the icon is hidden.
- **Respects accessibility:** Reduce Motion and VoiceOver support throughout.

Full changelog:

**Added:**
- Remembered sites:
	- Tick "Remember my choice for this site" and its links open straight in your chosen browser or Quick Preview
	- Toast shows where the link went, with a Change button
	- Manage in Preferences → Browser → Remembered Sites (search, remove one, forget all)
	- Pause Remembered Sites from the menu bar or Preferences
	- Hold ⌥ as a link opens to see the chooser
	- Links with any safety warning always show the chooser
- Chooser:
	- Arrow-key navigation (Quick Preview, browsers, remember option), Return or Space to select
	- Copy link button
	- Choose which screen it appears on (under the mouse or main screen)
	- Notice when a link was cleaned, with a "use original" option
	- Orange ? badge on browsers we haven't tested
- Quick Preview:
	- Native JavaScript alert, confirm and prompt dialogs, with "don't allow more dialogs"
	- File upload picker (needs the "User Selected File: Read Only" entitlement)
	- Find in Page (⌘F, ⌘G, ⇧⌘G) and zoom (⌘+, ⌘−, ⌘0)
	- Per-preview JavaScript switch, plus an "Allow JavaScript in Quick Preview" setting
	- Address bar shows the host in bold with the rest dimmed, a full-URL tooltip and a copy button
	- Download failure alerts, and no more overwriting files with the same name
- Link cleanup:
	- Removes tracking parameters (utm_*, fbclid, gclid and more)
	- Skips redirect pages from Google, YouTube, Facebook, Instagram, LinkedIn, Slack, DuckDuckGo and Steam
- Safety checks:
	- Brand look-alike warnings in three levels (serious, warning, advisory)
	- Raw IP address warnings, separating public from private and local addresses
	- Mixed-alphabet detection for international domains
	- Switch for flagging dangerous link types (javascript:, data:, file:)
- Browser support:
	- Finds other installed browsers automatically and marks them "Potentially unsupported"
	- More built-in browsers, including DuckDuckGo Browser, Dia, Zen, Orion, Mullvad, LibreWolf and others
- Menu bar:
	- Open Link from Clipboard
	- Recent Links (off by default, memory only, last 10)
	- Default browser status
- Preferences:
	- Quick Access card with the clipboard and recent-link actions, for when the menu bar icon is hidden
	- Browser display order moved into the Browser pane
	- Link Cleanup card
- Onboarding: new Updates card for automatic update checks (on by default)
- Accessibility:
	- Reduce Motion respected in the chooser, onboarding and toast
	- VoiceOver labels on the chooser
- Developer:
	- Debug button opens a dialog for testing any URL
	- Automated tests for safety checks, link cleaning, site matching and browser ordering

**Fixed:**
- Chooser fade-and-rise animation didn't play the first time it appeared
- Preview windows leaking memory after closing
- Keyboard shortcuts bypassing the chosen app mode
- Quick Preview:
	- Error screens for failed loads
	- Insecure http:// sites now show "Insecure Site Blocked" instead of a blank window
	- Pages that return 401, 403, 429 or 503 still render
- Reveal Downloads in Finder now works
- Launch at Login switch drifting out of sync with System Settings
- Favicon fetching: no more blank or generic icons from failed lookups
- Cancelling the default-browser prompt no longer shows an error, and it no longer shows two alerts
- App missing from the default browser list in System Settings
- Colour values being rounded incorrectly, and low contrast on "Use System Colour"
- Pause, recent-links and clipboard actions unreachable when the menu bar icon was hidden
- Spelling: "Appearance"
- Update setting no longer keeps a duplicate copy of its state

**Removed:**
- Global keyboard shortcut
- "Hide menu bar icon" setting (macOS now has its own switch)
- Sparkle's own "check for updates automatically?" prompt (replaced by the onboarding card)

**Patch:**
- Favicon lookups are skipped for flagged links, IP addresses and local network names, so those sites aren't revealed to a third party
- Redirect unwrapping deliberately leaves security rewriters (Outlook Safe Links, Proofpoint) alone
- Remembered sites never skip a safety warning
- JavaScript dialogs are titled with the page's host, so a page can't pass one off as a system message
- Stronger look-alike detection (international domains, disguised IP addresses)
- Recent Links keeps nothing on disk and hides query strings; the clipboard is read only when you click


> [!important]
> This app version is unsigned. You must trust the app manually to use it. If you don't already know how to do this, you are probably not the target audience.