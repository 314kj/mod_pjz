-- Cookie Express : shared codec
-- Item codes, line checksums and ASCII escaping shared by server, client and the host tool.
-- Every value here is part of the wire format: changing one breaks codes already sold.

CKX = CKX or {}
CKX.Codec = CKX.Codec or {}
local C = CKX.Codec

C.MAGIC   = "CKX1"
C.ALPHA   = "TF5GYDLUZXWH2JS7C6E9A8Q4VKMRP3BN"
C.SEED    = "CookieCheetah~lookchinnoi~2026~racing"
C.P1, C.B1, C.K1 = 2147483629, 40503, 1013
C.P2, C.B2, C.K2 = 1000000007, 9973, 7919
C.SUM_P   = 65521
C.HEX     = "0123456789abcdef"

local floor = math.floor
local byte  = string.byte
local sub   = string.sub

local function md(a, p)
    local r = a - floor(a / p) * p
    if r < 0 then r = r + p elseif r >= p then r = r - p end
    return r
end
C.md = md

local function lanes(s, h1, h2)
    local P1, B1, K1, P2, B2, K2 = C.P1, C.B1, C.K1, C.P2, C.B2, C.K2
    for i = 1, #s do
        local c = byte(s, i)
        h1 = md(h1 * B1 + c + K1, P1)
        h2 = md(h2 * B2 + c + K2, P2)
    end
    return h1, h2
end

local S1, S2 = lanes(C.SEED, 1, 1)

local function b32(n, width)
    local out = ""
    for _ = 1, width do
        local d = md(n, 32)
        n = floor(n / 32)
        out = sub(C.ALPHA, d + 1, d + 1) .. out
    end
    return out
end
C.b32 = b32

-- kind: "i" item fullType, "v" vehicle script fullName
function C.codeBody(kind, fullName)
    local h1, h2 = lanes(kind .. ":" .. fullName, S1, S2)
    -- finishing rounds so near-identical names get unrelated codes
    for _ = 1, 4 do
        h1 = md(h1 * C.B1 + md(h2, 65536) + C.K1, C.P1)
        h2 = md(h2 * C.B2 + md(h1, 65536) + C.K2, C.P2)
    end
    return b32(h1 * 512 + md(h2, 512), 8)
end

function C.prefixFor(kind)
    if kind == "v" then return "CV" end
    return "CX"
end

function C.codeFor(kind, fullName)
    local body = C.codeBody(kind, fullName)
    return C.prefixFor(kind) .. "-" .. sub(body, 1, 4) .. "-" .. sub(body, 5, 8)
end

-- "cx-tf5g-ydlu" / "CXTF5GYDLU" -> "i", "TF5GYDLU"
function C.parseCode(raw)
    if type(raw) ~= "string" then return nil end
    local s = ""
    local up = string.upper(raw)
    for i = 1, #up do
        local ch = sub(up, i, i)
        if ch ~= "-" and ch ~= " " then s = s .. ch end
    end
    if #s ~= 10 then return nil end
    local pre = sub(s, 1, 2)
    local kind = nil
    if pre == "CX" then kind = "i" elseif pre == "CV" then kind = "v" else return nil end
    local body = sub(s, 3, 10)
    for i = 1, 8 do
        if not string.find(C.ALPHA, sub(body, i, i), 1, true) then return nil end
    end
    return kind, body
end

function C.pretty(kind, body)
    return C.prefixFor(kind) .. "-" .. sub(body, 1, 4) .. "-" .. sub(body, 5, 8)
end

function C.lineSum(s)
    local a = 7
    for i = 1, #s do
        a = md(a * 33 + byte(s, i) + 42, C.SUM_P)
    end
    return b32(a, 4)
end

local function hex4(c)
    local out = ""
    for _ = 1, 4 do
        local d = md(c, 16)
        c = floor(c / 16)
        out = sub(C.HEX, d + 1, d + 1) .. out
    end
    return out
end

-- keep files pure ASCII: non-ASCII and separators become ~xxxx (UTF-16 code unit)
function C.escape(s)
    s = tostring(s or "")
    local parts, n = {}, 0
    for i = 1, #s do
        local c = byte(s, i)
        n = n + 1
        if c < 32 or c > 126 or c == 124 or c == 59 or c == 42 or c == 126 then
            parts[n] = "~" .. hex4(c)
        else
            parts[n] = sub(s, i, i)
        end
    end
    return table.concat(parts)
end

function C.unescape(s)
    s = tostring(s or "")
    local parts, n, i, len = {}, 0, 1, #s
    while i <= len do
        local ch = sub(s, i, i)
        if ch == "~" and i + 4 <= len then
            local v = tonumber(sub(s, i + 1, i + 4), 16)
            if v then
                n = n + 1; parts[n] = string.char(v); i = i + 5
            else
                n = n + 1; parts[n] = ch; i = i + 1
            end
        else
            n = n + 1; parts[n] = ch; i = i + 1
        end
    end
    return table.concat(parts)
end

function C.split(s, sep)
    local out, n, init = {}, 0, 1
    while true do
        local a = string.find(s, sep, init, true)
        n = n + 1
        if not a then
            out[n] = sub(s, init)
            return out, n
        end
        out[n] = sub(s, init, a - 1)
        init = a + #sep
    end
end

function C.trim(s)
    s = tostring(s or "")
    local a, b = 1, #s
    while a <= b and (sub(s, a, a) == " " or sub(s, a, a) == "\t" or sub(s, a, a) == "\r") do a = a + 1 end
    while b >= a and (sub(s, b, b) == " " or sub(s, b, b) == "\t" or sub(s, b, b) == "\r") do b = b - 1 end
    return sub(s, a, b)
end

-- "CX-AAAA-BBBB*2;CV-CCCC-DDDD" -> { {kind, body, n}, ... } or nil, reason
function C.parseItems(field)
    local list = {}
    local parts, n = C.split(field or "", ";")
    for i = 1, n do
        local p = C.trim(parts[i])
        if p ~= "" then
            local codeRaw, count = p, 1
            local star = string.find(p, "*", 1, true)
            if star then
                codeRaw = sub(p, 1, star - 1)
                count = tonumber(C.trim(sub(p, star + 1)))
            end
            if not count or count < 1 or count > 999 or count ~= floor(count) then
                return nil, "bad count in " .. p
            end
            local kind, body = C.parseCode(codeRaw)
            if not kind then return nil, "bad code " .. p end
            list[#list + 1] = { kind = kind, body = body, n = count }
        end
    end
    if #list == 0 then return nil, "no items" end
    return list
end

-- returns order table, or nil + reason ("partial" = checksum missing/mismatch, try again later)
function C.parseInboxLine(line)
    line = C.trim(line)
    if line == "" or sub(line, 1, 1) == "#" then return nil, "skip" end
    local f, n = C.split(line, "|")
    if n ~= 6 or f[1] ~= C.MAGIC then return nil, "partial" end
    local head = sub(line, 1, #line - #f[6] - 1)
    if C.lineSum(head) ~= f[6] then return nil, "partial" end
    local id = f[2]
    if id == "" or #id > 48 then return nil, "bad order id" end
    for i = 1, #id do
        local c = byte(id, i)
        local ok = (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 45 or c == 95 or c == 46
        if not ok then return nil, "bad order id" end
    end
    local o = { id = id, userKey = string.lower(f[3]), user = C.unescape(f[3]), note = C.unescape(f[5]) }  -- A-Z only; ~xxxx hex is already lower
    if f[3] == "" then return nil, "no user" end
    if f[4] == "!CANCEL" then
        o.cancel = true
        return o
    end
    local items, why = C.parseItems(f[4])
    if not items then return nil, why end
    o.items = items
    return o
end

function C.makeLine(fields)
    local head = C.MAGIC .. "|" .. table.concat(fields, "|")
    return head .. "|" .. C.lineSum(head)
end
