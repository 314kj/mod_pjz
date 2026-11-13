-- Cookie Exchange : the small wallet window (opened from the character screen)
-- Send money to a player who is online, or withdraw as bills (biggest bill first).

require "CookieExchange/CX_Const"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"

CXWalletWindow = ISPanel:derive("CXWalletWindow")

local FONT_S = getTextManager():getFontHeight(UIFont.Small)
local FONT_M = getTextManager():getFontHeight(UIFont.Medium)
local ROW = math.max(FONT_S + 10, 26)
local PAD = 12
local W = 330

local function T(key, ...) return getText(key, ...) end

local function numberOf(entry)
    local s = entry and entry:getText() or ""
    s = string.gsub(s, "[^%d]", "")
    local v = tonumber(s)
    if not v then return nil end
    return math.floor(v)
end

function CXWalletWindow:createChildren()
    ISPanel.createChildren(self)
    local y = PAD + FONT_M + 10

    self.closeBtn = ISButton:new(self.width - PAD - 24, PAD - 2, 24, 22, "X", self, CXWalletWindow.close)
    self.closeBtn:initialise()
    self:addChild(self.closeBtn)

    self.sendY = y
    y = y + FONT_S + 6
    self.who = ISComboBox:new(PAD, y, 150, ROW, self, nil)
    self.who:initialise()
    self:addChild(self.who)
    self.sendAmt = ISTextEntryBox:new("", PAD + 156, y, 80, ROW)
    self.sendAmt:initialise()
    self.sendAmt:instantiate()
    self.sendAmt:setOnlyNumbers(true)
    self:addChild(self.sendAmt)
    self.sendBtn = ISButton:new(PAD + 242, y, self.width - PAD * 2 - 242, ROW, T("IGUI_CX_Send"), self, CXWalletWindow.onSend)
    self.sendBtn:initialise()
    self:addChild(self.sendBtn)
    y = y + ROW + 14

    self.drawY = y
    y = y + FONT_S + 6
    self.drawAmt = ISTextEntryBox:new("", PAD, y, 236, ROW)
    self.drawAmt:initialise()
    self.drawAmt:instantiate()
    self.drawAmt:setOnlyNumbers(true)
    self:addChild(self.drawAmt)
    self.drawBtn = ISButton:new(PAD + 242, y, self.width - PAD * 2 - 242, ROW, T("IGUI_CX_Withdraw"), self, CXWalletWindow.onWithdraw)
    self.drawBtn:initialise()
    self:addChild(self.drawBtn)
    y = y + ROW + 6

    self.previewY = y
    y = y + FONT_S + 6
    self.statusY = y
    y = y + FONT_S + PAD
    self:setHeight(y)

    self:fillPlayers()
end

function CXWalletWindow:fillPlayers()
    if not self.who then return end
    local keep = self.who:getSelectedText()
    self.who:clear()
    if #CX.players == 0 then
        self.who:addOption(T("IGUI_CX_NoOneOnline"))
        return
    end
    for _, n in ipairs(CX.players) do self.who:addOption(n) end
    if keep then self.who:selectOptionFromText(keep) end
end

function CXWalletWindow:onSend()
    local amt = numberOf(self.sendAmt)
    local to = #CX.players > 0 and self.who:getSelectedText() or nil
    if not to then CX.status = T("IGUI_CX_Res_NotOnline"); CX.statusOk = false; return end
    if not amt or amt < 1 then CX.status = T("IGUI_CX_Res_BadAmount"); CX.statusOk = false; return end
    CX.status = "..."
    sendClientCommand(getPlayer(), CX.MOD, "send", { to = to, amt = amt })
end

function CXWalletWindow:onWithdraw()
    local amt = numberOf(self.drawAmt)
    if not amt or amt < 1 then CX.status = T("IGUI_CX_Res_BadAmount"); CX.statusOk = false; return end
    CX.status = "..."
    sendClientCommand(getPlayer(), CX.MOD, "withdraw", { amt = amt })
end

-- "$1,000 x5 · $100 x3" for the amount typed in the withdraw box
local function preview(amt)
    if not amt or amt < 1 then return "" end
    local parts, pieces = CX.breakdown(amt)
    if pieces > CX.MAX_PIECES then return T("IGUI_CX_Res_TooMany") end
    local out = {}
    for i = 1, #parts do
        out[#out + 1] = CX.money(parts[i].v * 100) .. " x" .. tostring(parts[i].n)
    end
    return T("IGUI_CX_YouGet") .. " " .. table.concat(out, "  ·  ")
end

function CXWalletWindow:render()
    ISPanel.render(self)
    self:drawText(T("IGUI_CX_Title") .. "  " .. (CX.bal and CX.money(CX.bal) or "..."), PAD, PAD, 1, 0.85, 0.4, 1, UIFont.Medium)
    self:drawText(T("IGUI_CX_SendHead"), PAD, self.sendY, 1, 1, 1, 0.9, UIFont.Small)
    self:drawText(T("IGUI_CX_WithdrawHead"), PAD, self.drawY, 1, 1, 1, 0.9, UIFont.Small)
    self:drawText(preview(numberOf(self.drawAmt)), PAD, self.previewY, 0.75, 0.75, 0.75, 1, UIFont.Small)
    if CX.status then
        local g = CX.statusOk and 1 or 0.55
        self:drawText(CX.status, PAD, self.statusY, CX.statusOk and 0.55 or 1, g, 0.55, 1, UIFont.Small)
    end
end

function CXWalletWindow:close()
    self:setVisible(false)
    self:removeFromUIManager()
    CX.window = nil
end

function CXWalletWindow:new(x, y)
    local o = ISPanel:new(x, y, W, 220)
    setmetatable(o, self)
    self.__index = self
    o.moveWithMouse = true
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.85 }
    o.borderColor = { r = 1, g = 0.85, b = 0.4, a = 0.6 }
    return o
end

function CX.toggleWallet()
    if CX.window then
        CX.window:close()
        return
    end
    CX.status = nil
    local x = getCore():getScreenWidth() / 2 - W / 2
    local y = getCore():getScreenHeight() / 2 - 140
    local w = CXWalletWindow:new(x, y)
    w:initialise()
    w:addToUIManager()
    CX.window = w
    sendClientCommand(getPlayer(), CX.MOD, "players", {})
    sendClientCommand(getPlayer(), CX.MOD, "hello", {})
end
