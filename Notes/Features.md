# Features

## Active

- Threshold maintenance — per item `{ label, threshold, batchSize }`; craft when stock < threshold
- Infinite crafting — `threshold = 0` requests every cycle regardless of stock; `batchSize = 0` disables an entry
- Shuffle — randomizes craft order for even buffer filling
- Craftables cache — one AE2 query per configured item at startup instead of a full pattern scan
- Craft timeout — unfinished crafts are cancelled after `requestTimeoutCycles`
- Hot config reload — `reloadConfig()` on start, no OC reboot after editing `config.lua`
- Config generator — `craftables.lua` writes a `config.lua` containing every AE2 craftable
- Graceful stop — Ctrl+C cancels all active crafts and prints a final threshold table
- **Concurrent craft limit** — `maxConcurrentCrafts` (default 8, `0` = unlimited). Cycle shows `🎚 Craft slots: n/max in use`; once full, remaining items are deferred to the next cycle and counted in the summary
- **Skip wait key** — `skipKey` (default `"r"`) ends the sleep phase early and starts the next cycle. Accepts a single character or an OC `keyboard.keys` name ("space", "enter")

- **Compact cycle status** — `compactStatus` (default true) replaces the per-item threshold table with one line: `✅ OK n/total   ❌ BELOW n/total` plus `🔄 INFINITE` / `⏭ SKIP` counts when non-zero. Items below threshold still appear individually in the craft-request section, so nothing is hidden. `false` restores the full table
- **CPU-aware scheduling** — per cycle the program starts at most `min(maxConcurrentCrafts - active, idle AE2 CPUs)` jobs and prints the CPU picture (`🖥 AE2 crafting CPUs: n idle / m total`)
- **Actionable craft failures** — `request failed (missing resources?)` is annotated with its three real causes (no idle/large-enough CPU, CPU set to player-only crafting, genuinely missing ingredient), and the cycle aborts at the first one instead of repeating it per item
- **diagnose.lua** — CPU inventory (size, co-processors, busy), config labels that match zero or several craft patterns, and an optional single test request that prints AE2's verdict

## Fixed

- AE2 craftable stacks are read with `craftable.getStack()`; the previously used `getItemStack()` does not exist on OC's AE2 craftable object and errored out in `findCraftable` and `craftables.lua`
- Craft requests are no longer declared failed while AE2 is still planning them (`isDone()` returns `(false, "computing")` in that window), which also removes the untracked-job case where AE2 submitted a craft the program had already written off
- Jobs that fail after being started are dropped from `activeCrafts` instead of holding a craft slot forever
- Craft cancellation works again: it goes through the CPU running the job, since the request tracker has no `cancel()` method

See [[PROJECT_CONTEXT]] and [[DECISIONS]].
