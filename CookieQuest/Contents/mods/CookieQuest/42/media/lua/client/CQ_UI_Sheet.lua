-- Cookie Quest - mission sheet item: parchment reader + inventory context menu
require "CQ_UI_Kit"

CQSheet = CQSheet or {}
local C = CQUI.C
local T = CQC.txt
local FS, FM, FL = UIFont.Small, UIFont.Medium, UIFont.Large

local INK = { 0.22, 0.13, 0.06 }
local INK2 = { 0.42, 0.28, 0.16 }
local RED = { 0.62, 0.12, 0.10 }

CQSheet.Win = CQUI.Window:derive("CQSheet_Win")
local S = CQSheet.Win

function S:new(x, y, mid, w, h)
    local o = CQUI.Window.new(self, x, y, w or 460, h or 620)
    o.mid = mid
    o.view = nil
    o.headerH = 40
    o.sentAt = 0
    return o
end

function S:drawFrame()
    local w, h = self.width, self.height
    CQUI.rbox(self, 6, 8, w, h, { 0, 0, 0 }, 0.4, 8)
    local paper = CQUI.tex("cq_paper")
    if paper then
        self:drawTextureScaled(paper, 0, 0, w, h, 1, 1, 1, 1)
    else
        CQUI.rbox(self, 0, 0, w, h, { 0.93, 0.86, 0.70 }, 1, 6)
        CQUI.border(self, 6, 6, w - 12, h - 12, INK2, 0.6)
    end
    local cs = 26
    local bx, by = w - cs - 34, 34
    local over = self:hit(bx, by, cs, cs, function() self:close() end)
    CQUI.rbox(self, bx, by, cs, cs, over and RED or INK2, over and 0.9 or 0.25, 13)
    CQUI.textC(self, "x", bx + cs / 2, by + (cs - CQUI.fh(FM)) / 2 - 1, over and { 1, 0.95, 0.9 } or INK, 1, FM)
end

function S:drawBody()
    local W, H = self.width, self.height
    local v = self.view
    if not v or v.mid ~= self.mid then
        if CQC.sheetView and CQC.sheetView.mid == self.mid then
            self.view = CQC.sheetView
            v = self.view
        end
    end
    local px, pw = 40, W - 80
    if not v then
        CQUI.textC(self, T("IGUI_CQ_Reading"), W / 2, H / 2 - 10, INK2, 1, FM)
        if getTimestampMs() - self.sentAt > 4000 then
            self.sentAt = getTimestampMs()
            CQC.send("peek", { mid = self.mid })
        end
        return
    end
    if v.missing then
        CQUI.textC(self, T("IGUI_CQ_SheetGone"), W / 2, H / 2 - 10, RED, 1, FM)
        return
    end
    local y = 46
    -- title
    local tl = CQUI.wrap(v.title or "", FL, pw)
    for i = 1, #tl do
        CQUI.textC(self, tl[i], W / 2, y, INK, 1, FL)
        y = y + CQUI.fh(FL) + 2
    end
    y = y + 4
    local orn = CQUI.tex("cq_orn")
    if orn then
        self:drawTextureScaled(orn, W / 2 - 60, y, 120, 20, 0.9, INK2[1], INK2[2], INK2[3])
    else
        CQUI.rect(self, W / 2 - 60, y + 9, 120, 1, INK2, 0.8)
    end
    y = y + 26
    -- story (scroll)
    local bottomBlock = 200
    local storyH = H - y - bottomBlock
    local off = self:beginScroll("story", px - 6, y, pw + 12, storyH)
    local used = CQUI.para(self, v.story or "", px, y - off, pw, INK, FS)
    self:endScroll(used + 6)
    y = y + storyH + 6
    CQUI.rect(self, px, y, pw, 1, INK2, 0.6)
    y = y + 8
    -- route
    if v.showSteps and v.steps then
        local parts = {}
        for i = 1, #v.steps do
            local st = v.steps[i]
            local lbl = (st.label and st.label ~= "") and st.label or T("IGUI_CQ_StepT_" .. tostring(st.t))
            parts[#parts + 1] = tostring(i) .. ". " .. lbl
        end
        local route = T("IGUI_CQ_Route") .. " " .. table.concat(parts, "  >  ")
        local u = CQUI.para(self, route, px, y, pw, INK, FS, 3)
        y = y + u + 4
    else
        CQUI.text(self, T("IGUI_CQ_RouteHidden", v.nSteps or 1), px, y, INK2)
        y = y + CQUI.fh(FS) + 4
    end
    local rt = v.rewardText
    if (not rt or rt == "") and v.rewards and #v.rewards > 0 then rt = CQUI.itemsText(v.rewards, 4) end
    if rt and rt ~= "" then
        local u = CQUI.para(self, T("IGUI_CQ_RewardIs", rt), px, y, pw, RED, FS, 2)
        y = y + u + 4
    end
    local scope
    if v.assign == "everyone" then scope = T("IGUI_CQ_ScopeAll") else scope = T("IGUI_CQ_ScopeMe") end
    if v.team then scope = scope .. "  " .. T("IGUI_CQ_ScopeTeam") end
    if v.timeLimit and v.timeLimit > 0 then scope = scope .. "  " .. T("IGUI_CQ_TimeLimit", CQUI.durMin(v.timeLimit)) end
    local u = CQUI.para(self, scope, px, y, pw, INK2, FS, 3)
    y = y + u + 8
    -- buttons
    local bh = CQUI.fh(FS) + 14
    local by = H - bh - 34
    if v.can then
        CQUI.btn(self, px, by, pw - 110, bh, T("IGUI_CQ_AcceptSheet"), function()
            CQC.send("accept", { mid = self.mid, via = "sheet" })
            self:close()
        end, "primary")
    else
        CQUI.btn(self, px, by, pw - 110, bh, T("IGUI_CQ_Err_" .. tostring(v.why or "x")), nil, "ghost", { disabled = true })
    end
    CQUI.btn(self, px + pw - 100, by, 100, bh, T("IGUI_CQ_Close"), function() self:close() end, "ghost")
end

function S:onClosed()
    if CQSheet.win == self then CQSheet.win = nil end
end

function CQSheet.open(mid)
    if not mid then return end
    if CQSheet.win then CQSheet.win:close() end
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local ww, h = CQUI.size(460, 620)
    local w = S:new((sw - ww) / 2, math.max(10, (sh - h) / 2), mid, ww, h)
    CQC.sheetView = nil
    w.sentAt = getTimestampMs()
    CQC.send("peek", { mid = mid })
    w:show()
    CQSheet.win = w
end

-- ===================================================================== context menu on the item
local function onFillInv(playerNum, context, items)
    local sheet = nil
    for _, v in ipairs(items) do
        local item = v
        if type(v) == "table" and v.items then item = v.items[1] end
        if item and item.getFullType and item:getFullType() == CQ.SHEET_TYPE then sheet = item; break end
    end
    if not sheet then return end
    local mid = CQ.sheetMid(sheet)
    if mid then
        context:addOptionOnTop(T("IGUI_CQ_ReadSheet"), nil, function() CQSheet.open(mid) end)
    else
        context:addOption(T("IGUI_CQ_SheetBlank"), nil, nil)
    end
end
Events.OnFillInventoryObjectContextMenu.Add(onFillInv)

CQC.on(function(what)
    if what == "sheet" and CQSheet.win and CQC.sheetView and CQC.sheetView.mid == CQSheet.win.mid then
        CQSheet.win.view = CQC.sheetView
    end
end)

return CQSheet
