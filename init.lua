-- Hammerspoon Main Config
-- This file loads all your automation scripts

-- Smart Cursor Jump - Move cursor intelligently between misaligned displays
require("smart-cursor-jump")

-- Smart Fill Screen - Auto-maximize windows when moved to a different display
require("smart-fill-screen")

-- Add more scripts below as you create them:
-- require("window-management")
-- require("hotkeys")
-- require("clipboard-history")

-- Notify that Hammerspoon has loaded
hs.notify.new({
    title="Hammerspoon", 
    informativeText="Config loaded successfully"
}):send()

print("Hammerspoon loaded - all scripts active")
