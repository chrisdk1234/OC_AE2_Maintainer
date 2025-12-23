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
    resolution = config.resolution or { maxWidth = 120, maxHeight = 35 },
    items = config.items or {}
    stealth = confing.stealth or false
}


if not package.loaded["ae2_helpers"] then
    colorPrint(colors.cyan, "📋 Loaded configuration:")
    colorPrint(colors.cyan, "   Sleep Interval: " .. cfg.sleepInterval .. "s")
    colorPrint(colors.cyan, "   Shuffle Items: " .. tostring(cfg.shuffle))
    colorPrint(colors.cyan, "   Timeout Cycles: " .. cfg.requestTimeoutCycles)
    colorPrint(colors.cyan, "   Resolution: " .. cfg.resolution.maxWidth .. "x" .. cfg.resolution.maxHeight)
    colorPrint(colors.cyan, "   Configured Items: " .. #cfg.items)
end

-- Active craft requests tracking
activeCrafts = {}


function reloadConfig()
    package.loaded.config = nil  -- Clear cache
    config = require("config")
    cfg.sleepInterval = config.sleepInterval or 60
    cfg.shuffle = config.shuffle or false
    cfg.requestTimeoutCycles = config.requestTimeoutCycles or 3
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
    
    colorPrint(colors.cyan, "🔍 Checking configured item thresholds:")
    colorPrint(colors.cyan, string.rep("=", 75))
    
    for i, entry in ipairs(cfg.items) do
        local label, threshold, batchSize = entry[1], entry[2], entry[3]
        
        if not batchSize or batchSize == 0 then
            -- Skip items with no batch size
            local line = string.format("%-45s %9s / %9s", label:sub(1,45), "---", "---")
            colorPrint(colors.cyan, line .. " >> SKIP (no batch size)")
        elseif not threshold or threshold == 0 then
            -- Handle infinite crafting (threshold = 0 or nil)
            local line = string.format("%-45s %9s / %9s", label:sub(1,45), "---", "∞")
            colorPrint(colors.blue, line .. " 🔄 INFINITE")
            
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
            
            local line = string.format("%-45s %9d / %9d", label:sub(1,45), current, threshold)
            if needs then
                print(line .. colors.red .. " ❌ BELOW" .. colors.reset)
            else
                print(line .. colors.green .. " ✅ OK" .. colors.reset)
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
    
    return needsCraftingList
end

function findCraftable(itemName)
    ensureCraftablesCache()
    
    local craftable = craftablesCache[itemName]
    if craftable then
        local itemStack = craftable.getItemStack()
        return craftable, itemStack
    end
    
    return nil, nil
end


function startCraft(itemName, amount, currentCycle)    
    local craftable = findCraftable(itemName)
    if not craftable then
        return nil, "Item not craftable: " .. itemName
    end
    
    local requestTracker = craftable.request(amount)
    
    if not requestTracker then
        return nil, "Craft failed to start (no tracker)"
    end
    
    local isDone, msg = requestTracker.isDone()
   
    if isDone == nil or msg ~= nil then
        return nil, "Craft failed: " .. tostring(msg)
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
    

    if cfg.shuffle then
        colorPrint(colors.magenta, "🔀 Shuffling craft order...")
        for i = #needsList, 2, -1 do
            local j = math.random(i)
            needsList[i], needsList[j] = needsList[j], needsList[i]
        end
    end
    
    for i, item in ipairs(needsList) do
        local alreadyCrafting, craftId = isItemCurrentlyBeingCrafted(item.label)
        
        colorPrint(colors.white, string.format("[%d/%d] Requesting craft: %4dx %s...", i, #needsList, item.batchSize, item.label))
        
        if alreadyCrafting then
            colorPrint(colors.cyan, string.format("  ⏭ SKIPPED → Already crafting #%d", craftId))
            skippedCount = skippedCount + 1
        else
            local craftId, errorMsg = startCraft(item.label, item.batchSize, currentCycle)
            if craftId then
                colorPrint(colors.green, string.format("  ✅ SUCCESS → Craft #%d started", craftId))
                table.insert(craftIds, craftId)
            else
                colorPrint(colors.red, string.format("  ❌ FAILED → %s", errorMsg))
                failedCount = failedCount + 1
            end
        end
    end
    
    print(string.format("\n✅ SUMMARY: Started %d craft requests, skipped %d already in progress, %d failed", 
        #craftIds, skippedCount, failedCount))
    return craftIds
end

function cleanupTimedOutCrafts(currentCycle)
    local timedOutCount = 0
    
    for craftId, craft in pairs(activeCrafts) do
        local cyclesElapsed = currentCycle - craft.startCycle
        
        if cyclesElapsed > cfg.requestTimeoutCycles then
            local tracker = craft.tracker
            
            -- Check if craft is already done/cancelled before timing out
            if tracker.isDone() or tracker.isCanceled() then
                -- Just clean it up silently, it's already finished
                activeCrafts[craftId] = nil
            else
                -- Try to cancel timed out craft
                local success, result = pcall(function() return tracker.cancel() end)
                
                if success and result then
                    colorPrint(colors.yellow, string.format("⏰ Timed out craft #%d after %d cycles: %s", craftId, cyclesElapsed - 1, craft.itemName))
                else
                    colorPrint(colors.red, string.format("⏰ Failed to cancel timed out craft #%d: %s", craftId, craft.itemName))
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
    
    local tracker = craft.tracker
    local isDone = tracker.isDone()
    local isCanceled = tracker.isCanceled()
    local cyclesElapsed = currentCycle - craft.startCycle
    
    local status = {
        id = craftId,
        itemName = craft.itemName,
        amount = craft.amount,
        isDone = isDone,
        isCanceled = isCanceled,
        startCycle = craft.startCycle,
        cyclesElapsed = cyclesElapsed
    }
    
    if isDone then
        status.status = "COMPLETED"
        local line = string.format("Craft #%d (%-35s)", craftId, craft.itemName:sub(1,35))
        colorPrint(colors.green, "✅ " .. line .. " COMPLETED")
    elseif isCanceled then
        status.status = "CANCELED"
        local line = string.format("Craft #%d (%-35s)", craftId, craft.itemName:sub(1,35))
        colorPrint(colors.red, "❌ " .. line .. " CANCELED")
    else
        status.status = "IN_PROGRESS"
        local line = string.format("Craft #%d (%-35s)", craftId, craft.itemName:sub(1,35))
        colorPrint(colors.yellow, string.format("⏳ %s IN PROGRESS (%d/%d cycles)", line, cyclesElapsed, cfg.requestTimeoutCycles))
    end
    
    return status
end

function checkActiveCrafts(currentCycle)    
    local count = 0
    for _ in pairs(activeCrafts) do
        count = count + 1
    end
    
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
    
    for craftId, craft in pairs(activeCrafts) do
        local tracker = craft.tracker
        if tracker.isDone() or tracker.isCanceled() then
            activeCrafts[craftId] = nil
            cleaned = cleaned + 1
        end
    end
    
    if cleaned > 0 then
        colorPrint(colors.yellow, string.format("🧹 Cleaned up %d completed craft(s)", cleaned))
    end
    
    return cleaned
end

function cancelAllActiveCrafts()
    local canceledCount = 0
    local failedCount = 0
    
    colorPrint(colors.yellow, "Canceling all active crafts...")
    
    for craftId, craft in pairs(activeCrafts) do
        local tracker = craft.tracker
        

        if not tracker.isDone() and not tracker.isCanceled() then
            local success, result = pcall(function() return tracker.cancel() end)
            
            if success and result then
                colorPrint(colors.yellow, string.format("  ⏹  Canceled craft #%d: %s", craftId, craft.itemName))
                canceledCount = canceledCount + 1
            else
                colorPrint(colors.red, string.format("  ❌ Failed to cancel craft #%d (error: %s): %s", craftId, tostring(result), craft.itemName))
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
