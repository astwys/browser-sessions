# Manual AE Checklist — Browser Sessions v1

Use this checklist for behavior that cannot be fully verified by unit tests: macOS menu bar visibility, live popover updates, confirmation focus, and accessibility spot checks.

## Setup

```bash
cd BrowserSessions
./scripts/build-app-bundle.sh
pkill -x BrowserSessions || true
```

Use `./scripts/run-app.sh` rather than `open` so environment variables are passed through.

## AE1 — Count includes known + process detections

1. Start at least one `agent-browser` session or a Playwright/Puppeteer browser.
2. Run `./scripts/run-app.sh`.
3. Confirm the menu bar count matches rows shown in the popover.

Expected: count equals total rows across all sections.

## AE2 — Three-tier popover

1. Open the menu bar popover.
2. Verify sections exist:
   - Known agent-browser sessions
   - Likely Playwright/Puppeteer browsers
   - Possible automation browsers

Expected: known rows show `known`; high rows show `high confidence`; low rows show `inspect only`.

## AE3 / AE10 — Zero-state and hide behavior

```bash
pkill -x BrowserSessions || true
./scripts/run-app.sh
```

Expected: when nothing is detected, no numeric `0` is shown. The menu bar item may be hidden.

Fallback check:

```bash
pkill -x BrowserSessions || true
BROWSER_SESSIONS_FORCE_ZERO_STATE=1 ./scripts/run-app.sh
```

Expected: item remains visible and popover shows “No automation browsers detected”.

## AE4 — Unknown age is acceptable

Inspect Playwright/Puppeteer rows.

Expected: URL/last-change metadata may be unknown in v1. No stale/abandoned label is shown.

## AE5 — Close known agent-browser session

1. Start an `agent-browser` session.
2. Open popover and click `Close` on the known row.
3. Confirm the inline dialog.

Expected: the confirmation stays inside the popover, close runs, a status message appears, and the list refreshes.

## AE6 — Close HIGH process row

1. Create a high-confidence Playwright/Puppeteer browser row.
2. Click `Close`.
3. Confirm.

Expected: copy says SIGTERM targets the browser PID only and revalidates first. The owning Node/test process must remain alive.

## AE7 — LOW rows are inspect-only

Create or observe a LOW row such as Chrome with `--remote-debugging-port=9222` only.

Expected: LOW row is visible but has no Close button.

## AE8 — Cancel confirmation

1. Click `Close` on a closable row.
2. Click `Cancel` in the inline confirmation.

Expected: only the confirmation panel closes; the popover remains open and no close action runs.

## AE9 — Accessibility spot check

Use VoiceOver or Accessibility Inspector on representative rows.

Expected: labels mention known/high/inspect-only state and PID when present.

## AE11 — Degraded CLI state

Temporarily launch with a PATH that cannot find `agent-browser` while a process row is detectable.

Expected: popover shows a degraded capability banner and still lists process detections.

## AE12 — Last row disappears while popover open

Close or stop the last detected browser while the popover is open.

Expected: within one poll/refresh, count drops to zero and empty state appears without crashing.

## AE13 — Signal classification sanity

Verify examples against expected UI:

- Playwright `--remote-debugging-pipe` → HIGH / closable
- Puppeteer cache + `--enable-automation` → HIGH / closable
- `--remote-debugging-port=9222` only → LOW / inspect-only
- `chrome_crashpad_handler` → not listed

## Completion note

Before calling v1 complete, report which AE sections were manually verified and any observed macOS version-specific behavior.
