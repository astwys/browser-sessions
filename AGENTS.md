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

- List: `agent-browser session list --json`, called only when the set of running `agent-browser*` processes changes. Every session has a daemon, so none running means no sessions and no spawn.
- Close: `agent-browser --session <name> close --json` (**not** `close --session`)
- Never call `get url` while polling: since 0.28.0 it can recreate a closed session as about:blank.

## Detection posture

**Visibility over confidence** — prefer listing possible browsers (LOW tier) over omitting. Close is gated on known/`agent-browser` or HIGH-confidence signals only.

Process data comes from libproc/sysctl (`ProcessTable`), never from `ps`, and only for the current user. The environment block is never read.

One row per browser main process:
- A browser is an exact executable name (`Google Chrome`, `Chromium`, `chrome-headless-shell`, …) or anything under `/ms-playwright/`. Substring matches let `chrome-devtools-mcp` in.
- Helpers are excluded: paths under `Helpers/` or `.xpc/`, `--type=` (Chromium) and `-contentproc` (Firefox) arguments.
- Signals come from the process's own executable and arguments. The parent only contributes "launched by Playwright/Puppeteer", matched on package paths (`playwright-core`, `node_modules/puppeteer`, …), so a child never inherits its browser's flags.

Signal summary:
- HIGH: `ms-playwright` paths, `--remote-debugging-pipe`, Playwright profile markers, Playwright/Puppeteer parent packages, Puppeteer path + `--enable-automation`
- LOW: `--remote-debugging-port=`, headless flags, user-data dirs, browser main processes without HIGH signals

## Manual testing

When UI behavior cannot be unit-tested (menu bar hide, live popover refresh, close confirmation focus, VoiceOver labels), use `docs/qa/manual-ae-checklist.md` and **notify the user** which AE sections need manual verification before calling v1 complete.

## Architecture note

Detection and close paths must stay protocol-backed so a privileged helper can replace in-process implementations later.
