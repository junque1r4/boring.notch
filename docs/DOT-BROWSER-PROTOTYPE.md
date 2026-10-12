# Embedded Dot browser prototype

12 October 2026. GPL-3.0-only; part of the junque1r4 Boring Notch fork.

## Purpose and scope

The Website mode loads the actual `https://chatgpt.com/dots/home` page in a
native WKWebView. It does not send through the private relay, imitate Dot with
another model, copy Safari cookies, or import ChatGPT messages into the relay
archive. ChatGPT owns rendering, conversation history, generation and uploads.

The existing **Notch chat** mode remains available with its existing encrypted
messages, draft and relay connection. A saved Website/Notch chat choice controls
which surface opens. Website is the prototype default.

The browser has an app-owned persistent WebKit profile. Sign-in is separate
from Safari. Its page is retained in memory when the notch closes, so reopening
does not intentionally reload the page or discard its current draft/scroll
position. Website data persistence and expiry follow WebKit and the website;
the old relay archive's AES-GCM guarantees do not describe browser caches.

No new entitlements, script bridge, content scraping, cookie extraction, TLS
exceptions, user-agent spoofing or cloud deployment are introduced. Monitoring
adapters have no access to this web view. Normal website requests go directly
to the website and its dependencies. The header shows the page host rather
than declaring authentication or delivery states the app cannot establish.

Dot uses the existing 760 × 450 point notch geometry. Existing main-notch hover,
opening/closing motion, launcher motion, Home, Shelf and media code are unchanged.
The existing pin/close/focus helper is reused for browser interaction. Uploads
use WebKit's native file-picker callback; sign-in popups hold the notch open.
Transient picker/popup windows are cancelled on browser dismissal. One retained
web view has one active notch owner; another visible display shows an explicit
occupied message rather than taking the first display's web view.

## Validation method

Compare actual Dot in Safari and the embedded view in the same account and
conversation. Use harmless fixed-text requests and a generated image containing
digits and shapes. Do not copy private conversation content into logs.

Measure from immediately before the UI Send action until the first observed
reply and complete reply. Accessibility observations are discrete and include
tool/observation overhead: report bounds, not exact server latency or token
streaming timings. A typing indicator is not a reply token. Do not infer a
causal speedup or statistical parity from one run.

Synthetic image fixture: 640 × 360 PNG, `BROWSER VISION CHECK: 6713`, two blue
circles and one yellow triangle. The question does not state the answer.

## Results recorded so far

- Signed Release build and deep strict signature verification passed.
- 56 focused hosted tests passed: test-host isolation, relay chat, browser navigation policy,
  scrolling, pin/geometry and launcher/motion regression suites.
- The prototype visibly loaded ChatGPT inside the notch. An unauthenticated
  `/dots/home` request displayed the website's 404/login page; its Log in
  control opened the website's authentication form inside the notch.
- Safari fixed-text test: reply absent at the 5.507-second observation and
  observed complete by 17.465 seconds. This is one bounded observation.
- Safari image test: attachment visibly appeared in the conversation; Dot
  replied by 24.471 seconds that the image content was not included. This is
  an unsuccessful vision test, despite successful visible attachment upload.
  The prompt prohibited tools, which may have prevented Dot from inspecting
  the attachment; a matched retry allowing ordinary image inspection is needed.
- Offline input check: the owner confirmed typing works. Live accessibility
  observations then verified text entry, Tab navigation through all three fields,
  input after a Website/Notch chat mode switch, and retained field text and scroll
  position after close/reopen. Pin interaction preceded successful input. These
  checks verify local browser input, not account authentication.
- Embedded account sign-in, actual Dot reply, older history, image comprehension,
  matched timing, restart persistence and physical hover verification are pending.

## Input and authentication investigation

The first embedded sign-in attempt exposed unreliable keyboard focus. Browser
clicks now activate/key the nonactivating notch panel and leave the clicked HTML
field's responder selection to WebKit. Attachment callbacks no longer repeatedly
reset its responder during observed page-state updates. A per-panel focus-return
context also prevents the old mode's teardown from clearing the new mode's input
hold. The initial change alone did not resolve the owner's issue; Apple displayed
`Failed to verify your identity. Try again.` Authentication remains unresolved.
The subsequent isolated input build passed the checks above. No further password
submission was automated, and the Apple rejection's cause has not been established.

`--dot-browser-input-check` (or the `DOT_BROWSER_INPUT_CHECK` Swift compilation
condition) loads an offline HTML form using a nonpersistent WebKit profile. It
blocks external navigation, uploads, forms and popups. Its default relay archive
is isolated and Keychain access is refused. This diagnostic permits typing,
focus, mode-switch and reopen checks without repeated account sign-in attempts.

The hosted test runner previously built an ad-hoc-signed copy of the production
app, whose startup opened the owner's real encrypted archive and resumed the
relay. That can prompt separately for the history key and OAuth credentials on
each new test binary. The test script now marks its host explicitly; the app
skips production-window/monitoring startup and termination side effects, uses an
isolated default archive, and refuses all real Dot Keychain operations under
XCTest. New regression tests verify that no production notch window opens and
all Keychain read/write/delete entry points refuse the test host. Release signing
continues to use the existing stable development certificate. No credentials or
Keychain ACLs are changed by this fix.

## Prototype limitations

The website's history is distinct from the retained relay transcript. Messages
previously sent through the relay do not automatically merge into the web chat.
The existing closed-notch unread indicator still describes relay messages;
the prototype has no supported bridge for the website's unread state.

Browser text/images and authentication must be verified with the real account
before claiming native-Dot parity. A loaded website or a successful build is
not that evidence. Website layout at compact dimensions, session expiry, content
process termination, multiple displays and screen lock also need live testing.
