--[[
    The diary window, drawn straight onto the artwork.

      cover view - the character name written on the masking tape
      book view  - left page: line 1 = character name, line 2 = the nickname you
                   type IN PLACE; everything below = what the diary holds.
                   right page: the two sticker buttons.

    Typing on the page: PZ's text box always draws white text and has no colour
    API, so it is parked far off screen where it is invisible, given keyboard
    focus, and we draw its contents ourselves in dark ink on the line - caret
    and all. The player types straight onto the paper.

    Every hot spot is a fraction of the texture, measured off the artwork, so
    the whole window scales and the text always lands on the drawn lines.
]]

require "ISUI/ISPanel"
require "ISUI/ISTextEntryBox"
require "AkaIKWID/AkaIKWID_Shared"

AkaIKWID_Window = ISPanel:derive("AkaIKWID_Window")

local T = AkaIKWID.T

-- measured on the artwork (1920x1080 spread, 692x1035 cover crop)
local A = {
    line1  = { x0 = 0.1432, x1 = 0.4615, y = 0.1620 },   -- character name
    line2  = { x0 = 0.1427, x1 = 0.4615, y = 0.2963 },   -- nickname (editable)
    btnRec = { x0 = 0.6115, y0 = 0.2574, x1 = 0.8469, y1 = 0.4287 },
    btnRes = { x0 = 0.6104, y0 = 0.5880, x1 = 0.8469, y1 = 0.7667 },
    notes  = { x0 = 0.1400, x1 = 0.4700, y0 = 0.3450, y1 = 0.9550 },
    -- the masking-tape label on the closed-book cover art
    tape   = { x0 = 0.1084, x1 = 0.8237, y0 = 0.1643, y1 = 0.3092 },
}

local INK      = { 0.16, 0.17, 0.42 }
local INK_FADE = { 0.45, 0.46, 0.60 }
local GREEN    = { 0.13, 0.42, 0.18 }
local AMBER    = { 0.58, 0.36, 0.06 }
local RED      = { 0.55, 0.16, 0.16 }
local COVER_AR = 384 / 574   -- the closed book is portrait

-- ---------------------------------------------------------------- text fitting

local FONTS
local function fontList()
    if FONTS then return FONTS end
    FONTS = {}
    for _, n in ipairs({ "Large", "Medium", "Small", "NewSmall" }) do
        if UIFont[n] then FONTS[#FONTS + 1] = UIFont[n] end
    end
    if #FONTS == 0 then FONTS = { UIFont.Small } end
    return FONTS
end

local function fitFont(text, maxW, maxH)
    local tm = getTextManager()
    local list = fontList()
    for _, f in ipairs(list) do
        local w = tm:MeasureStringX(f, text)
        local h = tm:getFontHeight(f)
        if w <= maxW and h <= maxH then return f, w, h end
    end
    local f = list[#list]
    return f, tm:MeasureStringX(f, text), tm:getFontHeight(f)
end

local function inside(mx, my, x, y, w, h)
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

-- ---------------------------------------------------------------- lifecycle

function AkaIKWID_Window:new(x, y, w, h, player, item, result)
    local o = ISPanel:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.player          = player
    o.item            = item
    o.result          = result
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor     = { r = 0, g = 0, b = 0, a = 0 }
    o.moveWithMouse   = true
    o.status          = result and result.msg or ""
    o.statusBad       = false
    o.editing         = false
    o.view            = (result or (AkaIKWID.book and AkaIKWID.book.signed)) and "book" or "cover"
    return o
end

function AkaIKWID_Window:createChildren()
    self.texBook  = getTexture("media/ui/AkaIKWID_book.png")
    self.texCover = getTexture("media/ui/AkaIKWID_cover.png")
    self.texRecHi = getTexture("media/ui/AkaIKWID_rec_hi.png")
    self.texResHi = getTexture("media/ui/AkaIKWID_res_hi.png")

    -- the keyboard catcher: parked off screen, never seen, only read from
    self.entry = ISTextEntryBox:new("", 8, self.height + 2000, 200, 22)
    self.entry:initialise()
    self.entry:instantiate()
    self.entry.font = UIFont.Small
    AkaIKWID.safe(function() self.entry:setMaxTextLength(22) end, nil)
    self:addChild(self.entry)
end

function AkaIKWID_Window:setStatus(text, bad)
    self.status    = text or ""
    self.statusBad = bad and true or false
end

function AkaIKWID_Window:onBook()
    if AkaIKWID.book and AkaIKWID.book.signed and self.view == "cover" and not self.result then
        -- keep the cover until clicked; nothing to do
    end
end

function AkaIKWID_Window:book()
    return AkaIKWID.book or AkaIKWID.emptyBook()
end

-- ---------------------------------------------------------------- geometry

function AkaIKWID_Window:box(r)
    return self.width * r.x0, self.height * r.y0,
           self.width * (r.x1 - r.x0), self.height * (r.y1 - r.y0)
end

function AkaIKWID_Window:lineBox(r)
    local h = self.height * 0.085
    return self.width * r.x0, self.height * r.y - h,
           self.width * (r.x1 - r.x0), h
end

function AkaIKWID_Window:coverBox()
    local h = self.height * 0.96
    local w = h * COVER_AR
    return (self.width - w) / 2, (self.height - h) / 2, w, h
end

function AkaIKWID_Window:closeBox()
    -- big enough to hit without aiming. The old one was an 18px "X" drawn in
    -- faint ink on a busy page and players could not find it.
    local s = math.max(26, self.height * 0.075)
    return self.width * 0.905 - s / 2, self.height * 0.025, s, s
end

function AkaIKWID_Window:mouse()
    return getMouseX() - self:getAbsoluteX(), getMouseY() - self:getAbsoluteY()
end

-- ---------------------------------------------------------------- drawing

function AkaIKWID_Window:drawFitted(text, x, y, w, h, col, alpha, centre)
    if text == nil or text == "" then return end
    local f, tw, th = fitFont(text, w, h)
    local tx = centre and (x + (w - tw) / 2) or x
    self:drawText(text, tx, y + (h - th) / 2, col[1], col[2], col[3], alpha or 1, f)
    return tx, tw, th, f
end

function AkaIKWID_Window:renderCover()
    local x, y, w, h = self:coverBox()
    self:drawTextureScaled(self.texCover, x, y, w, h, 1, 1, 1, 1)

    local t  = A.tape
    local tx = x + w * t.x0
    local ty = y + h * t.y0
    local tw = w * (t.x1 - t.x0)
    local th = h * (t.y1 - t.y0)

    -- the tape carries the character's name; the nickname sits under it
    self:drawFitted(AkaIKWID.charName(self.player), tx + tw * 0.06, ty,
                    tw * 0.88, th, { 0.22, 0.16, 0.12 }, 1, true)

    local book = self:book()
    local nick = book.signed and book.nickname or nil
    local sub  = nick
    local col  = { 0.93, 0.90, 0.84 }
    if sub == nil or sub == "" then
        sub = T("IGUI_AkaIKWID_NewShort", "(new)")
        col = { 0.80, 0.76, 0.70 }
    end
    self:drawFitted(sub, tx, ty + th * 1.10, tw, th * 0.55, col, 1, true)

    local hint = T("IGUI_AkaIKWID_ClickOpen", "click to open")
    local f, fw = fitFont(hint, self.width * 0.5, 20)
    self:drawText(hint, (self.width - fw) / 2, y + h - 2, 0.85, 0.85, 0.85, 0.75, f)
end

function AkaIKWID_Window:renderBook()
    self:drawTextureScaled(self.texBook, 0, 0, self.width, self.height, 1, 1, 1, 1)
    local mx, my = self:mouse()
    local book   = self:book()

    -- line 1: who you are
    local x, y, w, h = self:lineBox(A.line1)
    self:drawFitted(AkaIKWID.charName(self.player), x, y, w, h, INK, 1, true)

    -- line 2: the nickname, typed straight onto the paper
    x, y, w, h = self:lineBox(A.line2)
    if self.editing then
        local txt = self:entryText()
        local caret = ""
        if math.floor(AkaIKWID.nowMs() / 500) % 2 == 0 then caret = "|" end
        self:drawFitted(txt .. caret, x, y, w, h, INK, 1, true)
    else
        local nick = book.signed and book.nickname or nil
        if nick == nil or nick == "" then
            self:drawFitted(T("IGUI_AkaIKWID_TapNick", "( click here for a nickname )"),
                            x, y, w, h, INK_FADE, 1, true)
        else
            self:drawFitted(nick, x, y, w, h, INK, 1, true)
        end
        if inside(mx, my, x, y, w, h) then
            local hint = T("IGUI_AkaIKWID_TapHint", "click to write")
            local hf, hw = fitFont(hint, w, 16)
            self:drawText(hint, x + w - hw, self.height * A.line2.y + 3,
                          INK_FADE[1], INK_FADE[2], INK_FADE[3], 0.85, hf)
        end
    end

    self:renderNotes(book)

    self:renderSticker(A.btnRec, mx, my, self.texRecHi)
    self:renderSticker(A.btnRes, mx, my, self.texResHi)

    local bx, by, bw, bh = self:box(A.btnRes)
    local pct = T("IGUI_AkaIKWID_Back", "back") .. " " .. AkaIKWID.restorePercent() .. "%"
    local f, fw = fitFont(pct, bw, 18)
    self:drawText(pct, bx + (bw - fw) / 2, by + bh + 2, 0.30, 0.32, 0.36, 0.9, f)

    self:renderRestoreState(bx, by, bw)

    local dupe = self.result and self.result.kind == "restore" and self.status == self.result.msg
    if self.status ~= "" and not dupe then
        local r, g, b = GREEN[1], GREEN[2], GREEN[3]
        if self.statusBad then r, g, b = 0.55, 0.16, 0.16 end
        local sf, sw = fitFont(self.status, self.width * 0.24, 20)
        self:drawText(self.status, self.width * 0.705 - sw / 2, self.height * 0.828, r, g, b, 1, sf)
    end

    self:renderClose(mx, my)
end

--[[ One line in the gap above the green sticker that answers, before it is
     pressed, the only question that matters: will this give me anything, and
     if not, why not. Also where the two-click confirmation is asked. ]]
function AkaIKWID_Window:renderRestoreState(bx, by, bw)
    local book = self:book()
    local text, col

    if self.confirmUntil and AkaIKWID.nowMs() < self.confirmUntil then
        text = T("IGUI_AkaIKWID_Confirm", "sure? click again")
        col  = AMBER
    else
        local pd  = AkaIKWID.playerData(self.player)
        local why = AkaIKWID.whyNotRestore(book, pd.charId)
        if why then
            text = AkaIKWID.reason(why)
            col  = (why == "IGUI_AkaIKWID_ErrEmpty" or why == "IGUI_AkaIKWID_ErrUnsigned")
                   and INK_FADE or RED
        else
            local pay = AkaIKWID.payout(book, AkaIKWID.restorePercent())
            text = T("IGUI_AkaIKWID_Ready", "ready") .. ": " .. math.floor(pay) .. " EXP"
            col  = GREEN
        end
    end

    local h = math.max(11, self.height * 0.032)
    local f, fw = fitFont(text, bw, h)
    self:drawText(text, bx + (bw - fw) / 2, by - h - 2, col[1], col[2], col[3], 0.95, f)
end

function AkaIKWID_Window:renderSticker(r, mx, my, texHi)
    local x, y, w, h = self:box(r)
    if texHi and inside(mx, my, x, y, w, h) then
        self:drawTextureScaled(texHi, x, y, w, h, 1, 1, 1, 1)
    end
end

-- the lower half of the left page. Rows are sized to the space available so a
-- long list shrinks to fit instead of running off the paper.
function AkaIKWID_Window:renderNotes(book)
    local x, y, w, h = self:box(A.notes)
    local bottom = y + h
    local tm     = getTextManager()

    local head, rows, col = nil, nil, INK

    if self.result and self.result.kind == "restore" then
        col  = GREEN
        head = self.result.msg
        rows = AkaIKWID.rowsFromGiven(self.result.given)
        for _, r in ipairs(rows) do r.right = r.xp .. " EXP" end
    else
        if self.result and self.result.kind == "record" then col = GREEN end
        if not book.signed then
            self:drawFitted(T("IGUI_AkaIKWID_SignFirst", "Set a nickname to sign this diary."),
                            x, y, w, 18, INK_FADE, 1, false)
            return
        end
        local n = AkaIKWID.bookSkillCount(book)
        if n == 0 then
            self:drawFitted(T("IGUI_AkaIKWID_Empty", "Nothing written yet."),
                            x, y, w, 18, INK_FADE, 1, false)
            return
        end
        head = T("IGUI_AkaIKWID_Recorded", "Recorded") .. " " .. n .. " - "
               .. tostring(book.recChar or "?") .. ", "
               .. T("IGUI_AkaIKWID_Day", "day") .. " " .. tostring(book.recDay or 0)
        rows = AkaIKWID.rowsFromSkills(book.skills)
        for _, r in ipairs(rows) do r.right = r.xp .. " EXP" end
    end

    local headH = math.max(14, self.height * 0.040)
    self:drawFitted(head, x, y, w, headH, col, 1, false)

    -- what today's life knows that the paper does not: the last line of the
    -- page, in amber, so "I forgot to press record" is visible before it hurts
    if not (self.result and self.result.kind == "restore") then
        local p = AkaIKWID.pending(self.player, book)
        if p.xp > 0 then
            local ph = math.max(11, self.height * 0.032)
            local msg = T("IGUI_AkaIKWID_Pending", "not written down yet") .. ": "
                        .. p.n .. " " .. T("IGUI_AkaIKWID_Skills", "skills")
                        .. ", " .. math.floor(p.xp) .. " EXP"
            self:drawFitted(msg, x, bottom - ph, w, ph, AMBER, 1, false)
            bottom = bottom - ph - 2
        end
    end

    local top   = y + headH + math.max(4, self.height * 0.012)
    local avail = bottom - top
    if avail < 10 or #rows == 0 then return end

    self:drawRowList(x, top, w, avail, rows, col)
end

--[[ Two columns once the list gets long, so a character who has touched every
     skill in the game still fits on the page. One column while the list is
     short - two columns of three entries looks like a mistake. ]]
function AkaIKWID_Window:drawRowList(x, y, w, h, rows, col)
    local tm     = getTextManager()
    local MAX_H  = self.height * 0.045
    local MIN_H  = 11
    local GAP    = math.max(10, w * 0.04)

    local cols   = (#rows > 6) and 2 or 1
    local colW   = (w - GAP * (cols - 1)) / cols
    local perCol = math.ceil(#rows / cols)

    local rowH = h / perCol
    if rowH > MAX_H then rowH = MAX_H end
    if rowH < MIN_H then rowH = MIN_H end

    -- +0.5 so a column that fits exactly is not lost to float rounding
    local fit    = math.floor((h + 0.5) / rowH)
    local shown  = #rows
    local cut    = false
    if perCol > fit then
        shown  = fit * cols - 1                  -- keep a line for "+N more"
        perCol = fit
        cut    = true
    end

    local font = select(1, fitFont("Metalworking   9999 EXP", colW, rowH - 1))

    for i = 1, shown do
        local r    = rows[i]
        local c    = math.floor((i - 1) / perCol)
        local line = (i - 1) % perCol
        local cx   = x + c * (colW + GAP)
        local yy   = y + line * rowH

        local right = r.right or ""
        local rw    = tm:MeasureStringX(font, right)
        local room = colW - rw - 8
        local name = r.name
        while tm:MeasureStringX(font, name) > room and #name > 3 do
            name = string.sub(name, 1, #name - 2) .. "."
        end

        self:drawText(name, cx + 4, yy, col[1], col[2], col[3], 0.95, font)
        self:drawText(right, cx + colW - rw, yy, col[1], col[2], col[3], 0.78, font)
    end

    if cut then
        local left = #rows - shown
        local cx   = x + (cols - 1) * (colW + GAP)
        self:drawText("+ " .. left .. " " .. T("IGUI_AkaIKWID_Skills", "skills"),
                      cx + 4, y + perCol * rowH - rowH,
                      INK_FADE[1], INK_FADE[2], INK_FADE[3], 0.9, font)
    end
end

function AkaIKWID_Window:renderClose(mx, my)
    local x, y, w, h = self:closeBox()
    local hot = inside(mx, my, x, y, w, h)

    -- a real target: a tab of paper with a border, not a floating letter
    if hot then
        self:drawRect(x, y, w, h, 0.92, 0.72, 0.24, 0.20)
        self:drawRectBorder(x, y, w, h, 1, 0.45, 0.13, 0.13)
    else
        self:drawRect(x, y, w, h, 0.55, 0.96, 0.94, 0.88)
        self:drawRectBorder(x, y, w, h, 0.8, INK_FADE[1], INK_FADE[2], INK_FADE[3])
    end

    local col = hot and RED or INK
    local f, fw, fh = fitFont("X", w * 0.7, h * 0.6)
    self:drawText("X", x + (w - fw) / 2, y + (h - fh) / 2, col[1], col[2], col[3], 1, f)

    if hot then
        local hint = T("IGUI_AkaIKWID_Close", "close  (ESC)")
        local hf, hw = fitFont(hint, self.width * 0.2, 14)
        self:drawText(hint, x + w / 2 - hw / 2, y + h + 2, col[1], col[2], col[3], 0.9, hf)
    end
end

function AkaIKWID_Window:render()
    ISPanel.render(self)
    if self.view == "cover" then self:renderCover() else self:renderBook() end
end

-- ---------------------------------------------------------------- typing

function AkaIKWID_Window:entryText()
    local t = AkaIKWID.safe(function() return self.entry:getInternalText() end, nil)
    if type(t) ~= "string" then t = AkaIKWID.safe(function() return self.entry:getText() end, "") end
    return tostring(t or "")
end

function AkaIKWID_Window:startEditing()
    local book = self:book()
    self.editing = true
    AkaIKWID.safe(function() self.entry:setText(tostring(book.nickname or "")) end, nil)
    AkaIKWID.safe(function() self.entry:focus() end, nil)
    self:setStatus(T("IGUI_AkaIKWID_TypeHint", "type, then press Enter"), false)
end

function AkaIKWID_Window:commitNick()
    if not self.editing then return end
    self.editing = false
    AkaIKWID.safe(function() self.entry:unfocus() end, nil)

    local txt = self:entryText():gsub("^%s+", ""):gsub("%s+$", "")
    if #txt > 22 then txt = string.sub(txt, 1, 22) end
    if txt == "" then
        self:setStatus(T("IGUI_AkaIKWID_NeedNick", "A diary needs a name on it."), true)
        return
    end

    self:setStatus("...", false)
    AkaIKWID.requestSign(self.player, txt)
    AkaIKWID.safe(function() AkaIKWID.applyName(self.item, txt) end, nil)
end

-- ---------------------------------------------------------------- input

function AkaIKWID_Window:onMouseDown(x, y)
    local cx, cy, cw, ch = self:closeBox()
    if inside(x, y, cx, cy, cw, ch) then self:close() return true end

    if self.view == "cover" then
        self.view = "book"
        return true
    end

    local lx, ly, lw, lh = self:lineBox(A.line2)
    if inside(x, y, lx, ly, lw, lh) then
        if not self.editing then self:startEditing() end
        return true
    end
    if self.editing then self:commitNick() end

    local bx, by, bw, bh = self:box(A.btnRec)
    if inside(x, y, bx, by, bw, bh) then
        self.confirmUntil = nil        -- a click anywhere else drops the confirm
        self:onRecord()
        return true
    end

    bx, by, bw, bh = self:box(A.btnRes)
    if inside(x, y, bx, by, bw, bh) then self:onRestore() return true end
    self.confirmUntil = nil

    return ISPanel.onMouseDown(self, x, y)
end

function AkaIKWID_Window:onRightMouseDown(x, y)
    self:close()
    return true
end

-- ---------------------------------------------------------------- actions

function AkaIKWID_Window:onRecord()
    if not self:book().signed then
        self:setStatus(T("IGUI_AkaIKWID_SignFirst", "Set a nickname to sign this diary."), true)
        return
    end
    local pl, it = self.player, self.item
    self:close()
    AkaIKWID.startAction(pl, it, "record")
end

function AkaIKWID_Window:onRestore()
    local pd  = AkaIKWID.ensureBaseline(self.player)
    local why = AkaIKWID.whyNotRestore(self:book(), pd.charId)
    if why then
        self:setStatus(AkaIKWID.reason(why), true)
        return
    end

    -- reading back is once per life and cannot be undone, so it is asked twice
    local now = AkaIKWID.nowMs()
    if not (self.confirmUntil and now < self.confirmUntil) then
        self.confirmUntil = now + 6000
        self:setStatus(T("IGUI_AkaIKWID_Confirm", "sure? click again"), false)
        return
    end
    self.confirmUntil = nil

    local pl, it = self.player, self.item
    self:close()
    AkaIKWID.startAction(pl, it, "restore")
end

function AkaIKWID_Window:close()
    if self.editing then
        self.editing = false
        AkaIKWID.safe(function() self.entry:unfocus() end, nil)
    end
    self:setVisible(false)
    self:removeFromUIManager()
    AkaIKWID.openWindow = nil
end

-- ---------------------------------------------------------------- entry point

-- Enter commits the nickname
if Events and Events.OnKeyPressed then
    Events.OnKeyPressed.Add(function(key)
        local w = AkaIKWID.openWindow
        if w and w.editing and (key == 28 or key == 156) then
            pcall(function() w:commitNick() end)
        elseif w and key == 1 then          -- ESC
            pcall(function() w:close() end)
        end
    end)
end

function AkaIKWID.openDiary(player, item, result)
    if AkaIKWID.openWindow then
        pcall(function() AkaIKWID.openWindow:close() end)
        AkaIKWID.openWindow = nil
    end
    if not (player and item) then return end

    -- courtesy lock: a book somebody else signed does not open for you
    if not AkaIKWID.isMine(item, player) then
        AkaIKWID.halo(player, AkaIKWID.reason("IGUI_AkaIKWID_ErrNotYours"), true)
        return
    end
    AkaIKWID.lastItem = item
    AkaIKWID.ensureBaseline(player)   -- the page needs charId and the baseline

    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local w  = math.min(760, math.floor(sw * 0.55))
    local h  = math.floor(w * 576 / 1024)
    if h > sh * 0.75 then
        h = math.floor(sh * 0.75)
        w = math.floor(h * 1024 / 576)
    end

    local win = AkaIKWID_Window:new((sw - w) / 2, (sh - h) / 2, w, h, player, item, result)
    win:initialise()
    win:addToUIManager()
    AkaIKWID.openWindow = win

    AkaIKWID.requestLoad(player)   -- always show what the server actually has
    return win
end
