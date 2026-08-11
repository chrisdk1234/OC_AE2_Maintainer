# PROJECT_CONTEXT

OpenComputers (GTNH) Lua program that keeps AE2 stock levels topped up via autocrafting.
Runs on an in-game OC computer with an Adapter touching an ME Controller or ME Interface.

## Files

- `craftables.lua` — lists all AE2 craft patterns, optionally (re)generates `config.lua` with every craftable
- `config.lua` — runtime settings + maintained item list `{ label, threshold, batchSize }`
- `ae2_helpers.lua` — library: config load/reload, craftables cache, stock checks, craft start/track/cancel (globals, loaded via `require`)
- `level_maintainer.lua` — entry point; cycle loop, GPU resolution, interrupt + skip-key handling
- `diagnose.lua` — troubleshooting: CPU inventory, ambiguous/missing craft labels, single test request

## Functions (ae2_helpers.lua)

- `colorPrint(color, text)` — ANSI colored print
- `countActiveCrafts()` — number of entries in `activeCrafts`; single source of truth for the concurrency limit and all cycle displays
- `reloadConfig()` — drops `package.loaded.config`, re-reads `config.lua` into `cfg` (no reboot needed after config edits)
- `findConfiguredItem(itemName)` — exact or substring match against `cfg.items`
- `ensureCraftablesCache()` / `findCraftable(itemName)` — one `ME.getCraftables{label=…}` query per configured item, cached; `findCraftable` returns `craftable, stack` where the stack comes from **`craftable.getStack()`** (the OC/AE2 method name — `getItemStack` does not exist)
- `getCurrentStock(itemLabel)` — `ME.getItemsInNetwork{label=…}` size
- `checkAllThresholds()` — returns items below threshold (`threshold == 0` ⇒ infinite craft, `batchSize == 0` ⇒ skip); prints one OK/BELOW summary line, or the full per-item stock table when `cfg.compactStatus` is false
- `trackerState(tracker)` — decodes the async `CraftingStatus` into `COMPUTING` / `FAILED` / `CANCELED` / `COMPLETED` / `IN_PROGRESS`; never treats the `"computing"` second return of `isDone()` as an error
- `describeCraftFailure(reason)` — annotates AE2's generic `request failed (missing resources?)` with its three real causes
- `getCraftingCpuInfo()` — `ME.getCpus()` wrapper: `{ total, free, maxFreeStorage, list }`, or `nil` on proxies without `getCpus`
- `cancelCraftByItem(itemName)` — cancels via the CPU whose `finalOutput().label` matches (the tracker has no `cancel()`); needs a Crafting Monitor in the cluster
- `startCraft(itemName, amount, currentCycle)` — requests the craft, waits out AE2's async planning (`cfg.craftRequestTimeout`), fails on `hasFailed()`, then registers the tracker in `activeCrafts`
- `isItemCurrentlyBeingCrafted(itemName)` — dedupe guard against double requests
- `autoCraftNeededItems(currentCycle)` — main worker: threshold check → optional shuffle → start crafts up to `cfg.maxConcurrentCrafts` → summary (started / skipped / deferred / failed)
- `cleanupCompletedCrafts()`, `cleanupTimedOutCrafts(currentCycle)`, `checkCraftStatus(id, cycle)`, `checkActiveCrafts(cycle)`, `cancelAllActiveCrafts()` — craft lifecycle

## Functions (level_maintainer.lua)

- `onInterrupt()` — Ctrl+C handler, clears `running`
- `isSkipKey(char, code)` — matches `cfg.skipKey` against a `key_down` signal; accepts a single character or a `keyboard.keys` name
- `sleepUntilNextCycle(sleepTime)` — `event.pull` in ≤1 s slices until the deadline; returns `true` when the skip key was pressed
- `startMaintainer()` — cycle loop: cleanup → status → `autoCraftNeededItems` → interruptible/skippable sleep; on exit cancels remaining crafts and prints the final threshold table

See [[Features]] and [[DECISIONS]].
