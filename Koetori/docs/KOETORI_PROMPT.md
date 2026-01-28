# Koetori – Product & UX Prompt

Use this prompt when implementing or refining Koetori (iOS app + M5Stick recorder) so behavior stays consistent.

---

## Core record flow (must have)

- **One press = start recording.** No “load screen” or “wake” step. The first tap on the record control must start recording immediately. The user must never need to tap once to “wake” or “load” and then tap again to record.
- **Second press = stop and send.** The next press stops the recording, uploads it (mic path to API, or BLE path from M5Stick), and then shows results (transcript + memos). No extra confirmation step for “send.”
- **No intermediate “load” or “ready” screen.** The main screen is the record screen. Tapping the button should only ever: start recording, or stop-and-send. No separate “tap to load” or “tap to continue” before recording.

## iOS app

- **Record button:** Single, prominent control. Tap → start recording. Tap again → stop, upload, show results. Hit area is a full circle (e.g. 240pt) so the first tap always registers; no double-tap required.
- **Cancel:** While recording, a separate “Cancel” control discards the recording and does not upload.
- **History:** Recent memos (from mic and BLE) are listed in History; tapping one opens the same results view (transcript + memos).
- **BLE:** When connected to the M5Stick, audio can be received over BLE; same upload and results flow. No extra “load” step when the user presses the button on the device or in the app.

## M5Stick (if applicable)

- **Button A:** Press → start recording. Press again → stop, save/stream (e.g. to iOS via BLE or to file), then show result. No “tap to wake then tap to record” as the intended flow; if the device must wake from sleep, that wake should happen on the same press that starts recording where possible.
- **Button B:** Cancel recording or wake screen; no “load” step required before recording.

## Optional / future

- **Prompting for “Clau” or AI:** If the app or device later prompts an AI (e.g. Clau) or sends transcript/memos somewhere, the prompt or integration should assume the flow above: one press = record, second press = send. Any “prompt” or instruction set for the AI can be generated or updated from this document so behavior stays aligned.

---

_Generated so Koetori stays one-press-to-record, one-press-to-send, with no load/wake tap required._
