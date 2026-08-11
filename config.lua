-- config.lua (hand-tuned for OC_AE2_Maintainer)
-- sleepInterval in seconds; shuffle: randomize craft order
-- requestTimeoutCycles: max cycles before timing out crafts
-- resolution: terminal size limits (maxWidth, maxHeight)
-- items: { { label, threshold, batchSize }, … }
--
-- NOTE: with sleepInterval = 900 (15 min) and requestTimeoutCycles = 3,
-- a stuck craft is only considered timed out after ~45 min. Bump
-- requestTimeoutCycles up if your longest crafts (e.g. Assembly Line /
-- Quantum stuff) regularly run longer than that.
--
-- NOTE: "X stacks" comments assumed a stack size of 64 (no NBT on these
-- items pre-placement, so should be the normal default) - double check
-- in-game if any of these look off.

return {
  sleepInterval = 900,
  shuffle = true,
  requestTimeoutCycles = 1000,
  maxConcurrentCrafts = 8,   -- Concurrent craft job limit (0 = unlimited)
  craftRequestTimeout = 5,   -- Seconds to wait for AE2 to plan a job before moving on
  compactStatus = true,      -- true = one OK/BELOW summary line, false = one line per item
  skipKey = "r",             -- Press this key to skip the wait
  resolution = {
    maxWidth = 120,
    maxHeight = 35
  },
  items = {

    -- === Circuits: ULV-HV (any circuit only) ===
    { "Any ULV Circuit", 256, 64 },
    { "Any LV Circuit",  256, 64 },
    { "Any MV Circuit",  256, 64 },
    { "Any HV Circuit",  256, 64 },

    -- === Circuits: EV and above (any circuit) ===
    -- "Quantum Circuit" still not found anywhere in your 871 craftables -
    -- add a line once you have the exact label.
    { "Any EV Circuit",  128, 32 },
    { "Any IV Circuit",  128, 32 },
    { "Any LuV Circuit", 128, 32 },
    { "Any ZPM Circuit", 128, 32 },

    -- === Advanced (EBF) ingots — 1000 threshold / 200 batch, all 20 ===
    { "Hastelloy-X Ingot",              1000, 200 },
    { "Palladium Ingot",                1000, 200 },
    { "Energetic Alloy Ingot",          1000, 200 },
    { "Hastelloy-W Ingot",              1000, 200 },
    { "Bronze Ingot",                   1000, 200 },
    { "Zircaloy-4 Ingot",               1000, 200 },
    { "Tungstensteel Ingot",            1000, 200 },
    { "Hastelloy-N Ingot",              1000, 200 },
    { "Maraging Steel 300 Ingot",       1000, 200 },
    { "Watertight Steel Ingot",         1000, 200 },
    { "Rhodium-Plated Palladium Ingot", 1000, 200 },
    { "Tantalum Ingot",                 1000, 200 },
    { "Kanthal Ingot",                  1000, 200 },
    { "Maraging Steel 250 Ingot",       1000, 200 },
    { "Inconel-625 Ingot",              1000, 200 },
    { "Soldering Alloy Ingot",          1000, 200 },
    { "Vibrant Alloy Ingot",            1000, 200 },
    { "Vanadium-Gallium Ingot",         1000, 200 },
    { "TPV-Alloy Ingot",                1000, 200 },
    { "HSS-G Ingot",                    1000, 200 },
    -- candidates NOT included (no matching "Molten X" pattern found,
    -- so EBF requirement unconfirmed from your data - add manually if needed):
    -- Chrome Ingot, Osmiridium Ingot, Staballoy Ingot

    -- === Superconductor wires (real, not "Base") — 2000 / 200, all 3 ===
    { "1x Superconductor HV Wire", 2000, 200 },
    { "1x Superconductor EV Wire", 2000, 200 },
    { "1x Superconductor IV Wire", 2000, 200 },

    -- === SMD components — 1000 / 400, all 5 ===
    { "SMD Resistor",   1000, 400 },
    { "SMD Capacitor",  1000, 400 },
    { "SMD Inductor",   1000, 400 },
    { "SMD Diode",      1000, 400 },
    { "SMD Transistor", 1000, 400 },

    -- === AE2 components ===
    -- Interface, Dual Interface & 3 of the cards: 2 stacks / 32 batch
    { "ME Interface",            128, 32 },
    { "ME Dual Interface",       128, 32 },
    { "Pattern Capacity Card",   128, 32 },
    { "Acceleration Card",       128, 32 },
    -- Equal Distribution Card: only one stack (batch picked at 1/4 stack - adjust if you want tighter)
    { "Equal Distribution Card", 64,  16 },
    { "Sticky Card",             128, 32 },
    -- Fluix crystals/seeds/pearls left as originally set (no note given)
    { "Fluix Crystal",      64, 16 },
    { "Pure Fluix Crystal", 64, 16 },
    { "Fluix Seed",         16, 4 },
    { "Fluix Pearl",        16, 4 },

    -- === Processors ===
    -- Central Processing Unit / Nano Processor / Quantum Processor removed per your edit
    { "Integrated Processor",  320, 64 }, -- 5 stacks / 1 stack batch
    { "Engineering Processor", 8,   2 },
    { "Logic Processor",       8,   2 },
    { "Calculation Processor", 8,   2 },

    -- === AE2 cables (fluix + dense) — 5 stacks / 1 stack batch ===
    { "ME Covered Cable - Fluix",       320, 64 },
    { "ME Dense Covered Cable - Fluix", 320, 64 },

    -- Multiblock hatches/busses section removed per your edit

  },
}