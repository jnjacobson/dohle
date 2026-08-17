-- hammerspoon-whisper: ⌥Space toggles mic recording; on stop, the audio is sent to
-- OpenAI's transcription API and the result is pasted at the current text caret.
-- Esc aborts while recording or transcribing.

local M = {}

local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*)/")
package.path = DIR .. "/?.lua;" .. package.path
local pill = require("pill")
local RECORDER = DIR .. "/recorder"
local AUDIO_FILE = "/tmp/hammerspoon-whisper.m4a"
local MODEL = "gpt-transcribe"
local KEY_FILE = os.getenv("HOME") .. "/.config/openai/api_key"
local CONFIG_FILE = DIR .. "/config.json"

local SND_START = hs.sound.getByName("Purr")
local SND_STOP = hs.sound.getByName("Pop")
local SND_ABORT = hs.sound.getByName("Bottle")

local recordTask = nil
local curlTask = nil
local aborted = false
local escKey -- defined below

local function setStatus(state)
    if state == "recording" then
        pill.show({ red = 1, green = 0.23, blue = 0.19, alpha = 1 }, "mic")
    elseif state == "transcribing" then
        pill.show({ red = 1, green = 1, blue = 1, alpha = 1 }, "loading")
    else
        pill.hide()
    end
end

local function idle()
    setStatus(nil)
    escKey:disable()
    os.remove(AUDIO_FILE)
end

local function apiKey()
    local key = os.getenv("OPENAI_API_KEY")
    if key and #key > 0 then return key end
    local f = io.open(KEY_FILE, "r")
    if f then
        key = f:read("*l")
        f:close()
        if key and #key > 0 then return key end
    end
    return nil
end

local function paste(text)
    local pb = hs.pasteboard
    local previous = pb.getContents()
    pb.setContents(text)
    hs.eventtap.keyStroke({ "cmd" }, "v", 0)
    -- restore the old clipboard once the paste has gone through
    hs.timer.doAfter(0.5, function()
        if previous then pb.setContents(previous) end
    end)
end

local errEsc -- defined below; only active while an error is on screen
local function showError(msg)
    local lines = {}
    for line in msg:gmatch("[^\n]+") do
        while #line > 72 do
            local brk = line:sub(1, 72):match(".*()%s") or 72
            if brk < 40 then brk = 72 end
            table.insert(lines, (line:sub(1, brk):gsub("%s+$", "")))
            line = line:sub(brk + 1):gsub("^%s+", "")
        end
        if #line > 0 then table.insert(lines, line) end
    end
    table.insert(lines, "")
    table.insert(lines, "(Esc to dismiss)")
    hs.alert.closeAll(0)
    hs.alert.show(table.concat(lines, "\n"), { textSize = 14, padding = 18 }, hs.screen.mainScreen(), 1e6)
    errEsc:enable()
end
errEsc = hs.hotkey.new({}, "escape", function()
    hs.alert.closeAll(0)
    errEsc:disable()
end)

-- config.json (see config.dist.json): read on every transcription — no reload needed
local function config()
    local f = io.open(CONFIG_FILE, "r")
    if not f then return {} end
    local raw = f:read("*a")
    f:close()
    local ok, cfg = pcall(hs.json.decode, raw)
    if not ok or type(cfg) ~= "table" then
        showError("Invalid JSON in " .. CONFIG_FILE)
        return {}
    end
    return cfg
end

local function transcribe()
    local key = apiKey()
    if not key then
        idle()
        showError("No OpenAI API key found (env OPENAI_API_KEY or " .. KEY_FILE .. ")")
        return
    end

    setStatus("transcribing")
    curlTask = hs.task.new("/usr/bin/curl", function(exitCode, stdOut, stdErr)
        curlTask = nil
        local wasAborted = aborted
        idle()
        if wasAborted then return end
        local text = (stdOut or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if exitCode ~= 0 then
            showError("Transcription failed: " .. (stdErr ~= "" and stdErr or text))
            return
        end
        if #text == 0 then return end
        -- API errors come back as a JSON object even with response_format=text
        if text:sub(1, 1) == "{" then
            showError("OpenAI error: " .. text:sub(1, 200))
            return
        end
        paste(text)
    end, (function()
        local args = {
            "-s", "--max-time", "60",
            "https://api.openai.com/v1/audio/transcriptions",
            "-H", "Authorization: Bearer " .. key,
            "-F", "file=@" .. AUDIO_FILE,
            "-F", "model=" .. MODEL,
            "-F", "response_format=text",
        }
        local cfg = config()
        for _, term in ipairs(cfg.glossary or {}) do
            table.insert(args, "-F")
            table.insert(args, "keywords[]=" .. term)
        end
        for _, lang in ipairs(cfg.languages or {}) do
            table.insert(args, "-F")
            table.insert(args, "languages[]=" .. lang)
        end
        return args
    end)())
    curlTask:start()
end

local function startRecording()
    os.remove(AUDIO_FILE)
    aborted = false
    recordTask = hs.task.new(RECORDER, function(exitCode, stdOut, stdErr)
        recordTask = nil
        if aborted then
            idle()
            SND_ABORT:play()
            return
        end
        if exitCode ~= 0 then
            idle()
            showError("Recording failed: " .. (stdErr or ""))
            return
        end
        SND_STOP:play()
        transcribe()
    end, function(_, stdOut, _)
        local last
        for num in (stdOut or ""):gmatch("[-%.%d]+") do last = num end
        local db = tonumber(last)
        if db then pill.updateBars(db) end
        return true
    end, { AUDIO_FILE })
    if recordTask:start() then
        setStatus("recording")
        escKey:enable()
        SND_START:play()
    else
        recordTask = nil
        showError("Could not start recorder at " .. RECORDER)
    end
end

local function stopRecording()
    if recordTask then
        recordTask:terminate() -- SIGTERM → recorder finalizes the file and exits 0
    end
end

local function abort()
    aborted = true
    if recordTask then
        recordTask:terminate()
    elseif curlTask then
        curlTask:terminate()
        curlTask = nil
        idle()
        SND_ABORT:play()
    end
end

-- only active while recording/transcribing, so Esc behaves normally otherwise
escKey = hs.hotkey.new({}, "escape", abort)

hs.hotkey.bind({ "alt" }, "space", function()
    if recordTask then
        stopRecording()
    else
        startRecording()
    end
end)

return M
