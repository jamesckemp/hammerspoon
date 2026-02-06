# Hammerspoon Config

My personal [Hammerspoon](https://www.hammerspoon.org/) configuration for macOS automation.

## Scripts

### Smart Cursor Jump

Intelligently moves the cursor between misaligned displays.

If your monitors have different heights or aren't perfectly aligned, macOS cursor transitions are frustrating - the cursor stops at edges where there's no adjacent display. This script detects when your cursor hits an edge and instantly warps it to the appropriate location on the adjacent display.

**Features:**
- Instant transitions using eventtap (no polling delay)
- Velocity-based targeting when multiple displays are adjacent
- Pre-computed jump zones for zero latency
- Works in background
- Auto-reconfigures on display changes

**Configuration** (in `smart-cursor-jump.lua`):
```lua
local EDGE_THRESHOLD = 5  -- Pixels from edge to trigger jump
local DEBUG = true        -- Enable console logging
```

### Smart Fill Screen

Automatically maximizes windows when moved to a different display.

When you drag a window from one monitor to another, it instantly fills the destination screen. Windows moved within the same display are unaffected.

**How it works:**
- Tracks each window's current screen using `hs.window.filter`
- On `windowMoved`, compares the window's screen against its last known screen
- If the screen changed, fills the window to the new screen's frame after a brief settle delay
- Cleans up tracking when windows are destroyed

**Configuration** (in `smart-fill-screen.lua`):
```lua
local DEBUG = true  -- Enable console logging
```

## Installation

1. Install [Hammerspoon](https://www.hammerspoon.org/)
2. Clone this repo:
   ```bash
   git clone git@github.com:jamesckemp/hammerspoon.git ~/.hammerspoon
   ```
3. Reload Hammerspoon
4. Grant Accessibility permissions when prompted

## License

MIT
