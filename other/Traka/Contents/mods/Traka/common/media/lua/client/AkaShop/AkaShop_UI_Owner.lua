--[[===========================================================================
    Traka - "who owns this shop?"

    An admin setting up a shop FOR somebody had no way to say who that somebody
    was. The register call quietly used whoever pressed the button, so every
    shop an admin made for a player belonged to the admin, and the player it
    was for could not price a single item in it.

    The server had always accepted an owner - AkaShopCore.register takes one -
    the client just never asked. This window is the missing question.

    It serves two moments that are really the same question:
      - creating a shop:   who should own it
      - an existing shop:  who should own it now

    Ownership can only be handed to somebody ONLINE. That is a deliberate
    limit, not a shortcut: a typed name is how the Staff box used to work and
    it is exactly why it "did not work" - one wrong character and you have
    given a shop, its stock and its till to nobody at all, with no error to
    tell you so.
============================================================================]]

require "ISUI/ISCollapsableWindow"

AkaShopOwnerPick = ISCollapsableWindow:derive("AkaShopOwnerPick")
AkaShopOwnerPick.instance = nil

--- `onPick(username)` is called with the chosen name. Everything about what
--- happens next belongs to the caller - this window only answers "who".
function AkaShopOwnerPick.open(title, onPick, opts)
    opts = opts or {}
    local w, h = 460, 380
    local o = AkaShopOwnerPick:new((getCore():getScreenWidth() - w) / 2,
                                   (getCore():getScreenHeight() - h) / 2, w, h)
    o.title   = title or "Who owns this shop?"
    o.onPick  = onPick
    o.allowMe = opts.allowMe ~= false        -- default: "me" is a valid answer
    o.note    = opts.note
    o:initialise(); o:addToUIManager()
    AkaShopOwnerPick.instance = o
    -- Ask immediately. The list is empty for the fraction of a second it takes
    -- the server to answer, which is why there is a placeholder row below
    -- rather than a window that looks broken on open.
    AkaShopClient.send("whoOnline", opts.query or { mode = "owner" })
    return o
end

function AkaShopOwnerPick:new(x, y, w, h)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    setmetatable(o, self); self.__index = self
    AkaShopUI.skin(o)
    o:setResizable(false)
    return o
end

local function drawRow(lb, y, item, alt)
    local d = item.item
    local far
    if d.me then                    far = "you"
    elseif (d.dist or -1) < 0 then  far = ""
    elseif d.dist < 1000 then       far = d.dist .. " tiles"
    else                            far = string.format("%.1f km", d.dist / 1000) end
    return AkaShopUI.drawColumns(lb, y, item, alt, {
        { text = d.user or "?", x = 8,
          c = d.me and AkaShopUI.C.dim or AkaShopUI.C.who },
        { text = far, x = lb:getWidth() - 110,
          c = (d.dist or 9999) <= 20 and AkaShopUI.C.good or AkaShopUI.C.dim },
    })
end

function AkaShopOwnerPick:createChildren()
    ISCollapsableWindow.createChildren(self)
    local th = self:titleBarHeight()

    AkaShopUI.label(self, 12, th + 8,
        self.note or "Only players who are online can be given a shop.",
        AkaShopUI.C.dim)

    self.lb = AkaShopUI.list(self, 12, th + 32, self:getWidth() - 24,
                             self:getHeight() - th - 84, drawRow, self)
    self.lb.itemheight = 26
    self.lb.ondblclick = AkaShopOwnerPick.onDouble
    self.lb.target = self
    self:fill({})

    AkaShopUI.button(self, 12, self:getHeight() - 40, 150, 28, "Refresh",
                     self, AkaShopOwnerPick.onRefresh, "OwnRefresh")
    AkaShopUI.button(self, self:getWidth() - 300, self:getHeight() - 40, 140, 28,
                     "Choose", self, AkaShopOwnerPick.onOk, "OwnOk")
    AkaShopUI.button(self, self:getWidth() - 152, self:getHeight() - 40, 140, 28,
                     "Cancel", self, AkaShopOwnerPick.onCancel, "OwnNo")
end

function AkaShopOwnerPick:fill(players)
    local sel = AkaShopUI.selected(self.lb)
    self.lb:clear()
    if self.allowMe then
        local me = AkaShopClient.myName()
        self.lb:addItem(me, { user = me, me = true, dist = 0 })
    end
    for _, p in ipairs(players or {}) do
        self.lb:addItem(p.user, p)
    end
    if #(self.lb.items or {}) == 0 then
        self.lb:addItem("-", { user = "waiting for the server...", dist = -1, none = true })
    end
    if sel then
        for i, r in ipairs(self.lb.items or {}) do
            if r.item and r.item.user == sel.user then self.lb.selected = i end
        end
    end
end

function AkaShopOwnerPick:onRefresh()
    AkaShopClient.send("whoOnline", { mode = "owner" })
end

function AkaShopOwnerPick.onDouble(target, item)
    if target then target:take(item) end
end

function AkaShopOwnerPick:onOk()
    self:take(AkaShopUI.selected(self.lb))
end

function AkaShopOwnerPick:take(p)
    if not p or p.none then
        return AkaShopClient.notify("Pick a player from the list first.", true)
    end
    local fn = self.onPick
    self:onCancel()
    if fn then fn(p.user) end
end

function AkaShopOwnerPick:onCancel()
    if AkaShopOwnerPick.instance == self then AkaShopOwnerPick.instance = nil end
    self:setVisible(false); self:removeFromUIManager()
end
