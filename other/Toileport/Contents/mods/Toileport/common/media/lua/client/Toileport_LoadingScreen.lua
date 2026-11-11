--[[ ============================================================
  TOILEPORT  [MP]  --  loading screen overlay           KACHASIG
  A full-screen image shown for SandboxVars.Toileport.LoadingSeconds
  while the warp happens, then the onDone callback (the teleport)
  fires and the overlay removes itself.
  Image: media/textures/Toileport_Loading.png (replace freely).
============================================================ ]]

require "ISUI/ISUIElement"

Toileport = Toileport or {}
local TP = Toileport

ToileportLoading = ISUIElement:derive("ToileportLoading")

-- texture name resolution differs by folder/registration, so try a few.
local function resolveLoadingTex()
    local names = {
        "media/ui/Toileport_Loading.png",
        "media/textures/Toileport_Loading.png",
        "Toileport_Loading",
    }
    for _, n in ipairs(names) do
        local t = getTexture(n)
        if t then return t end
    end
    return nil
end

function ToileportLoading:new()
    local core = getCore()
    local w = core:getScreenWidth()
    local h = core:getScreenHeight()
    local o = ISUIElement:new(0, 0, w, h)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 1 }
    o.tex   = resolveLoadingTex()
    o.endMs = 0
    o.fired = false
    o.onDone = nil
    return o
end

function ToileportLoading:render()
    local w, h = self:getWidth(), self:getHeight()
    -- opaque black backdrop (drawRect is alpha-first: a,r,g,b)
    self:drawRect(0, 0, w, h, 1.0, 0, 0, 0)
    if self.tex then
        self:drawTextureScaled(self.tex, 0, 0, w, h, 1.0, 1.0, 1.0, 1.0)
    else
        -- fallback so the screen is never blank if the image fails to load
        local txt = "Flushing..."
        local tw = getTextManager():MeasureStringX(UIFont.Large, txt)
        self:drawText(txt, w * 0.5 - tw * 0.5, h * 0.5 - 16, 0.24, 0.50, 0.77, 1.0, UIFont.Large)
    end
end

function ToileportLoading:update()
    if self.fired then return end
    if getTimestampMs() >= self.endMs then
        self.fired = true
        local cb = self.onDone
        self:setVisible(false)
        self:removeFromUIManager()
        if cb then pcall(cb) end
    end
end

-- show the overlay for `seconds`, then run onDone()
function TP.showLoading(seconds, onDone)
    seconds = tonumber(seconds) or TP.getLoadingSeconds()
    pcall(function() TP.playFlush(getPlayer()) end)
    -- 0 seconds => skip overlay, run immediately
    if seconds <= 0 then
        if onDone then pcall(onDone) end
        return
    end
    local ui = ToileportLoading:new()
    ui:initialise()
    ui:instantiate()
    ui.endMs  = getTimestampMs() + (seconds * 1000)
    ui.onDone = onDone
    ui:addToUIManager()
    if ui.setAlwaysOnTop then pcall(function() ui:setAlwaysOnTop(true) end) end
    if ui.bringToTop then pcall(function() ui:bringToTop() end) end
end
