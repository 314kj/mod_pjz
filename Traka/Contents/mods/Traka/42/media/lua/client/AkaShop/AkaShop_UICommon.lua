--[[===========================================================================
    AkaShop - small shared UI helpers used by all three windows.
============================================================================]]

require "ISUI/ISPanel"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISModalDialog"

AkaShopUI = AkaShopUI or {}

AkaShopUI.PAD  = 10

--- Everything steps up one size. Small was chosen when the windows were narrow
--- and it reads like fine print on a 1440p monitor across a room, which is
--- where this game is usually played. Medium is the new body font and Large
--- carries prices and window titles; every window below is widened to match,
--- because the fastest way to make a UI look broken is to grow the type and
--- leave the boxes the same size.
AkaShopUI.ROW      = 26
AkaShopUI.FONT     = UIFont.Medium
AkaShopUI.FONT_BIG = UIFont.Large

--[[ Dark grey theme.
     Everything is a neutral grey so the coloured text carries the meaning, and
     the greys are spaced far enough apart to stay legible on a dim monitor:
     body text #E6E9EB on window #1A1D1F is roughly 13:1 contrast, the dimmest
     label #A0A5AA on the lightest surface #2E3236 still clears 6:1. Colour is
     used only for money, stock and errors, never as the only cue. ]]
AkaShopUI.THEME = {
    window  = { r = 0.102, g = 0.114, b = 0.122, a = 0.96 },  -- #1A1D1F
    panel   = { r = 0.145, g = 0.157, b = 0.169, a = 0.94 },  -- #25282B
    border  = { r = 0.345, g = 0.365, b = 0.384, a = 0.90 },  -- #585D62
    button  = { r = 0.180, g = 0.196, b = 0.212, a = 0.96 },  -- #2E3236
    buttonOver = { r = 0.275, g = 0.302, b = 0.329, a = 1.0 },
    buttonOn   = { r = 0.192, g = 0.310, b = 0.427, a = 1.0 },-- active tab
    rowSel  = { a = 0.55, r = 0.192, g = 0.310, b = 0.427 },
    rowAlt  = { a = 0.05, r = 1, g = 1, b = 1 },
    rowLine = { a = 0.28, r = 0.45, g = 0.47, b = 0.49 },
}

-- text colours, as plain r,g,b triples
local T = {
    text   = { 0.902, 0.914, 0.922 },   -- #E6E9EB  body
    dim    = { 0.627, 0.647, 0.667 },   -- #A0A5AA  secondary
    money  = { 0.960, 0.800, 0.420 },   -- amber
    good   = { 0.545, 0.851, 0.600 },   -- in stock / today
    bad    = { 0.925, 0.522, 0.522 },   -- out of stock / closed
    who    = { 0.694, 0.788, 0.922 },   -- player names
    title  = { 0.980, 0.980, 0.980 },
}
AkaShopUI.C = T

function AkaShopUI.label(parent, x, y, text, colour, font)
    colour = colour or T.text
    local l = ISLabel:new(x, y, 22, text, colour[1], colour[2], colour[3], 1,
                          font or AkaShopUI.FONT, true)
    l:initialise()
    l:instantiate()
    parent:addChild(l)
    return l
end

function AkaShopUI.button(parent, x, y, w, h, text, target, fn, internal)
    local th = AkaShopUI.THEME
    local b = ISButton:new(x, y, w, h, text, target, fn)
    b.internal = internal or text
    b:initialise()
    b:instantiate()
    b.backgroundColor          = { r = th.button.r, g = th.button.g, b = th.button.b, a = th.button.a }
    b.backgroundColorMouseOver = th.buttonOver
    b.borderColor              = th.border
    b.textColor                = { r = T.text[1], g = T.text[2], b = T.text[3], a = 1 }
    parent:addChild(b)
    return b
end

function AkaShopUI.setButtonActive(b, on)
    local th = AkaShopUI.THEME
    if on then
        b.backgroundColor = { r = th.buttonOn.r, g = th.buttonOn.g, b = th.buttonOn.b, a = 1 }
    else
        b.backgroundColor = { r = th.button.r, g = th.button.g, b = th.button.b, a = th.button.a }
    end
end

function AkaShopUI.entry(parent, x, y, w, h, text, numbersOnly)
    local th = AkaShopUI.THEME
    local e = ISTextEntryBox:new(text or "", x, y, w, h)
    e:initialise()
    e:instantiate()
    if numbersOnly then e:setOnlyNumbers(true) end
    e.backgroundColor = th.panel
    e.borderColor     = th.border
    parent:addChild(e)
    return e
end

function AkaShopUI.list(parent, x, y, w, h, drawFn, target)
    local th = AkaShopUI.THEME
    local lb = ISScrollingListBox:new(x, y, w, h)
    lb:initialise()
    lb:instantiate()
    lb.itemheight = AkaShopUI.ROW
    lb.selected = 0
    lb.joypadParent = parent
    lb.font = AkaShopUI.FONT
    lb.drawBorder = true
    lb.backgroundColor = th.panel
    lb.borderColor     = th.border
    lb.target = target or parent
    if drawFn then lb.doDrawItem = drawFn end
    parent:addChild(lb)
    return lb
end

--- Paint a window in the AkaShop greys. Call from the class's :new().
function AkaShopUI.skin(win)
    local th = AkaShopUI.THEME
    win.backgroundColor = { r = th.window.r, g = th.window.g, b = th.window.b, a = th.window.a }
    win.borderColor     = { r = th.border.r, g = th.border.g, b = th.border.b, a = th.border.a }
    return win
end

--- Selected data object of a list box, or nil.
function AkaShopUI.selected(lb)
    if not lb or not lb.items then return nil end
    local row = lb.items[lb.selected]
    return row and row.item or nil
end

function AkaShopUI.num(entry, default)
    if not entry then return default end
    local v = tonumber(entry:getInternalText())
    if not v then return default end
    return math.floor(v)
end

function AkaShopUI.setNum(entry, v)
    if entry then entry:setText(tostring(math.floor(v or 0))) end
end

--- Generic column row painter. cols = { {text=, x=, c=<colour triple>} , ... }
--- NOTE drawRect/drawRectBorder take (x, y, w, h, ALPHA, r, g, b).
function AkaShopUI.drawColumns(lb, y, item, alt, cols)
    local th = AkaShopUI.THEME
    local h  = item.height or AkaShopUI.ROW
    local w  = lb:getWidth()
    if lb.selected == item.index then
        lb:drawRect(0, y, w, h - 1, th.rowSel.a, th.rowSel.r, th.rowSel.g, th.rowSel.b)
    elseif alt then
        lb:drawRect(0, y, w, h - 1, th.rowAlt.a, th.rowAlt.r, th.rowAlt.g, th.rowAlt.b)
    end
    lb:drawRectBorder(0, y, w, h, th.rowLine.a, th.rowLine.r, th.rowLine.g, th.rowLine.b)
    local ty = y + 3
    for i = 1, #cols do
        local col = cols[i]
        local c = col.c or T.text
        lb:drawText(tostring(col.text), col.x, ty, c[1], c[2], c[3], 1, AkaShopUI.FONT)
    end
    return y + h
end

function AkaShopUI.confirm(text, target, fn)
    local w, h = 340, 160
    local x = (getCore():getScreenWidth() - w) / 2
    local y = (getCore():getScreenHeight() - h) / 2
    local m = ISModalDialog:new(x, y, w, h, text, true, target,
        function(tgt, button)
            if button and button.internal == "YES" then fn(tgt) end
        end)
    m:initialise()
    m:addToUIManager()
    return m
end

--============================================== what the player is carrying ==
--[[ ONE walk of the inventory, indexed by fullType, cached for a fraction of a
     second and shared by every window.

     THE BUG THIS EXISTS TO FIX (v3.5.2). A depot card can be a PACK - one row
     standing for every kind of ring on the server. Working out "how many of
     this pack am I carrying" used to mean one full inventory walk PER MEMBER
     TYPE, and that number ran to dozens. The rail recomputed it ten times a
     second, and each walk asked the character what it was wearing once per
     item examined. Three multiplications stacked on top of each other:
     members x items x worn-slots, at 10Hz. A player with a bag of jewellery
     standing in front of a buying counter was doing millions of guarded calls
     a second, and their frame rate said so.

     Now: one walk, bucketed by fullType, answered from a table. Everything
     downstream - counts, the wallet, the pack picker, the deposit list - reads
     that table. Nothing walks the inventory to answer a question about a
     number on screen.

     The cache is deliberately short-lived rather than event-driven. Items
     arrive in a player's bag by a hundred routes this mod never sees, so a
     timestamp that expires is honest where a subscription would quietly go
     stale. Anything this mod does itself that moves an item calls dirty() and
     gets an instant rebuild. ]]

local STOCK_TTL = 1000          -- ms
local stockIdx, stockAt, packMemo = nil, -100000, {}

local function nowMs()
    local t
    if pcall(function() t = getTimestampMs() end) and type(t) == "number" then return t end
    if pcall(function() t = getTimestamp() end) and type(t) == "number" then return t * 1000 end
    return 0
end

--- Throw the index away. Call this after anything that moves items in or out
--- of the player, so the next read is fresh instead of up to half a second old.
function AkaShopUI.stockDirty()
    stockIdx, packMemo = nil, {}
end

--- { byFt = { [ft] = { ft=, name=, n=, items={...} } }, wallet = n, total = n }
function AkaShopUI.stock()
    local now = nowMs()
    if stockIdx and (now - stockAt) < STOCK_TTL then return stockIdx end

    local idx = { byFt = {}, wallet = 0, total = 0 }
    local pl  = AkaShopClient.me()
    if pl then
        local currency = AkaShop.getCurrency()
        local inv
        pcall(function() inv = pl:getInventory() end)
        local items = inv and AkaShop.collectItems(inv, nil, nil, pl) or {}
        for i = 1, #items do
            local it = items[i]
            local ft = it:getFullType()
            local rec = idx.byFt[ft]
            if not rec then
                rec = { ft = ft, name = it:getDisplayName() or ft, n = 0, items = {} }
                idx.byFt[ft] = rec
            end
            rec.n = rec.n + 1
            rec.items[rec.n] = it
            idx.total = idx.total + 1
            if ft == currency then idx.wallet = idx.wallet + 1 end
        end
    end

    stockIdx, stockAt, packMemo = idx, now, {}
    return idx
end

function AkaShopUI.stockCount(ft)
    if not ft then return 0 end
    local rec = AkaShopUI.stock().byFt[ft]
    return rec and rec.n or 0
end

--- How many of a PACK the player is carrying, and which member type should be
--- handed over first - the worst-condition one, because somebody at a
--- buy-back counter wants to dump their junk, not have the machine take the
--- good ring and leave them the scrap.
---
--- Reading condition is seven guarded getter calls per item, so the answer is
--- memoised for the life of the index rather than recomputed per frame.
function AkaShopUI.packCarry(packId)
    if not packId then return 0, nil end
    local idx  = AkaShopUI.stock()
    local memo = packMemo[packId]
    if memo then return memo.n, memo.ft end

    local total, bestFt, bestWear = 0, nil, nil
    for _, ft in ipairs(AkaShopPacks.members(packId)) do
        local rec = idx.byFt[ft]
        if rec then
            total = total + rec.n
            for i = 1, rec.n do
                local w = 1
                pcall(function()
                    w = AkaShopStock.wear(AkaShopStock.stateOf(rec.items[i])) or 1
                end)
                -- higher wear = more ruined = goes first
                if bestWear == nil or w > bestWear then bestWear, bestFt = w, ft end
            end
        end
    end

    packMemo[packId] = { n = total, ft = bestFt }
    return total, bestFt
end

--- Aggregate what the player is carrying: { {ft=, name=, count=}, ... }
--- Uses exactly the same "sellable" rule as the server, so the counts shown
--- here are the counts the server will accept.
function AkaShopUI.playerStock()
    local out = {}
    local currency = AkaShop.getCurrency()
    for ft, rec in pairs(AkaShopUI.stock().byFt) do
        if ft ~= currency then
            table.insert(out, { ft = ft, name = rec.name, count = rec.n })
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

--=================================================== two-language name box ==
-- A shop carries an English and a Thai name, so registering or renaming one
-- needs two fields; the vanilla ISTextBox only offers one.

AkaShopNameDialog = ISPanel:derive("AkaShopNameDialog")

function AkaShopNameDialog:new(titleText, defEN, defTH, onOk)
    local w, h = 430, 216
    local x = (getCore():getScreenWidth() - w) / 2
    local y = (getCore():getScreenHeight() - h) / 2
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.titleText = titleText or "Shop name"
    o.defEN = defEN or ""
    o.defTH = defTH or ""
    o.onOk = onOk
    o.moveWithMouse = true
    AkaShopUI.skin(o)
    return o
end

function AkaShopNameDialog:createChildren()
    ISPanel.createChildren(self)
    local C = AkaShopUI.C
    AkaShopUI.label(self, 14, 12, self.titleText, C.title)

    AkaShopUI.label(self, 14, 52, "Name (Thai)", C.text)
    self.eTH = AkaShopUI.entry(self, 132, 48, 282, 22, self.defTH, false)
    AkaShopUI.label(self, 14, 84, "Name (English)", C.text)
    self.eEN = AkaShopUI.entry(self, 132, 80, 282, 22, self.defEN, false)

    AkaShopUI.label(self, 14, 114,
        "Shown everywhere as \"Thai / English\". Either field may be", C.dim)
    AkaShopUI.label(self, 14, 132,
        "left blank, in which case only the other one is used.", C.dim)

    AkaShopUI.button(self, 14, 168, 190, 26, "OK", self, self.onAccept)
    AkaShopUI.button(self, 226, 168, 190, 26, "Cancel", self, self.onCancel)
end

function AkaShopNameDialog:onAccept()
    local en = self.eEN:getInternalText()
    local th = self.eTH:getInternalText()
    self:removeFromUIManager()
    if self.onOk then self.onOk(en, th) end
end

function AkaShopNameDialog:onCancel()
    self:removeFromUIManager()
end

--- Ask for both shop names. onOk(englishName, thaiName)
function AkaShopUI.askNames(title, defEN, defTH, onOk)
    local d = AkaShopNameDialog:new(title, defEN, defTH, onOk)
    d:initialise()
    d:instantiate()
    d:addToUIManager()
    pcall(function() d.eEN:focus() end)
    return d
end

function AkaShopUI.walletOf()
    return AkaShopUI.stock().wallet
end


--============================================ v3 widgets (centred header, +/-)

--- Centre a label inside `w`. ISLabel has no centring of its own, so the width
--- is measured and the x recomputed; call again after the text changes.
function AkaShopUI.centre(lbl, w)
    if not lbl then return end
    local tw = 0
    pcall(function() tw = getTextManager():MeasureStringX(AkaShopUI.FONT, lbl.name or "") end)
    lbl:setX(math.floor((w - tw) / 2))
end

--- Item textures are looked up once per fullType and cached forever. Calling
--- instanceItem() to fetch an icon would build and throw away a real item on
--- every frame of every row, which is the single easiest way to make a shop
--- window stutter.
--============================================================== item art ====
--[[ A REAL Texture for an item type, or nil. Never anything else.

     THE BUG (v3.7.3). `Item:getIcon()` returns the icon's NAME - a string - and
     it was being used as a fallback for getNormalTexture(). The string then
     travelled all the way to drawTextureScaledAspect, which is a Java method
     with a typed signature, so the picker threw

         expected argument of type Texture, got String

     once per visible row per frame. Caught by the UI's own pcall, so nothing
     crashed; it just filled console.txt and cost a frame's worth of exception
     building eight times over.

     The lesson worth keeping: a getter called getIcon does not have to return an
     icon. Check what a Java accessor actually hands back rather than trusting
     its name - and make the function that wraps it promise ONE type, so no
     caller has to wonder.

     The name still has value: PZ keeps item art at media/textures/Item_<name>,
     so the name can be turned into a texture. That is a lookup, not a cast. ]]

local texCache = {}

local function resolveTexture(ft)
    local si
    if not pcall(function() si = getScriptManager():FindItem(ft) end) then return nil end
    if not si then return nil end

    -- The real thing, when the build has it.
    local tex
    if type(si.getNormalTexture) == "function" then
        pcall(function() tex = si:getNormalTexture() end)
    end
    if tex ~= nil and type(tex) ~= "string" then return tex end

    -- Otherwise a NAME, which has to be looked up before anybody can draw it.
    local name
    if type(si.getIcon) == "function" then
        pcall(function() name = si:getIcon() end)
    end
    if type(name) ~= "string" or name == "" then return nil end

    local t
    pcall(function() t = getTexture("Item_" .. name) end)
    if t == nil then pcall(function() t = getTexture(name) end) end
    if type(t) == "string" then return nil end
    return t
end

function AkaShopUI.itemTexture(ft)
    if not ft then return nil end
    local hit = texCache[ft]
    if hit ~= nil then return hit or nil end
    local tex = resolveTexture(ft)
    -- A miss is cached as false: an item type with no art must not be looked up
    -- again on every frame it is on screen.
    texCache[ft] = tex or false
    return tex
end

--- Draw an item's picture, or draw nothing. The ONLY place this mod hands a
--- texture to the engine, so the "must be a Texture" rule is enforced once
--- instead of at three call sites that each have to remember it.
--- `stretch` fills the box exactly instead of preserving the picture's shape;
--- the shop list wants that, the cards do not.
function AkaShopUI.drawItemIcon(ui, ft, x, y, w, h, stretch)
    if not (ui and ft) then return false end
    local tex = AkaShopUI.itemTexture(ft)
    if tex == nil or type(tex) == "string" then return false end
    local ok = pcall(function()
        if stretch then ui:drawTextureScaled(tex, x, y, w, h, 1, 1, 1, 1)
        else            ui:drawTextureScaledAspect(tex, x, y, w, h, 1, 1, 1, 1) end
    end)
    if not ok then texCache[ft] = false end     -- never try that one again
    return ok
end

--- Wear 0..1 -> a colour triple, matching the mockup's green / amber / red.
function AkaShopUI.wearColour(w)
    w = w or 0
    if w <= 0.001 then return T.good end
    if w < 0.45 then return { 0.859, 0.706, 0.416 } end
    return T.bad
end

--- A small horizontal bar, used for condition and for the weight quota.
function AkaShopUI.bar(lb, x, y, w, h, frac, col)
    frac = math.max(0, math.min(1, frac or 0))
    lb:drawRect(x, y, w, h, 0.5, 0.16, 0.17, 0.19)
    if frac > 0 then
        lb:drawRect(x, y, math.floor(w * frac), h, 0.95, col[1], col[2], col[3])
    end
    lb:drawRectBorder(x, y, w, h, 0.5, 0.28, 0.30, 0.32)
end

--- Row of [-] [n] [+] used instead of a quantity text box. Returns the two
--- buttons so the caller can enable/disable them.
function AkaShopUI.stepper(parent, x, y, target, onMinus, onPlus)
    local minus = AkaShopUI.button(parent, x,      y, 22, 22, "-", target, onMinus)
    local plus  = AkaShopUI.button(parent, x + 62, y, 22, 22, "+", target, onPlus)
    return minus, plus
end
