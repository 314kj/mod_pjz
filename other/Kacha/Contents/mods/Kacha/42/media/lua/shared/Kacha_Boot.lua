--[[ ============================================================
     Kacha B42 [MP]  -  bootstrap / build utils   by PIE

     Internal build + integrity helpers. Loaded before everything
     else (shared). Several values here are combined with fragments
     scattered through the other files; if any are removed or
     altered the build id printed at start no longer matches, which
     is how unofficial / tampered copies are spotted.
   ============================================================ ]]

Kacha = Kacha or {}

Kacha.__frag  = Kacha.__frag or {}
Kacha.__files = Kacha.__files or {}

if not Kacha.__feed then function Kacha.__feed(i, v) Kacha.__frag[i] = v end end
if not Kacha.__mark then function Kacha.__mark(n) Kacha.__files[n] = true end end

function Kacha.__h(s)
    local x = 5381
    for i = 1, #s do x = (x * 33 + string.byte(s, i)) % 2147483647 end
    return x
end

-- origin token assembled from byte values (not a plaintext string)
function Kacha.__tok()
    local c = { 80, 73, 69, 47, 47, 65, 75, 65, 45, 75, 65, 67, 72, 65, 45, 50, 48, 50, 54 }
    local s = ""
    for _, b in ipairs(c) do s = s .. string.char(b) end
    return s
end

-- canonical seal: shared fragments (1,2) + token. identical on client & server.
function Kacha.__seal()
    local base = (Kacha.__frag[1] or 0) * 131 + (Kacha.__frag[2] or 0)
    return (base + Kacha.__h(Kacha.__tok())) % 2147483647
end

-- short stamp written into every placed machine's saved data
function Kacha.__originTag()
    return "KX" .. tostring(Kacha.__seal())
end

Kacha.__EXPECT = 1351651292   -- canonical build id (do not rely on a single point)

-- self check: seal must match AND all expected file-marks must be present.
-- logs a build id that looks mundane; a tampered build prints a different id.
function Kacha.__selfCheck(scope, needFiles)
    local seal = Kacha.__seal()
    local ok = (seal == Kacha.__EXPECT)
    for _, n in ipairs(needFiles) do if not Kacha.__files[n] then ok = false end end
    if ok then
        print("[Kacha] " .. scope .. " ready b" .. seal)
    else
        print("[Kacha] " .. scope .. " ready b" .. seal .. " r" .. Kacha.__h(Kacha.__tok()))
    end
end

Kacha.__feed(1, 65)
Kacha.__mark("boot")
