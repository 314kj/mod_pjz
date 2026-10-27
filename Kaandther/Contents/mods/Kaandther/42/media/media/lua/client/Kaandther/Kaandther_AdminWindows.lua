--[[ ============================================================
     kaandther - ADMIN sub-windows: Add + Import/Create (client, staff)
     Import: BASE-GAME SETS (checkbox) + CUSTOM (name + own weapons +
             which category's numbers).  Autocomplete on the add field.
     Robust item scan with fallback so suggestions always appear.
     ============================================================ ]]
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISTextEntryBox"

Kaandther = Kaandther or {}
Kaandther.UI = Kaandther.UI or {}
local drawIcon = Kaandther.UI.drawIcon or function() end
local function shortName(ft) if not ft then return "?" end return (ft:gsub("^.-%.","")) end
local CATLBL = { blunt="Blunt",shortblade="Short Blade",longblade="Long Blade",axe="Axe",spear="Spear",firearm="Firearm",improvised="Improvised" }

-- ---- item scan (robust, cached, with fallback) ----
Kaandther.UI._items=nil
local function allItems()
    if Kaandther.UI._items then return Kaandther.UI._items end
    local out={}
    pcall(function()
        local sm=getScriptManager(); local list=sm and sm:getAllItems()
        if list then
            for i=0,list:size()-1 do
                local si=list:get(i); local full
                pcall(function() full=si:getFullName() end)
                if not full then pcall(function() full=si:getModuleName().."."..si:getName() end) end
                if full then local nm; pcall(function() nm=si:getDisplayName() end)
                    out[#out+1]={ft=full, name=nm or shortName(full)} end
            end
        end
    end)
    if #out==0 then   -- fallback: known weapons
        local seen={}
        for ft in pairs((Kaandther.Presets and Kaandther.Presets.MAP) or {}) do if not seen[ft] then out[#out+1]={ft=ft,name=shortName(ft)}; seen[ft]=true end end
        for ft in pairs((Kaandther.Config and Kaandther.Config.WEAPONS) or {}) do if not seen[ft] then out[#out+1]={ft=ft,name=shortName(ft)}; seen[ft]=true end end
    end
    table.sort(out,function(a,b) return a.ft<b.ft end)
    Kaandther.UI._items=out; return out
end
function Kaandther.UI.searchItems(q,max)
    q=(q or ""):lower(); max=max or 8; local res={}
    if q=="" then return res end
    for _,it in ipairs(allItems()) do
        if it.ft:lower():find(q,1,true) or (it.name or ""):lower():find(q,1,true) then
            res[#res+1]=it; if #res>=max then break end end
    end
    return res
end

local function mkEntry(self,x,y,w) local e=ISTextEntryBox:new("",x,y,w,24); e:initialise(); e:instantiate(); e.font=UIFont.Small; self:addChild(e); return e end
local function mkBtn(self,x,y,w,h,l,fn) local b=ISButton:new(x,y,w,h,l,self,fn); b:initialise(); b:instantiate(); self:addChild(b); return b end

--[[ ===== ADD WINDOW ===== ]]
KaandtherAdd = ISCollapsableWindow:derive("KaandtherAdd")
local AD=KaandtherAdd
function AD:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.resizable=false
    pcall(function() if self.resizeWidget then self.resizeWidget:setVisible(false) end end)
    pcall(function() if self.resizeWidget2 then self.resizeWidget2:setVisible(false) end end)
    self.sugScroll=0
    local top=self:titleBarHeight()
    self.eSearch=mkEntry(self, 12, top+30, self.width-90)
    self.bAdd=mkBtn(self, self.width-70, top+29, 58, 24, "Add", AD.onAddTyped)
    self.bClose=mkBtn(self, self.width-82, self.height-34, 70, 24, "Close", AD.onClose)
    self.sugY=top+62
end
function AD:onAddTyped() local ft=self.eSearch:getText():gsub("%s+",""); if ft=="" then return end
    Kaandther.Admin.addType(ft); self.eSearch:setText(""); if self.parentPanel then self.parentPanel.refreshTick=12 end end
function AD:onClose() self:setVisible(false); self:removeFromUIManager() end
function AD:onMouseWheel(del) self.sugScroll=math.max(0, math.min(self.sugMax or 0,(self.sugScroll or 0)+del)); return true end
function AD:onMouseDown(x,y)
    local vis=self.visSug or {}
    for i,it in ipairs(vis) do local ry=self.sugY+(i-1)*22
        if y>=ry-2 and y<=ry+20 then Kaandther.Admin.addType(it.ft); self.eSearch:setText("")
            if self.parentPanel then self.parentPanel.refreshTick=12 end return true end end
    return ISCollapsableWindow.onMouseDown(self,x,y)
end
function AD:prerender()
    ISCollapsableWindow.prerender(self)
    local top=self:titleBarHeight(); local fS=UIFont.Small
    self:drawRect(0,top,self.width,self.height-top,0.95,0.08,0.09,0.11)
    self:drawRectBorder(0,top,self.width,self.height-top,0.6,0.85,0.72,0.32)
    self:drawText("type a weapon name or Base.Type, then Add", 12, top+10, 0.6,0.62,0.66,1, fS)
    self.curSug=Kaandther.UI.searchItems(self.eSearch:getText(), 40)
    local rowsMax=math.floor((self.height-34-self.sugY)/22)
    self.sugMax=math.max(0,#self.curSug-rowsMax)
    if (self.sugScroll or 0)>self.sugMax then self.sugScroll=self.sugMax end
    self.visSug={}
    for i=1,math.min(rowsMax,#self.curSug) do self.visSug[i]=self.curSug[i+(self.sugScroll or 0)] end
    local n=#self.visSug
    if n>0 then self:drawRect(10,self.sugY-4,self.width-20,n*22+6,0.96,0.05,0.06,0.09); self:drawRectBorder(10,self.sugY-4,self.width-20,n*22+6,0.8,0.3,0.42,0.58) end
    for i,it in ipairs(self.visSug) do local ry=self.sugY+(i-1)*22
        drawIcon(self, it.ft, 14, ry, 18)
        self:drawText(it.name or shortName(it.ft), 38, ry+2, 0.9,0.9,0.9,1, fS)
        self:drawText(it.ft, self.width-12-getTextManager():MeasureStringX(fS,it.ft), ry+2, 0.45,0.47,0.52,1, fS)
    end
    if self.sugMax>0 then self:drawText("scroll for more ("..#self.curSug..")", 12, self.height-30, 0.5,0.55,0.6,1, fS) end
    if #self.curSug==0 and self.eSearch:getText()~="" then self:drawText("no match - type full Base.Type + Add", 12, self.sugY, 0.55,0.55,0.5,1, fS) end
end
function Kaandther.UI.openAdd(parent)
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    local ww,hh=500,420; local win=KaandtherAdd:new(sw/2-ww/2, sh/2-hh/2, ww, hh); win.title="Add Weapon"; win.parentPanel=parent
    win:initialise(); win:addToUIManager(); return win
end

--[[ ===== IMPORT / CREATE WINDOW ===== ]]
KaandtherImport = ISCollapsableWindow:derive("KaandtherImport")
local IM=KaandtherImport
function IM:createChildren()
    ISCollapsableWindow.createChildren(self)
    self.resizable=false
    pcall(function() if self.resizeWidget then self.resizeWidget:setVisible(false) end end)
    pcall(function() if self.resizeWidget2 then self.resizeWidget2:setVisible(false) end end)
    local top=self:titleBarHeight()
    self.cats=(Kaandther.Presets and Kaandther.Presets.categories and Kaandther.Presets.categories()) or {}
    self.checked={}; self.baseList={}
    for _,c in ipairs(self.cats) do self.baseList[c]={}
        for ft,cc in pairs((Kaandther.Presets and Kaandther.Presets.MAP) or {}) do if cc==c then self.baseList[c][#self.baseList[c]+1]=ft end end
        table.sort(self.baseList[c]) end
    self.sel={kind="base", cat=self.cats[1]}
    self.numIdx=1; self.imScroll=0; self.sugScroll=0
    local rx=194
    self.eName=mkEntry(self, rx+50, top+8, self.width-rx-60); self.eName:setText("")
    self.eAdd=mkEntry(self, rx, self.height-90, self.width-rx-52)
    self.bAddRow=mkBtn(self, self.width-46, self.height-91, 36, 24, "+", IM.onAddRow)
    self.bImport=mkBtn(self, self.width-92, self.height-34, 82, 24, "Import", IM.onImport)
    self.bSave=mkBtn(self, self.width-182, self.height-34, 84, 24, "Save preset", IM.onSave)
    self.bCancel=mkBtn(self, 12, self.height-34, 74, 24, "Cancel", IM.onClose)
    self.listY=top+30
end
function IM:curList()
    if self.sel.kind=="base" then return self.baseList[self.sel.cat] or {} end
    self.customList=self.customList or {}; return self.customList
end
function IM:addFT(ft)
    if not ft or ft=="" then return end
    if not ft:find("%.") then ft="Base."..ft end
    local l=self:curList(); l[#l+1]=ft
    if self.sel.kind=="base" then self.checked[self.sel.cat]=true end
end
function IM:onAddRow() self:addFT(self.eAdd:getText():gsub("%s+","")); self.eAdd:setText(""); self.sugScroll=0 end
function IM:customName() local nm=(self.eName:getText():gsub("^%s+",""):gsub("%s+$","")); if nm=="" then nm="Custom" end return nm end
function IM:onSave()   -- save custom definition only (no weapon apply)
    if self.sel.kind~="custom" then return end
    pcall(function()
        local nm=self:customName()
        if self.sel.name and self.sel.name~=nm then Kaandther.Admin.delCustom(self.sel.name) end
        Kaandther.Admin.saveCustom(nm, self.cats[self.numIdx] or "improvised", self.customList or {})
        self.sel={kind="custom", name=nm}
    end)
    if self.parentPanel then self.parentPanel.refreshTick=8 end
end
function IM:onImport()
    pcall(function()
        for _,c in ipairs(self.cats) do if self.checked[c] then for _,ft in ipairs(self.baseList[c] or {}) do Kaandther.Admin.applyCategory(ft,c) end end end
        if self.sel.kind=="custom" then
            local nm=self:customName()
            if self.sel.name and self.sel.name~=nm then Kaandther.Admin.delCustom(self.sel.name) end
            Kaandther.Admin.applyCustom(nm, self.cats[self.numIdx] or "improvised", self.customList or {})
        end
    end)
    if self.parentPanel then self.parentPanel.refreshTick=15 end
    self:onClose()
end
function IM:onClose() self:setVisible(false); self:removeFromUIManager() end
function IM:onMouseWheel(del)
    if self._overSug and (self.sugMax or 0)>0 then self.sugScroll=math.max(0,math.min(self.sugMax,(self.sugScroll or 0)+del))
    else self.imScroll=math.max(0, math.min(self.imMax or 0, (self.imScroll or 0)+del*22)) end
    return true
end
function IM:onMouseDown(x,y)
    local top=self:titleBarHeight(); local rx=194
    if self.sel.kind=="custom" and x>=rx+88 and x<=rx+208 and y>=top+37 and y<=top+57 then
        self.numIdx=(self.numIdx % #self.cats)+1; return true end
    for i,it in ipairs(self.visSug or {}) do local ry=self.sugY+(i-1)*20
        if x>=rx-2 and y>=ry-1 and y<=ry+18 then self:addFT(it.ft); self.eAdd:setText(""); self.sugScroll=0; return true end end
    for _,r in ipairs(self.leftRows or {}) do
        if y>=r.y-2 and y<=r.y+18 then
            if r.kind=="custom" and x>=160 and x<=182 then Kaandther.Admin.delCustom(r.name)
                if self.parentPanel then self.parentPanel.refreshTick=8 end
                if self.sel.name==r.name then self.sel={kind="base",cat=self.cats[1]} end return true end
            if x>=8 and x<=182 then
                if r.kind=="base" then if x<=26 then self.checked[r.cat]=not self.checked[r.cat] else self.sel={kind="base",cat=r.cat}; self.imScroll=0 end
                elseif r.kind=="new" then self.sel={kind="custom"}; self.customList={}; self.eName:setText("New Set"); self.imScroll=0
                elseif r.kind=="custom" then self.sel={kind="custom",name=r.name}; self.eName:setText(r.name); self.imScroll=0
                    local def=(Kaandther.Config.CUSTOM or {})[r.name] or {}; self.customList={}
                    for _,ft in ipairs(def.weapons or {}) do self.customList[#self.customList+1]=ft end
                    for i2,c in ipairs(self.cats) do if c==def.cat then self.numIdx=i2 end end end
                return true end end end
    for _,r in ipairs(self.wRows or {}) do
        if x>=self.width-40 and x<=self.width-12 and y>=r.y and y<=r.y+18 then table.remove(self:curList(), r.i); return true end end
    return ISCollapsableWindow.onMouseDown(self,x,y)
end
function IM:prerender()
    ISCollapsableWindow.prerender(self)
    local top=self:titleBarHeight(); local fS,fM=UIFont.Small,UIFont.Medium
    self:drawRect(0,top,self.width,self.height-top,0.95,0.08,0.09,0.11)
    self:drawRectBorder(0,top,self.width,self.height-top,0.6,0.85,0.72,0.32)
    self:drawRect(184,top,1,self.height-top,0.5,0.3,0.3,0.34)
    if self.eName then self.eName:setVisible(self.sel.kind=="custom") end
    if self.bSave then self.bSave:setVisible(self.sel.kind=="custom") end
    -- LEFT
    self.leftRows={}
    local ly=self.listY
    self:drawText("BASE-GAME SETS", 10, ly-16, 0.5,0.53,0.58,1, fS)
    for _,c in ipairs(self.cats) do
        if self.sel.kind=="base" and self.sel.cat==c then self:drawRect(8,ly-2,174,20,0.3,0.2,0.35,0.5) end
        local ck=self.checked[c]
        self:drawRect(12,ly+2,13,13, ck and 1 or 0.8, ck and 0.2 or 0.06, ck and 0.7 or 0.07, ck and 0.35 or 0.09)
        self:drawRectBorder(12,ly+2,13,13,0.8,0.4,0.42,0.46)
        self:drawText((CATLBL[c] or c).." ("..#(self.baseList[c] or {})..")", 32, ly+1, 0.9,0.9,0.9,1, fS)
        self.leftRows[#self.leftRows+1]={kind="base",cat=c,y=ly}; ly=ly+22
    end
    ly=ly+8; self:drawText("CUSTOM", 10, ly-2, 0.5,0.53,0.58,1, fS); ly=ly+16
    if self.sel.kind=="custom" and not self.sel.name then self:drawRect(8,ly-2,174,20,0.3,0.3,0.25,0.5) end
    self:drawText("+ New custom preset", 12, ly+1, 0.55,0.75,0.6,1, fS); self.leftRows[#self.leftRows+1]={kind="new",y=ly}; ly=ly+22
    for name in pairs(Kaandther.Config.CUSTOM or {}) do
        if self.sel.kind=="custom" and self.sel.name==name then self:drawRect(8,ly-2,174,20,0.3,0.3,0.25,0.5) end
        self:drawText(name, 12, ly+1, 0.85,0.78,0.55,1, fS)
        self:drawText("X", 166, ly+1, 0.8,0.35,0.35,1, fS)
        self.leftRows[#self.leftRows+1]={kind="custom",name=name,y=ly}; ly=ly+22
    end
    -- RIGHT
    local rx=194
    local listTop
    if self.sel.kind=="custom" then
        self:drawText("Name", rx, top+12, 0.7,0.72,0.76,1, fS)
        local nc=CATLBL[self.cats[self.numIdx]] or self.cats[self.numIdx] or "?"
        self:drawText("numbers from:", rx, top+40, 0.6,0.62,0.66,1, fS)
        self:drawRect(rx+88,top+37,120,20,0.9,0.14,0.16,0.2); self:drawRectBorder(rx+88,top+37,120,20,0.8,0.4,0.42,0.5)
        self:drawText(nc.."  >", rx+94, top+40, 0.85,0.85,0.9,1, fS)
        listTop=top+66
    else
        self:drawText((CATLBL[self.sel.cat] or self.sel.cat).." weapons  (X removes)", rx, top+12, 0.7,0.72,0.76,1, fS)
        listTop=top+34
    end
    local listBottom=self.height-120
    self:drawRect(rx-2, listTop-2, self.width-rx-8, listBottom-listTop+4, 0.4, 0.04,0.05,0.07)
    local l=self:curList(); self.wRows={}
    local yy=listTop-(self.imScroll or 0)
    for i,ft in ipairs(l) do
        if yy>=listTop-22 and yy<=listBottom-18 then
            drawIcon(self, ft, rx, yy, 18)
            self:drawText(shortName(ft), rx+24, yy+2, 0.88,0.88,0.88,1, fS)
            self:drawText(ft, rx+150, yy+3, 0.42,0.44,0.48,1, fS)
            self:drawText("X", self.width-30, yy+2, 0.8,0.35,0.35,1, fS)
            self.wRows[#self.wRows+1]={i=i,y=yy}
        end
        yy=yy+22
    end
    local content=#l*22; self.imMax=math.max(0, content-(listBottom-listTop))
    if (self.imScroll or 0)>self.imMax then self.imScroll=self.imMax end
    if self.imMax>0 then local h=listBottom-listTop; local bh=math.max(18,h*h/content)
        self:drawRect(self.width-12, listTop+(h-bh)*((self.imScroll or 0)/self.imMax), 4, bh, 0.7, 0.35,0.4,0.5) end
    -- add + scrollable suggestions
    self:drawText("add: type name / Base.Type -> pick or +  (wheel to scroll)", rx, self.height-108, 0.5,0.55,0.6,1, fS)
    local all=Kaandther.UI.searchItems(self.eAdd:getText(), 40)
    local rows=5; self.sugMax=math.max(0,#all-rows)
    if (self.sugScroll or 0)>self.sugMax then self.sugScroll=self.sugMax end
    self.visSug={}
    for i=1,math.min(rows,#all) do self.visSug[i]=all[i+(self.sugScroll or 0)] end
    local n=#self.visSug
    self.sugY=self.height-92-(n*20)-4
    self._overSug=false
    if n>0 then
        self:drawRect(rx-2,self.sugY-3,self.width-rx-48,n*20+6,0.98,0.05,0.06,0.09)
        self:drawRectBorder(rx-2,self.sugY-3,self.width-rx-48,n*20+6,0.85,0.3,0.45,0.6)
        local my=0; pcall(function() my=self:getMouseY() end)
        if my>=self.sugY-3 and my<=self.sugY+n*20 then self._overSug=true end
        for i,it in ipairs(self.visSug) do local ry=self.sugY+(i-1)*20
            drawIcon(self, it.ft, rx, ry, 16)
            self:drawText(it.name or shortName(it.ft), rx+20, ry+1, 0.85,0.88,0.92,1, fS)
            self:drawText(it.ft, self.width-52-getTextManager():MeasureStringX(fS,it.ft), ry+1, 0.45,0.47,0.5,1, fS)
        end
        if self.sugMax>0 then self:drawText("("..#all..") wheel", self.width-90, self.sugY-16, 0.5,0.55,0.6,1, fS) end
    end
    local nsel=0 for _,c in ipairs(self.cats) do if self.checked[c] then nsel=nsel+1 end end
    self:drawText(nsel.." base checked"..(self.sel.kind=="custom" and " + custom" or ""), 96, self.height-30, 0.5,0.55,0.6,1, fS)
end
function Kaandther.UI.openImport(parent)
    local sw,sh=getCore():getScreenWidth(),getCore():getScreenHeight()
    local hh=math.min(460, sh-60)
    local ww=620; local win=KaandtherImport:new(sw/2-ww/2, math.max(20,sh/2-hh/2), ww, hh); win.title="Import / Create Preset"; win.parentPanel=parent
    win:initialise(); win:addToUIManager(); return win
end
