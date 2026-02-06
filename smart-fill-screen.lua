-- Smart Fill Screen
-- Automatically maximizes windows when moved to a different display
-- Tracks each window's screen and fills on cross-display moves

local DEBUG = true

-- Track each window's last known screen (keyed by window ID)
local windowScreens = {}

-- Seed the tracking table with a window's current screen
local function trackWindow(win)
    if not win or not win.id then return end
    local id = win:id()
    if id and id > 0 then
        local screen = win:screen()
        if screen then
            windowScreens[id] = screen:id()
        end
    end
end

-- Handle a window move: check if it changed screens
local function onWindowMoved(win)
    if not win or not win.id then return end
    local id = win:id()
    if not id or id <= 0 then return end

    local currentScreen = win:screen()
    if not currentScreen then return end

    local currentScreenId = currentScreen:id()
    local previousScreenId = windowScreens[id]

    -- Update tracking
    windowScreens[id] = currentScreenId

    -- If we have no previous record, this is the first move we've seen — just track it
    if not previousScreenId then return end

    -- If screen changed, fill the window after a short delay to let the move settle
    if currentScreenId ~= previousScreenId then
        if DEBUG then
            print(string.format("Smart Fill Screen: window '%s' moved to new display — filling",
                win:title() or "untitled"))
        end
        hs.timer.doAfter(0.1, function()
            -- Re-check the window is still valid and on the same screen
            if not win or not win:id() then return end
            local screen = win:screen()
            if not screen then return end
            win:setFrame(screen:frame())
            windowScreens[id] = screen:id()
        end)
    end
end

-- Clean up tracking on window destroy
local function onWindowDestroyed(win)
    if not win or not win.id then return end
    local id = win:id()
    if id then
        windowScreens[id] = nil
    end
end

-- Cleanup previous instance
if smartFillScreen then
    if smartFillScreen.filter then
        smartFillScreen.filter:unsubscribeAll()
    end
end

smartFillScreen = {
    filter = nil
}

-- Create window filter (all windows)
local wf = hs.window.filter.new()

-- Seed tracking for new/focused windows
wf:subscribe(hs.window.filter.windowCreated, trackWindow)
wf:subscribe(hs.window.filter.windowFocused, trackWindow)

-- Detect cross-screen moves
wf:subscribe(hs.window.filter.windowMoved, onWindowMoved)

-- Clean up on destroy
wf:subscribe(hs.window.filter.windowDestroyed, onWindowDestroyed)

smartFillScreen.filter = wf

-- Seed tracking for all existing windows
for _, win in ipairs(hs.window.allWindows()) do
    trackWindow(win)
end

-- Startup message
print("=====================================")
print("Smart Fill Screen loaded")
print(string.format("  Debug mode: %s", DEBUG and "ON" or "OFF"))
print(string.format("  Tracking %d existing windows", #hs.window.allWindows()))
print("  Windows will auto-fill when moved to a new display")
print("=====================================")
