local event = require("event")
local term = require("term")
local component = require("component")

require("ae2_helpers")

-------------------------------------------------------------------------------
-- Level Maintainer
-------------------------------------------------------------------------------

local running = true
local cycles = 0
local interruptReceived = false

local function onInterrupt()
    if not interruptReceived then
        interruptReceived = true
        colorPrint(colors.yellow, "\n✋Interrupt signal received, stopping maintainer")
        running = false
    end
end

local realPrint = print
local realcolorPrint = colorPrint

local function applySteath()
    if cfg and cfg.stealth then
        _G.print = function(...) end
        _G.colorPrint = function(...) end
    else
        _G.print = realPrint
        _G.colorPrint = realcolorPrint
    end
end


function startMaintainer()    
    cycles = 0
    running = true
    interruptReceived = false
    
    -- Main loop
    while running do
        cycles = cycles + 1
        
        term.clear()
        
        print(string.format("🔄 CYCLE #%d", cycles))
        print(string.rep("-", 50))
        
        -- Clean up any completed crafts from previous cycles
        cleanupCompletedCrafts()
        cleanupTimedOutCrafts(cycles)
        
        -- Check current active crafts
        local activeCraftCount = 0
        for _ in pairs(activeCrafts) do
            activeCraftCount = activeCraftCount + 1
        end
        
        if activeCraftCount > 0 then
            print("📊 " .. activeCraftCount .. " active crafts in progress...")
            checkActiveCrafts(cycles)
        end
        
        print("")
        autoCraftNeededItems(cycles)
        
        local sleepTime = cfg.sleepInterval
        print(string.format("\n🛌 Sleeping for %d seconds... (Ctrl+C to stop)", sleepTime))

        local elapsed = 0
        local SLEEP_CHUNK_SIZE = math.min(5.0, sleepTime / 8)  -- Sleep in ~8 chunks or 5s max
        while running and elapsed < sleepTime do
            local sleepChunk = math.min(SLEEP_CHUNK_SIZE, sleepTime - elapsed)
            os.sleep(sleepChunk)
            elapsed = elapsed + sleepChunk
        end
        
        if not running then
            break
        end
    end
    
    event.ignore("interrupted", onInterrupt)
    
    term.clear()
    
    print("🏁 Level Maintainer stopped")
    print("📊 Completed " .. cycles .. " monitoring cycles")
    
    -- Check for active crafts and cancel them
    local finalActiveCrafts = 0
    for _ in pairs(activeCrafts) do
        finalActiveCrafts = finalActiveCrafts + 1
    end
    
    if finalActiveCrafts > 0 then
        checkActiveCrafts(cycles)
        
        print("")
        local canceled, failed = cancelAllActiveCrafts()
        
        if canceled > 0 then
            colorPrint(colors.green, "\n✅ Successfully canceled " .. canceled .. " craft(s)")
        end
        if failed > 0 then
            colorPrint(colors.yellow, "⚠️  " .. failed .. " craft(s) could not be canceled (may have completed)")
        end
    else
        colorPrint(colors.green, "\n✅ No active crafts to cancel")
    end
    
    colorPrint(colors.cyan, "\n📋 Final Status:")
    colorPrint(colors.cyan, "---------------")
    checkAllThresholds()
end

colorPrint(colors.white, "\n🏭 Level Maintainer")
colorPrint(colors.white, "===================")

if not cfg then
    colorPrint(colors.red, "❌ Error: Configuration not loaded!")
    colorPrint(colors.red, "   Make sure config.lua exists and is readable")
    return
elseif not checkAllThresholds or not autoCraftNeededItems then
    colorPrint(colors.red, "❌ Error: AE2 Helpers library not properly loaded!")
    colorPrint(colors.red, "   Make sure ae2_helpers.lua is present and working")
    return
elseif not cfg.sleepInterval or not cfg.items then
    colorPrint(colors.red, "❌ Error: Configuration is incomplete!")
    colorPrint(colors.red, "   config.lua must have sleepInterval and items")
    return
end

if component.isAvailable("gpu") then
    local gpu = component.gpu
    local maxWidth, maxHeight = gpu.maxResolution()
    
    local targetWidth = math.min(cfg.resolution.maxWidth, maxWidth)
    local targetHeight = math.min(cfg.resolution.maxHeight, maxHeight)
    
    gpu.setResolution(targetWidth, targetHeight)
    term.clear()
    print(string.format("Set resolution to %dx%d (max: %dx%d)", targetWidth, targetHeight, maxWidth, maxHeight))
end


event.listen("interrupted", onInterrupt)

-- Reload config to ensure we have the latest settings
reloadConfig()

-- Preload craftables cache
ensureCraftablesCache()

-- Auto-start the maintainer
colorPrint(colors.green, "\n🚀 Starting maintainer in 3 seconds...")
os.sleep(3)
startMaintainer()
