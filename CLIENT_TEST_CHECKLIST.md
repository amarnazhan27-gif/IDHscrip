# IDH / NasiHub Client System v3.0 — Manual Runtime Test Checklist

This document details the manual test procedures to validate the client system in private/testing experiences.

---

## 1. Lifecycle & System Integrity

- [ ] **Script Load**
  - Execute script in clean environment.
  - Verify UI opens without throwing runtime errors.
  - Verify `shared.IDH_CLIENT_RUNTIME` is registered.
- [ ] **Re-execution**
  - Execute script a second time while UI is already running.
  - Verify old UI and connections are cleaned up, without duplicate threads or duplicate UI elements.
  - Verify no memory or connection leaks.
- [ ] **Spectate & Re-execution (Case E)**
  - Start Spectating a player, then re-execute the script or call `RuntimeController.cleanup()`.
  - Verify `PlayerController.stopSpectate()` is invoked and camera restores smoothly to local player's Humanoid.
- [ ] **Mode Switching**
  - Switch rapidly between **HOME**, **FISHING**, **MINING**, **AVATAR**, **SPOTS**, **SETTINGS**, **DIAGNOSTICS**.
  - Verify running background tasks of the previous mode terminate immediately (generation ID check).

---

## 2. Auto Fishing

- [ ] **Fishing Toggle ON / OFF**
  - Toggle Fishing ON, then immediately OFF.
  - Verify all virtual inputs (Space key) and camera locks are released.
- [ ] **No Rod Scenario**
  - Unequip all tools and clear Backpack. Toggle Fishing ON.
  - Verify UI displays `"No rod found"` / warning logged, does not crash or loop endlessly.
- [ ] **Reeling GUI Appears**
  - Equip a valid fishing rod and cast.
  - When the Reeling GUI appears, verify transition from `WAITING_BITE` to `REELING`.
  - Verify `lastFishingGuiOpenedAt` is recorded in Diagnostics.
- [ ] **Bar Disappears (bar-gone)**
  - When minigame finishes and GUI disappears, verify state is recorded as `UNKNOWN` / `RESULT_UNCONFIRMED`.
  - Verify `fishConfirmed` count **does NOT** increment.
  - Verify `lastFishingGuiClosedAt` is recorded in Diagnostics.
- [ ] **Bite Timeout without GUI**
  - Cast into an area or state where no bite occurs.
  - Wait for `biteTimeout` (15s) to elapse.
  - Verify state transitions to timeout/reset and recasts cleanly **without** prematurely entering `REELING`.
- [ ] **Respawn during Fishing**
  - Reset character while in `CASTING`, `WAITING_BITE`, or `REELING`.
  - Verify fishing state machine resets to `IDLE`, WalkSpeed/JumpEnabled are restored, and fishing resumes cleanly on new character.

---

## 3. Auto Mining & Target Canonicalization

- [ ] **Mining: No Target Available**
  - Toggle Mining ON when no mineable parts/models are in range.
  - Verify state shows `SCAN` / `IDLE` waiting without error loops.
- [ ] **Child Part Tagged Ore Inside Generic Model (Case A)**
  - Place a child `Part` tagged `Ore` (or with `IsOre=true`) inside a generic untagged Model (e.g. `Model "Building"`).
  - Verify strong child evidence is **NOT** lost and child Part remains the selected target.
- [ ] **Generic Model Containing Neon Decorative Parts (Case B)**
  - Place a generic decoration Model with `Neon` parts but no semantic mining tags/attributes/names.
  - Verify it is **NOT** selected as a mining target (rejected by `MIN_SEMANTIC_SCORE` floor).
- [ ] **Model with Mining Evidence on Descendant (Case C)**
  - Place a `Model` where descendants provide aggregate mining evidence (e.g. `Model "CrystalNode"` with child ore parts).
  - Verify the canonical `Model` is selected once (globally deduplicated, child parts not added as separate duplicate targets).
- [ ] **Path Blocked Exceeding Max Recomputes (Case D)**
  - Block character path with dynamic obstacles continuously.
  - Verify `Path.Blocked` recomputes up to exact limit `maxPathRecomputes` (3) and logs `"Path.Blocked — recomputing (1/3)"`, `(2/3)`, `(3/3)`, then logs `"Path blocked — recompute limit reached"` and returns `"blocked"`.
  - Verify **no** `"(4/3)"` log occurs.
- [ ] **Target Disappears / Depleted mid-mining**
  - Delete or deplete the target instance while character is walking towards or swinging at it.
  - Verify `isTargetDepleted()` detects instance removal and cleanly triggers completion / retargeting without getting stuck.
- [ ] **WalkSpeed Restoration Guarantee**
  - Verify original `WalkSpeed` is restored in all cases (target reached, target gone, mode switch, error, timeout, blocked).

---

## 4. Avatar & Player Utilities

- [ ] **Avatar Copy**
  - Select a target player and click Copy Avatar.
  - Verify `Humanoid:ApplyDescriptionAsync()` (or fallback `ApplyDescription()`) is called safely.
  - Verify avatar appearance updates.
- [ ] **Avatar Restore**
  - Click Restore Original.
  - Verify appearance returns to the local player's initial state saved at startup/spawn.
- [ ] **Target Leaves during Copy**
  - If target leaves while copy is in progress, verify UI gracefully shows `"Target unavailable"` without error.
- [ ] **Character Respawn during Async Avatar Apply**
  - Respawn character while an async avatar copy is resolving.
  - Verify generation guard prevents the stale coroutine from mutating the new character unexpectedly.
- [ ] **Spectate Player**
  - Select a player and start spectating.
  - Verify `CameraSubject` updates to the target Humanoid.
- [ ] **Spectate Stop & Cleanup**
  - Stop spectating or destroy runtime.
  - Verify `CameraSubject` is restored to local player's Humanoid.
  - Verify script re-execution or script kill leaves the camera normal.

---

## 5. Spot Manager & Persistence

- [ ] **Save Spot**
  - Save current position with a descriptive name.
  - Verify spot appears in the list and persists in JSON (if file IO is supported).
- [ ] **Teleport to Spot**
  - Teleport to a saved spot. Verify `HumanoidRootPart.CFrame` is updated.
- [ ] **Malformed JSON Resilience**
  - Inject invalid JSON (wrong types, `NaN`, non-numeric coords) into the spots file.
  - Reload script and verify corrupt entries are skipped safely with a warning log rather than crashing.
