-- pill.lua: floating status pill (hs.canvas), centered on screen.
-- withBars=true: a small live waveform driven by updateBars().
-- withBars=false: a pulsing dot.

local M = {}

local BAR_COUNT = 5
-- attenuation from the center bar outwards
local BAR_WEIGHTS = { 0.35, 0.7, 1.0, 0.7, 0.35 }
local canvas = nil
local hasBars = false
local level = 0
local jitters = { 1, 1, 1, 1, 1 }
local tick = 0
local pulseTimer = nil
local BAR_X0 = 17 -- left edge of the first bar, centers the 32px bar block

function M.hide()
    if pulseTimer then
        pulseTimer:stop()
        pulseTimer = nil
    end
    if canvas then
        canvas:delete()
        canvas = nil
    end
end

function M.show(color, withBars)
    M.hide()
    local sf = hs.screen.mainScreen():frame()
    local h = 44
    local w = withBars and 66 or 44
    canvas = hs.canvas.new({ x = sf.x + (sf.w - w) / 2, y = sf.y + (sf.h - h) / 2, w = w, h = h })
    canvas:appendElements({
        type = "rectangle",
        action = "fill",
        roundedRectRadii = { xRadius = h / 2, yRadius = h / 2 },
        fillColor = { red = 0, green = 0, blue = 0, alpha = 1 },
    })
    hasBars = withBars
    level = 0
    if withBars then
        for i = 1, BAR_COUNT do
            canvas:appendElements({
                type = "rectangle",
                action = "fill",
                roundedRectRadii = { xRadius = 2, yRadius = 2 },
                fillColor = color,
                frame = { x = BAR_X0 + (i - 1) * 7, y = h / 2 - 3, w = 4, h = 6 },
            })
        end
    else
        canvas:appendElements({
            type = "oval",
            action = "fill",
            fillColor = color,
            frame = { x = w / 2 - 7, y = h / 2 - 7, w = 14, h = 14 },
        })
        local phase = 0
        pulseTimer = hs.timer.doEvery(0.05, function()
            if not canvas then return end
            phase = phase + 0.5
            local alpha = 0.4 + 0.55 * (math.sin(phase) + 1) / 2
            canvas[2].fillColor = { red = color.red, green = color.green, blue = color.blue, alpha = alpha }
        end)
    end
    canvas:level("status")
    canvas:behavior({ "canJoinAllSpaces" })
    canvas:show()
end

-- waveform: the center bar follows the mic level (dBFS), the outer bars
-- mirror it with decreasing height so the motion fades out to both sides
function M.updateBars(db)
    if not canvas or not hasBars then return end
    -- RMS scale: quiet room is ~-60..-50 dB; normal speech should hit ~1.0
    local target = math.max(0, math.min(1, (db + 48) / 20))
    level = level + (target - level) * 0.9
    -- per-bar jitter keeps the bars from moving in lockstep;
    -- refreshed only every 4th tick (5x/s) so it wobbles instead of flickering
    tick = tick + 1
    if tick % 4 == 1 then
        for i = 1, BAR_COUNT do
            jitters[i] = 0.85 + math.random() * 0.3
        end
    end
    for i = 1, BAR_COUNT do
        local bh = 6 + math.min(1, level * BAR_WEIGHTS[i] * jitters[i]) * 26
        canvas[1 + i].frame = { x = BAR_X0 + (i - 1) * 7, y = 22 - bh / 2, w = 4, h = bh }
    end
end

return M
