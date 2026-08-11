-- diagnose.lua
--
-- Explains "request failed (missing resources?)". That AE2 message means
-- submitJob() returned no crafting link, which happens for THREE different
-- reasons, only one of which is actually about resources:
--   1) no idle crafting CPU, or none with enough bytes for the batch
--   2) the CPU only accepts player requests (this program is a machine)
--   3) an ingredient really is missing
-- This script prints the facts needed to tell them apart.

require("ae2_helpers")

-------------------------------------------------------------------------------
-- 1) Crafting CPUs
-------------------------------------------------------------------------------
local function cpuReport()
    colorPrint(colors.white, "🖥 CRAFTING CPUs")
    colorPrint(colors.cyan, string.rep("=", 62))

    local info = getCraftingCpuInfo()
    if not info then
        colorPrint(colors.red, "   ME proxy has no getCpus() - cannot inspect CPUs")
        return nil
    end

    if info.total == 0 then
        colorPrint(colors.red, "   No crafting CPUs in this network. Every request will fail.")
        return info
    end

    local index = 0
    for _, cpu in pairs(info.list) do
        index = index + 1
        local name = cpu.name
        if name == nil or name == "" then name = "(unnamed)" end

        local busy = isCpuBusy(cpu)
        local busyText = busy and "BUSY" or "idle"
        if type(cpu.busy) ~= "boolean" then
            -- Worth seeing: a non-boolean flag is why the CPU readout can lie
            busyText = string.format("%s (busy flag is %s: %s)", busyText, type(cpu.busy), tostring(cpu.busy))
        end

        local line = string.format("   [%d] %-20s %8d bytes  %2d co-proc  %s",
            index, name:sub(1, 20), tonumber(cpu.storage) or 0,
            tonumber(cpu.coprocessors) or 0, busyText)
        colorPrint(busy and colors.yellow or colors.green, line)
    end

    colorPrint(colors.cyan, string.format("   → %d idle / %d total, largest idle CPU: %d bytes",
        info.free, info.total, info.maxFreeStorage))
    colorPrint(colors.cyan, string.format("   → maxConcurrentCrafts = %d caps tracked jobs; this CPU list is only",
        cfg.maxConcurrentCrafts))
    colorPrint(colors.cyan, "     informational and never blocks a request on its own")

    if info.free == 0 then
        colorPrint(colors.yellow, "   ⚠ No CPU reports itself idle - either they are all busy, or this OC")
        colorPrint(colors.yellow, "     build reports the busy flag in a form that cannot be read")
    end
    colorPrint(colors.yellow, "   ⚠ A CPU whose crafting mode is 'player only' is invisible to this")
    colorPrint(colors.yellow, "     program (requests arrive as a machine, not as you). Check the")
    colorPrint(colors.yellow, "     crafting monitor of each CPU if manual requests work but these do not.")

    return info
end

-------------------------------------------------------------------------------
-- 2) Configured items vs the network
-------------------------------------------------------------------------------
local function itemReport()
    colorPrint(colors.white, "\n📦 CONFIGURED ITEMS (only problems are listed)")
    colorPrint(colors.cyan, string.rep("=", 62))

    local missing, ambiguous, ok = 0, 0, 0

    for _, entry in ipairs(cfg.items) do
        local label, batchSize = entry[1], entry[3]
        local craftables = ME.getCraftables({ label = label })
        local count = (craftables and #craftables) or 0

        if count == 0 then
            missing = missing + 1
            colorPrint(colors.red, string.format("   ❌ %-45s no craft pattern with this exact label", label:sub(1, 45)))
        elseif count > 1 then
            ambiguous = ambiguous + 1
            colorPrint(colors.yellow, string.format("   ⚠ %-45s %d patterns share this label", label:sub(1, 45), count))
        else
            ok = ok + 1
        end

        -- A batch whose job tree does not fit into a CPU is a common cause of a
        -- failed (simulated) job
        if count > 0 and batchSize and batchSize > 1024 then
            colorPrint(colors.yellow, string.format("     ↳ batch %d is large; if this one fails, try a smaller batchSize", batchSize))
        end
    end

    colorPrint(colors.cyan, string.format("   → %d fine, %d ambiguous label(s), %d not craftable", ok, ambiguous, missing))
end

-------------------------------------------------------------------------------
-- 3) Live single request, with the real AE2 verdict
-------------------------------------------------------------------------------
local function testRequest(label, amount)
    local craftables = ME.getCraftables({ label = label })
    if not craftables or #craftables == 0 then
        colorPrint(colors.red, "   No craft pattern with that exact label")
        return
    end

    colorPrint(colors.white, string.format("   Requesting %dx %s ...", amount, label))
    local tracker, requestError = craftables[1].request(amount)
    if not tracker then
        colorPrint(colors.red, "   Request rejected: " .. tostring(requestError))
        return
    end

    -- AE2 plans on a worker thread; poll until it settles
    local waited = 0
    while tracker.isComputing and tracker.isComputing() and waited < 15 do
        os.sleep(0.5)
        waited = waited + 0.5
    end

    local state, reason = trackerState(tracker)
    if state == "FAILED" then
        colorPrint(colors.red, "   💥 " .. describeCraftFailure(reason))
        colorPrint(colors.cyan, "   Same amount works in the ME terminal? → cause 1 or 2 above, not a missing ingredient.")
    elseif state == "COMPUTING" then
        colorPrint(colors.yellow, string.format("   🧮 still planning after %.0fs - job tree is big, raise craftRequestTimeout", waited))
    else
        colorPrint(colors.green, "   ✅ Accepted by AE2 (state: " .. state .. ")")
        colorPrint(colors.cyan, "   A real job is now running; cancel it in the ME terminal if you do not want it.")
    end
end

-------------------------------------------------------------------------------

colorPrint(colors.white, "\n🔧 AE2 Maintainer Diagnostics")
colorPrint(colors.white, "=============================")

cpuReport()
itemReport()

colorPrint(colors.white, "\n🧪 LIVE TEST")
colorPrint(colors.cyan, string.rep("=", 62))
io.write("Item label to test-request (blank = skip): ")
local label = io.read()
if label and label ~= "" then
    io.write("Amount [1]: ")
    local amount = tonumber(io.read()) or 1
    testRequest(label, amount)
end

colorPrint(colors.white, "\nDone.")
