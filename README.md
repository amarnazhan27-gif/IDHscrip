# IDH / NasiHub Client System v3.0

Client-side systems architecture designed for private/test experiences.

[![CodeRabbit Pull Request Reviews](https://img.shields.io/badge/CodeRabbit-PR%20Reviews-brightgreen)](https://coderabbit.ai)

---

## 1. Architecture Overview (v3.0)

The system is built on a modular controller pattern managed by a centralized runtime:

```
                  ┌───────────────────────────────┐
                  │       RuntimeController       │
                  │ (Lifecycle, Gen IDs, Cleanup) │
                  └───────────────┬───────────────┘
                                  │
      ┌───────────────────────────┼───────────────────────────┐
      │                           │                           │
┌─────▼──────────────┐  ┌─────────▼───────────┐  ┌────────────▼─────────┐
│ FishingController  │  │  MiningController   │  │   AvatarController   │
│ - FishingUIAdapter │  │ - TargetResolver    │  │ - ApplyDescAsync     │
│ - ResultObserver   │  │ - MiningMovement    │  │ - Generation Guard   │
│ - ToolResolver     │  │ - ActionAdapter     │  └──────────────────────┘
└────────────────────┘  └─────────────────────┘
```

### Core Controllers:
- **`RuntimeController`**: Singleton lifecycle manager tracking all `RBXScriptConnection` instances and generational task IDs. Guarantees clean cleanup on re-execution or termination.
- **`CharacterState`**: Saves and restores exact `WalkSpeed`, `JumpPower`, and `JumpEnabled` values per character. Never hardcodes default speeds.
- **`PerformanceMonitor`**: Computes exponential moving average of frame-time (`frameTime`) and frame-rate (`frameFPS`) based on Heartbeat `dt`.
- **`FishingController`**: Explicit state machine (`IDLE` → `CASTING` → `WAITING_BITE` → `REELING` → `RESULT_PENDING`).
- **`MiningController`**: Proximity scoring, pathfinding navigation, aim positioning, and instance depletion verification.
- **`AvatarController`**: `HumanoidDescription` copy and restore utility using `ApplyDescriptionAsync` with fallback.
- **`PlayerController`**: Event-driven player list, camera spectate with automatic restoration on cleanup, and XYZ clipboard export.
- **`SpotManager`**: Validated JSON persistence for coordinate waypoints (bounds and type-checked, max 10 spots).
- **`UIController`**: 7-tab responsive sidebar interface (Home, Fishing, Mining, Avatar, Spots, Settings, Diagnostics).

---

## 2. Auto Fishing & Confirmation Mechanics

### Result States & Evidence
| State | Trigger | Counted in `fishConfirmed`? |
|---|---|---|
| `SUCCESS_CONFIRMED` | Authoritative client evidence | Yes |
| `RESULT_UNCONFIRMED` / `UNKNOWN` | `bar-gone`, `tool-deactivate`, `gui-hidden` | **No** (Remains UNCONFIRMED) |
| `TIMEOUT` | `bite-timeout-no-gui`, minigame timer | **No** (Counted in `fishFailed`) |

> **Important**: `bar-gone` and `tool-deactivate` are treated strictly as `UNKNOWN`. `fishConfirmed` is never artificially incremented without verified client-side evidence.

### GUI Resolution Strategy
1. **Named Path**: `PlayerGui.Reeling.MainFrame.Frame.{WhiteBar, RedBar}`
2. **Structural Search**: Simultaneous search for WhiteBar and RedBar in all ScreenGuis.
3. **Color Fallback**: Heuristic match on white target bar and red fish bar.

### Waiting for Bite
`WAITING_BITE` continuously observes the UI for Reeling bar appearance. It does **not** assume a bite occurred when the timer expires. If the timer elapses without a GUI appearing, the cycle resets cleanly with `bite-timeout-no-gui`.

---

## 3. Auto Mining & Model Support

### Target Scoring Priority
1. **CollectionService Tags** (+20): `ore`, `crystal`, `mine`, `gem`
2. **Attributes** (+15): `IsOre`, `IsCrystal`, `IsMineTarget`, `Mineable`, `OreType`
3. **Container Name** (+8): Parent folder matching mineral naming conventions
4. **Semantics** (+4): `Neon` material, `MeshPart`, Collision properties
5. **Name Heuristic (CRYS_OK)** (+3): Low-confidence fallback only

### Model & BasePart Support
- Supports both `Model` and `BasePart` targets.
- Position is resolved via `PrimaryPart.Position`, `GetPivot().Position`, or bounding box center.
- Size is resolved via `GetBoundingBox()` for Models.
- Part candidates belonging to a valid mining Model are normalized to the Model to prevent duplicate targeting.

### Pathfinding & `Path.Blocked`
- Uses `PathfindingService` with direct `MoveTo` fallback.
- Actively listens to `path.Blocked` and automatically recomputes path up to `maxPathRecomputes` (3).
- Guaranteed exact `WalkSpeed` restoration on arrival, mode switch, target disappearance, or timeout.

---

## 4. Avatar & Player Utilities

- **Copy Avatar**: Applies target's `HumanoidDescription` using `Humanoid:ApplyDescriptionAsync()`, falling back to `ApplyDescription()`.
- **Generation Guard**: Captures avatar generation ID to prevent stale async tasks from modifying a newly respawned character.
- **Spectate**: Safely sets `CameraSubject` to target Humanoid; automatically restored to local Humanoid upon stopping or runtime cleanup.

---

## 5. Diagnostics & Observability

The **Diagnostics** tab provides live telemetry for runtime inspection:
- **Runtime**: Mode, Alive status, `FPS`, `frameTime` (ms), Slow-frame flag.
- **Fishing Trace**:
  - `lastFishingResultReason`
  - `lastFishingResultState`
  - `lastFishingProgress`
  - `lastFishingGuiOpenedAt`
  - `lastFishingGuiClosedAt`
  - `lastFishingToolState`
- **Mining**: State, Target identity & class, Cache entries & age.
- **Avatar & Spectate**: Status, Spectate active state.
- **Capabilities**: Available executor APIs (`fileIO`, `clipboard`, `httpReq`, `VIM`, `VU`).
- **Log Stream**: Last 5 events from rolling 150-line circular log.

---

## 6. Scope & Limitations

- **No Server Authority Claims**: Fishing success and mining damage depend on server-side authority. The client observes instance state changes (e.g., target `.Parent == nil` for mining).
- **No Anti-Cheat/Evasion Logic**: Contains no anti-ban, anti-detection, staff evasion, or remote exploitation mechanisms. Intended solely for private experience testing.
