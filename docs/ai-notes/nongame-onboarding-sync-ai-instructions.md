# Non-game repo onboarding — sync-ai-instructions half (deferred)

## Status

**Done:** the `agent-workflow-init` half (secrets, labels, Actions setting,
`agent.yml` stub committed direct-to-default-branch) has been run against all
30 non-game candidate repos via `scripts/onboard-consumer.sh`. Zero failures.
All 30 now have a live `ai-implement` pipeline.

**Done:** the `sync-ai-instructions` half has been run for 5 repos total —
`quotes` (`dotnet-webapi`, 2026-07-28, committed+pushed), `flowhub`
(`dotnet-blazor`, 2026-07-28, committed+pushed), and, after bucket-2
inspection (2026-07-30), 3 more confirmed clean matches: `llmeter`
(`dotnet-webapi`, first-time init), `demo-feedback-poc` (`dotnet-blazor`,
first-time init), `mgrabber-nextgen` (`dotnet-blazor` — turned out to already
be onboarded 2026-07-26; this audit's original table was stale on that one).
All 5 committed and pushed 2026-07-30.

**Bucket 2 (ambiguous) resolved via actual inspection**, 2026-07-30 — the
original table's stack-fit column was guessed from the GitHub languages API
only; real code inspection (via `gh api` contents, no full clone needed for
most) changed several verdicts:

| Repo | Original guess | Actual verdict (inspected) |
|---|---|---|
| `llmeter` | Unclear | **dotnet-webapi fit** — clean ASP.NET Core minimal API + worker |
| `mgrabber-nextgen` | Unclear | **dotnet-blazor fit** — clean Blazor Server + Minimal API host |
| `demo-feedback-poc` | Possible dotnet-webapi | **dotnet-blazor fit** — Blazor Web App (server+WASM), languages API was misleading |
| `PersonalLibrary` | Unclear | **No clean fit** — legacy .NET Framework class-library collection (mixed v3.5/v4.8, non-SDK-style), not a service; `dotnet-fx48-legacy` is the closest available overlay but a loose/debatable match |
| `bridge` | Partial (go overlay) | **No fit** — polyglot CLI tool (Go core + shell shim + Python Telegram bot + Svelte companion UI); needs a new overlay type not on today's roster |
| `signal-chat-to-telegram` | Unclear | **No fit** — plain run-once console tool, no host/worker/web shape at all |
| `Digital-Signage` | Unclear | **Not a real candidate yet** — empty placeholder repo (README title only, no code) |
| `MusicGrabber` | Unclear | **Not a real candidate yet** — empty placeholder repo (README title only, no code) |

**Bucket 1 resolved**, 2026-07-30 — inspected the 6 original candidates via
real code, not the languages API. `quicktask-vikunja` turned out to be a
**Flutter app** (existing `flutter` overlay fits, no new overlay needed,
synced same day). The other 5 confirmed 3 new overlays were worth authoring:

| New overlay | Repo(s) synced | Notes |
|---|---|---|
| `gdscript-godot` | `civil-war-battlefield` | Godot 4.4, real active game (not a scaffold). Single-repo calibration — kept generic. |
| `dotnet-library` | `CommonLibrary`, `Extensions`, `StringKing`, `CodeConverterSingleFile`, `SaveOutlookCalendar` | Standalone overlay, **not** built on the shared `dotnet-core` partial (that partial assumes ASP.NET Core service shape — Modular Monolith, EF Core, Minimal API — irrelevant to a plain library/console tool). `StringKing`'s `StringKingUI` subproject is legacy net48 WinForms — a mixed-repo edge case, synced as `dotnet-library` anyway since the rest of the repo fits; flag if it needs separate treatment later. |
| `shell-scripts` | `linux-scripts`, `powershell`, `screenpresso-localsend` | Lighter-weight by design — often no build/test tooling at all. `SampleWebNano` dropped from this bucket: turned out to be a Docker/container sample, not a script collection, despite its PowerShell language tag. |

All 3 overlays committed to `ai-instructions` ([`5850ff4`](https://github.com/freaxnx01/ai-instructions/commit/5850ff4)), pass the byte budget with headroom (22–24KB assembled vs the 39.5KB ceiling), markdownlint clean. README "Supported stacks" table updated. All 9 repos above synced, committed, and pushed same day.

**`dotnet-scripts`** (pure `.csx`/`dotnet-script` files, no `.csproj`) — does not fit `dotnet-library` or any existing overlay. Left unassigned; not onboarded.

**Bucket 3 resolved**, 2026-07-30 — inspected all 5; verdict is **skip
`/sync-ai-instructions` for all of them**, per-repo, as anticipated:

| Repo | Verdict |
|---|---|
| `claude-code-plugins` | Claude Code plugin marketplace (`.claude-plugin` structure) — domain-specific, not a language stack |
| `agent-skills` | Same shape (skills/plugin repo). **No `CLAUDE.md` exists at all** — worth a hand-written one eventually, but that's a new task, not a sync-ai-instructions candidate |
| `ai-instructions` | Self-referential — this repo **is** the overlay source; its own `CLAUDE.md` explicitly documents it's never a consumer of its own output |
| `agent-os` | Hand-written `CLAUDE.md` describing host-specific infra (LXC container, mirror config) — inherently repo-specific |
| `config` | Thin existing hand-written `CLAUDE.md` (commit conventions) for a dotfiles/shell-config repo |

Also synced same day: `quicktask-vikunja` (existing `flutter` overlay was
stale, refreshed to `5850ff4`) — the bucket-1 repo that turned out not to
need a new overlay.

**Status: all 3 buckets now resolved.** Remaining open items, not blocking:
`dotnet-scripts` (no overlay fits — pure `.csx` files), and whether
`agent-skills` eventually gets a hand-written `CLAUDE.md` (separate task).

Full context: this followed onboarding all 37 `game-*` repos (same two-part
flow, `browser-game` stack, no ambiguity there since they're homogeneous).
This non-game batch is far more heterogeneous, and that heterogeneity is
exactly what's blocking the second half.

## The 30 candidate repos

Already excluded from this list (don't onboard at all): forks (`dotfiles`,
`engomo-tomcat`, `traefik-example`, `FlowHub-CAS-AISE`), non-code repos
(`obsidian-it`, `ideas-lab`, `misc`, `LINQPad-Queries`), `agent-workflow` itself
(self-modification guard makes it a special dogfooding case, not a normal
consumer), and `agent-action-sandbox` (already a dedicated pipeline test
sandbox).

Candidates, with detected language (via `gh api repos/freaxnx01/<repo>/languages`)
and stack-fit assessment against the 7 overlays currently in
`freaxnx01/ai-instructions/.ai/stacks/` (`browser-game`, `ci`, `dotnet-blazor`,
`dotnet-fx48-legacy`, `dotnet-webapi`, `flutter`, `go`):

| Repo | Language(s) | Stack fit |
|---|---|---|
| `quotes` | C#, ASP.NET Core (per description) | **Clean match: `dotnet-webapi`** |
| `flowhub` | C#, TS, Python, Dockerfile (".NET 10, Blazor" per description) | **Clean match: `dotnet-blazor`** |
| `CodeConverterSingleFile` | Batchfile, C# | No fit — plain C# utility, no webapi/blazor/fx48 shape |
| `CommonLibrary` | C# | No fit — pure library, no generic "dotnet-library" overlay exists |
| `Extensions` | C# | No fit — same as above |
| `PersonalLibrary` | C#, CSS, HTML, JS, RTF | Unclear — has web assets but unconfirmed if webapi/blazor |
| `SampleWebNano` | Dockerfile, PowerShell | No fit |
| `StringKing` | C# | No fit — pure library |
| `bridge` | Go, HTML, JS, Just, Makefile, PowerShell, Python, Shell, Svelte | Partial — has a `go` overlay but repo is polyglot/CLI, not a pure Go service |
| `build-ci` | Dockerfile | No fit |
| `civil-war-battlefield` | GDScript | **No overlay exists** (Godot/GDScript) |
| `common` | (none detected) | No fit |
| `dotnet-scripts` | C# | No fit — scripts, not webapi/blazor |
| `freaxnx01.github.io` | CSS, HTML, JS, Python | No fit (not `browser-game` — it's the games hub, not a game) |
| `github-pages-example` | CSS, HTML | No fit |
| `linux-scripts` | Shell | **No overlay exists** (pure shell) |
| `llmeter` | C#, Dockerfile | Unclear — could be `dotnet-webapi` if it's a service |
| `mgrabber-nextgen` | Bru, C#, Dockerfile, HTML, Just, Shell | Unclear |
| `powershell` | Batchfile, PowerShell, Shell | **No overlay exists** |
| `quicktask-vikunja` | C, C++, CMake, Dart, Just, Kotlin, Shell | **No overlay exists** (Android/Kotlin/Dart) |
| `screenpresso-localsend` | PowerShell, Shell | **No overlay exists** |
| `signal-chat-to-telegram` | C# | Unclear — console/worker app, not webapi/blazor |
| `Digital-Signage` | (none detected) | Unclear |
| `SaveOutlookCalendar` | C# | No fit — console/script tool |
| `MusicGrabber` | (none detected) | Unclear |
| `demo-feedback-poc` | C#, CSS, HTML, JS | Possible `dotnet-webapi` fit |
| `claude-code-plugins` | (none detected) | Meta/tooling — likely wants bespoke conventions, not a generic stack |
| `agent-skills` | (none detected) | Meta/tooling — same |
| `ai-instructions` | (none detected) | Meta/tooling — this IS the stack-source repo, self-referential |
| `agent-os` | (none detected) | Meta/tooling |
| `config` | (none detected) | Meta/tooling — personal dotfiles-adjacent config |

## The open decision

`/sync-ai-instructions` requires picking **exactly one** existing stack
overlay, and stops/asks if none matches — it will not silently proceed
without one. Given the table above, only 2 of 30 repos (`quotes`, `flowhub`)
have an unambiguous existing match. The rest fall into three buckets:

1. **Needs a new stack overlay that doesn't exist yet** — GDScript/Godot
   (`civil-war-battlefield`), shell/PowerShell (`linux-scripts`, `powershell`,
   `screenpresso-localsend`, `SampleWebNano`), Kotlin/Dart/Android
   (`quicktask-vikunja`), and arguably a generic "dotnet-library" overlay for
   the several pure-C#-library repos (`CommonLibrary`, `Extensions`,
   `StringKing`, `CodeConverterSingleFile`, `dotnet-scripts`,
   `SaveOutlookCalendar`).
2. **Ambiguous — needs inspection to confirm webapi/blazor/fx48 fit** (or "no
   fit, needs a new overlay") — `PersonalLibrary`, `bridge`, `llmeter`,
   `mgrabber-nextgen`, `signal-chat-to-telegram`, `Digital-Signage`,
   `MusicGrabber`, `demo-feedback-poc`.
3. **Meta/tooling repos that may not want a generic stack at all** —
   `claude-code-plugins`, `agent-skills`, `ai-instructions`, `agent-os`,
   `config`. These likely already have (or want) bespoke, hand-written
   instructions rather than an assembled base+stack file.

No decision has been made on any of: whether to author new stack overlays
(and which ones, in what order), how to handle bucket 3 (skip entirely?
base-instructions only, no stack?), or whether to just do the 2 clean matches
now and park the rest.

## Outcome (resolved 2026-07-30)

All 3 buckets are resolved — see the Status section above for the full
breakdown. Final count across the original 30 candidates:

- **15 repos synced**: `quotes`, `flowhub`, `llmeter`, `demo-feedback-poc`,
  `mgrabber-nextgen`, `civil-war-battlefield`, `CommonLibrary`, `Extensions`,
  `StringKing`, `CodeConverterSingleFile`, `SaveOutlookCalendar`,
  `linux-scripts`, `powershell`, `screenpresso-localsend`,
  `quicktask-vikunja`.
- **3 new overlays authored**: `gdscript-godot`, `dotnet-library`,
  `shell-scripts` (`ai-instructions@5850ff4`).
- **5 repos deliberately skipped** (bucket 3, bespoke instructions stay
  hand-written): `claude-code-plugins`, `agent-skills`, `ai-instructions`,
  `agent-os`, `config`.
- **3 repos with no clean fit**: `PersonalLibrary` (debatable
  `dotnet-fx48-legacy`, not actually run), `bridge`, `signal-chat-to-telegram`.
- **3 repos not real candidates**: `Digital-Signage`, `MusicGrabber` (empty
  placeholders), `SampleWebNano` (turned out to be a Docker sample).
- **1 repo unassigned**: `dotnet-scripts` (no `.csproj`, doesn't fit any
  overlay).

No further action needed unless: `PersonalLibrary` gets manually assigned
`dotnet-fx48-legacy` despite the loose fit, `bridge`/`signal-chat-to-telegram`
get a bespoke treatment, `dotnet-scripts` gets its own overlay, or
`agent-skills` gets a hand-written `CLAUDE.md`.
