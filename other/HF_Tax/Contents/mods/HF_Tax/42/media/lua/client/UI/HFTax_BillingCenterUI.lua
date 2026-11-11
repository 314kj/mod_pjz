-- =============================================================================
-- Mod Name: HF_Tax (Project Zomboid B42.20+)
-- Original work: Copyright (c) 2026 matasa. All Rights Reserved.
-- UI revision: AKA (LOOKCHINNOL), published with the author's permission.
--
-- HFTax_BillingCenterUI.lua -- personal tax and house tax on one screen.
--
-- The whole screen is a pure function of a model table:
--     HFTaxUI.BillingCenter.render(element, model, W, H)
-- Nothing in here reads ModData or the player. That is what lets the same
-- drawing code run under _dev/render.lua to produce the design mock-up --
-- the picture and the game are the same code, so they cannot drift apart.
-- =============================================================================

---@diagnostic disable: undefined-global

-- PZ loads a folder in FILENAME order, and "HFTax_BillingCenterUI" sorts
-- before "HFTax_Theme" -- so the theme has to be required, not hoped for.
-- (PZ-B42-lua-load-order-RULE: this exact mistake killed Kuraya's auction and
-- credit systems on every server boot for several releases.)
require "UI/HFTax_Theme"

HFTaxUI = HFTaxUI or {}
HFTaxUI.BillingCenter = HFTaxUI.BillingCenter or {}

local BC = HFTaxUI.BillingCenter
local T = HFTaxUI.Theme

-- Locked widths. The rail never stretches; the two columns are the stretch.
local RAIL_W = 132

-- Click zones are handed back to the window so hit testing uses the very same
-- numbers that drew the thing. Rebuilt every frame.
local function zone(m, name, r, payload)
    if not r then return end
    m.__zones[#m.__zones + 1] = {
        name = name, x = r.x, y = r.y, w = r.w, h = r.h, payload = payload,
    }
end

-- ------------------------------------------------------------- title bar ---
local function titleBar(e, m, W)
    local P = T.pad()
    local h = T.h(T.F.M) + P * 2

    T.fill(e, 0, 0, W, h, T.C.card)
    T.fill(e, 0, h - 1, W, 1, T.C.line2)

    local ih = h - P
    T.art(e, "ic_invoice", P, math.floor((h - ih) / 2), ih, ih)

    local tx = P + ih + P
    T.text(e, "HF TAX", tx, math.floor((h - T.h(T.F.M)) / 2), T.C.purplePale, T.F.M)
    tx = tx + T.w(T.F.M, "HF TAX") + P

    local sy = math.floor((h - T.h(T.F.S)) / 2)
    T.text(e, "BILLING CENTER", tx, sy, T.C.textFaint, T.F.S)

    -- ? and X sit on the title bar of every window in the family, so a player
    -- who is lost never has to find out where this particular screen hid them.
    local bw = T.h(T.F.M) + P
    local bh = h - P
    local by = math.floor((h - bh) / 2)
    zone(m, "close", T.button(e, "close", "X", W - bw - P, by, bw, bh))
    -- The ? only appears once there is a manual behind it. A help button that
    -- opens nothing is worse than no help button: it spends the one place a
    -- lost player looks.
    if m.helpAvailable then
        zone(m, "help", T.button(e, "close", "?", W - bw * 2 - P * 2, by, bw, bh))
    end
    return h
end

-- ------------------------------------------------------------------ rail ---
local function rail(e, m, y0, H)
    local P = T.pad()
    T.fill(e, 0, y0, RAIL_W, H - y0, T.C.bg0)
    T.fill(e, RAIL_W - 1, y0, 1, H - y0, T.C.line)

    local items = {
        { id = "bills",   art = "ic_invoice", label = "BILLS",   accent = T.C.purple },
        { id = "history", art = "ic_paid",    label = "HISTORY", accent = T.C.green },
    }

    local ih = T.h(T.F.S) * 2
    local rowH = ih + T.h(T.F.S) + P * 2
    local y = y0 + P

    for i = 1, #items do
        local it = items[i]
        local on = (m.page == it.id)
        if on then
            T.fill(e, 0, y, RAIL_W, rowH, T.C.card)
            T.fill(e, 0, y, 3, rowH, it.accent)
        end
        T.art(e, it.art, math.floor((RAIL_W - ih) / 2), y + P, ih, ih, on and 1.0 or 0.45)
        T.textC(e, it.label, math.floor(RAIL_W / 2), y + P + ih,
            on and T.C.purplePale or T.C.textFaint, T.F.S)
        zone(m, "page:" .. it.id, { x = 0, y = y, w = RAIL_W, h = rowH })
        y = y + rowH
    end

    -- Streak lives at the bottom of the rail: always in view, never in the way.
    local sh = T.h(T.F.S) * 2 + T.h(T.F.L) + P * 3
    local sy = H - sh - P
    T.fill(e, 0, sy, RAIL_W, 1, T.C.line)
    -- The rail is a locked 132px but the font is not: at UI scale 1.5 the full
    -- label is wider than the rail. Clip against the rail, not against hope.
    T.textC(e, T.clip("ON-TIME STREAK", T.F.S, RAIL_W - 8), math.floor(RAIL_W / 2),
        sy + P, T.C.textFaint, T.F.S)
    T.textC(e, "x " .. tostring(m.streak), math.floor(RAIL_W / 2), sy + P + T.h(T.F.S),
        T.C.green, T.F.L)

    local pipN, pipS = 7, math.max(6, math.floor(T.h(T.F.S) * 0.6))
    local pipGap = 3
    local px = math.floor((RAIL_W - (pipN * pipS + (pipN - 1) * pipGap)) / 2)
    local py = sy + P + T.h(T.F.S) + T.h(T.F.L) + math.floor(P / 2)
    for i = 1, pipN do
        T.fill(e, px + (i - 1) * (pipS + pipGap), py, pipS, pipS,
            i <= m.streak and T.C.green or T.C.raise2)
    end
end

-- ------------------------------------------------------------ wallet bar ---
local function walletBar(e, m, x, y, W)
    local P = T.pad()
    local h = T.h(T.F.XL) + T.h(T.F.S) + P * 3
    T.panel(e, x, y, W, h, T.C.card, T.C.line)

    -- Total due: the one number the screen exists to show.
    local ih = T.h(T.F.XL)
    local cx = x + P
    T.art(e, m.totalDue > 0 and "ic_unpaid" or "ic_paid", cx, y + P + T.h(T.F.S), ih, ih)
    cx = cx + ih + P

    T.text(e, "TOTAL DUE", cx, y + P, T.C.textFaint, T.F.S)
    T.text(e, T.money(m.totalDue), cx, y + P + T.h(T.F.S),
        m.totalDue > 0 and T.C.redFg or T.C.green, T.F.XL)
    cx = cx + math.max(T.w(T.F.XL, T.money(m.totalDue)), T.w(T.F.S, "TOTAL DUE")) + P * 2

    T.fill(e, cx, y + P, 1, h - P * 2, T.C.line)
    cx = cx + P

    -- Counters. Icon over number, so the row reads without any sentence.
    local counts = {
        { art = "ic_invoice", v = m.bills, c = T.C.textDim,  bg = T.C.raise },
        { art = "ic_due",     v = m.late,  c = T.C.orange,   bg = T.C.raise },
        { art = "ic_cutoff",  v = m.cut,   c = T.C.redFg,    bg = T.C.redBg },
    }
    local cw = T.h(T.F.L) * 2
    local ch = h - P * 2
    for i = 1, #counts do
        local it = counts[i]
        T.panel(e, cx, y + P, cw, ch, it.bg, it.v > 0 and it.c or T.C.line2)
        local a = it.v > 0 and 1.0 or 0.4
        local aih = math.floor(ch * 0.5)
        T.art(e, it.art, cx + math.floor((cw - aih) / 2), y + P + math.floor(P / 2), aih, aih, a)
        T.textC(e, tostring(it.v), cx + math.floor(cw / 2),
            y + P + math.floor(P / 2) + aih, it.v > 0 and it.c or T.C.textFaint, T.F.M)
        cx = cx + cw + math.floor(P / 2)
    end

    -- Wallets and PAY ALL are anchored to the right edge, so they stay put no
    -- matter how wide the numbers on the left get.
    local btnW = T.w(T.F.M, "PAY ALL") + T.h(T.F.L) * 4
    local walW = T.w(T.F.L, "$0,000") + T.h(T.F.L) * 3
    local bh = h - P * 2
    local bx = x + W - P - btnW

    local canPay = m.totalDue > 0 and m.payable
    local r = T.button(e, canPay and "go" or "off", "PAY ALL", bx, y + P, btnW, bh, "ic_cash", T.F.M)
    if canPay then zone(m, "payall", r) end
    -- "1 BILLS" reads like a bug even when the number is right.
    local billWord = (m.bills == 1) and " BILL" or " BILLS"
    T.textC(e, canPay and (T.money(m.totalDue) .. " - " .. m.bills .. billWord) or "NOTHING TO PAY",
        bx + math.floor(btnW / 2), y + P + bh - T.h(T.F.S) - 2,
        canPay and T.C.green or T.C.textFaint, T.F.S)

    local function wallet(wx, art, label, value, on, col)
        T.panel(e, wx, y + P, walW, bh, T.C.raise, on and col or T.C.line2)
        local wih = math.floor(bh * 0.55)
        T.art(e, art, wx + math.floor(P / 2), y + P + math.floor((bh - wih) / 2), wih, wih,
            on and 1.0 or 0.35)
        local tx = wx + math.floor(P / 2) + wih + math.floor(P / 2)
        T.text(e, label, tx, y + P + math.floor(P / 2), T.C.textFaint, T.F.S)
        T.text(e, on and T.money(value) or "DISABLED", tx,
            y + P + math.floor(P / 2) + T.h(T.F.S),
            on and col or T.C.textFaint, on and T.F.L or T.F.S)
    end

    bx = bx - P - walW
    wallet(bx, "ic_bank", "BANK", m.wallet.bank, m.wallet.bankOn, T.C.cyan)
    bx = bx - math.floor(P / 2) - walW
    wallet(bx, "ic_purse", "CASH", m.wallet.cash, m.wallet.cashOn, T.C.green)

    return h
end

-- ----------------------------------------------------------------- cards ---
---One bill. Compact by default; only the selected one opens up. That is the
---whole answer to "too much detail" -- the detail still exists, it just waits
---to be asked for.
local function billCard(e, m, b, x, y, w, expanded)
    local P = T.pad()
    local artH = T.h(T.F.L) + T.h(T.F.S)
    local topH = artH + P * 2
    local drawerH = expanded and (T.h(T.F.M) + P * 3) or 0
    local h = topH + drawerH

    T.panel(e, x, y, w, h, expanded and T.C.raise2 or T.C.card,
        expanded and T.C.purple or T.C.line)

    local st = T.status(b.status)
    T.fill(e, x, y, 4, h, st.c)

    -- art column
    local ax = x + 4 + P
    T.art(e, b.art, ax, y + P, artH, artH, b.status == "paid" and 0.55 or 1.0)

    -- middle: number then countdown. Nothing else on a closed card.
    local mx = ax + artH + P
    local rightW = math.floor(w * 0.36)
    local midW = w - (mx - x) - rightW - P

    T.text(e, T.clip(b.no, T.F.M, midW), mx, y + P,
        b.status == "paid" and T.C.textDim or T.C.textHi, T.F.M)

    local fy = y + P + T.h(T.F.M) + math.floor(P / 2)
    local nx = mx
    if b.frac then
        local fw = T.fuse(e, mx, fy + 2, b.frac, st.c)
        nx = mx + fw + P
    end
    T.text(e, T.clip(b.note, T.F.S, midW - (nx - mx)), nx, fy,
        b.status == "paid" and T.C.textFaint or st.c, T.F.S)

    -- Right side: amount, and the status mark to the LEFT of it on the same
    -- line. Stacking them made the mark hang past the bottom of a short card
    -- at UI scale 1.0, which is the sort of thing only a rendered frame shows.
    local rx = x + w - P
    local amtY = y + math.floor((topH - T.h(T.F.L)) / 2)
    T.textR(e, T.money(b.amount), rx, amtY,
        b.status == "paid" and T.C.green or T.C.redFg, T.F.L)

    local markR = rx - T.w(T.F.L, T.money(b.amount)) - P
    local midY = y + math.floor(topH / 2)

    if b.status == "paid" then
        -- The SUCCESS stamp does NOT go here. It is 3:1 and rotated, so at row
        -- height it either gets clipped or forces the row taller -- and a row
        -- grown to fit a decoration is a row that scans worse for every bill
        -- in the list. The stamp lives on the receipt instead, big and faint.
        local aw = T.artRightW(e, "th_paid", markR, midY, math.floor(T.h(T.F.L) * 2.6))
        if aw == 0 then T.textR(e, st.label, markR, amtY, T.C.green, T.F.S) end
    elseif b.status == "due" or b.status == "late" then
        -- Thai word art -- the only way Thai can exist on screen at all, since
        -- PZ's bitmap font has no Thai glyphs. A picture is a picture.
        local aw = T.artRightW(e, "th_unpaid", markR, midY, math.floor(T.h(T.F.L) * 2.6))
        if aw == 0 then T.textR(e, st.label, markR, amtY, st.c, T.F.S) end
    elseif b.status ~= "none" then
        -- CUT OFF / QUEUED stay as text chips. The ACCESS DENIED stamp is 1.4:1
        -- and would have to shrink below reading size to fit a closed card; it
        -- gets used at full size on the receipt, where there is room for it.
        -- Text colour is the *readable* one, not the status colour: CUT OFF's
        -- status colour is the same dark red as its own background.
        local fg = (b.status == "cut") and T.C.redFg or T.C.textDim
        local cw = T.w(T.F.S, st.label) + T.h(T.F.S)
        local chH = T.h(T.F.S) + math.floor(P / 2)
        T.panel(e, markR - cw, midY - math.floor(chH / 2), cw, chH,
            b.status == "cut" and T.C.redBg or T.C.raise, st.c)
        T.textC(e, st.label, markR - math.floor(cw / 2),
            midY - math.floor(chH / 2) + math.floor((chH - T.h(T.F.S)) / 2), fg, T.F.S)
    end

    zone(m, "bill:" .. b.no, { x = x, y = y, w = w, h = topH }, b.no)

    if expanded then
        local dy = y + topH
        T.fill(e, x + 4, dy, w - 4, 1, T.C.line2)

        -- chips explain where the number came from, in place of a sentence
        local chx = x + 4 + P
        local chy = dy + P
        for i = 1, #(b.chips or {}) do
            local ch = b.chips[i]
            local cw = T.iconChip(e, ch.art, ch.text, chx, chy,
                ch.warn and T.C.orange or T.C.textDim,
                ch.warn and T.C.redBg or T.C.card)
            chx = chx + cw + math.floor(P / 2)
        end

        -- actions, right aligned, bottom anchored
        local bh = T.h(T.F.M) + P
        local bx = x + w - P
        for i = #(b.actions or {}), 1, -1 do
            local act = b.actions[i]
            local bw
            local r
            if act.art == "btn_details" then
                -- Thai button art, drawn at its own aspect
                bw = math.floor(bh * 3.6)
                T.art(e, "btn_details", bx - bw, chy - 2, bw, bh + 4)
                r = { x = bx - bw, y = chy - 2, w = bw, h = bh + 4 }
            else
                bw = T.w(T.F.S, act.label) + T.h(T.F.M) * 2
                r = T.button(e, act.style, act.label, bx - bw, chy, bw, bh, act.art)
            end
            zone(m, "act:" .. act.id .. ":" .. b.no, r, b.no)
            bx = bx - bw - math.floor(P / 2)
        end
    end

    return h
end

-- --------------------------------------------------------------- columns ---
local function column(e, m, col, x, y, w, h)
    local P = T.pad()
    T.panel(e, x, y, w, h, T.C.bg0, T.C.line)
    T.fill(e, x, y, w, 3, col.accent)

    -- header sits on a wooden plank from the art set
    local artH = T.h(T.F.L) + T.h(T.F.M)
    local headH = artH + T.h(T.F.S) + P * 3
    -- Flat card, no wooden plank behind it. Decorative texture under a header
    -- fights the text for attention and buys nothing the header did not
    -- already say; the artwork earns its place as icons, not as wallpaper.
    T.fill(e, x + 1, y + 3, w - 2, headH, T.C.card)
    T.fill(e, x, y + 3 + headH, w, 1, T.C.line)

    T.art(e, col.art, x + P, y + 3 + P, artH, artH)

    local tx = x + P + artH + P
    local ty = y + 3 + P
    local tagW = T.chip(e, col.tag, tx, ty, col.accent, T.C.raise)
    T.text(e, T.clip(col.name, T.F.M, w * 0.4), tx + tagW + math.floor(P / 2), ty,
        T.C.textHi, T.F.M)
    T.text(e, col.id, tx + tagW + math.floor(P / 2) + T.w(T.F.M, col.name) + math.floor(P / 2),
        ty + 2, T.C.textFaint, T.F.S)

    -- fact chips replace the paragraph the old screen had here
    local fx = tx
    local fy = ty + T.h(T.F.M) + math.floor(P / 2)
    for i = 1, #col.facts do
        local f = col.facts[i]
        local cw = T.iconChip(e, f.art, f.text, fx, fy,
            f.bad and T.C.redFg or (f.good and T.C.green or T.C.textDim),
            f.bad and T.C.redBg or T.C.raise)
        fx = fx + cw + math.floor(P / 2)
    end

    -- due amount pinned to the right of the header
    T.textR(e, T.money(col.due), x + w - P, ty, col.due > 0 and T.C.redFg or T.C.green, T.F.L)
    if col.selector then
        local sw = T.w(T.F.S, col.selector) + T.h(T.F.M) * 2
        local r = { x = x + w - P - sw, y = fy, w = sw, h = T.h(T.F.S) + P }
        T.button(e, "close", col.selector, r.x, r.y, r.w, r.h)
        zone(m, "houses", r)
    end

    -- Footer first, list second. Both anchored from the bottom, which is the
    -- only arrangement where content flowing down cannot collide with a button
    -- growing up (PZ-B42-UI-layout-gate-RULE, rule 2).
    local footH = T.h(T.F.M) + P * 2
    local footY = y + h - footH - P
    local r = T.button(e, col.footStyle, col.footLabel, x + P, footY, w - P * 2, footH,
        col.footArt, T.F.M)
    if col.footStyle ~= "off" then zone(m, col.footZone, r) end

    -- list
    local listY = y + 3 + headH + 1
    local listH = footY - listY - P
    T.fill(e, x + 1, listY, w - 2, listH, T.C.bg0)

    if #col.bills == 0 then
        local ih = T.h(T.F.XL) * 2
        T.art(e, col.emptyArt, x + math.floor((w - ih) / 2), listY + math.floor(listH / 2) - ih,
            ih, ih, 0.5)
        T.textC(e, col.emptyTitle, x + math.floor(w / 2), listY + math.floor(listH / 2) + P,
            T.C.green, T.F.M)
        T.textC(e, col.emptyNote, x + math.floor(w / 2),
            listY + math.floor(listH / 2) + P + T.h(T.F.M) + 4, T.C.textFaint, T.F.S)
        return
    end

    local first = math.max(1, math.min(col.scroll or 1, #col.bills))
    local by = listY + P
    local shown = 0
    for i = first, #col.bills do
        local b = col.bills[i]
        local expanded = (b.no == m.selected)
        local ch = billCard(e, m, b, x + P, by, w - P * 2 - 6, expanded)
        by = by + ch + math.floor(P / 2)
        shown = shown + 1
        if by > listY + listH then break end   -- never draw past the list box
    end
    -- Handed back so the wheel handler knows how far it may scroll without
    -- having to guess how many cards fitted.
    col.__shown = shown

    -- scrollbar: only when there is something off screen to reach
    if shown < #col.bills or first > 1 then
        local thumb = math.max(24, math.floor(listH * shown / #col.bills))
        local track = listH - 4 - thumb
        local pos = 0
        if #col.bills > shown then
            pos = math.floor(track * (first - 1) / (#col.bills - shown))
        end
        T.fill(e, x + w - 5, listY + 2, 4, listH - 4, T.C.raise2)
        T.fill(e, x + w - 5, listY + 2 + pos, 4, thumb, T.C.purpleDeep)
    end
end

-- --------------------------------------------------------- pay confirm ---
---Asks which wallet to pay from. The green buttons used to guess (cash first,
---bank if cash was disabled) and just fire -- a silent guess about the
---player's money is the one thing a tax screen must never do.
---
---Each method shows its balance and, when it cannot cover the bill, how much
---it is short. That answer is available before the click, so a payment can
---only fail for a reason the player has already been shown.
local function confirmDialog(e, m, W, H)
    local P = T.pad()
    local c = m.confirm

    T.fill(e, 0, 0, W, H, T.C.bg0, 0.84)

    local pw = math.min(math.floor(W * 0.42), W - P * 14)
    local rowH = T.h(T.F.L) + T.h(T.F.S) + P * 2
    local headH = T.h(T.F.L) + T.h(T.F.S) + P * 2
    local totH = T.h(T.F.XL) + P * 2
    local ph = 3 + headH + totH + rowH * 2 + T.h(T.F.M) + P * 5
    local px = math.floor((W - pw) / 2)
    local py = math.floor((H - ph) / 2)

    T.panel(e, px, py, pw, ph, T.C.card, T.C.purpleDeep)
    T.fill(e, px, py, pw, 3, T.C.purple)

    -- header
    local ih = T.h(T.F.L) + T.h(T.F.S)
    T.art(e, "ic_cash", px + P, py + 3 + P, ih, ih)
    T.text(e, c.title, px + P + ih + P, py + 3 + P, T.C.textHi, T.F.L)
    T.text(e, c.subtitle, px + P + ih + P, py + 3 + P + T.h(T.F.L), T.C.textFaint, T.F.S)

    -- amount
    local ty = py + 3 + headH
    T.panel(e, px + P, ty, pw - P * 2, totH, T.C.bg0, T.C.line2)
    T.text(e, "TOTAL TO PAY", px + P * 2, ty + math.floor((totH - T.h(T.F.S)) / 2),
        T.C.textFaint, T.F.S)
    T.textR(e, T.money(c.amount), px + pw - P * 2,
        ty + math.floor((totH - T.h(T.F.XL)) / 2), T.C.redFg, T.F.XL)

    -- one row per wallet
    local y = ty + totH + P
    local methods = {
        { id = "cash", label = "PAY WITH CASH", art = "ic_purse", have = c.cash,
          on = c.cashOn, col = T.C.green, style = "go",
          note = c.cashOn and "IN YOUR INVENTORY" or "DISABLED BY THE SERVER" },
        { id = "bank", label = "PAY WITH BANK", art = "ic_bank", have = c.bank,
          on = c.bankOn, col = T.C.cyan, style = "bank",
          note = c.bankOn and "AKACOUNT BALANCE" or "DISABLED BY THE SERVER" },
    }

    for i = 1, #methods do
        local mth = methods[i]
        local enough = mth.on and (mth.have >= c.amount)
        local r = T.button(e, enough and mth.style or "off", "", px + P, y, pw - P * 2, rowH)

        local aih = rowH - P
        T.art(e, mth.art, px + P * 2, y + math.floor((rowH - aih) / 2), aih, aih,
            enough and 1.0 or 0.35)

        local tx = px + P * 2 + aih + P
        local b = T.BTN[enough and mth.style or "off"]
        T.text(e, mth.label, tx, y + math.floor(P / 2), b.fg, T.F.M)

        local sub = mth.note
        if mth.on and not enough then
            sub = "SHORT " .. T.money(c.amount - mth.have)
        end
        T.text(e, sub, tx, y + math.floor(P / 2) + T.h(T.F.M),
            enough and b.fg or T.C.textFaint, T.F.S)

        T.textR(e, mth.on and T.money(mth.have) or "OFF", px + pw - P * 2,
            y + math.floor((rowH - T.h(T.F.L)) / 2),
            enough and mth.col or T.C.textFaint, T.F.L)

        if enough then zone(m, "confirm:" .. mth.id, r) end
        y = y + rowH + math.floor(P / 2)
    end

    local bh = T.h(T.F.M) + P
    zone(m, "confirm:close",
        T.button(e, "close", "CANCEL", px + P, y + math.floor(P / 2), pw - P * 2, bh, nil, T.F.M))
end

-- --------------------------------------------------------------- receipt ---
---The bill detail. An overlay inside this same window, never a second
---ISCollapsableWindow: an overlay dies with its parent, so it can never be
---left behind as an invisible panel that still eats clicks.
local function receipt(e, m, W, H)
    local P = T.pad()
    local r = m.receipt

    -- Veil. Dim, not opaque -- the player keeps their place in the list behind.
    T.fill(e, 0, 0, W, H, T.C.bg0, 0.84)

    local pw = math.min(math.floor(W * 0.62), W - P * 12)
    local lineH = T.h(T.F.S) + P
    local headH = T.h(T.F.L) + T.h(T.F.S) + P * 2
    -- The body gets a floor height so the watermark has somewhere to live. A
    -- receipt with three lines and a stamp squeezed into the gap looks worse
    -- than a receipt with air in it.
    local bodyH = math.max(lineH * (#r.lines) + T.h(T.F.S) + P * 2, math.floor(pw * 0.28))
    local totH = T.h(T.F.XL) + P * 2
    local footH = T.h(T.F.M) + P * 2
    local ph = 3 + headH + bodyH + totH + footH + P * 3
    local px = math.floor((W - pw) / 2)
    local py = math.floor((H - ph) / 2)

    T.panel(e, px, py, pw, ph, T.C.card, T.C.purpleDeep)
    T.fill(e, px, py, pw, 3, r.accent)

    -- header
    local ih = T.h(T.F.L) + T.h(T.F.S)
    T.art(e, r.art, px + P, py + 3 + P, ih, ih)
    local hx = px + P + ih + P
    T.text(e, r.title, hx, py + 3 + P, T.C.textHi, T.F.L)
    T.text(e, r.subtitle, hx, py + 3 + P + T.h(T.F.L), T.C.textFaint, T.F.S)

    local xw = T.h(T.F.M) + P
    zone(m, "receipt:close",
        T.button(e, "close", "X", px + pw - P - xw, py + 3 + P, xw, T.h(T.F.M) + P))
    T.fill(e, px + P, py + 3 + headH, pw - P * 2, 1, T.C.line)

    -- The stamp, centred over the body and faint enough to read straight
    -- through. This is where a 3:1 rotated stamp actually fits: there is room
    -- for it at a size where the word is legible, and nothing has to grow.
    local by = py + 3 + headH
    if r.stamp then
        T.artFit(e, r.stamp, px + math.floor(pw / 2), by + math.floor(bodyH / 2),
            math.floor(pw * 0.62), bodyH - P * 2, 0.17)
    end

    -- line items
    local ly = by + P
    for i = 1, #r.lines do
        local ln = r.lines[i]
        local iy = ly + math.floor((lineH - T.h(T.F.S)) / 2)
        local aih = T.h(T.F.S)
        T.art(e, ln.art, px + P, iy, aih, aih, 0.9)

        local lx = px + P + aih + math.floor(P / 2)
        T.text(e, ln.label, lx, iy, T.C.text, T.F.S)
        lx = lx + T.w(T.F.S, ln.label) + math.floor(P / 2)
        if ln.note then
            T.text(e, ln.note, lx, iy, T.C.textFaint, T.F.S)
            lx = lx + T.w(T.F.S, ln.note) + math.floor(P / 2)
        end

        local amt = ln.neg and ("+" .. T.money(ln.amount)) or T.money(ln.amount)
        local ax = px + pw - P - T.w(T.F.S, amt)
        -- leader rule instead of a row of dots: one drawRect, not forty
        if ax - lx > P then
            T.fill(e, lx, iy + math.floor(T.h(T.F.S) / 2), ax - lx - P, 1, T.C.line2, 0.7)
        end
        T.text(e, amt, ax, iy, ln.neg and T.C.orange or T.C.textHi, T.F.S)
        ly = ly + lineH
    end

    if r.footnote then
        T.text(e, r.footnote, px + P, ly + 2, T.C.textFaint, T.F.S)
    end

    -- total
    local ty = by + bodyH
    T.panel(e, px + P, ty, pw - P * 2, totH, T.C.bg0, T.C.line2)
    T.text(e, "AMOUNT DUE", px + P * 2, ty + math.floor((totH - T.h(T.F.S)) / 2),
        T.C.textFaint, T.F.S)
    T.textR(e, T.money(r.total), px + pw - P * 2,
        ty + math.floor((totH - T.h(T.F.XL)) / 2),
        r.paid and T.C.green or T.C.redFg, T.F.XL)

    -- actions
    local fy = ty + totH + P
    local bh = T.h(T.F.M) + P
    local closeW = math.floor(pw * 0.2)
    zone(m, "receipt:closeBtn",
        T.button(e, "close", "CLOSE", px + pw - P - closeW, fy, closeW, bh, nil, T.F.M))

    local acts = r.actions or {}
    local aw = math.floor((pw - P * 2 - closeW - P) / math.max(1, #acts)) - P
    local ax = px + P
    for i = 1, #acts do
        local a = acts[i]
        zone(m, "receipt:" .. a.id,
            T.button(e, a.style, a.label, ax, fy, aw, bh, a.art, T.F.M))
        ax = ax + aw + P
    end
end

-- ---------------------------------------------------------------- render ---
function BC.render(e, m, W, H)
    m.__zones = {}
    local P = T.pad()

    T.fill(e, 0, 0, W, H, T.C.bg1)
    T.line_(e, 0, 0, W, H, T.C.line)

    local top = titleBar(e, m, W)
    rail(e, m, top, H)

    local mx = RAIL_W + P
    local mw = W - RAIL_W - P * 2
    local my = top + P

    local barH = walletBar(e, m, mx, my, mw)
    my = my + barH + P

    local colH = H - my - P
    local colW = math.floor((mw - P) / 2)
    column(e, m, m.colPersonal, mx, my, colW, colH)
    column(e, m, m.colHouse, mx + colW + P, my, mw - colW - P, colH)

    -- Overlays own the mouse while they are open. Throwing the underlying
    -- zones away is what makes that true, rather than a rule everyone has to
    -- remember: there is nothing left behind the veil to click.
    if m.receipt then
        m.__zones = {}
        receipt(e, m, W, H)
    end
    -- The pay confirm sits on top of the receipt, because you can start a
    -- payment from inside it.
    if m.confirm then
        m.__zones = {}
        confirmDialog(e, m, W, H)
    end

    return m.__zones
end

return BC
