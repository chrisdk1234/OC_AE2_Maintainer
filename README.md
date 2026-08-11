<img width="1485" height="879" alt="image" src="https://github.com/user-attachments/assets/d585584f-ca4d-4fba-805a-6c51d3cd0123" />



HUGE shoutout to [@Yunis](https://github.com/ynsrkn) for contributing his improved gui and maintainer functionality to this repo.


Basic knowledge of the mod is assumed

download by using: (press INSERT on your keyboard to paste it into the OC terminal)
```
wget https://raw.githubusercontent.com/chrisdk1234/OC_AE2_Maintainer/main/config.lua && wget https://raw.githubusercontent.com/chrisdk1234/OC_AE2_Maintainer/main/level_maintainer.lua && wget https://raw.githubusercontent.com/chrisdk1234/OC_AE2_Maintainer/main/craftables.lua && wget https://raw.githubusercontent.com/chrisdk1234/OC_AE2_Maintainer/main/ae2_helpers.lua && wget https://raw.githubusercontent.com/chrisdk1234/OC_AE2_Maintainer/main/diagnose.lua
```

HOW TO USE:

craftables : shows all availible crafts in the AE2 system and gives the option to generate / refresh a config.lua file with all crafts in it with (threshold = defaultThreshold, batchSize = defaultBatchSize).
default values can be edited inside the file itself with .\edit craftables.lua

config : contains an array of all maintained items with the form {"item label", threhsold, batchsize}, sleeptimer that dictates how long the program waits until it does another parse, and a shuffle mode used to enable shuffling of the items choosed for crafting, usefull for ensuring even filling of buffers and for infinite crafting

config options:

- sleepInterval : seconds to wait between cycles
- shuffle : randomize craft order
- requestTimeoutCycles : cycles before an unfinished craft gets cancelled
- maxConcurrentCrafts : never run more than this many crafting jobs at once (default 8, set 0 for unlimited). The program additionally never requests more jobs than there are idle AE2 crafting CPUs, since every job needs one. Items that do not fit are deferred to the next cycle
- craftRequestTimeout : seconds to wait for AE2 to finish planning a job before moving on (default 5). AE2 plans asynchronously, so this is what lets a failure be reported against the item that caused it
- compactStatus : true (default) prints one line per cycle, e.g. `✅ OK 55/62   ❌ BELOW 5/62   🔄 INFINITE 2`, instead of one line per maintained item. Set false for the full per-item table
- skipKey : press this key during the sleep phase to skip the remaining wait and start the next cycle immediately (default "r"). Single characters ("r", "n") or key names from OpenComputers keyboard.keys ("space", "enter") both work
- resolution : terminal size limits (maxWidth, maxHeight)

level_maintainer : executes the program with mentioned settings, will run forever and print out various info to the terminal.

diagnose : run this when crafts fail. Lists your crafting CPUs (size, co-processors, busy), flags config labels that match no craft pattern or several, and can fire a single test request and print AE2's real verdict.

TROUBLESHOOTING "request failed (missing resources?)":

That AE2 message does not only mean missing items. AE2 returns it whenever it cannot hand the job to a crafting CPU, which happens when:

- no crafting CPU is idle, or none is large enough to hold the job (a big batchSize needs many bytes) -> lower batchSize, add crafting storage, or lower maxConcurrentCrafts
- the CPU is set to accept player requests only. This program requests as a machine, so those CPUs are skipped even though your manual request works. Check the crafting mode on each CPU / crafting monitor
- an ingredient really is missing

Run `diagnose` to see which of the three it is.

Since AE2 uses the same message for all three, the maintainer treats the first such failure like running out of craft slots: it prints the error once and defers the remaining items to the next cycle instead of repeating it for every item. Keep `shuffle = true` so a single item with a genuinely missing ingredient cannot block the rest of the list every cycle.

IMPORTANT:

THE PROGRAM NEEDS AN INTERFACE OR A MECONTROLLER CONNECTED TO AN OC ADAPTER BLOCK.

No need to reboot the oc-computer after updating config.lua anymore

ingame computers parts used (lower quality might work but not guaranteed):
- GPU tier 3
- Internet Card (NEEDED TO DOWNLOAD FROM GITHUB)
- CPU tier 3
- Memory tier 3.5
- Hard Disk Drive tier 2
- EEPROM with Lua BIOS (craft it ingame)
- OpenOS floppy (craft it ingame)

