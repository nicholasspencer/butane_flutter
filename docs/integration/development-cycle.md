# Autonomous Integration Development Cycle

How butane_flutter's integration harness is built, tested, and maintained through an autonomous agent pipeline with beads-based issue tracking.

## The Pipeline

Three systems work together: the **factory loop** for autonomous implementation, **beads** (`bd`) for issue tracking and bug discovery, and the **harness** itself for validation.

```mermaid
flowchart TD
    subgraph Human["Human (Nico)"]
        PLAN["Write design doc\n+ implementation plan"]
        REVIEW["Review PRs\n+ grant permissions"]
        UNBLOCK["Unblock hardware issues\n(TCC, device auth)"]
    end

    subgraph Factory["Factory Loop (Autonomous)"]
        BP[Blueprint\nPlanning skill]
        SV[Supervisor\nDispatch + monitor]
        FA[Factory Agent\nImplementation]
    end

    subgraph Beads["Beads (bd) Issue Tracking"]
        CREATE["bd create\nNew beads"]
        CLAIM["bd update --claim\nAssign to factory"]
        CLOSE["bd close\nWith reason/SHA"]
        DISC["discovered-from\nLink bugs to parent"]
    end

    subgraph Harness["Integration Harness"]
        COORD[Coordinator CLI]
        CENTRAL[Central App]
        PERIPH[Peripheral App]
    end

    PLAN --> BP
    BP --> SV
    SV -->|dispatch| FA
    FA -->|implements| CREATE
    FA -->|runs| COORD
    COORD --> CENTRAL & PERIPH
    CENTRAL & PERIPH -->|failures| DISC
    DISC --> FA
    FA --> CLAIM
    FA -->|fix + verify| CLOSE
    CLOSE -->|re-run| COORD
    FA -->|PR| REVIEW
    SV -->|blocked?| UNBLOCK

    style Human fill:#2d1b69,stroke:#8b5cf6,color:#eee
    style Factory fill:#1a1a2e,stroke:#e94560,color:#eee
    style Beads fill:#0d3b66,stroke:#3a86ff,color:#eee
    style Harness fill:#1b4332,stroke:#40916c,color:#eee
```

## Phased Build-Out

The harness was built in phases, each tracked as beads with dependency chains. The factory loop executed each phase autonomously — planning decomposed the work, the supervisor dispatched agents, and factory agents implemented task-by-task.

```mermaid
flowchart LR
    subgraph Phase1["Phase 1: Pigeon API"]
        V5C["butane_flutter-v5c\nPigeon data models"]
        A44["butane_flutter-a44\nSubscription callbacks"]
    end

    subgraph Phase2["Phase 2: Platform Interface"]
        CF8["butane_flutter-cf8\nAbstract methods + channel impl"]
    end

    subgraph Phase3["Phase 3: Swift"]
        H9A["butane_flutter-h9a\nPeripheralManager.swift"]
    end

    subgraph Phase4["Phase 4: Dart Porcelain"]
        P70["butane_flutter-70p\nPeripheralManager class"]
    end

    subgraph Phase5["Phase 5: Harness App"]
        S6C["butane_flutter-6c8\nApp scaffold"]
        TPQ["butane_flutter-tpq\nCentral role"]
        UVV["butane_flutter-uvv\nPeripheral role"]
    end

    subgraph Phase6["Phase 6: Coordinator"]
        LIR["butane_flutter-lir\nCLI + launch script"]
        E2E["butane_flutter-41i\nE2E verification"]
    end

    V5C --> CF8
    A44 --> CF8
    CF8 --> H9A
    H9A --> P70
    P70 --> S6C
    S6C --> TPQ & UVV
    TPQ --> LIR
    UVV --> LIR
    LIR --> E2E

    style Phase1 fill:#16213e,stroke:#0f3460,color:#eee
    style Phase2 fill:#16213e,stroke:#0f3460,color:#eee
    style Phase3 fill:#16213e,stroke:#0f3460,color:#eee
    style Phase4 fill:#16213e,stroke:#0f3460,color:#eee
    style Phase5 fill:#16213e,stroke:#0f3460,color:#eee
    style Phase6 fill:#16213e,stroke:#0f3460,color:#eee
```

## Bug Discovery During E2E Verification

When the E2E verification bead (`butane_flutter-41i`) runs the harness, failures are tracked as bug beads linked via `discovered-from`. This creates an audit trail of what broke, what fixed it, and how it was found.

```mermaid
sequenceDiagram
    participant SV as Supervisor
    participant FA as Factory Agent
    participant H as Harness (Coordinator)
    participant BD as Beads (bd)

    SV->>FA: Dispatch butane_flutter-41i
    FA->>BD: bd update butane_flutter-41i --claim

    loop Fix-and-Iterate
        FA->>H: Run coordinator
        H-->>FA: Results: 12/15 pass, 3 FAIL

        Note over FA,BD: For each new failure:

        FA->>BD: bd list (check for existing bug)
        FA->>BD: bd create "read_characteristic:<br/>UUID case mismatch" -t bug -p 1<br/>--deps discovered-from:butane_flutter-41i

        FA->>FA: Investigate + implement fix
        FA->>FA: git commit -m "fix(darwin):..."

        FA->>BD: bd close butane_flutter-wga<br/>--reason "Fixed in commit abc123"

        FA->>H: Re-run coordinator
        H-->>FA: Results: 14/15 pass, 1 FAIL
    end

    FA->>H: Final run: 15/15 pass ✅
    FA->>BD: bd close butane_flutter-41i<br/>--reason "15/15 steps pass"
    FA-->>SV: Complete
```

### Real Bug Discovery Chain

During the `butane_flutter-41i` E2E verification, four bugs were discovered and fixed autonomously:

```mermaid
flowchart TD
    E2E["butane_flutter-41i\nE2E Verification\n(parent task)"]

    WGA["butane_flutter-wga 🐛\nread_characteristic: UUID case\nmismatch in peripheral read\nresponse lookup"]

    K5K["butane_flutter-5k9 🐛\nwrite_characteristic: didWriteValueFor\nuses wrong continuation map"]

    JPS["butane_flutter-jps 🐛\nnotification round-trip: updateValue\nlookup fails — UUID case mismatch\nin services dictionary"]

    FUL["butane_flutter-ful 🐛\nnotification round-trip: initial\nsinkValue read emits spurious\nempty notification event"]

    H9L["butane_flutter-h9l 💡\nUse mDNS for harness device\ndiscovery instead of hardcoded IPs"]

    E2E -->|discovered-from| WGA
    E2E -->|discovered-from| K5K
    E2E -->|discovered-from| JPS
    E2E -->|discovered-from| FUL
    E2E -->|discovered-from| H9L

    WGA -.->|"fixed in ~2 min"| WGA_CLOSED["✅ Closed"]
    K5K -.->|"fixed in ~2 min"| K5K_CLOSED["✅ Closed"]
    JPS -.->|"fixed in ~12 min"| JPS_CLOSED["✅ Closed"]
    FUL -.->|"fixed in ~1 min"| FUL_CLOSED["✅ Closed"]
    H9L -.->|"improvement idea"| H9L_OPEN["📋 Open (P2)"]

    style E2E fill:#1a1a2e,stroke:#e94560,color:#eee
    style WGA fill:#8b0000,stroke:#ff4444,color:#eee
    style K5K fill:#8b0000,stroke:#ff4444,color:#eee
    style JPS fill:#8b0000,stroke:#ff4444,color:#eee
    style FUL fill:#8b0000,stroke:#ff4444,color:#eee
    style H9L fill:#0d3b66,stroke:#3a86ff,color:#eee
    style WGA_CLOSED fill:#1b4332,stroke:#40916c,color:#eee
    style K5K_CLOSED fill:#1b4332,stroke:#40916c,color:#eee
    style JPS_CLOSED fill:#1b4332,stroke:#40916c,color:#eee
    style FUL_CLOSED fill:#1b4332,stroke:#40916c,color:#eee
    style H9L_OPEN fill:#0d3b66,stroke:#3a86ff,color:#eee
```

## Beads Workflow

### Issue Lifecycle

```mermaid
stateDiagram-v2
    [*] --> open: bd create
    open --> ready: Human marks ready\nor unblocked
    ready --> in_progress: Supervisor dispatches\nbd update --claim
    in_progress --> open: Agent blocked\n(needs human input)
    in_progress --> closed: bd close --reason "..."
    closed --> [*]

    note right of ready
        bd ready shows all
        unblocked work items
    end note

    note right of in_progress
        Assigned to "factory"
        agent during dispatch
    end note
```

### Dependency Types

| Type | Meaning | Example |
|------|---------|---------|
| `blocks` | Must complete before dependent can start | `lir` (coordinator) blocks `41i` (E2E) |
| `discovered-from` | Bug/idea found while working on parent | `wga` (UUID bug) discovered from `41i` (E2E run) |
| `parent-child` | Subtask of a larger bead | `v5c.1`, `v5c.2` are children of `v5c` |

### Beads Commands Used in This Project

```bash
# Check what's ready to work on
bd ready --json

# Create a feature bead
bd create "Peripheral Manager Pigeon API" \
  -t feature -p 2 --json

# Create a bug discovered during another task
bd create "UUID case mismatch in read response" \
  -t bug -p 1 \
  --deps discovered-from:butane_flutter-41i --json

# Claim and start working
bd update butane_flutter-41i --claim --json

# Close with context
bd close butane_flutter-41i \
  --reason "15/15 steps pass. Error forwarding implemented." --json

# View full issue with comments and deps
bd show butane_flutter-41i --json
```

## Supervisor Dispatch Cycle

The supervisor runs autonomously (via heartbeat/cron), checks for ready work, and dispatches factory agents:

```mermaid
sequenceDiagram
    participant CRON as Cron / Heartbeat
    participant SV as Supervisor
    participant BD as Beads
    participant FA as Factory Agent
    participant GIT as Git

    CRON->>SV: Heartbeat tick
    SV->>BD: bd ready --json
    BD-->>SV: [butane_flutter-41i] ready

    SV->>SV: Check capacity\n(no other agents running)
    SV->>GIT: Create worktree\n.worktrees/butane_flutter-41i
    SV->>FA: Spawn agent in worktree\nwith bead context + design doc

    FA->>BD: bd update 41i --claim
    FA->>FA: Implement (fix-iterate loop)
    FA->>GIT: Commit fixes to branch
    FA->>GIT: Push branch, open PR
    FA->>BD: bd close 41i --reason "Done"
    FA-->>SV: Complete

    SV->>BD: bd comment 41i "Factory completed:..."
    SV->>SV: Clean up worktree

    Note over SV: Next heartbeat checks\nfor more ready work
```

## Cross-Device E2E Flow

The harness runs across two physical devices because CoreBluetooth can't do loopback (Central and Peripheral on the same Mac can't discover each other).

```mermaid
flowchart TB
    subgraph Mac["Mac Studio (macOS)"]
        COORD["Coordinator CLI\n(Dart)"]
        CENTRAL_APP["Harness App\nROLE=central\nWS :19100"]
        BLE_C["CoreBluetooth\nCentral Manager"]
    end

    subgraph iPad["iPad mini (iOS, USB)"]
        PERIPH_APP["Harness App\nROLE=peripheral\nWS :19101"]
        BLE_P["CoreBluetooth\nPeripheral Manager"]
    end

    COORD <-->|"WS localhost:19100"| CENTRAL_APP
    COORD <-->|"WS 192.168.x.x:19101"| PERIPH_APP
    CENTRAL_APP --> BLE_C
    PERIPH_APP --> BLE_P
    BLE_C <-.->|"BLE over-the-air"| BLE_P

    style Mac fill:#1a1a2e,stroke:#e94560,color:#eee
    style iPad fill:#16213e,stroke:#0f3460,color:#eee
```

### Known Constraints

- **macOS TCC Bluetooth authorization** — `flutter clean` invalidates the Bluetooth permission grant. Rebuilding requires human to re-approve in System Settings. Headless CI must pre-approve or use profiles.
- **iPad first-run permissions** — Bluetooth and Local Network permissions require manual tap on first install. Subsequent runs persist permissions unless the app is reinstalled.
- **IP addressing** — Currently uses `PERIPHERAL_HOST` env var for the iPad's IP. Future improvement: mDNS-based discovery (`butane_flutter-h9l`).

## Project Bead Map (Complete)

All beads created during harness development, showing the full dependency graph:

```mermaid
flowchart TD
    V5C["v5c ✅\nPigeon API definitions"]
    V5C1["v5c.1 ✅\nData models"]
    V5C2["v5c.2 ✅\nData models (retry)"]
    V5C3["v5c.3 ✅\nHost + Flutter API"]
    V5C4["v5c.4 ✅\nCodegen + validation"]

    CF8["cf8 ✅\nPlatform Interface"]
    CF81["cf8.1 ✅\nPM model classes"]
    CF82["cf8.2 ✅\nAbstract methods"]
    CF83["cf8.3 ✅\nChannel impl"]

    A44["a44 ✅\nSubscription support"]
    H9A["h9a ✅\nPeripheralManager.swift"]
    P70["70p ✅\nDart porcelain"]
    S6C["6c8 ✅\nApp scaffold"]
    TPQ["tpq ✅\nCentral role"]
    UVV["uvv ✅\nPeripheral role"]
    LIR["lir ✅\nCoordinator CLI"]
    E2E["41i ✅\nE2E verification"]

    WGA["wga 🐛✅\nUUID case (read)"]
    K5K["5k9 🐛✅\nWrong continuation map"]
    JPS["jps 🐛✅\nUUID case (updateValue)"]
    FUL["ful 🐛✅\nSpurious notification"]

    H9L["h9l 📋\nmDNS discovery"]
    A1A["1a2 📋\nNordic BLE mock"]
    F8B["8fb 📋\niOS device support"]

    V5C --> V5C1 & V5C2 & V5C3 & V5C4
    CF8 --> CF81 & CF82 & CF83
    LIR --> E2E
    E2E --> WGA & K5K & JPS & FUL & H9L
    E2E --> F8B

    style V5C fill:#1b4332,stroke:#40916c,color:#eee
    style CF8 fill:#1b4332,stroke:#40916c,color:#eee
    style E2E fill:#1b4332,stroke:#40916c,color:#eee
    style WGA fill:#5c1a1a,stroke:#ff6666,color:#eee
    style K5K fill:#5c1a1a,stroke:#ff6666,color:#eee
    style JPS fill:#5c1a1a,stroke:#ff6666,color:#eee
    style FUL fill:#5c1a1a,stroke:#ff6666,color:#eee
    style H9L fill:#0d3b66,stroke:#3a86ff,color:#eee
    style A1A fill:#0d3b66,stroke:#3a86ff,color:#eee
    style F8B fill:#0d3b66,stroke:#3a86ff,color:#eee
```

**Legend:** ✅ Closed | 🐛 Bug | 📋 Open/Backlog | 💡 Improvement idea
