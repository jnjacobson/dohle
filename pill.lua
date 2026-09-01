-- pill.lua: floating status pill (hs.canvas) with five bars, centered on screen.
-- mode "mic": a live waveform driven by updateBars().
-- mode "loading": a self-running wave animation.

local M = {}

local BAR_COUNT = 5
-- attenuation from the center bar outwards
local BAR_WEIGHTS = { 0.35, 0.7, 1.0, 0.7, 0.35 }
local canvas = nil
local micDriven = false
local level = 0
local jitters = { 1, 1, 1, 1, 1 }
local tick = 0
local loadingTimer = nil
local BAR_X0 = 17 -- left edge of the first bar, centers the 32px bar block

function M.hide()
    if loadingTimer then
        loadingTimer:stop()
        loadingTimer = nil
    end
    if canvas then
        canvas:delete()
        canvas = nil
    end
end

function M.show(color, mode)
    M.hide()
    local sf = hs.screen.mainScreen():frame()
    local w, h = 66, 44
    canvas = hs.canvas.new({ x = sf.x + (sf.w - w) / 2, y = sf.y + (sf.h - h) / 2, w = w, h = h })
    canvas:appendElements({
        type = "rectangle",
        action = "fill",
        roundedRectRadii = { xRadius = h / 2, yRadius = h / 2 },
        fillColor = { red = 0, green = 0, blue = 0, alpha = 1 },
    })
    micDriven = (mode == "mic")
    level = 0
    for i = 1, BAR_COUNT do
        canvas:appendElements({
            type = "rectangle",
            action = "fill",
            roundedRectRadii = { xRadius = 2, yRadius = 2 },
            fillColor = color,
            frame = { x = BAR_X0 + (i - 1) * 7, y = h / 2 - 3, w = 4, h = 6 },
        })
    end
    if mode == "loading" then
        -- a sine wave travels across the bars
        local phase = 0
        loadingTimer = hs.timer.doEvery(0.05, function()
            if not canvas then return end
            phase = phase + 0.5
            for i = 1, BAR_COUNT do
                local v = (math.sin(phase - (i - 1) * 0.7) + 1) / 2
                local bh = 8 + v * 14
                canvas[1 + i].frame = { x = BAR_X0 + (i - 1) * 7, y = h / 2 - bh / 2, w = 4, h = bh }
            end
        end)
    end
    canvas:level("status")
    canvas:behavior({ "canJoinAllSpaces" })
    canvas:show()
end

-- waveform: the center bar follows the mic level (dBFS), the outer bars
-- mirror it with decreasing height so the motion fades out to both sides
function M.updateBars(db)
    if not canvas or not micDriven then return end
    -- RMS scale: quiet room is ~-70 dB (post-16kHz-downsampling); speech hits ~1.0
    local target = math.max(0, math.min(1, (db + 48) / 20))
    -- fast attack, slow release: bars jump up with speech but sink gently in pauses
    level = level + (target - level) * (target > level and 0.9 or 0.25)
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
