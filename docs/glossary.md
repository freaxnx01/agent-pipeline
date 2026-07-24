# Glossary

## Scope creep

Scope creep is when work quietly expands beyond what was originally asked for —
a bug fix that grows into a refactor, a small feature that pulls in unrelated
cleanup, or a discovery made mid-task ("found a flaky test", "this dependency
is vulnerable") that gets fixed on the spot instead of being written down for
later. It happens one small, reasonable-looking step at a time, which is what
makes it hard to notice from the inside — each hop seems justified, but three
or four hops away from the original request you're effectively doing a
different project without ever deciding to. This repo's convention is to treat
anything outside the stated scope as a **discovery**, not automatically a
**task**: capture it (`/capture-idea`, `docs/TODO.md`, `/gh:new`, `/fj:new`)
and keep going on the original ask, only expanding scope when that expansion
is a deliberate decision rather than a drift. See
[`partials/scope-boundary.md`](../partials/scope-boundary.md) for the full
rule.
