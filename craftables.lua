-- craftables.lua

local component = require("component")
local fs        = require("filesystem")

-------------------------------------------------------------------------------
-- 1) Locate ME component
-------------------------------------------------------------------------------
local ctrlAddr = component.list("me_controller")()
local intfAddr = component.list("me_interface")()
local addr     = ctrlAddr or intfAddr
               or error("No AE2 ME controller or interface found")
local ME = component.proxy(addr)

-- Pick the right method
local craftsFetcher
if     ME.getCraftables     then craftsFetcher = ME.getCraftables
elseif ME.getAvailableItems then craftsFetcher = ME.getAvailableItems
else   error("ME proxy has no getCraftables/getAvailableItems") end

-------------------------------------------------------------------------------
-- 2) Config-generation settings
-------------------------------------------------------------------------------

local cfg_path         = "./config.lua"
local defaultThreshold = 512
local defaultBatchSize = 64

local function generateConfig()
  local crafts = craftsFetcher()
  local seen   = {}
  local list   = {}

  -- 1) collect unique labels into a flat list
  for _, pattern in ipairs(crafts) do
    local label = pattern.getStack().label
    if not seen[label] then
      seen[label] = true
      table.insert(list, { label, defaultThreshold, defaultBatchSize })
    end
  end

  -- 2) sort so output is always in the same order
  table.sort(list, function(a, b)
    return a[1] < b[1]
  end)

  -- 3) write out the config file
  local out = assert(io.open(cfg_path, "w"))

  -- header
  out:write([[
-- config.lua  (auto-generated)
-- sleepInterval in seconds; 
-- shuffle: randomize craft order  
-- requestTimeoutCycles: max cycles before timing out crafts
-- maxConcurrentCrafts: max crafting jobs running at once (0 = unlimited)
-- craftRequestTimeout: seconds to wait for AE2 to plan a job
-- compactStatus: true = one summary line per cycle instead of one line per item
-- skipKey: key to press to skip the remaining sleep time
-- resolution: terminal size limits (maxWidth, maxHeight)
-- items: { { label, threshold, batchSize }, … }

return {
  sleepInterval = 60,
  shuffle = true,
  requestTimeoutCycles = 3,
  maxConcurrentCrafts = 8,
  craftRequestTimeout = 5,
  compactStatus = true,
  skipKey = "r",
  resolution = {
    maxWidth = 120,
    maxHeight = 35
  },
  items = { 
]])

  -- body
  for _, entry in ipairs(list) do
    local lab, thr, bs = entry[1], entry[2], entry[3]
    out:write(string.format(
      "    { %q, %d, %d },\n",
      lab, thr, bs
    ))
  end

  -- footer
  out:write([[
  },
}
]])
  out:close()

  print(("✔ Wrote %d items to %s"):format(#list, cfg_path))
end

-- Print available crafts
local crafts = craftsFetcher()
print("Available crafts:")
for _, pattern in ipairs(crafts) do
  local label = pattern.getStack().label
  print("- " .. label)
end
print(("::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::"))

-- 3) Prompt the user & maybe generate
io.write("Generate and REFRESH config.lua? [y/N] ")
local ans = io.read():lower():sub(1,1)
if ans == "y" then
  generateConfig()
end