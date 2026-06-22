---
date: 2026-06-21
topic: automation-browser-menu-bar
---

# Automation Browser Menu Bar

## Summary

A macOS menu bar app will hide when possible when no supported automation browsers are detected, otherwise fall back to a neutral zero-state. When it detects live `agent-browser`, Playwright, Puppeteer, or likely automation Chrome/Chromium sessions, it shows a count; its popover prioritizes visibility by listing what exists in three confidence tiers, enough detail to recognize each session/process, and allowing individual close actions (where confidence allows) after confirmation.

---

## Problem Frame

Agents can start browser sessions in the background through `agent-browser`, Playwright, Puppeteer, or similar automation tools. Those browser sessions can keep running after the initiating agent has moved on, become detached from the user's current mental context, or survive after the agent harness exits.

The current workaround is manual: remember that a browser may have been launched, inspect terminals or process lists, run tool-specific commands, and decide whether anything is safe to close. That creates uncertainty and makes it easy to leave automation browsers running unnoticed.

---

## Actors

- A1. User: Supervises local agent/browser automation and wants quick visibility without opening terminals.
- A2. `agent-browser` session: A named browser session discoverable through `agent-browser` commands.
- A3. Possible automation browser: A Chrome/Chromium process associated with Playwright, Puppeteer, or automation-like launch characteristics.
- A4. macOS platform: Provides status item behavior, TCC permissions, and process inspection APIs that may limit detection or close actions.

---

## Key Flows

- F1. Menu bar visibility
  - **Trigger:** The app's polling detects zero or more automation browser sessions/processes.
  - **Actors:** A1, A2, A3, A4
  - **Steps:** The app counts known and possible automation browsers. When count is zero, it hides the menu bar item if macOS allows; otherwise it shows the neutral zero-state (R5a). When count is nonzero, it shows a visible count and updates on subsequent polls.
  - **Outcome:** The user can tell at a glance whether any automation browser exists, without false alarm from a broken hidden state.
  - **Covered by:** R1, R2, R3, R5, R5a, R6, R7

- F2. Inspect live sessions
  - **Trigger:** The user opens the menu bar popover.
  - **Actors:** A1, A2, A3
  - **Steps:** The app shows three sections (known, closable possible, inspect-only possible). Each row includes source/name, visible confidence, URL or domain when available, process age, last-change age when available, PID, and bounded process details. The list live-updates on each poll while the popover remains open (R7a).
  - **Outcome:** The user can recognize what is running, see which entries are safe to close, and decide what matters without reopening the popover.
  - **Covered by:** R4, R4a, R8, R8a, R8b, R9, R10, R7a

- F3. Close an entry
  - **Trigger:** The user chooses Close on a closable listed entry.
  - **Actors:** A1, A2, A3
  - **Steps:** The app shows a confirmation with the entry's source, confidence, process name, PID, URL/domain when available, ages, and exact consequence. If the entry changes or disappears during confirmation, the dialog updates or closes non-destructively (R14c). If confirmed, it closes the `agent-browser` session or kills the browser PID after revalidation, then refreshes the whole list and restores sensible focus (R15, R16a).
  - **Outcome:** The user can clean up one session/process safely and see the updated reality afterward.
  - **Covered by:** R11, R12, R13, R13a, R14, R14a, R14b, R14c, R15, R16, R16a

- F4. First launch and permissions
  - **Trigger:** The user launches the app for the first time, or macOS prompts for permissions needed for detection or metadata collection.
  - **Actors:** A1, A4
  - **Steps:** The app explains what it needs to supervise automation browsers locally. If the user grants permissions, detection runs at full capability per the metadata contract. If the user denies or revokes permissions, the app continues with degraded detection and metadata (R17, R18) and surfaces a non-blocking status in the popover when capability is reduced.
  - **Outcome:** The user understands why the app asks for access and can still use reduced supervision rather than failing silently.
  - **Covered by:** R17, R18, R19

- F5. Zero-state fallback
  - **Trigger:** Polling finds no automation browsers, but macOS does not allow fully hiding the status item.
  - **Actors:** A1, A4
  - **Steps:** The app shows a neutral zero-state menu bar item (no numeric count). Opening it shows a short empty-state message and continues polling. When detection later finds entries, the app transitions to the normal visible count state (F1).
  - **Outcome:** The user is not misled by a stale count when nothing is running, even when true hide is unavailable.
  - **Covered by:** R5, R5a, R20

- F6. Popover lifecycle
  - **Trigger:** The user keeps the popover open while polling updates the underlying list, closes the last detected entry, or dismisses the popover.
  - **Actors:** A1, A2, A3
  - **Steps:** While open, rows update in place without clearing user context unnecessarily; selection/focus follows stable row identity when possible (R7a, R16a). When the last entry disappears, the popover shows an empty state and the menu bar transitions to hidden or neutral zero-state on the next poll (R21). Escape or click-outside dismisses the popover and returns focus to the menu bar item (R22). If a confirmation dialog is open when the target entry changes, the dialog reflects the new reality or closes without destructive action (R14c).
  - **Outcome:** Live supervision feels continuous rather than stale, including the N→0 transition.
  - **Covered by:** R7a, R14c, R16a, R21, R22

---

## Requirements

**Detection and counting**
- R1. The app must detect live `agent-browser` sessions and include them in the menu bar count.
- R1a. If `agent-browser` is not installed, not on PATH, or `session list` fails, the app must treat known-session detection as unavailable for that poll, surface a non-blocking status when the popover is open, and continue detecting possible automation browsers.
- R2. The app must detect likely Playwright, Puppeteer, and other automation-looking Chrome/Chromium browser processes and include them in the menu bar count, using an explicit v1 set of supported detection signals.
- R2a. Possible automation browser detection is best-effort and limited to the supported signal types defined during planning; anything outside those signals is out of scope for v1.
- R2b. Each possible automation browser must be classified as high-confidence (closable) or low-confidence (inspect-only) using the v1 signal table defined during planning.
- R3. The menu bar count must include known sessions and all detected possible automation browsers, including low-confidence entries the user cannot close.
- R3a. The popover may optionally show a short note when count > 0 but no closable entries exist; this note is not required in v1.

**Menu bar behavior**
- R5. When no automation browser sessions/processes are detected, the app should hide the menu bar item if possible.
- R5a. If hiding is impractical on the target macOS version, the app must show a neutral zero-state item with no numeric count and an empty-state popover message while continuing to poll.
- R6. When one or more sessions/processes are detected, the app must show a visible menu bar count.
- R6a. Counts above 99 may display as `99+`; exact overflow formatting is a planning detail.
- R7. The app must refresh its detection state by polling every few seconds.
- R7a. While the popover is open, each poll must refresh visible rows in place rather than requiring the user to close and reopen the popover.

**Popover structure and information**
- R4. The popover must use three sections: **Known sessions**, **Closable automation browsers**, and **Inspect-only possible browsers**.
- R4a. High-confidence Playwright/Puppeteer entries belong in **Closable automation browsers**, not mixed with inspect-only rows without distinction.
- R8. Each row must show enough information for the user to recognize the entry: source/name, visible confidence label, URL or domain when safely available, process age, last-change age when available, PID, and bounded process details.
- R8a. Displayed metadata must be minimized and local-only by default: prefer domain over full URL for possible automation browsers, avoid displaying query parameters/secrets, and do not persist or log sensitive URL/title/process metadata.
- R8b. Confidence must be visible in the row UI for possible automation browsers, not only in VoiceOver labels. Known `agent-browser` sessions may omit a separate confidence badge.
- R9. The app must show both process age and last-change age when both are available; if last-change age cannot be computed safely or reliably for an entry, the app may show it as unknown or omit it.
- R9a. **Last-change age** means time since the last safely observed navigation-relevant change for that entry: active URL/domain for `agent-browser` sessions when available; active tab URL/title change for high-confidence browser processes when readable; otherwise unknown.
- R10. The app must not label sessions as stale, bad, blocked, errored, or waiting-for-human in v1.

**Closing behavior**
- R11. The app must support closing individual listed entries when the entry is a known `agent-browser` session or a high-confidence Playwright/Puppeteer automation browser.
- R11a. Low-confidence possible automation browsers are inspect-only in v1; they may show process details but must not offer a destructive Close action.
- R12. Closing an `agent-browser` entry means closing the named `agent-browser` session via the integration contract below.
- R13. Closing a high-confidence Playwright or Puppeteer browser entry means killing the browser PID only, not the owning test or agent process.
- R13a. Immediately before killing any PID, the app must revalidate that the PID still matches the selected entry's process identity, including executable/command evidence and process start time where available. If cmdline evidence no longer matches, abort the kill and refresh.
- R14. Every close action must require confirmation before taking effect.
- R14a. If the user cancels confirmation, no close action occurs and the list remains unchanged except for normal polling updates.
- R14b. If the close command fails, permission is denied, or the entry disappears before confirmation completes, the app must show a non-destructive status/error and refresh the full list.
- R14c. If the selected entry changes identity or disappears while confirmation is open, the dialog must update to reflect the new state or close without performing a destructive action.
- R15. After any close attempt, the app must refresh the whole list from the current system state.

**Permissions, degradation, and lifecycle**
- R17. On first launch, the app must explain why local process inspection (and any optional URL/title reads) are needed before requesting permissions.
- R18. If required permissions are denied, the app must continue running with the best available degraded detection and clearly indicate reduced capability in the popover.
- R19. The app must not crash or exit when `agent-browser` or process inspection APIs are unavailable; it must degrade gracefully for that poll cycle.
- R20. In neutral zero-state, the app must continue polling and must not display a nonzero count.
- R21. When the last detected entry disappears while the popover is open, the popover must show an empty state and the menu bar must transition to hidden or neutral zero-state on the next poll.
- R22. The popover must be dismissible via Escape and click-outside, returning focus to the menu bar item.
- R23. Launch-at-login is out of scope for v1; the user starts the app manually. Planning should note this as an obvious v1.1 enhancement if always-on supervision becomes important.

**Accessibility**
- R16. The menu bar item, popover rows, and confirmation dialog must be keyboard-operable and expose clear VoiceOver labels, including source/name, confidence where relevant, PID, inspect-only vs closable state, and the Close action's consequence.
- R16a. After a list refresh or successful close, keyboard focus should remain on a sensible target: the same row if it still exists, otherwise the next row or the menu bar item if the list is empty.

---

## Metadata Contract (v1)

| Field | Known `agent-browser` | High-confidence PW/PP | Low-confidence possible |
| --- | --- | --- | --- |
| Section | Known sessions | Closable automation browsers | Inspect-only possible browsers |
| Source/name | Session name | Detected framework or "Automation browser" | "Possible automation browser" |
| Confidence label | Optional (implicit known) | Required: "High confidence" | Required: "Inspect only" |
| URL/domain | Session URL/domain when available | Domain preferred; full URL only if already sanitized | Domain preferred; often unknown |
| Process age | If applicable | Required | Required |
| Last-change age | URL change when available | Tab URL/title change when readable | Usually unknown |
| PID | When applicable | Required | Required |
| Process details | Bounded cmdline slice or executable path | Bounded cmdline slice, parent PID optional | Bounded cmdline slice |
| Close action | Yes | Yes | No |

Sensitive fields must follow R8a. Exact collection mechanics and permission needs are planning tasks, but the displayed shape above is fixed for v1.

---

## `agent-browser` Integration Contract (v1)

Planning and implementation must treat this as the minimum CLI contract:

| Operation | Command shape | Success | Failure handling |
| --- | --- | --- | --- |
| List sessions | `agent-browser session list` (exact flag order resolved in planning) | Parse stable session name + optional URL/domain per row | Treat as zero known sessions for that poll; show non-blocking status in popover |
| Close session | `agent-browser --session <name> close` (exact invocation verified against installed CLI) | Entry removed on next refresh | Show R14b error; refresh full list |
| CLI missing | n/a | n/a | Known-session detection unavailable; continue possible-browser detection |

The app must tolerate CLI timeouts and malformed output without crashing. Version assumptions are resolved during planning against the installed `agent-browser` skill/docs.

---

## Acceptance Examples

- AE1. **Covers R1, R3, R6.** Given two active `agent-browser` sessions and one detected Playwright browser process, when the app polls, the menu bar count shows three total automation browsers.
- AE2. **Covers R4, R4a, R8, R8a, R8b.** Given one known `agent-browser` session, one high-confidence Playwright browser, and one low-confidence possible browser, when the user opens the popover, each entry appears in the correct section with visible confidence labels where required and minimized URL/domain display.
- AE3. **Covers R5.** Given no detected automation browser sessions or processes, when the app polls, the menu bar item is hidden if the platform allows it.
- AE4. **Covers R9, R9a, R10.** Given a browser process that has existed for many hours with no safely observed URL/title changes, when it appears in the popover, the app shows available age/change metadata or unknown values and does not label it stale or bad.
- AE5. **Covers R11, R12, R14, R15.** Given a listed `agent-browser` session, when the user clicks Close and confirms, the app closes that named session and refreshes the full list afterward.
- AE6. **Covers R11, R13, R13a, R14, R15.** Given a high-confidence Playwright or Puppeteer browser process, when the user clicks Close and confirms, the app revalidates process identity, kills only that browser PID, and refreshes the full list afterward.
- AE7. **Covers R11a, R8b.** Given a low-confidence possible automation browser, when the user opens its row, the app exposes inspection details with an inspect-only confidence label but does not offer Close.
- AE8. **Covers R14a, R14b, R14c.** Given a close confirmation, when the user cancels, the entry disappears, or identity changes before close completes, the app avoids destructive action, reports the outcome when needed, and refreshes from current state.
- AE9. **Covers R16, R16a.** Given the user navigates with keyboard or VoiceOver, when they focus a row or confirmation dialog, the app announces the entry identity, PID, closable vs inspect-only state, and the consequence of any Close action; after refresh, focus lands on a sensible target.
- AE10. **Covers R5a, R20, F5.** Given no detected automation browsers and macOS cannot hide the status item, when the app polls, the menu bar shows neutral zero-state with no numeric count and an empty-state popover message while continuing to poll.
- AE11. **Covers R1a, R18, R19, F4.** Given `agent-browser` is missing or `session list` fails, when the app polls, it still lists possible automation browsers if detectable, shows a non-blocking degraded-capability status, and does not crash.
- AE12. **Covers R21, R7a, F6.** Given the popover is open and the user closes or loses the last detected entry, when the next poll runs, the popover shows an empty state and the menu bar transitions to hidden or neutral zero-state.
- AE13. **Covers R4a, R8b, R11.** Given a high-confidence Playwright browser classified from possible-process signals, when the user opens the popover, it appears under **Closable automation browsers** with a visible high-confidence label and an offered Close action.

---

## Success Criteria

- The user can tell at a glance whether any automation browser exists, including when hide is unavailable.
- The user can open the popover and recognize each listed entry, its confidence tier, and whether Close is available without going to a terminal first.
- The user can safely close a known or high-confidence leftover browser/session with confirmation, including when the list changes during confirmation.
- Permission denial or CLI failure degrades gracefully instead of failing silently or crashing.
- The requirements are clear enough that planning does not need to invent the product behavior, v1 exclusions, metadata shape, or success criteria.

---

## Scope Boundaries

- Bulk close is not in v1.
- Stale warnings, abandoned-session judgments, blocked/error/waiting-for-human states, and other agent-level status labels are not in v1.
- Ignore rules and false-positive suppression are not in v1.
- `agent-browser` dashboard integration is not in v1.
- Launch-at-login is not in v1 (R23).
- The app does not try to close owning Playwright/Puppeteer Node/test processes in v1.
- The app does not offer destructive close actions for low-confidence possible automation browsers in v1.
- The app does not attempt to provide a full browser automation dashboard or agent task monitor.

---

## Key Decisions

- Broad detection over perfect attribution: Possible automation browsers are included in the count, but separated from known sessions in the popover.
- Three-tier popover over ambiguous two-section labeling: Closable high-confidence browsers are visually and structurally distinct from inspect-only possibles.
- Count trust tradeoff accepted: The menu bar count intentionally includes low-confidence possible automation browsers; occasional false positives are acceptable for this user's visibility-first use case.
- Confidence must be visible in UI, not only assistive text: Close availability must not surprise users who only read section headers.
- Visibility over judgment: v1 shows raw metadata and avoids stale/bad labels so the user remains the decision-maker.
- Individual cleanup over bulk cleanup: Close exists for one entry at a time, always behind confirmation.
- Confidence-gated cleanup: Low-confidence possible automation browsers are inspect-only; destructive close is limited to known or high-confidence entries.
- Live popover refresh: Open popover reflects current reality on each poll rather than freezing until reopen.
- Refresh from reality after mutation: After close, the app re-runs detection instead of trying to maintain optimistic state.
- Graceful degradation over hard failure: Missing CLI, denied permissions, or partial detection must reduce capability visibly rather than fail silently.

---

## Dependencies / Assumptions

- `agent-browser` exposes active named sessions through `session list` and closes named sessions through `--session <name> close`, subject to verification during planning.
- Playwright/Puppeteer/possible automation browser detection will rely on process-level signals and may occasionally produce false positives.
- Hiding the menu bar item entirely at zero sessions may depend on macOS status item behavior; if true hiding is impractical, neutral zero-state (R5a) is the required fallback—not an optional planning guess.
- URL/title reads for possible browsers may require additional permissions or prove fragile; degraded rows must still satisfy the metadata contract with unknown fields.

---

## Outstanding Questions

### Deferred to Planning

- [Affects R2, R2b][Needs research] Final v1 signal table for high-confidence vs low-confidence Playwright/Puppeteer/possible automation browsers, with example false positives for each tier.
- [Affects R8, R9a][Technical] Exact permission set and collection mechanics for URL/title/process cmdline reads on target macOS versions.
- [Affects R5, R5a][Technical] Validate hide vs neutral zero-state behavior on supported macOS versions and pick the zero-state visual treatment.
- [Affects R12][Technical] Verify exact `agent-browser session list` / close command syntax and output shape against the installed CLI version.
- [Affects R13a][Technical] Define the minimal process-identity tuple used for PID revalidation (start time tolerance, cmdline match rules).
