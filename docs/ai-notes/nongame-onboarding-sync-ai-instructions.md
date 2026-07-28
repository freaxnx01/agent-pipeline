# Non-game repo onboarding — sync-ai-instructions half (deferred)

## Status

**Done:** the `agent-workflow-init` half (secrets, labels, Actions setting,
`agent.yml` stub committed direct-to-default-branch) has been run against all
30 non-game candidate repos via `scripts/onboard-consumer.sh`. Zero failures.
All 30 now have a live `ai-implement` pipeline.

**Deferred:** the `sync-ai-instructions` half (CLAUDE.md + a stack overlay from
`freaxnx01/ai-instructions`) has **not** been run for any of them. No scope
decision has been made yet — see below.

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

## Next step, when resumed

1. Decide scope: run `/sync-ai-instructions` now for just `quotes` and
   `flowhub` (the 2 clean matches), and explicitly park the other 28 pending
   further triage — or tackle bucket 2's ambiguous repos first by actually
   inspecting them (clone + look, not just `languages` API guesswork).
2. For bucket 1, decide whether new stack overlays are worth authoring in
   `freaxnx01/ai-instructions` (`.ai/stacks/gdscript-godot.md`,
   `.ai/stacks/shell.md`, `.ai/stacks/dotnet-library.md`,
   `.ai/stacks/kotlin-android.md` or similar) before onboarding those repos,
   or accept they stay un-onboarded for the instructions half indefinitely.
3. For bucket 3 (meta/tooling repos), decide per-repo rather than batch —
   some may already have adequate hand-written `CLAUDE.md` files that
   shouldn't be overwritten by a generic assembly.
4. Whatever is decided, execution is just running `/sync-ai-instructions
   [stack]` (or `/init-repo` if `agent-workflow-init` somehow needs re-running
   too, though it doesn't for these 30 — that half is done) per repo, one at a
   time, from that repo's own working directory.
