# AGENTS.md — Browser Sessions

## Product scope (v1)

Supervise local automation browsers from the menu bar. See `docs/brainstorms/2026-06-21-automation-browser-menu-bar-requirements.md`.

**Out of scope v1:** bulk close, stale labels, ignore rules, dashboard integration, launch-at-login, killing Node/test owner processes.

## Stack

- Swift 6, SwiftUI `MenuBarExtra` (.`window` style), macOS 14+
- SwiftPM + `scripts/build-app-bundle.sh` until full Xcode project lands
- `LSUIElement` — no Dock icon

## Safety rules

- Confirm before any close action
- Revalidate PID identity before kill (start time + cmdline signals)
- Kill browser PID only — never Playwright/Puppeteer Node parent
- LOW-confidence rows: inspect-only, no Close
- Do not log or persist URL/cmdline secrets

## CLI contract (`agent-browser`)

- List: `agent-browser session list --json`
- Close: `agent-browser --session <name> close --json` (**not** `close --session`)

## Detection posture

**Visibility over confidence** — prefer listing possible browsers (LOW tier) over omitting. Close is gated on known/`agent-browser` or HIGH-confidence signals only.

## Manual testing

When UI behavior cannot be unit-tested (menu bar hide, live popover refresh), use `docs/qa/manual-ae-checklist.md` (U7) and **notify the user** which AE sections need manual verification before calling v1 complete.

## Architecture note

Detection and close paths must stay protocol-backed so a privileged helper can replace in-process implementations later.
