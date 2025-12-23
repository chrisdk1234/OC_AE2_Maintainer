-- config.lua  (auto-generated)  
-- sleepInterval: seconds between checks
-- shuffle: randomize craft order  
-- requestTimeoutCycles: max cycles before timing out crafts
-- resolution: terminal size limits (maxWidth, maxHeight)
-- items: { { label, threshold, batchSize }, … }

return {
  sleepInterval = 40,
  shuffle = true,
  stealth = false, -- silences a lot of print statements when true
  requestTimeoutCycles = 3,  -- Maximum cycles before timing out a craft
  resolution = {
    maxWidth = 120,   -- Maximum terminal width
    maxHeight = 35    -- Maximum terminal height  
  },
  items = {
    { "Bronze Ingot", 0, 64 },
    { "Crystaltine Dust", 0, 64 },
    { "Crystaltine Ingot", 0, 64 },
    { "Invar Ingot", 0, 64 },
  },
}