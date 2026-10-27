--[[ ============================================================
  PROJECT DUNKA [MP] -- Summoning Terminal (code-drawn)   KACHASIG
  Dark / hazard themed. No image skin. CAPTCHA = random quiz OR
  numbered tile puzzle. Pass -> SUMMON HORDE fires the server summon.
  Opened by DunKaWarnUI after the player acknowledges the warning.
============================================================ ]]--

require "ISUI/ISPanel"
require "DunKa_Shared"

DunKaSummonUI = ISPanel:derive("DunKaSummonUI")

local W, H   = 560, 486
local CH     = { x = 16,  y = 78,  w = 250, h = 250 }   -- challenge zone
local RX     = 288                                       -- readout column x
local BTN    = { x = 16,  y = H-52, w = W-32, h = 40 }
local CLOSE  = { x = W-30, y = 8,   w = 22,  h = 22 }

-- theme colours (r,g,b)
local C_RED   = {0.89,0.29,0.29}
local C_RED2  = {0.94,0.42,0.42}
local C_AMBER = {0.94,0.62,0.15}
local C_GREEN = {0.59,0.77,0.35}
local C_MUTE  = {0.53,0.53,0.50}
local C_TXT   = {0.85,0.84,0.80}

local QUIZ = {
    { q="2 + 3 = ?",           opts={"5","4","6","8"},  correct=1 },
    { q="Which is largest?",   opts={"9","2","5","7"},  correct=1 },
    { q="10 - 4 = ?",          opts={"6","5","7","3"},  correct=1 },
    { q="Pick an even number", opts={"8","3","7","5"},  correct=1 },
    { q="3 x 3 = ?",           opts={"9","6","12","3"}, correct=1 },
    { q="Smallest number?",    opts={"1","4","9","6"},  correct=1 },
}
local ABBR   = { White="W", Yellow="Y", Blue="B" }
local ORDER  = { "White", "Yellow", "Blue" }

local function inRect(px,py, x,y,w,h) return px>=x and px<=x+w and py>=y and py<=y+h end
local function pickRank(player)
    local inv = player:getInventory()
    for _,rid in ipairs(DunKa.RANK_ORDER) do
        local rdef = DunKa.RANKS[rid]
        if rdef and inv:getItemCount(rdef.item) > 0 then return rid end
    end
    return nil
end

function DunKaSummonUI:initialise() ISPanel.initialise(self) end

function DunKaSummonUI:new(player, sq)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    local o = ISPanel.new(self, (sw-W)/2, (sh-H)/2, W, H)
    o:noBackground(); o.moveWithMouse = true
    o.player, o.sq = player, sq
    o.rankId  = pickRank(player)
    o.solved  = false
    o.resultTimer = 0
    o.resultPass  = false
    return o
end

function DunKaSummonUI.openFor(player, sq)
    if DunKaSummonUI.instance then pcall(function() DunKaSummonUI.instance:close() end) end
    local ui = DunKaSummonUI:new(player, sq)
    ui:initialise(); ui:addToUIManager(); ui:startChallenge()
    DunKaSummonUI.instance = ui
    return ui
end

function DunKaSummonUI:close()
    DunKaSummonUI.instance = nil
    self:setVisible(false); self:removeFromUIManager()
end
function DunKaSummonUI:onRightMouseDown(x,y) self:close(); return true end

-- ---------------- challenge ----------------
function DunKaSummonUI:startChallenge()
    self.solved = false; self.resultTimer = 0
    self.mode = (ZombRand(2)==0) and "quiz" or "puzzle"
    if self.mode=="quiz" then self:initQuiz() else self:initPuzzle() end
end

function DunKaSummonUI:initQuiz()
    local src = QUIZ[ZombRand(#QUIZ)+1]
    local list = {}
    for i,txt in ipairs(src.opts) do list[#list+1]={text=txt, correct=(i==src.correct)} end
    for i=#list,2,-1 do local j=ZombRand(i)+1; list[i],list[j]=list[j],list[i] end
    self.quizQ = src.q; self.answers = list
    self.answerRects = {}
    local aw = math.floor((CH.w-18)/2); local ah = 44
    local ax = CH.x+6; local ay = CH.y+CH.h-(ah*2+8)-8
    for i=1,4 do
        local col=(i-1)%2; local row=math.floor((i-1)/2)
        self.answerRects[i] = { x=ax+col*(aw+6), y=ay+row*(ah+6), w=aw, h=ah }
    end
end

function DunKaSummonUI:initPuzzle()
    self.perm = {1,2,3,4,5,6,7,8,9}
    repeat
        for i=9,2,-1 do local j=ZombRand(i)+1; self.perm[i],self.perm[j]=self.perm[j],self.perm[i] end
    until not self:puzzleSolved()
    self.selTile = nil
    local side = math.min(CH.w, CH.h) - 24
    self.pCell = math.floor(side/3)
    self.pGX = CH.x + math.floor((CH.w - self.pCell*3)/2)
    self.pGY = CH.y + 30
end
function DunKaSummonUI:puzzleSolved()
    for i=1,9 do if self.perm[i]~=i then return false end end
    return true
end

function DunKaSummonUI:passNow() self.solved=true; self.resultPass=true; self.resultTimer=90 end
function DunKaSummonUI:failNow() self.resultPass=false; self.resultTimer=55 end

function DunKaSummonUI:answerQuiz(i)
    local a=self.answers and self.answers[i]; if not a then return end
    if a.correct then self:passNow() else self:failNow() end
end

function DunKaSummonUI:puzzleAt(x,y)
    if not self.pCell then return nil end
    for i=0,8 do
        local cx=self.pGX+(i%3)*self.pCell; local cy=self.pGY+math.floor(i/3)*self.pCell
        if inRect(x,y, cx,cy, self.pCell-3, self.pCell-3) then return i+1 end
    end
    return nil
end
function DunKaSummonUI:puzzleClick(i)
    if self.selTile==nil then self.selTile=i
    else
        self.perm[self.selTile], self.perm[i] = self.perm[i], self.perm[self.selTile]
        self.selTile=nil
        if self:puzzleSolved() then self:passNow() end
    end
end

function DunKaSummonUI:onSummon()
    if not self.rankId then DunKa.notify(self.player, "No key card in inventory"); return end
    if not self.solved then DunKa.notify(self.player, "Verify you are human first!"); self:failNow(); return end
    if DunKa.requestSummon then DunKa.requestSummon(self.player, self.sq, self.rankId) end
    self:close()
end

function DunKaSummonUI:onMouseDown(x, y)
    if inRect(x,y, CLOSE.x,CLOSE.y,CLOSE.w,CLOSE.h) then self:close(); return true end
    if inRect(x,y, BTN.x,BTN.y,BTN.w,BTN.h) then self:onSummon(); return true end
    if not self.solved and self.resultTimer==0 then
        if self.mode=="quiz" and self.answerRects then
            for i,r in ipairs(self.answerRects) do
                if inRect(x,y,r.x,r.y,r.w,r.h) then self:answerQuiz(i); return true end
            end
        elseif self.mode=="puzzle" then
            local i=self:puzzleAt(x,y); if i then self:puzzleClick(i); return true end
        end
    end
    return ISPanel.onMouseDown(self, x, y)
end

function DunKaSummonUI:update()
    if self.resultTimer and self.resultTimer>0 then
        self.resultTimer = self.resultTimer - 1
        if self.resultTimer==0 and not self.resultPass and not self.solved then self:startChallenge() end
    end
end

-- ---------------- render ----------------
local function col(c) return c[1],c[2],c[3] end

function DunKaSummonUI:readout(label, y, val, vc, big)
    self:drawText(label, RX, y, 0.53,0.53,0.50, 1, UIFont.Small)
    local r,g,b = col(vc or C_TXT)
    self:drawText(val, RX, y+16, r,g,b, 1, big and UIFont.Large or UIFont.Medium)
end

function DunKaSummonUI:render()
    -- shell
    self:drawRect(0,0,W,H, 0.97, 0.083,0.086,0.102)
    self:drawRectBorder(0,0,W,H, 1, col(C_RED))
    -- title bar
    self:drawRect(0,0,W,32, 1, 0.11,0.115,0.13)
    self:drawText("HORDE SUMMONING TERMINAL", 14, 8, 0.94,0.58,0.58, 1, UIFont.Medium)
    self:drawText("X", W-24, 6, 0.6,0.6,0.57, 1, UIFont.Medium)
    -- warning strip
    self:drawRect(0,32,W,24, 1, 0.16,0.08,0.08)
    self:drawText("! human verification required", 16, 36, 0.94,0.42,0.42, 1, UIFont.Small)

    local ok, err = pcall(function() self:renderBody() end)
    if not ok then
        self:drawText("[render error - please screenshot this]", 16, 72, 1,0.4,0.4, 1, UIFont.Medium)
        self:drawText(tostring(err), 16, 94, 1,0.6,0.6, 1, UIFont.Small)
        print("[DunKa][UI] render error: "..tostring(err))
    end
end

function DunKaSummonUI:renderBody()

    -- challenge zone frame
    self:drawText("SOLVE TO ARM", CH.x, CH.y-16, 0.53,0.53,0.50, 1, UIFont.Small)
    self:drawRect(CH.x, CH.y, CH.w, CH.h, 1, 0.043,0.047,0.055)
    self:drawRectBorder(CH.x, CH.y, CH.w, CH.h, 1, 0.29,0.11,0.11)
    if not self.solved then
        if self.mode=="quiz" then self:renderQuiz() else self:renderPuzzle() end
    else
        self:drawTextCentre("VERIFIED", CH.x+CH.w/2, CH.y+CH.h/2-11, 0.59,0.77,0.35, 1, UIFont.Large)
    end

    -- readout column
    local rdef = self.rankId and DunKa.RANKS[self.rankId]
    if rdef then
        self:readout("RANK", 76, tostring(self.rankId), C_AMBER, true)
        self:readout("INCOMING", 134, DunKa.getRankCount(self.rankId).." zombies", C_RED2, true)
        local parts={}
        local rc=DunKa.getRankConfig()[self.rankId] or {}
        for _,c in ipairs(ORDER) do local q=rc[c]; if q and q>0 then parts[#parts+1]=ABBR[c]..q end end
        self:readout("REWARD", 192, table.concat(parts," "), C_GREEN, true)
    else
        self:readout("RANK", 76, "-- no card --", C_RED, true)
    end
    if DunKa.isOnCooldown and DunKa.isOnCooldown() then
        self:readout("COOLDOWN", 250, DunKa.fmtRemaining(DunKa.cooldownRemainingMs()), C_AMBER, true)
    else
        self:readout("COOLDOWN", 250, "READY", C_GREEN, true)
    end

    -- result flash
    if self.resultTimer and self.resultTimer>0 then
        local txt = self.resultPass and "ACCESS GRANTED" or "ACCESS DENIED"
        local c = self.resultPass and C_GREEN or C_RED2
        self:drawTextCentre(txt, CH.x+CH.w/2, CH.y+CH.h/2-11, c[1],c[2],c[3], 1, UIFont.Large)
    end

    -- summon button
    local armed = self.solved and self.rankId
    local a = armed and 1.0 or 0.4
    self:drawRect(BTN.x,BTN.y,BTN.w,BTN.h, a, 0.64,0.18,0.18)
    self:drawRectBorder(BTN.x,BTN.y,BTN.w,BTN.h, math.max(a,0.6), col(C_RED2))
    self:drawTextCentre("SUMMON HORDE", BTN.x+BTN.w/2, BTN.y+BTN.h/2-11, 0.99,0.92,0.92, a<1 and 0.6 or 1, UIFont.Large)
end

function DunKaSummonUI:renderQuiz()
    self:drawTextCentre(self.quizQ or "?", CH.x+CH.w/2, CH.y+18, 0.9,0.9,0.85, 1, UIFont.Medium)
    for i,r in ipairs(self.answerRects) do
        self:drawRect(r.x,r.y,r.w,r.h, 0.9, 0.14,0.10,0.10)
        self:drawRectBorder(r.x,r.y,r.w,r.h, 0.9, 0.45,0.24,0.24)
        local a=self.answers[i]
        self:drawTextCentre(a and a.text or "", r.x+r.w/2, r.y+r.h/2-11, 0.92,0.9,0.85, 1, UIFont.Large)
    end
end

function DunKaSummonUI:renderPuzzle()
    self:drawText("arrange 1 - 9 in order", CH.x+10, CH.y+8, 0.5,0.5,0.47, 1, UIFont.Small)
    for i=1,9 do
        local cx=self.pGX+((i-1)%3)*self.pCell
        local cy=self.pGY+math.floor((i-1)/3)*self.pCell
        local n=self.perm[i]
        local ok=(n==i)
        self:drawRect(cx,cy,self.pCell-3,self.pCell-3, 1, ok and 0.10 or 0.14, ok and 0.16 or 0.10, ok and 0.10 or 0.10)
        if self.selTile==i then self:drawRectBorder(cx,cy,self.pCell-3,self.pCell-3, 1, 0.94,0.62,0.15)
        else self:drawRectBorder(cx,cy,self.pCell-3,self.pCell-3, 1, 0.4,0.22,0.22) end
        local r,g,b = ok and 0.59 or 0.9, ok and 0.77 or 0.85, ok and 0.35 or 0.8
        self:drawTextCentre(tostring(n), cx+(self.pCell-3)/2, cy+(self.pCell-3)/2-11, r,g,b, 1, UIFont.Large)
    end
end

print("[DunKa] SummonUI terminal loaded")
