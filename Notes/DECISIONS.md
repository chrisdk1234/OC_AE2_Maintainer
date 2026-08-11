# DECISIONS

## 2026-08-11 — `compactStatus` defaults to on, and the summary prints in both modes

The maintained-item list grows without bound, so a per-item table per cycle scrolls the terminal out of use.
`checkAllThresholds` now counts OK / BELOW / INFINITE / SKIP always and prints the per-item lines only when
`compactStatus` is false; the summary line is printed in both modes, so verbose output gains a total instead of
losing one. Default is on (`config.compactStatus ~= false`, so an absent key means compact) because that is the
useful behavior for a long item list — the `or` idiom used by the other options cannot express a default-true flag.

Nothing is hidden by compacting: items below threshold are still printed one per line by `autoCraftNeededItems`
when it requests them, and that section is bounded by the concurrency budget.

## 2026-08-11 — Craft requests are asynchronous; only `hasFailed()` reports failure

Source of truth: `li.cil.oc.integration.appeng.NetworkControl` in GTNH's OpenComputers fork.
`Craftable.request(amount)` returns a `CraftingStatus` immediately and plans the job on a worker thread.
`CraftingStatus.isDone()` / `isCanceled()` return `(false, "computing")` while planning, so the old
`local isDone, msg = tracker.isDone(); if msg ~= nil then fail end` treated *every* still-planning request as a
failure — and AE2 could still submit the job afterwards, leaving an untracked craft running.

Now: `startCraft` polls `isComputing()` for up to `cfg.craftRequestTimeout` seconds, then asks `hasFailed()`.
A job that is still planning is registered as active and resolved in a later cycle. `trackerState()` is the single
decoder (`COMPUTING` / `FAILED` / `CANCELED` / `COMPLETED` / `IN_PROGRESS`) used by status display and cleanup, so a
job that fails after being started releases its craft slot instead of holding it forever.

## 2026-08-11 — Concurrency is capped by idle AE2 CPUs, not just by config

`CraftingGridCache.submitJob` returns null — surfaced as `request failed (missing resources?)` — when the job is a
simulation, when no active idle CPU has `availableStorage >= job.getByteTotal()`, **or** when the CPU's
`CraftingAllow` mode excludes non-player sources. Requests from this program carry a `MachineSource`, which is why
a CPU set to player-only crafting fails here while a manual request in the terminal succeeds.

So the per-cycle budget is `min(maxConcurrentCrafts - active, idle CPUs)` from `ME.getCpus()`, and
`describeCraftFailure` appends those three causes to the message. `getCpus` is probed with `pcall`, so an ME proxy
without it falls back to the config limit alone.

## 2026-08-11 — Cancellation goes through the CPU, not the tracker

`CraftingStatus` has no `cancel()` callback (only `isComputing`/`hasFailed`/`isCanceled`/`isDone`), so the old
`pcall(tracker.cancel)` could never succeed — every timeout and shutdown cancel silently failed. `cancelCraftByItem`
walks `ME.getCpus()`, matches `cpu.finalOutput().label`, and calls `cpu.cancel()`. R: `finalOutput()` needs a
Crafting Monitor in the CPU cluster, otherwise the job cannot be identified and the failure is reported as such.

## 2026-08-11 — `getStack()` is the AE2 craftable accessor

OC's AE2 craftable object exposes `getStack()`, not `getItemStack()`. Every call site now uses `getStack()`
(`ae2_helpers.lua` `findCraftable`, both loops in `craftables.lua`). No compatibility shim: the old name never
existed, so a fallback would only hide real errors.

## 2026-08-11 — Concurrency limit enforced in `autoCraftNeededItems`, not in `startCraft`

The limit is a scheduling decision, so it belongs where the per-cycle craft list is walked. `activeCount` is
seeded once from [[PROJECT_CONTEXT|countActiveCrafts]] and incremented on each successful start, which avoids
re-counting `activeCrafts` per item. Items that do not fit are deferred (the loop breaks) rather than dropped —
they are re-evaluated next cycle against fresh stock numbers. `0` means unlimited; because `0` is truthy in Lua,
`config.maxConcurrentCrafts or 8` preserves an explicit `0`.

R: the limit counts *this program's* tracked jobs, not AE2 CPUs occupied by other players or systems.

## 2026-08-11 — Sleep phase driven by `event.pull`, not `os.sleep`

The chunked `os.sleep` loop could not observe key presses. `sleepUntilNextCycle` pulls `key_down` in ≤1 s slices
until an uptime deadline: the skip key returns early, other events still reach the registered `interrupted`
listener (OC dispatches listeners from inside `event.pull`), and the 1 s ceiling keeps Ctrl+C responsive.
`isSkipKey` checks the character code first and falls back to `keyboard.keys[name]`, so both `"r"` and `"space"`
style config values work, and shift-R matches lowercase config.

See [[Features]].
