-- Cookie Exchange : small JSON reader / writer for the shop file (Zomboid/Lua/CookieExchange_Shop.json)
-- Enough for the shop: objects, arrays, strings, numbers, true/false/null. Output is indented so the
-- file stays easy to edit by hand.

CX = CX or {}
CX.json = {}

local J = CX.json

-- ------------------------------------------------------------------------------
-- write
-- ------------------------------------------------------------------------------
local ESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }

local function str(s)
    local out = string.gsub(s, '["\\\n\r\t]', function(c) return ESC[c] end)
    return '"' .. out .. '"'
end

local function isArray(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    for i = 1, n do
        if t[i] == nil then return false end
    end
    return true, n
end

local function enc(v, ind, out)
    local tv = type(v)
    if tv == "string" then
        out[#out + 1] = str(v)
    elseif tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then v = 0 end
        if v == math.floor(v) then out[#out + 1] = tostring(math.floor(v)) else out[#out + 1] = tostring(v) end
    elseif tv == "boolean" then
        out[#out + 1] = v and "true" or "false"
    elseif tv == "table" then
        local arr, n = isArray(v)
        local pad = string.rep("  ", ind + 1)
        if arr then
            if n == 0 then out[#out + 1] = "[]"; return end
            -- short arrays of plain values stay on one line
            local flat = true
            for i = 1, n do if type(v[i]) == "table" then flat = false; break end end
            if flat then
                out[#out + 1] = "["
                for i = 1, n do
                    if i > 1 then out[#out + 1] = ", " end
                    enc(v[i], ind, out)
                end
                out[#out + 1] = "]"
                return
            end
            out[#out + 1] = "[\n"
            for i = 1, n do
                out[#out + 1] = pad
                enc(v[i], ind + 1, out)
                out[#out + 1] = (i < n) and ",\n" or "\n"
            end
            out[#out + 1] = string.rep("  ", ind) .. "]"
        else
            local keys = {}
            for k in pairs(v) do if type(k) == "string" then keys[#keys + 1] = k end end
            table.sort(keys)
            if #keys == 0 then out[#out + 1] = "{}"; return end
            out[#out + 1] = "{\n"
            for i, k in ipairs(keys) do
                out[#out + 1] = pad .. str(k) .. ": "
                enc(v[k], ind + 1, out)
                out[#out + 1] = (i < #keys) and ",\n" or "\n"
            end
            out[#out + 1] = string.rep("  ", ind) .. "}"
        end
    else
        out[#out + 1] = "null"
    end
end

function J.encode(v)
    local out = {}
    enc(v, 0, out)
    return table.concat(out)
end

-- ------------------------------------------------------------------------------
-- read  (returns value, or nil + "error at <pos>")
-- ------------------------------------------------------------------------------
local UNESC = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }

-- Kahlua strings are Java strings (one char per letter), plain Lua strings are bytes
local WIDE = string.len("ก") == 1

local function utf8(cp)
    if cp < 0x80 or WIDE then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

function J.decode(s)
    if type(s) ~= "string" then return nil, "not text" end
    local pos = 1
    local val

    local function err(why) error({ cxjson = why .. " at " .. tostring(pos) }) end

    local function ws()
        pos = string.find(s, "[^ \t\r\n]", pos) or (#s + 1)
    end

    local function readString()
        pos = pos + 1
        local out = {}
        while true do
            local c = string.sub(s, pos, pos)
            if c == "" then err("unfinished string") end
            if c == '"' then pos = pos + 1; break end
            if c == "\\" then
                local e = string.sub(s, pos + 1, pos + 1)
                if e == "u" then
                    local hex = string.sub(s, pos + 2, pos + 5)
                    local cp = tonumber(hex, 16)
                    if not cp then err("bad \\u") end
                    out[#out + 1] = utf8(cp)
                    pos = pos + 6
                elseif UNESC[e] then
                    out[#out + 1] = UNESC[e]
                    pos = pos + 2
                else
                    err("bad escape")
                end
            else
                local stop = string.find(s, '["\\]', pos) or (#s + 1)
                out[#out + 1] = string.sub(s, pos, stop - 1)
                pos = stop
            end
        end
        return table.concat(out)
    end

    function val()
        ws()
        local c = string.sub(s, pos, pos)
        if c == "{" then
            pos = pos + 1
            local t = {}
            ws()
            if string.sub(s, pos, pos) == "}" then pos = pos + 1; return t end
            while true do
                ws()
                if string.sub(s, pos, pos) ~= '"' then err("expected key") end
                local k = readString()
                ws()
                if string.sub(s, pos, pos) ~= ":" then err("expected :") end
                pos = pos + 1
                t[k] = val()
                ws()
                local d = string.sub(s, pos, pos)
                pos = pos + 1
                if d == "}" then return t end
                if d ~= "," then err("expected , or }") end
            end
        elseif c == "[" then
            pos = pos + 1
            local t = {}
            ws()
            if string.sub(s, pos, pos) == "]" then pos = pos + 1; return t end
            while true do
                t[#t + 1] = val()
                ws()
                local d = string.sub(s, pos, pos)
                pos = pos + 1
                if d == "]" then return t end
                if d ~= "," then err("expected , or ]") end
            end
        elseif c == '"' then
            return readString()
        elseif string.sub(s, pos, pos + 3) == "true" then
            pos = pos + 4; return true
        elseif string.sub(s, pos, pos + 4) == "false" then
            pos = pos + 5; return false
        elseif string.sub(s, pos, pos + 3) == "null" then
            pos = pos + 4; return nil
        else
            local a, b = string.find(s, "^-?%d+%.?%d*", pos)
            if not a then err("unexpected character") end
            local num = string.sub(s, a, b)
            pos = b + 1
            local n = tonumber(num)
            if not n then err("bad number") end
            return n
        end
    end

    local ok, res = pcall(function()
        local v = val()
        ws()
        if pos <= #s then err("extra text") end
        return v
    end)
    if ok then return res end
    if type(res) == "table" and res.cxjson then return nil, res.cxjson end
    return nil, tostring(res)
end
