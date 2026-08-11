local component = require("component")
local computer  = require("computer")
local fs        = require("filesystem")
local craftDelay = 0

colors = {
    reset = "\27[0m",
    red = "\27[31m",
    green = "\27[32m", 
    yellow = "\27[33m",
    blue = "\27[34m",
    magenta = "\27[35m",
    cyan = "\27[36m",
    white = "\27[37m"
}

function colorPrint(color, text)
    print(color .. text .. colors.reset)
end


local ctrlAddr = component.list("me_controller")()
local intfAddr = component.list("me_interface")()
local addr     = ctrlAddr or intfAddr
               or error("No AE2 ME controller or interface found")
ME = component.proxy(addr)

local config = require("config")
cfg = {
    sleepInterval = config.sleepInterval or 60,
    shuffle = config.shuffle or false,
    requestTimeoutCycles = config.requestTimeoutCycles or 3,
    maxConcurrentCrafts = config.maxConcurrentCrafts or 8,
    craftRequestTimeout = config.craftRequestTimeout or 5,
    compactStatus = config.compactStatus ~= false,
    skipKey = config.skipKey or "r",
    resolution = config.resolution or { maxWidth = 120, maxHeight = 35 },
    items = config.items or {}
}


local function concurrencyLabel()
    if cfg.maxConcurrentCrafts and cfg.maxConcurrentCrafts > 0 then
        return tostring(cfg.maxConcurrentCrafts)
    end
    return "unlimited"
end

if not package.loaded["ae2_helpers"] then
    colorPrint(colors.cyan, "📋 Loaded configuration:")
    colorPrint(colors.cyan, "   Sleep Interval: " .. cfg.sleepInterval .. "s")
    colorPrint(colors.cyan, "   Shuffle Items: " .. tostring(cfg.shuffle))
    colorPrint(colors.cyan, "   Timeout Cycles: " .. cfg.requestTimeoutCycles)
    colorPrint(colors.cyan, "   Max Concurrent Crafts: " .. concurrencyLabel())
    colorPrint(colors.cyan, "   Craft Request Timeout: " .. cfg.craftRequestTimeout .. "s")
    colorPrint(colors.cyan, "   Compact Status: " .. tostring(cfg.compactStatus))
    colorPrint(colors.cyan, "   Skip Wait Key: " .. tostring(cfg.skipKey):upper())
    colorPrint(colors.cyan, "   Resolution: " .. cfg.resolution.maxWidth .. "x" .. cfg.resolution.maxHeight)
    colorPrint(colors.cyan, "   Configured Items: " .. #cfg.items)
end

-- Active craft requests tracking
activeCrafts = {}

function countActiveCrafts()
    local count = 0
    for _ in pairs(activeCrafts) do
        count = count + 1
    end
    return count
end

-------------------------------------------------------------------------------
-- Craft tracker helpers
--
-- AE2 plans a job on a worker thread, so the tracker returned by request() is
-- a state machine: computing → (link | failed). Its isDone()/isCanceled() both
-- return (false, "computing") while planning, so the second return value must
-- NOT be treated as an error. Only hasFailed() reports a real failure.
-------------------------------------------------------------------------------

local function trackerComputing(tracker)
    if not tracker.isComputing then return false end
    local ok, computing = pcall(tracker.isComputing)
    return ok and computing == true
end

local function trackerFailed(tracker)
    if not tracker.hasFailed then return false end
    local ok, failed, reason = pcall(tracker.hasFailed)
    if not ok then return false end
    return failed == true, reason
end

-- "COMPUTING" | "FAILED" | "CANCELED" | "COMPLETED" | "IN_PROGRESS"
function trackerState(tracker)
    if trackerComputing(tracker) then
        return "COMPUTING"
    end

    local failed, reason = trackerFailed(tracker)
    if failed then
        return "FAILED", reason
    end

    if tracker.isCanceled() then return "CANCELED" end
    if tracker.isDone() then return "COMPLETED" end
    return "IN_PROGRESS"
end

-- AE2 refused to place the job. Same message whether no CPU would take it or
-- the ingredients are missing, so this says nothing about which of the two.
function isCraftRefusal(reason)
    local text = tostring(reason):lower()
    return text:find("missing resources") ~= nil or text:find("no controller") ~= nil
end

-- AE2 gives one generic reason whenever submitJob() hands back no crafting
-- link. What it means can only be narrowed down with evidence from the running
-- cycle: pass how many jobs AE2 has already accepted. Once it has accepted one,
-- the CPUs demonstrably do serve machine requests, so a refusal after that is
-- about this item, not about the CPUs.
function describeCraftFailure(reason, acceptedThisCycle)
    local text = tostring(reason or "unknown")
    if not text:lower():find("missing resources") then
        return text
    end

    if acceptedThisCycle and acceptedThisCycle > 0 then
        return text .. string.format(
            "\n     ↳ AE2 took %d job(s) this cycle, so CPUs do accept machine requests → this item is missing an ingredient, or the CPUs just filled up",
            acceptedThisCycle)
    end

    return text .. "\n     ↳ nothing accepted yet this cycle: no idle CPU with enough bytes, CPU set to player-only crafting, or an ingredient is missing - run diagnose"
end

-- Only ever true for a real boolean true. Depending on the OC build, the busy
-- flag from getCpus() has been seen as something other than a Lua boolean, and
-- a truthy non-boolean must not make an idle CPU look busy.
function isCpuBusy(cpu)
    return cpu.busy == true
end

-- { total, free, maxFreeStorage, list } or nil when the ME proxy is too old.
-- INFORMATIONAL ONLY: never gate craft requests on this. AE2 decides whether a
-- job can be placed, and it answers that when we ask it - see isCraftRefusal().
function getCraftingCpuInfo()
    if not ME.getCpus then return nil end

    local ok, cpus = pcall(ME.getCpus)
    if not ok or type(cpus) ~= "table" then return nil end

    local info = { total = 0, free = 0, maxFreeStorage = 0, list = cpus }
    for _, cpu in pairs(cpus) do
        info.total = info.total + 1
        if not isCpuBusy(cpu) then
            info.free = info.free + 1
            local storage = tonumber(cpu.storage) or 0
            if storage > info.maxFreeStorage then
                info.maxFreeStorage = storage
            end
        end
    end

    return info
end

-- The request tracker has no cancel() method, so a running job can only be
-- stopped through the CPU executing it. Identifying that CPU needs a Crafting
-- Monitor in the cluster (finalOutput() is what tells us what it is making).
function cancelCraftByItem(itemName)
    if not ME.getCpus then return false, "ME proxy has no getCpus" end

    local ok, cpus = pcall(ME.getCpus)
    if not ok or type(cpus) ~= "table" then return false, "getCpus failed" end

    for _, entry in pairs(cpus) do
        if entry.busy and entry.cpu then
            local gotOutput, output = pcall(entry.cpu.finalOutput)
            if gotOutput and type(output) == "table" and output.label == itemName then
                local canceled, result = pcall(entry.cpu.cancel)
                if canceled and result then
                    return true
                end
                return false, tostring(result)
            end
        end
    end

    return false, "no CPU reported this item (CPU needs a Crafting Monitor to be identifiable)"
end


function reloadConfig()
    package.loaded.config = nil  -- Clear cache
    config = require("config")
    cfg.sleepInterval = config.sleepInterval or 60
    cfg.shuffle = config.shuffle or false
    cfg.requestTimeoutCycles = config.requestTimeoutCycles or 3
    cfg.maxConcurrentCrafts = config.maxConcurrentCrafts or 8
    cfg.craftRequestTimeout = config.craftRequestTimeout or 5
    cfg.compactStatus = config.compactStatus ~= false
    cfg.skipKey = config.skipKey or "r"
    cfg.resolution = config.resolution or { maxWidth = 120, maxHeight = 35 }
    cfg.items = config.items or {}
    colorPrint(colors.green, "🔄 Configuration reloaded")
    return cfg
end

function findConfiguredItem(itemName)
    for i, entry in ipairs(cfg.items) do
        local label, threshold, batchSize = entry[1], entry[2], entry[3]
        if label == itemName or string.find(string.lower(label), string.lower(itemName)) then
            return {
                index = i,
                label = label,
                threshold = threshold,
                batchSize = batchSize
            }
        end
    end
    return nil
end

local craftablesCache = {}
local craftablesCacheLoaded = false

function ensureCraftablesCache()
    if not craftablesCacheLoaded then
        local startTime = computer.uptime()
        colorPrint(colors.yellow, "🔄 Loading craftables cache...")
        
        craftablesCache = {}
        local cachedCount = 0
        
        -- Query each configured item directly from AE2
        for i, entry in ipairs(cfg.items) do
            local itemName = entry[1]
            local queryStart = computer.uptime()
            
            local craftablesList = ME.getCraftables({ label = itemName })
            local queryTime = computer.uptime() - queryStart
            
            if craftablesList and #craftablesList > 0 then
                local craftable = craftablesList[1] -- Take first match
                craftablesCache[itemName] = craftable
                cachedCount = cachedCount + 1
                colorPrint(colors.yellow, string.format("  [%d/%d] ✓ %s (%.3fs)", i, #cfg.items, itemName, queryTime))
                if #craftablesList > 1 then
                    -- Labels are matched exactly but are not unique in GTNH; a
                    -- wrong variant here requests a recipe you cannot build
                    colorPrint(colors.yellow, string.format(
                        "          ⚠ %d patterns share this label - using the first one",
                        #craftablesList))
                end
            else
                colorPrint(colors.red, string.format("  [%d/%d] ❌ %s (%.3fs) - NOT CRAFTABLE", i, #cfg.items, itemName, queryTime))
            end
        end
        
        local totalTime = computer.uptime() - startTime
        craftablesCacheLoaded = true
        colorPrint(colors.green, string.format("📚 Cache loaded: %d/%d items in %.1fs total", cachedCount, #cfg.items, totalTime))
    end
    return craftablesCache
end


function getCurrentStock(itemLabel)
    local inNet = ME.getItemsInNetwork({ label = itemLabel })
    return (inNet[1] and inNet[1].size) or 0
end


function checkAllThresholds()
    local needsCraftingList = {}
    local okCount, belowCount, infiniteCount, skippedCount = 0, 0, 0, 0
    local verbose = not cfg.compactStatus

    colorPrint(colors.cyan, string.format("🔍 Checking %d configured item thresholds:", #cfg.items))
    if verbose then
        colorPrint(colors.cyan, string.rep("=", 75))
    end

    for i, entry in ipairs(cfg.items) do
        local label, threshold, batchSize = entry[1], entry[2], entry[3]

        if not batchSize or batchSize == 0 then
            -- Skip items with no batch size
            skippedCount = skippedCount + 1
            if verbose then
                local line = string.format("%-45s %9s / %9s", label:sub(1,45), "---", "---")
                colorPrint(colors.cyan, line .. " >> SKIP (no batch size)")
            end
        elseif not threshold or threshold == 0 then
            -- Handle infinite crafting (threshold = 0 or nil)
            infiniteCount = infiniteCount + 1
            if verbose then
                local line = string.format("%-45s %9s / %9s", label:sub(1,45), "---", "∞")
                colorPrint(colors.blue, line .. " 🔄 INFINITE")
            end

            table.insert(needsCraftingList, {
                label = label,
                threshold = 0,
                batchSize = batchSize,
                current = 0,
                deficit = math.huge,
                infinite = true
            })
        else
            -- Normal threshold checking
            local current = getCurrentStock(label)
            local needs = current < threshold

            if needs then
                belowCount = belowCount + 1
            else
                okCount = okCount + 1
            end

            if verbose then
                local line = string.format("%-45s %9d / %9d", label:sub(1,45), current, threshold)
                if needs then
                    print(line .. colors.red .. " ❌ BELOW" .. colors.reset)
                else
                    print(line .. colors.green .. " ✅ OK" .. colors.reset)
                end
            end

            if needs then
                table.insert(needsCraftingList, {
                    label = label,
                    threshold = threshold,
                    batchSize = batchSize,
                    current = current,
                    deficit = threshold - current,
                    infinite = false
                })
            end
        end
    end

    local total = #cfg.items
    local summary = string.format("✅ OK %d/%d   ❌ BELOW %d/%d", okCount, total, belowCount, total)
    if infiniteCount > 0 then
        summary = summary .. string.format("   🔄 INFINITE %d", infiniteCount)
    end
    if skippedCount > 0 then
        summary = summary .. string.format("   ⏭ SKIP %d", skippedCount)
    end
    colorPrint(belowCount > 0 and colors.yellow or colors.green, summary)

    return needsCraftingList
end

function findCraftable(itemName)
    ensureCraftablesCache()
    
    local craftable = craftablesCache[itemName]
    if craftable then
        local itemStack = craftable.getStack()
        return craftable, itemStack
    end
    
    return nil, nil
end


function startCraft(itemName, amount, currentCycle)    
    local craftable = findCraftable(itemName)
    if not craftable then
        return nil, "Item not craftable: " .. itemName
    end
    
    local requestTracker, requestError = craftable.request(amount)

    if not requestTracker then
        return nil, "Craft request rejected: " .. tostring(requestError)
    end

    -- Wait for AE2 to finish planning so a failure is reported against the item
    -- that caused it. Without this the job may still be submitted after we gave
    -- up on it, leaving an untracked craft running in the network.
    local waited = 0
    while trackerComputing(requestTracker) and waited < cfg.craftRequestTimeout do
        os.sleep(0.25)
        waited = waited + 0.25
    end

    -- Raw reason: only the caller knows the cycle context needed to explain it
    local failed, reason = trackerFailed(requestTracker)
    if failed then
        return nil, tostring(reason)
    end

    local craftId = 1
    while activeCrafts[craftId] do
        craftId = craftId + 1
    end
    
    activeCrafts[craftId] = {
        id = craftId,
        itemName = itemName,
        amount = amount,
        tracker = requestTracker,
        startCycle = currentCycle
    }
    if craftDelay > 0 then os.sleep(craftDelay)
    end
    return craftId
end

function isItemCurrentlyBeingCrafted(itemName)
    for craftId, craft in pairs(activeCrafts) do
        if craft.itemName == itemName then
            return true, craftId
        end
    end
    return false
end

-- Refused requests tolerated in one cycle before the rest is deferred
local REFUSAL_ABORT_LIMIT = 3

function autoCraftNeededItems(currentCycle)
    local needsList = checkAllThresholds()
    
    if #needsList == 0 then
        colorPrint(colors.green, "✅ All configured items are above their thresholds!")
        return {}
    end
    
    colorPrint(colors.yellow, string.format("\n🚀 Auto-crafting %d items below threshold:", #needsList))
    colorPrint(colors.yellow, string.rep("=", 75))
    
    local craftIds = {}
    local skippedCount = 0
    local failedCount = 0
    local deferredCount = 0
    local refusals = 0

    -- 0 = unlimited concurrent crafts
    local maxConcurrent = cfg.maxConcurrentCrafts or 8
    local activeCount = countActiveCrafts()
    local cpuInfo = getCraftingCpuInfo()

    -- Budget of NEW jobs for this cycle, from the config limit alone. The CPU
    -- readout below is printed for information but must NOT cap this: whether
    -- AE2 will place a job is AE2's answer to give, and a wrong busy flag here
    -- would otherwise stop all crafting. Surplus requests are not spammed
    -- either - refusals are bounded per cycle, see REFUSAL_ABORT_LIMIT.
    local budget = math.huge
    if maxConcurrent > 0 then
        budget = math.max(0, maxConcurrent - activeCount)
        colorPrint(colors.cyan, string.format("🎚 Craft slots: %d/%d in use", activeCount, maxConcurrent))
    end
    if cpuInfo and cpuInfo.total > 0 then
        colorPrint(colors.cyan, string.format("🖥 AE2 crafting CPUs: %d idle / %d total (largest idle: %d bytes)",
            cpuInfo.free, cpuInfo.total, cpuInfo.maxFreeStorage))
    end

    if cfg.shuffle then
        colorPrint(colors.magenta, "🔀 Shuffling craft order...")
        for i = #needsList, 2, -1 do
            local j = math.random(i)
            needsList[i], needsList[j] = needsList[j], needsList[i]
        end
    end

    for i, item in ipairs(needsList) do
        local alreadyCrafting, craftId = isItemCurrentlyBeingCrafted(item.label)

        if not alreadyCrafting and budget <= 0 then
            deferredCount = #needsList - i + 1
            colorPrint(colors.magenta, string.format(
                "⏸ craft slot limit (%d/%d tracked jobs) → deferring %d item(s) to next cycle",
                activeCount + #craftIds, maxConcurrent, deferredCount))
            break
        end

        colorPrint(colors.white, string.format("[%d/%d] Requesting craft: %4dx %s...", i, #needsList, item.batchSize, item.label))

        if alreadyCrafting then
            colorPrint(colors.cyan, string.format("  ⏭ SKIPPED → Already crafting #%d", craftId))
            skippedCount = skippedCount + 1
        else
            local craftId, errorMsg = startCraft(item.label, item.batchSize, currentCycle)
            if craftId then
                colorPrint(colors.green, string.format("  ✅ SUCCESS → Craft #%d started", craftId))
                table.insert(craftIds, craftId)
                budget = budget - 1
            else
                colorPrint(colors.red, string.format("  ❌ FAILED → %s", describeCraftFailure(errorMsg, #craftIds)))
                failedCount = failedCount + 1

                -- "no CPU would take this job" and "this item is missing an
                -- ingredient" arrive as the same message, so a single refusal
                -- proves nothing. Keep going, and stop once the refusals
                -- themselves say the network is not taking work: two in a row
                -- with nothing accepted, or REFUSAL_ABORT_LIMIT in total. That
                -- bounds the error spam without letting one unbuildable item
                -- starve the rest of the list.
                if isCraftRefusal(errorMsg) then
                    refusals = refusals + 1

                    local nothingAccepted = #craftIds == 0 and refusals >= 2
                    if nothingAccepted or refusals >= REFUSAL_ABORT_LIMIT then
                        deferredCount = #needsList - i
                        if deferredCount > 0 then
                            local why = nothingAccepted
                                and string.format("AE2 accepted nothing this cycle (%d refusals)", refusals)
                                or string.format("%d refused requests this cycle", refusals)
                            colorPrint(colors.magenta, string.format(
                                "⏸ %s → deferring %d item(s) to next cycle", why, deferredCount))
                        end
                        break
                    end
                end
            end
        end
    end
    
    print(string.format("\n✅ SUMMARY: Started %d craft requests, skipped %d already in progress, %d deferred, %d failed",
        #craftIds, skippedCount, deferredCount, failedCount))
    return craftIds
end

function cleanupTimedOutCrafts(currentCycle)
    local timedOutCount = 0
    
    for craftId, craft in pairs(activeCrafts) do
        local cyclesElapsed = currentCycle - craft.startCycle
        
        if cyclesElapsed > cfg.requestTimeoutCycles then
            local state = trackerState(craft.tracker)

            -- Check if craft is already done/cancelled/failed before timing out
            if state == "COMPLETED" or state == "CANCELED" or state == "FAILED" then
                -- Just clean it up silently, it is no longer running
                activeCrafts[craftId] = nil
            else
                -- Try to cancel timed out craft through the CPU running it
                local success, result = cancelCraftByItem(craft.itemName)

                if success then
                    colorPrint(colors.yellow, string.format("⏰ Timed out craft #%d after %d cycles: %s", craftId, cyclesElapsed - 1, craft.itemName))
                else
                    colorPrint(colors.red, string.format("⏰ Failed to cancel timed out craft #%d (%s): %s", craftId, tostring(result), craft.itemName))
                end
                
                activeCrafts[craftId] = nil
                timedOutCount = timedOutCount + 1
            end
        end
    end
    
    return timedOutCount
end

function checkCraftStatus(craftId, currentCycle)
    local craft = activeCrafts[craftId]
    
    if not craft then
        colorPrint(colors.red, string.format("❌ Craft ID %d not found", craftId))
        return nil
    end
    
    local state, reason = trackerState(craft.tracker)
    local cyclesElapsed = currentCycle - craft.startCycle
    local line = string.format("Craft #%d (%-35s)", craftId, craft.itemName:sub(1,35))

    local status = {
        id = craftId,
        itemName = craft.itemName,
        amount = craft.amount,
        status = state,
        reason = reason,
        isDone = state == "COMPLETED",
        isCanceled = state == "CANCELED",
        startCycle = craft.startCycle,
        cyclesElapsed = cyclesElapsed
    }

    if state == "COMPLETED" then
        colorPrint(colors.green, "✅ " .. line .. " COMPLETED")
    elseif state == "CANCELED" then
        colorPrint(colors.red, "❌ " .. line .. " CANCELED")
    elseif state == "FAILED" then
        colorPrint(colors.red, "💥 " .. line .. " FAILED: " .. describeCraftFailure(reason))
    elseif state == "COMPUTING" then
        colorPrint(colors.yellow, "🧮 " .. line .. " AE2 STILL PLANNING")
    else
        colorPrint(colors.yellow, string.format("⏳ %s IN PROGRESS (%d/%d cycles)", line, cyclesElapsed, cfg.requestTimeoutCycles))
    end

    return status
end

function checkActiveCrafts(currentCycle)
    local count = countActiveCrafts()

    if count == 0 then
        colorPrint(colors.cyan, "📭 No active crafts to monitor")
        return {}
    end
    
    colorPrint(colors.cyan, string.format("📊 Checking %d active craft(s):", count))
    colorPrint(colors.cyan, string.rep("=", 50))
    
    local statuses = {}
    
    for craftId, craft in pairs(activeCrafts) do
        local status = checkCraftStatus(craftId, currentCycle)
        table.insert(statuses, status)
    end
    
    return statuses
end

function cleanupCompletedCrafts()
    local cleaned = 0
    local failed = 0

    for craftId, craft in pairs(activeCrafts) do
        local state, reason = trackerState(craft.tracker)

        if state == "FAILED" then
            -- A job can still fail after it was requested; drop it so it stops
            -- occupying a craft slot
            colorPrint(colors.red, string.format("💥 Craft #%d (%s) failed: %s",
                craftId, craft.itemName, describeCraftFailure(reason)))
            activeCrafts[craftId] = nil
            failed = failed + 1
        elseif state == "COMPLETED" or state == "CANCELED" then
            activeCrafts[craftId] = nil
            cleaned = cleaned + 1
        end
    end

    if cleaned > 0 then
        colorPrint(colors.yellow, string.format("🧹 Cleaned up %d completed craft(s)", cleaned))
    end

    return cleaned + failed
end

function cancelAllActiveCrafts()
    local canceledCount = 0
    local failedCount = 0
    
    colorPrint(colors.yellow, "Canceling all active crafts...")
    
    for craftId, craft in pairs(activeCrafts) do
        local state = trackerState(craft.tracker)

        if state == "IN_PROGRESS" or state == "COMPUTING" then
            local success, result = cancelCraftByItem(craft.itemName)

            if success then
                colorPrint(colors.yellow, string.format("  ⏹  Canceled craft #%d: %s", craftId, craft.itemName))
                canceledCount = canceledCount + 1
            else
                colorPrint(colors.red, string.format("  ❌ Failed to cancel craft #%d (%s): %s", craftId, tostring(result), craft.itemName))
                failedCount = failedCount + 1
            end
        end
    end
    

    activeCrafts = {}
    
    if canceledCount > 0 or failedCount > 0 then
        colorPrint(colors.cyan, string.format("📊 Cancellation summary: %d canceled, %d failed", canceledCount, failedCount))
    else
        colorPrint(colors.cyan, "📭 No active crafts to cancel")
    end
    
    return canceledCount, failedCount
end


if not package.loaded["ae2_helpers"] then
    colorPrint(colors.magenta, "\n📚 AE2 Helpers Library Loaded")
end
