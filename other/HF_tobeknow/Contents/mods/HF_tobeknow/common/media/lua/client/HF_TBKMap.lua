-- Author: AKA (LOOKCHINNOL)  ·  Copyright (c) 2026 AKA. All Rights Reserved.
-- HF_TBKMap - ใบแผนที่หมู่เกาะ
-- ข้อความบนจอเป็นภาษาอังกฤษล้วน (ฟอนต์ PZ ไม่มี glyph ไทย) ตัวหนังสือไทยอยู่ในรูป PNG แทน

require "ISUI/ISCollapsableWindow"
require "ISUI/ISPanel"
require "ISUI/ISButton"

HFTBK = HFTBK or {}
HFTBK.ITEM = "Base.HF_TBKMap"
HFTBK.TEX  = "media/textures/HF_TBKMap/hf_islandmap.png"

-- getTexture() คืน Java object ไม่ใช่ table -> ต้องเรียกเมธอด ไม่ใช่อ่านฟิลด์ .w/.h
local function texSize(tex)
	if not tex then return nil end
	local ok, w, h = pcall(function() return tex:getWidth(), tex:getHeight() end)
	if not ok or type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then
		return nil
	end
	return w, h
end

local function T(key, fallback)
	local ok, s = pcall(function() return getText(key) end)
	if ok and type(s) == "string" and s ~= "" and s ~= key then return s end
	return fallback
end

--------------------------------------------------------------------- view

HFTBKView = ISPanel:derive("HFTBKView")

function HFTBKView:new(x, y, w, h)
	local o = ISPanel.new(self, x, y, w, h)
	setmetatable(o, self)
	self.__index = self
	o.backgroundColor = { r = 0.07, g = 0.06, b = 0.05, a = 1 }
	o.borderColor     = { r = 0.42, g = 0.36, b = 0.28, a = 1 }
	o.zoom    = 1.0
	o.offX    = 0
	o.offY    = 0
	o.dragging = false
	o.fitted  = false
	o.errShown = false
	o.tex     = nil
	o.drawn   = 0
	return o
end

function HFTBKView:ensureTexture()
	if self.tex == nil then
		local ok, t = pcall(function() return getTexture(HFTBK.TEX) end)
		if ok then self.tex = t end
	end
	return self.tex
end

function HFTBKView:fit()
	local tw, th = texSize(self:ensureTexture())
	if not tw then return false end
	local s = math.min(self.width / tw, self.height / th)
	if s <= 0 then return false end
	self.zoom = s
	self.offX = (self.width - tw * s) / 2
	self.offY = (self.height - th * s) / 2
	self.fitted = true
	return true
end

function HFTBKView:drawMap()
	local tex = self:ensureTexture()
	local tw, th = texSize(tex)
	if not tw then error("texture unavailable: " .. tostring(HFTBK.TEX)) end
	if not self.fitted then self:fit() end
	self:setStencilRect(0, 0, self.width, self.height)
	self:drawTextureScaled(tex, self.offX, self.offY, tw * self.zoom, th * self.zoom, 1, 1, 1, 1)
	self:clearStencilRect()
	self.drawn = self.drawn + 1
end

function HFTBKView:render()
	ISPanel.render(self)
	local ok, err = pcall(function() self:drawMap() end)
	if not ok then
		if not self.errShown then
			self.errShown = true
			print("[HF_TBKMap] draw error: " .. tostring(err))
		end
		self:drawTextCentre("Map image failed to load.", self.width / 2, self.height / 2 - 22, 1, 0.55, 0.4, 1, UIFont.Medium)
		self:drawTextCentre(HFTBK.TEX, self.width / 2, self.height / 2 + 4, 0.7, 0.7, 0.7, 1, UIFont.Small)
		self:drawTextCentre("Check that the mod folder is installed correctly.", self.width / 2, self.height / 2 + 24, 0.7, 0.7, 0.7, 1, UIFont.Small)
	end
end

function HFTBKView:onMouseDown(x, y)
	self.dragging = true
	return true
end

function HFTBKView:onMouseUp(x, y)
	self.dragging = false
	return true
end

function HFTBKView:onMouseUpOutside(x, y)
	self.dragging = false
	return true
end

function HFTBKView:onMouseMove(dx, dy)
	if self.dragging then
		self.offX = self.offX + dx
		self.offY = self.offY + dy
	end
end

function HFTBKView:onMouseMoveOutside(dx, dy)
	self.dragging = false
end

function HFTBKView:onMouseWheel(del)
	local tw, th = texSize(self:ensureTexture())
	if not tw then return true end
	local old = self.zoom
	if old <= 0 then old = 1 end
	local z = old
	if del < 0 then z = old * 1.2 else z = old / 1.2 end
	if z < 0.05 then z = 0.05 end
	if z > 6.0 then z = 6.0 end
	local mx = self:getMouseX()
	local my = self:getMouseY()
	self.offX = mx - (mx - self.offX) * (z / old)
	self.offY = my - (my - self.offY) * (z / old)
	self.zoom = z
	return true
end

--------------------------------------------------------------------- window

HFTBKWindow = ISCollapsableWindow:derive("HFTBKWindow")

function HFTBKWindow:new(x, y, w, h)
	local o = ISCollapsableWindow.new(self, x, y, w, h)
	setmetatable(o, self)
	self.__index = self
	o.title = "Island Map"
	o.resizable = true
	o.drawFrame = true
	o.btnH = 26
	return o
end

function HFTBKWindow:createChildren()
	ISCollapsableWindow.createChildren(self)
	local th = self:titleBarHeight()
	local bh = self.btnH

	self.view = HFTBKView:new(4, th + 4, self.width - 8, self.height - th - bh - 14)
	self.view:initialise()
	self:addChild(self.view)

	self.btnFit = ISButton:new(4, self.height - bh - 4, 90, bh, "Fit", self, HFTBKWindow.onFit)
	self.btnFit:initialise()
	self.btnFit:instantiate()
	self.btnFit.borderColor = { r = 0.5, g = 0.45, b = 0.35, a = 1 }
	self:addChild(self.btnFit)

	self.btnClose2 = ISButton:new(98, self.height - bh - 4, 90, bh, "Close", self, HFTBKWindow.onCloseBtn)
	self.btnClose2:initialise()
	self.btnClose2:instantiate()
	self.btnClose2.borderColor = { r = 0.5, g = 0.45, b = 0.35, a = 1 }
	self:addChild(self.btnClose2)
end

function HFTBKWindow:onFit()
	if self.view then self.view:fit() end
end

function HFTBKWindow:onCloseBtn()
	self:close()
end

function HFTBKWindow:close()
	self:setVisible(false)
	self:removeFromUIManager()
	HFTBK.window = nil
end

-- จัดผังทุกเฟรม แทนการพึ่ง onResize ที่ไม่การันตีว่ามีในทุกบิลด์
function HFTBKWindow:prerender()
	ISCollapsableWindow.prerender(self)
	local th = self:titleBarHeight()
	local bh = self.btnH
	if self.view then
		local vw = self.width - 8
		local vh = self.height - th - bh - 14
		if vw < 40 then vw = 40 end
		if vh < 40 then vh = 40 end
		self.view:setX(4)
		self.view:setY(th + 4)
		self.view:setWidth(vw)
		self.view:setHeight(vh)
	end
	if self.btnFit then
		self.btnFit:setX(4)
		self.btnFit:setY(self.height - bh - 4)
	end
	if self.btnClose2 then
		self.btnClose2:setX(98)
		self.btnClose2:setY(self.height - bh - 4)
	end
end

function HFTBKWindow:render()
	ISCollapsableWindow.render(self)
	local hint = "Drag to pan  ·  Mouse wheel to zoom"
	self:drawText(hint, 196, self.height - self.btnH - 1, 0.68, 0.64, 0.58, 1, UIFont.Small)
end

--------------------------------------------------------------------- open

function HFTBK.open()
	if HFTBK.window then
		local ok, vis = pcall(function() return HFTBK.window:getIsVisible() end)
		if ok and vis then
			HFTBK.window:bringToTop()
			return
		end
		HFTBK.window = nil
	end
	local core = getCore()
	local sw = core:getScreenWidth()
	local sh = core:getScreenHeight()
	local w = math.min(920, sw - 60)
	local h = math.min(980, sh - 60)
	if w < 400 then w = 400 end
	if h < 400 then h = 400 end
	local win = HFTBKWindow:new((sw - w) / 2, (sh - h) / 2, w, h)
	win:initialise()
	win:addToUIManager()
	win:setVisible(true)
	HFTBK.window = win
end

--------------------------------------------------------------------- context menu

local function fullTypeOf(it)
	if not it then return nil end
	local ok, ft = pcall(function() return it:getFullType() end)
	if ok and type(ft) == "string" then return ft end
	return nil
end

local function findMapItem(items)
	if type(items) ~= "table" then return nil end
	for i = 1, #items do
		local e = items[i]
		if type(e) == "table" and e.items and e.items[1] then e = e.items[1] end
		if fullTypeOf(e) == HFTBK.ITEM then return e end
	end
	return nil
end

local function onFillInventoryContextMenu(player, context, items)
	local ok = pcall(function()
		if not context or not findMapItem(items) then return end
		context:addOption(T("ContextMenu_HF_TBKMap_Read", "Read: Island Map"), nil, function()
			HFTBK.open()
		end)
	end)
	if not ok then
		print("[HF_TBKMap] context menu error")
	end
end

if Events and Events.OnFillInventoryObjectContextMenu then
	Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryContextMenu)
end

--------------------------------------------------------------------- admin fallback
-- เปิดแผนที่ได้โดยไม่ต้องมีไอเทม: แอดมิน/debug คลิกขวาที่พื้น
-- มีไว้เพื่อไม่ให้ "ไอเทมหาย" = "เปิดแผนที่ไม่ได้เลย"

local function isStaff()
	local ok, yes = pcall(function()
		local p = getSpecificPlayer(0)
		if p and p.isAccessLevel then
			if p:isAccessLevel("admin") or p:isAccessLevel("moderator") or p:isAccessLevel("overseer")
				or p:isAccessLevel("gm") or p:isAccessLevel("observer") then
				return true
			end
		end
		if isAdmin and isAdmin() then return true end
		if isDebugEnabled and isDebugEnabled() then return true end
		if getCore and getCore():getGameMode() == "Sandbox" then return false end
		return false
	end)
	return ok and yes == true
end

local function onFillWorldContextMenu(player, context, worldobjects, test)
	if test then return end
	pcall(function()
		if not context then return end
		if not isStaff() then return end
		context:addOption(T("ContextMenu_HF_TBKMap_Admin", "Island Map (admin)"), nil, function()
			HFTBK.open()
		end)
	end)
end

if Events and Events.OnFillWorldObjectContextMenu then
	Events.OnFillWorldObjectContextMenu.Add(onFillWorldContextMenu)
end

--------------------------------------------------------------------- self probe
-- probe-first: บอกใน console.txt ไปเลยว่าเอนจินรู้จักไอเทมนี้ไหม
-- จะได้ไม่ต้องเดาว่า "หาไอเทมไม่เจอ" เพราะม็อดไม่โหลด หรือเพราะ script ผิด

local function selfProbe()
	local msg = "[HF_TBKMap] probe: "
	local ok, res = pcall(function()
		local sm = getScriptManager()
		if not sm then return "no script manager" end
		local it = sm:FindItem(HFTBK.ITEM)
		if not it then return "ITEM NOT FOUND -> the .txt script did not load" end
		local inst = instanceItem(HFTBK.ITEM)
		if not inst then return "item def found but instanceItem() returned nil" end
		return "OK - " .. HFTBK.ITEM .. " exists and can be spawned"
	end)
	if ok then print(msg .. tostring(res)) else print(msg .. "threw: " .. tostring(res)) end

	local tex = getTexture(HFTBK.TEX)
	local w, h = texSize(tex)
	if w then
		print("[HF_TBKMap] probe: texture OK " .. tostring(w) .. "x" .. tostring(h))
	else
		print("[HF_TBKMap] probe: TEXTURE MISSING -> " .. HFTBK.TEX)
	end
end

if Events and Events.OnGameStart then
	Events.OnGameStart.Add(function() pcall(selfProbe) end)
end

print("[HF_TBKMap] client loaded")
