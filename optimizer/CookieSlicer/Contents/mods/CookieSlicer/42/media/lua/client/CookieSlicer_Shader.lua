-- Cookie Slicer (client): screen looks drawn by a real shader.
-- The Cookie Slicer Helper (v1.1.0+) draws one extra full-screen pass right after the
-- game's own screen shader and before any window (media/shaders/cookie_post.*).
-- This file holds the looks and their settings, checks whether this PC can run them,
-- picks settings that fit the PC ("recommend"), and writes the choice to
-- Zomboid/Lua/CookieSlicer_shader.txt, which the helper reads.
-- Without the helper the simple colour layers of CookieSlicer_Look.lua are used.
-- Copyright (c) AKA / Cookie Cheetah. See workshop.txt for the license.
if isServer() then return end

local CS = CookieSlicer
if not CS then return end

local SHADER_FILE = "CookieSlicer_shader.txt"

-- sliders on the Shader page (value range and step)
CS.SH_PARAMS = {
    { id = "mix",   min = 0,    max = 1,   step = 0.1 },  -- how much of the look
    { id = "exp",   min = -1,   max = 1,   step = 0.1 },  -- brightness (stops)
    { id = "con",   min = 0.6,  max = 1.6, step = 0.05 }, -- contrast
    { id = "sat",   min = 0,    max = 2,   step = 0.1 },  -- colour
    { id = "warm",  min = -1,   max = 1,   step = 0.1 },  -- cool .. warm
    { id = "bloom", min = 0,    max = 1.5, step = 0.1 },  -- glow of bright light
    { id = "vig",   min = 0,    max = 1,   step = 0.05 }, -- dark edges
    { id = "sharp", min = 0,    max = 1,   step = 0.05 }, -- sharpness
    { id = "grain", min = 0,    max = 1,   step = 0.05 }, -- film grain
}

-- The looks. p = slider values; the rest are fixed per look:
-- thr = glow threshold, glow = how much more lights glow at night, tone = film curve,
-- fade = lifted blacks, sh / hi = colour in the shadows / highlights {r, g, b, amount}.
-- "natural" switches the pass off (the game's picture, no cost).
CS.SHADER_LOOKS = {
    { id = "natural", off = true, swatch = { 0.42, 0.55, 0.38 },
      p = { mix = 0, exp = 0, con = 1, sat = 1, warm = 0, bloom = 0, vig = 0, sharp = 0, grain = 0 } },
    { id = "golden", swatch = { 0.80, 0.58, 0.30 },  -- warm, vivid, soft glow
      p = { mix = 1, exp = 0, con = 1.12, sat = 1.3, warm = 0.45, bloom = 0.55, vig = 0.25, sharp = 0.15, grain = 0 },
      thr = 0.55, glow = 0.4, tone = 0.6, fade = 0, sh = { 0.35, 0.15, 0.55, 0.35 }, hi = { 1.0, 0.75, 0.4, 0.3 } },
    { id = "film", swatch = { 0.40, 0.52, 0.56 },    -- true-to-life film, deep shadows
      p = { mix = 1, exp = 0, con = 1.12, sat = 1.05, warm = 0.15, bloom = 0.3, vig = 0.3, sharp = 0.25, grain = 0.15 },
      thr = 0.65, glow = 0.2, tone = 1.0, fade = 0, sh = { 0.0, 0.25, 0.4, 0.3 }, hi = { 1.0, 0.8, 0.55, 0.3 } },
    { id = "glow", swatch = { 0.20, 0.22, 0.42 },    -- lights glow in colour at night
      p = { mix = 1, exp = 0, con = 1.05, sat = 1.2, warm = 0.1, bloom = 0.8, vig = 0.2, sharp = 0.1, grain = 0 },
      thr = 0.45, glow = 1.0, tone = 0.5, fade = 0, sh = { 0.1, 0.15, 0.45, 0.4 }, hi = { 1.0, 0.6, 0.3, 0.3 } },
    { id = "vivid", swatch = { 0.30, 0.66, 0.36 },   -- punchy colour, crisp
      p = { mix = 1, exp = 0.05, con = 1.25, sat = 1.45, warm = 0, bloom = 0.25, vig = 0.15, sharp = 0.45, grain = 0 },
      thr = 0.7, glow = 0.2, tone = 0.3, fade = 0 },
    { id = "cinema", swatch = { 0.62, 0.50, 0.36 },  -- teal and orange
      p = { mix = 1, exp = 0, con = 1.1, sat = 0.9, warm = 0.35, bloom = 0.2, vig = 0.4, sharp = 0.1, grain = 0.2 },
      thr = 0.65, glow = 0.2, tone = 0.7, fade = 0, sh = { 0.0, 0.35, 0.4, 0.4 }, hi = { 1.0, 0.65, 0.35, 0.4 } },
    { id = "retro", swatch = { 0.60, 0.55, 0.45 },   -- faded photo
      p = { mix = 1, exp = 0, con = 0.9, sat = 0.55, warm = 0.45, bloom = 0.15, vig = 0.45, sharp = 0, grain = 0.45 },
      thr = 0.7, glow = 0, tone = 0.3, fade = 0.6, hi = { 1.0, 0.85, 0.6, 0.4 } },
    { id = "dark", swatch = { 0.16, 0.18, 0.24 },    -- real fear: dark, lights stand out
      p = { mix = 1, exp = -0.2, con = 1.15, sat = 0.8, warm = -0.2, bloom = 0.35, vig = 0.55, sharp = 0.1, grain = 0.15 },
      thr = 0.5, glow = 0.6, tone = 0.6, fade = 0, sh = { 0.1, 0.15, 0.35, 0.5 } },
}

function CS.shaderLook(id)
    for _, l in ipairs(CS.SHADER_LOOKS) do
        if l.id == id then return l end
    end
    return CS.SHADER_LOOKS[1]
end

function CS.verLess(a, b)
    local function parts(v)
        local t = {}
        for n in string.gmatch(tostring(v or ""), "%d+") do t[#t + 1] = tonumber(n) end
        return t
    end
    local x, y = parts(a), parts(b)
    for i = 1, math.max(#x, #y) do
        local p, q = x[i] or 0, y[i] or 0
        if p ~= q then return p < q end
    end
    return false
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- ---------------------------------------------------------------- settings

-- sh_on (1/0), sh_look, sh_q ("auto" or 0..2), sh_<look>_<param> (changed sliders)
local function S(k, default)
    local v = CS.settings["sh_" .. k]
    if v == nil then return default end
    return v
end

function CS.shaderOn() return tostring(S("on", "1")) == "1" end
function CS.shaderLookId() return tostring(S("look", "golden")) end

function CS.shaderParam(lookId, id)
    local look = CS.shaderLook(lookId)
    local v = tonumber(CS.settings["sh_" .. look.id .. "_" .. id])
    if v == nil then v = look.p[id] or 0 end
    return v
end

function CS.shaderSetParam(lookId, id, v)
    for _, prm in ipairs(CS.SH_PARAMS) do
        if prm.id == id then
            v = clamp(v, prm.min, prm.max)
            v = math.floor(v / prm.step + 0.5) * prm.step
            local look = CS.shaderLook(lookId)
            local key = "sh_" .. look.id .. "_" .. id
            if math.abs(v - (look.p[id] or 0)) < prm.step / 2 then
                CS.settings[key] = nil -- back at the look's own value
            else
                CS.settings[key] = string.format("%.2f", v)
            end
            CS.saveSettings()
            CS.shaderWrite()
            return v
        end
    end
end

function CS.shaderResetLook(lookId)
    local look = CS.shaderLook(lookId)
    for _, prm in ipairs(CS.SH_PARAMS) do CS.settings["sh_" .. look.id .. "_" .. prm.id] = nil end
    CS.saveSettings()
    CS.shaderWrite()
end

function CS.shaderSet(k, v)
    CS.settings["sh_" .. k] = v
    CS.saveSettings()
    CS.shaderWrite()
end

-- ---------------------------------------------------------------- this PC

-- graphics chips built into the CPU share its memory and power
local INTEGRATED = { "intel", "uhd", "iris", "hd graphics", "radeon%(tm%) graphics", "radeon graphics",
                     "vega %d", "radeon r%d", "apple", "adreno", "mali", "llvmpipe", "microsoft basic" }

-- own-memory cards whose names would otherwise look built-in
local DISCRETE_FIRST = { "arc%(tm%) a", "arc a%d", "rx vega", "radeon pro", "quadro" }

-- "discrete" / "integrated" / "unknown"
function CS.gpuClass()
    local name = string.lower(tostring(CS.pc.gpu or ""))
    if name == "" or name == "nil" then return "unknown" end
    for _, w in ipairs(DISCRETE_FIRST) do
        if string.find(name, w) then return "discrete" end
    end
    for _, w in ipairs(INTEGRATED) do
        if string.find(name, w) then return "integrated" end
    end
    if string.find(name, "nvidia") or string.find(name, "geforce") or string.find(name, "rtx")
        or string.find(name, "gtx") or string.find(name, "radeon") or string.find(name, " rx ") then
        return "discrete"
    end
    return "unknown"
end

-- how long the pass may take on this GPU (ms per frame)
function CS.shaderBudget()
    local c = CS.gpuClass()
    if c == "discrete" then return 1.5 elseif c == "integrated" then return 0.8 end
    return 1.2
end

-- quality: 0 = grading only, 1 = glow from 2 smaller copies, 2 = glow from 4
function CS.shaderQuality()
    local q = S("q", "auto")
    if q ~= "auto" and tonumber(q) then return clamp(math.floor(tonumber(q)), 0, 2) end
    local c = CS.gpuClass()
    if c == "discrete" then return 2 end
    return 1
end

function CS.helperCanShade()
    local pc = CS.pc
    return pc.fresh and pc.helper ~= nil and not CS.verLess(pc.helper, CS.SHADER_HELPER_MIN)
        and tonumber(pc.shader_hook) == 1
end

-- the shader is drawing the look now (the colour layers stay off then)
function CS.shaderActive()
    if not CS.helperCanShade() or not CS.shaderOn() then return false end
    if tonumber(CS.pc.shader_ok) == 0 then return false end -- failed to start on this PC
    return not CS.shaderLook(CS.shaderLookId()).off
end

-- what the window shows under "can this PC run it":
-- list of { id, state ("ok" / "warn" / "bad" / "wait"), value text args }
function CS.shaderCheck()
    local pc = CS.pc
    local rows = {}
    -- 1. helper
    if not pc.present then
        rows[#rows + 1] = { id = "helper", state = "bad", key = "Req_helperNone" }
    elseif not pc.fresh then
        rows[#rows + 1] = { id = "helper", state = "bad", key = "Req_helperStopped" }
    elseif CS.verLess(pc.helper, CS.SHADER_HELPER_MIN) then
        rows[#rows + 1] = { id = "helper", state = "bad", key = "Req_helperOld", a = tostring(pc.helper), b = CS.SHADER_HELPER_MIN }
    elseif tonumber(pc.shader_hook) ~= 1 then
        rows[#rows + 1] = { id = "helper", state = "bad", key = "Req_noHook" }
    else
        rows[#rows + 1] = { id = "helper", state = "ok", key = "Req_helperOk", a = tostring(pc.helper) }
    end
    -- 2. graphics card
    local cls = CS.gpuClass()
    if pc.fresh and pc.gpu then
        local vram = ""
        local total, free = tonumber(pc.vram_total_mb), tonumber(pc.vram_free_mb)
        if total and (total < 256 or total > 98304) then total = nil end -- some drivers report nonsense
        if free and total and free > total then free = nil end
        if total and total > 0 then
            vram = free and string.format("%.1f / %.1f GB", free / 1024, total / 1024) or string.format("%.1f GB", total / 1024)
        end
        rows[#rows + 1] = { id = "gpu", state = cls == "integrated" and "warn" or "ok",
                            key = cls == "integrated" and "Req_gpuShared" or (cls == "discrete" and "Req_gpuOwn" or "Req_gpuUnknown"),
                            a = tostring(pc.gpu), b = vram }
    else
        rows[#rows + 1] = { id = "gpu", state = "wait", key = "Req_gpuWait" }
    end
    -- 3. OpenGL 3.0 or newer
    local gl = tostring(pc.gl or "")
    local major, minor = string.match(gl, "^(%d+)%.(%d+)")
    if major then
        local ok = tonumber(major) > 3 or (tonumber(major) == 3 and tonumber(minor) >= 0)
        rows[#rows + 1] = { id = "gl", state = ok and "ok" or "bad", key = ok and "Req_glOk" or "Req_glOld", a = major .. "." .. minor }
    else
        rows[#rows + 1] = { id = "gl", state = "wait", key = "Req_glWait" }
    end
    -- 4. measured cost of the pass
    local ms = tonumber(pc.shader_ms)
    local budget = CS.shaderBudget()
    if tonumber(pc.shader_ok) == 0 then
        rows[#rows + 1] = { id = "cost", state = "bad", key = "Req_failed", a = tostring(pc.shader_err or "?") }
    elseif ms and ms > 0 and tonumber(pc.shader_active) == 1 then
        rows[#rows + 1] = { id = "cost", state = ms <= budget and "ok" or "warn",
                            key = ms <= budget and "Req_costOk" or "Req_costHigh",
                            a = string.format("%.2f", ms), b = string.format("%.1f", budget) }
    else
        rows[#rows + 1] = { id = "cost", state = "wait", key = getPlayer() and "Req_costOff" or "Req_costMenu",
                            a = string.format("%.1f", budget) }
    end
    -- overall
    local worst = "ok"
    for _, r in ipairs(rows) do
        if r.state == "bad" then worst = "bad"
        elseif r.state == "warn" and worst ~= "bad" then worst = "warn" end
    end
    return rows, worst
end

-- "Compatible recommend": keep the chosen look, pick the quality this PC can carry
-- (measured cost when known, else the kind of graphics card), apply at once.
-- returns the quality picked and the reason key for the message
function CS.shaderRecommend()
    local cls = CS.gpuClass()
    local q = (cls == "discrete") and 2 or 1
    local why = "Rec_" .. cls
    local ms, cur = tonumber(CS.pc.shader_ms), CS.shaderQuality()
    local budget = CS.shaderBudget()
    if ms and ms > 0 and tonumber(CS.pc.shader_active) == 1 then
        if ms > budget then
            q = math.max(0, math.min(q, cur - 1))
            why = "Rec_tooSlow"
        elseif ms < budget * 0.35 and cur < 2 and cls ~= "integrated" then
            q = cur + 1
            why = "Rec_room"
        else
            q = math.min(q, math.max(cur, 0))
        end
    end
    local f = CS.fps
    if getPlayer() and f.n >= 10 and f.avg < 30 then
        q = math.min(q, cls == "discrete" and 1 or 0)
        why = "Rec_lowFps"
    end
    CS.settings.sh_q = tostring(q)
    CS.settings.sh_on = "1"
    CS.saveSettings()
    CS.shaderWrite()
    return q, why
end

-- ---------------------------------------------------------------- to the helper

CS.shaderSplit = -1 -- compare line (part of the screen width), -1 = off

local last = nil
local function fmt(v) return string.format("%.3f", tonumber(v) or 0) end
local function vec4(t)
    if not t then return "0,0,0,0" end
    return fmt(t[1]) .. "," .. fmt(t[2]) .. "," .. fmt(t[3]) .. "," .. fmt(t[4])
end

-- the current choice as the helper reads it (written only when it changed)
function CS.shaderWrite()
    local id = CS.shaderLookId()
    local look = CS.shaderLook(id)
    local on = CS.shaderOn() and not look.off
    local lines = { "on=" .. (on and "1" or "0"), "look=" .. look.id, "q=" .. tostring(CS.shaderQuality()),
                    "split=" .. fmt(CS.shaderSplit) }
    for _, prm in ipairs(CS.SH_PARAMS) do
        lines[#lines + 1] = prm.id .. "=" .. fmt(CS.shaderParam(id, prm.id))
    end
    lines[#lines + 1] = "thr=" .. fmt(look.thr or 0.6)
    lines[#lines + 1] = "glow=" .. fmt(look.glow or 0)
    lines[#lines + 1] = "tone=" .. fmt(look.tone or 0)
    lines[#lines + 1] = "fade=" .. fmt(look.fade or 0)
    lines[#lines + 1] = "sh=" .. vec4(look.sh)
    lines[#lines + 1] = "hi=" .. vec4(look.hi)
    local text = table.concat(lines, "\n") .. "\n"
    if text == last then return false end
    local ok = pcall(function()
        local w = getFileWriter(SHADER_FILE, true, false)
        if not w then return end
        w:write(text)
        w:close()
    end)
    if ok then last = text end
    return ok
end

function CS.shaderSetSplit(v)
    v = tonumber(v) or -1
    if v ~= CS.shaderSplit then
        CS.shaderSplit = v
        CS.shaderWrite()
    end
end

-- write once at start (the helper may have started before this file existed),
-- and turn the compare line off when a game starts or ends
local function onStart()
    CS.shaderSplit = -1
    last = nil
    CS.shaderWrite()
end

-- once a second: "auto" quality and the like depend on what the helper found out
-- (writes only when something changed)
local lastCheck = 0
local function everySecond()
    local now = getTimestampMs()
    if now - lastCheck < 1000 then return end
    lastCheck = now
    CS.shaderWrite()
end

Events.OnGameStart.Add(onStart)
Events.OnMainMenuEnter.Add(onStart)
Events.OnTick.Add(everySecond)
Events.OnFETick.Add(everySecond)
