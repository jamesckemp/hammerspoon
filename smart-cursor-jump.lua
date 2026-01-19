-- Smart Cursor Jump
-- Intelligently move cursor between misaligned displays
-- Pre-computes jump zones at init for instant edge transitions

-- Configuration
local EDGE_THRESHOLD = 5      -- Pixels from edge to trigger jump
local CHECK_INTERVAL = 0.02   -- How often to check cursor position (seconds)
local DEBUG = true            -- Enable verbose logging
local JUMP_COOLDOWN = 0.05    -- Tiny cooldown to prevent double-jumps (50ms)

-- Pre-computed data (populated at init)
local displays = {}
local jumpZones = {}  -- jumpZones[displayId][edge] = list of {yMin, yMax, targetDisplay, targetX/Y}

-- State tracking
local lastPosition = nil
local lastJumpTime = 0
local tickCount = 0
local velocity = {x = 0, y = 0}  -- Cursor velocity (instantaneous)

-- Get all display frames
local function getDisplays()
    local screens = hs.screen.allScreens()
    local result = {}

    for i, screen in ipairs(screens) do
        local frame = screen:frame()
        local display = {
            id = i,
            x = frame.x,
            y = frame.y,
            w = frame.w,
            h = frame.h,
            right = frame.x + frame.w,
            bottom = frame.y + frame.h,
            screen = screen
        }
        table.insert(result, display)
    end

    return result
end

-- Find which display contains a point
local function getCurrentDisplay(x, y)
    for _, display in ipairs(displays) do
        if x >= display.x and x < display.right and
           y >= display.y and y < display.bottom then
            return display
        end
    end

    -- Fallback: find nearest display
    local nearestDisplay = nil
    local nearestDist = math.huge
    for _, display in ipairs(displays) do
        local dx = 0
        local dy = 0
        if x < display.x then dx = display.x - x
        elseif x >= display.right then dx = x - display.right + 1
        end
        if y < display.y then dy = display.y - y
        elseif y >= display.bottom then dy = y - display.bottom + 1
        end
        local dist = dx + dy
        if dist < nearestDist then
            nearestDist = dist
            nearestDisplay = display
        end
    end

    return nearestDisplay
end

-- Check if cursor is at edge of display
local function getEdgeInfo(x, y, display)
    if not display then return nil, nil end

    if x <= display.x + EDGE_THRESHOLD then
        return 'left', display.x
    elseif x >= display.right - EDGE_THRESHOLD then
        return 'right', display.right
    elseif y <= display.y + EDGE_THRESHOLD then
        return 'top', display.y
    elseif y >= display.bottom - EDGE_THRESHOLD then
        return 'bottom', display.bottom
    end

    return nil, nil
end

-- Compute all jump zones for a display edge
local function computeEdgeZones(sourceDisplay, edge)
    local zones = {}

    for _, targetDisplay in ipairs(displays) do
        if targetDisplay.id ~= sourceDisplay.id then
            local isAdjacent = false
            local zone = nil

            if edge == 'right' then
                -- Target must be to the right (allow large gaps for non-adjacent displays)
                if targetDisplay.x >= sourceDisplay.right - 10 then
                    isAdjacent = true
                    zone = {
                        -- Y range on source display that maps to this target
                        sourceMin = math.max(sourceDisplay.y, targetDisplay.y - 100),
                        sourceMax = math.min(sourceDisplay.bottom, targetDisplay.bottom + 100),
                        -- Target display info
                        targetDisplay = targetDisplay,
                        targetX = targetDisplay.x + 10,
                        -- Whether target actually contains source Y range
                        targetYMin = targetDisplay.y,
                        targetYMax = targetDisplay.bottom
                    }
                end

            elseif edge == 'left' then
                if targetDisplay.right <= sourceDisplay.x + 10 then
                    isAdjacent = true
                    zone = {
                        sourceMin = math.max(sourceDisplay.y, targetDisplay.y - 100),
                        sourceMax = math.min(sourceDisplay.bottom, targetDisplay.bottom + 100),
                        targetDisplay = targetDisplay,
                        targetX = targetDisplay.right - 10,
                        targetYMin = targetDisplay.y,
                        targetYMax = targetDisplay.bottom
                    }
                end

            elseif edge == 'bottom' then
                if targetDisplay.y >= sourceDisplay.bottom - 10 then
                    isAdjacent = true
                    zone = {
                        sourceMin = math.max(sourceDisplay.x, targetDisplay.x - 100),
                        sourceMax = math.min(sourceDisplay.right, targetDisplay.right + 100),
                        targetDisplay = targetDisplay,
                        targetY = targetDisplay.y + 10,
                        targetXMin = targetDisplay.x,
                        targetXMax = targetDisplay.right
                    }
                end

            elseif edge == 'top' then
                if targetDisplay.bottom <= sourceDisplay.y + 10 then
                    isAdjacent = true
                    zone = {
                        sourceMin = math.max(sourceDisplay.x, targetDisplay.x - 100),
                        sourceMax = math.min(sourceDisplay.right, targetDisplay.right + 100),
                        targetDisplay = targetDisplay,
                        targetY = targetDisplay.bottom - 10,
                        targetXMin = targetDisplay.x,
                        targetXMax = targetDisplay.right
                    }
                end
            end

            if isAdjacent and zone then
                table.insert(zones, zone)
            end
        end
    end

    -- Sort zones by priority: prefer zones that directly contain the cursor coordinate
    -- This is handled at lookup time based on cursor position

    return zones
end

-- Pre-compute all jump zones for all displays
local function computeAllJumpZones()
    jumpZones = {}

    for _, display in ipairs(displays) do
        jumpZones[display.id] = {
            left = computeEdgeZones(display, 'left'),
            right = computeEdgeZones(display, 'right'),
            top = computeEdgeZones(display, 'top'),
            bottom = computeEdgeZones(display, 'bottom')
        }
    end

    if DEBUG then
        print("  Pre-computed jump zones:")
        for displayId, edges in pairs(jumpZones) do
            for edge, zones in pairs(edges) do
                if #zones > 0 then
                    for _, zone in ipairs(zones) do
                        print(string.format("    Display %d %s edge -> Display %d (source range: %.0f-%.0f)",
                            displayId, edge, zone.targetDisplay.id, zone.sourceMin, zone.sourceMax))
                    end
                end
            end
        end
    end
end

-- Find the best jump target for a cursor position at an edge
-- Uses velocity to determine directional intent
local function findJumpTarget(displayId, edge, cursorX, cursorY, vel)
    local zones = jumpZones[displayId] and jumpZones[displayId][edge]
    if not zones or #zones == 0 then
        return nil
    end

    -- Find best matching zone - consider ALL zones, use directional intent
    local bestZone = nil
    local bestScore = -math.huge

    for _, zone in ipairs(zones) do
        local score = 0
        local targetCenter
        local directionMatch = false

        if edge == 'left' or edge == 'right' then
            targetCenter = (zone.targetYMin + zone.targetYMax) / 2

            -- Base score: prefer zones that contain cursor Y
            if cursorY >= zone.targetYMin and cursorY <= zone.targetYMax then
                score = 1000  -- Direct containment
            else
                -- Distance penalty for being outside target range
                local dist = 0
                if cursorY < zone.targetYMin then dist = zone.targetYMin - cursorY
                else dist = cursorY - zone.targetYMax end
                score = 500 - dist  -- Start at 500, subtract distance
            end

            -- Directional bonus: if moving up/down, prefer targets in that direction
            if math.abs(vel.y) > 10 then  -- Significant vertical movement
                if vel.y < 0 and targetCenter < cursorY then
                    -- Moving up, target is above -> big bonus
                    directionMatch = true
                    score = score + 800
                    if DEBUG then
                        print(string.format("    Directional bonus: moving UP toward display %d (+800)", zone.targetDisplay.id))
                    end
                elseif vel.y > 0 and targetCenter > cursorY then
                    -- Moving down, target is below -> big bonus
                    directionMatch = true
                    score = score + 800
                    if DEBUG then
                        print(string.format("    Directional bonus: moving DOWN toward display %d (+800)", zone.targetDisplay.id))
                    end
                end
            end

        else  -- top/bottom
            targetCenter = (zone.targetXMin + zone.targetXMax) / 2

            if cursorX >= zone.targetXMin and cursorX <= zone.targetXMax then
                score = 1000
            else
                local dist = 0
                if cursorX < zone.targetXMin then dist = zone.targetXMin - cursorX
                else dist = cursorX - zone.targetXMax end
                score = 500 - dist
            end

            -- Directional bonus for horizontal movement
            if math.abs(vel.x) > 10 then
                if vel.x < 0 and targetCenter < cursorX then
                    directionMatch = true
                    score = score + 800
                    if DEBUG then
                        print(string.format("    Directional bonus: moving LEFT toward display %d (+800)", zone.targetDisplay.id))
                    end
                elseif vel.x > 0 and targetCenter > cursorX then
                    directionMatch = true
                    score = score + 800
                    if DEBUG then
                        print(string.format("    Directional bonus: moving RIGHT toward display %d (+800)", zone.targetDisplay.id))
                    end
                end
            end
        end

        if DEBUG then
            print(string.format("    Zone -> Display %d: score=%.0f, dirMatch=%s (vel: %.1f, %.1f)",
                zone.targetDisplay.id, score, tostring(directionMatch), vel.x, vel.y))
        end

        if score > bestScore then
            bestScore = score
            bestZone = zone
        end
    end

    -- Only jump if we have a reasonable score (either containment or strong directional intent)
    if not bestZone or bestScore < 200 then
        return nil
    end

    -- Calculate target position
    local targetX, targetY

    if edge == 'left' or edge == 'right' then
        targetX = bestZone.targetX
        targetY = math.max(bestZone.targetYMin + 10, math.min(cursorY, bestZone.targetYMax - 10))
    else
        targetY = bestZone.targetY
        targetX = math.max(bestZone.targetXMin + 10, math.min(cursorX, bestZone.targetXMax - 10))
    end

    return {
        x = targetX,
        y = targetY,
        targetDisplay = bestZone.targetDisplay
    }
end

-- Main cursor monitoring function
local function checkCursor()
    tickCount = tickCount + 1

    -- Heartbeat every 5 seconds
    if DEBUG and tickCount % 250 == 0 then
        print(string.format("♥ Heartbeat: tick %d", tickCount))
    end

    local currentPos = hs.mouse.absolutePosition()
    local currentX, currentY = currentPos.x, currentPos.y
    local now = hs.timer.secondsSinceEpoch()

    -- Update velocity (instantaneous - no smoothing for accurate direction)
    if lastPosition then
        velocity.x = currentX - lastPosition.x
        velocity.y = currentY - lastPosition.y
    end

    -- Tiny cooldown to prevent double-jumps
    if now - lastJumpTime < JUMP_COOLDOWN then
        lastPosition = {x = currentX, y = currentY}
        return
    end

    local currentDisplay = getCurrentDisplay(currentX, currentY)
    if not currentDisplay then
        lastPosition = {x = currentX, y = currentY}
        return
    end

    local edge, edgeCoord = getEdgeInfo(currentX, currentY, currentDisplay)

    if edge then
        -- Look up pre-computed jump target with directional intent
        local target = findJumpTarget(currentDisplay.id, edge, currentX, currentY, velocity)

        if target then
            if DEBUG then
                print(string.format("✓ JUMP: (%.0f, %.0f) -> (%.0f, %.0f) [display %d -> %d] (vel: %.1f, %.1f)",
                    currentX, currentY, target.x, target.y, currentDisplay.id, target.targetDisplay.id,
                    velocity.x, velocity.y))
            end

            hs.mouse.absolutePosition({x = target.x, y = target.y})
            lastJumpTime = now
            lastPosition = {x = target.x, y = target.y}
            return
        end
    end

    lastPosition = {x = currentX, y = currentY}
end

-- Protected timer callback
local function safeCheckCursor()
    local ok, err = pcall(checkCursor)
    if not ok then
        print(string.format("ERROR in checkCursor: %s", tostring(err)))
    end
end

-- Initialize: compute displays and jump zones
local function initialize()
    displays = getDisplays()
    computeAllJumpZones()
end

-- Handle display configuration changes
local function onScreensChanged()
    print("Display configuration changed - recomputing jump zones")
    initialize()
end

-- Cleanup previous instance
if smartCursorJump then
    if smartCursorJump.timer then
        smartCursorJump.timer:stop()
    end
    if smartCursorJump.screenWatcher then
        smartCursorJump.screenWatcher:stop()
    end
end

-- Initialize global state
smartCursorJump = {
    timer = nil,
    screenWatcher = nil
}

-- Run initialization
initialize()

-- Start timer
smartCursorJump.timer = hs.timer.doEvery(CHECK_INTERVAL, safeCheckCursor)

-- Watch for display changes
smartCursorJump.screenWatcher = hs.screen.watcher.new(onScreensChanged)
smartCursorJump.screenWatcher:start()

-- Startup message
print("=====================================")
print("Smart Cursor Jump loaded (instant mode)")
print(string.format("  Edge threshold: %dpx", EDGE_THRESHOLD))
print(string.format("  Check interval: %.0fms", CHECK_INTERVAL * 1000))
print(string.format("  Jump cooldown: %.0fms", JUMP_COOLDOWN * 1000))
print(string.format("  Debug mode: %s", DEBUG and "ON" or "OFF"))
print("  Directional intent: enabled (velocity-based)")
print("  Detected displays:")
for _, display in ipairs(displays) do
    print(string.format("    Display %d: x=%.0f, y=%.0f, w=%.0f, h=%.0f (right=%.0f, bottom=%.0f)",
        display.id, display.x, display.y, display.w, display.h, display.right, display.bottom))
end
print("  Jump zones computed - instant edge transitions ready!")
print("")
print("  TIP: To disable macOS native display transitions:")
print("    System Settings > Displays > Arrange...")
print("    Drag displays apart so edges don't touch")
print("=====================================")
