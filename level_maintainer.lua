local event = require("event")
local term = require("term")
local component = require("component")
local computer = require("computer")
local keyboard = require("keyboard")

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

-- true when the pressed key matches cfg.skipKey (single char like "r", or a
-- keyboard.keys name like "space")
local function isSkipKey(char, code)
    local want = tostring(cfg.skipKey or "r"):lower()

    if char and char > 0 and char < 256 and string.char(char):lower() == want then
        return true
    end

    return keyboard.keys[want] ~= nil and code == keyboard.keys[want]
end

-- Sleeps up to sleepTime seconds; returns true if the wait was skipped by key
local function sleepUntilNextCycle(sleepTime)
    local deadline = computer.uptime() + sleepTime

    while running do
        local remaining = deadline - computer.uptime()
        if remaining <= 0 then
            return false
        end

        -- 1s slices keep the interrupt handler responsive
        local name, _, char, code = event.pull(math.min(1, remaining), "key_down")
        if name == "key_down" and isSkipKey(char, code) then
            return true
        end
    end

    return false
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
        local activeCraftCount = countActiveCrafts()

        if activeCraftCount > 0 then
            print("📊 " .. activeCraftCount .. " active crafts in progress...")
            checkActiveCrafts(cycles)
        end
        
        print("")
        autoCraftNeededItems(cycles)
        
        local sleepTime = cfg.sleepInterval
        print(string.format("\n🛌 Sleeping for %d seconds... (press %s to skip, Ctrl+C to stop)",
            sleepTime, tostring(cfg.skipKey):upper()))

        if sleepUntilNextCycle(sleepTime) then
            colorPrint(colors.magenta, "⏩ Wait skipped, starting next cycle")
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
    local finalActiveCrafts = countActiveCrafts()

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
