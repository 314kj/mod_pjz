--[[ Akacamp shared constants & helpers ]]
Akacamp = Akacamp or {}

Akacamp.SIZES = { "small", "medium", "large", "extra" }
Akacamp.KIT_OF = { small="Akacamp.TentKitSmall", medium="Akacamp.TentKitMedium",
                   large="Akacamp.TentKitLarge", extra="Akacamp.TentKitExtra" }
Akacamp.SIZE_OF_KIT = { TentKitSmall="small", TentKitMedium="medium",
                        TentKitLarge="large", TentKitExtra="extra" }

-- staff whitelist (B42 getAccessLevel returns lowercase; never compare to "None")
Akacamp.STAFF = { admin=true, moderator=true, gm=true }
function Akacamp.isStaff(player)
    if not player then return false end
    local lvl = player.getAccessLevel and player:getAccessLevel()
    if not lvl then return false end
    return Akacamp.STAFF[tostring(lvl):lower()] == true
end

function Akacamp.newKitId()
    return "aka_" .. tostring(ZombRand(2000000000)) .. "_" .. tostring(getTimestampMs() % 1000000)
end

-- default canvas->zip recipe (admin-configurable)
Akacamp.DEFAULT_RECIPE = { { item = "Base.Twine", count = 2 } }

-- per-size zipper tint (r,g,b 0..1) so sizes are visually distinct
Akacamp.ZIP_COLOR = {
    small  = { 0.45, 0.90, 0.45 },   -- green
    medium = { 0.45, 0.65, 1.00 },   -- blue
    large  = { 1.00, 0.60, 0.20 },   -- orange
    extra  = { 0.95, 0.45, 0.95 },   -- magenta
}

-- ---- overworld tent tiles (camp_hf) -------------------------------------
-- 5 sprites per size: corner (SpriteGridPos 3,0) + front row (0,1 1,1 2,1 3,1).
-- mod.info: tiledef=camp_hf 336  +  pack=camp_hf_pack
Akacamp.TENT_SPRITES = {
    small  = { "camp_hf_19",  "camp_hf_20",  "camp_hf_21",  "camp_hf_22",  "camp_hf_23"  },
    medium = { "camp_hf_51",  "camp_hf_52",  "camp_hf_53",  "camp_hf_54",  "camp_hf_55"  },
    large  = { "camp_hf_83",  "camp_hf_84",  "camp_hf_85",  "camp_hf_86",  "camp_hf_87"  },
    extra  = { "camp_hf_115", "camp_hf_116", "camp_hf_117", "camp_hf_118", "camp_hf_119" },
}
Akacamp.TENT_CUSTOMNAME = "hf_tent"   -- matches CustomName in camp_hf.tiles

-- the moveable item (rolled-tent icon) the player places for each size
Akacamp.MOVEABLE_OF = {
    small = "Base.HFTentSmall", medium = "Base.HFTentMedium",
    large = "Base.HFTentLarge", extra = "Base.HFTentExtra",
}

-- reverse: a camp_hf sprite name -> size
Akacamp._SPRITE_SIZE = nil
function Akacamp.sizeOfSprite(name)
    if not name then return nil end
    if not Akacamp._SPRITE_SIZE then
        Akacamp._SPRITE_SIZE = {}
        for sz, list in pairs(Akacamp.TENT_SPRITES) do
            for _, sp in ipairs(list) do Akacamp._SPRITE_SIZE[sp] = sz end
        end
    end
    return Akacamp._SPRITE_SIZE[name]
end

-- true if an IsoObject is one of our pitched tent tiles; also yields its size
function Akacamp.isTentObject(o)
    if not o then return false end
    -- vanilla method first: IsoObject:isTent() (works for any real tent)
    if o.isTent then local ok,res = pcall(function() return o:isTent() end); if ok and res then return true end end
    local md = o.getModData and o:getModData()
    if md and md.AkacampTent then return true end
    local spr = o.getSprite and o:getSprite()
    local nm  = spr and spr.getName and spr:getName()
    return nm ~= nil and string.find(nm, "camp_hf_") ~= nil
end
function Akacamp.tentSizeOf(o)
    local spr = o and o.getSprite and o:getSprite()
    local nm  = spr and spr.getName and spr:getName()
    return Akacamp.sizeOfSprite(nm)
end
