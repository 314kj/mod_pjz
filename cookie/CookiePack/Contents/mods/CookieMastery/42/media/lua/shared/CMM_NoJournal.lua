-- Cookie Mastery - nothing from the mastery system goes into a skill journal.
--
-- * Mastery levels, teacher points, branch, apprentice links: global ModData on the server only.
--   Journals copy the character (XP, recipes, kills), never global ModData, so they never see it.
-- * Bonus skill XP from a mentor, an apprentice link or a master book is real skill XP, so a journal
--   would count it. We remember how much each character got per skill and take it back out:
--   Skill Recovery Journal (SRJ): the bonus is added with SRJ's own "not flat XP" switch on, and
--   SRJ.calculateGainedSkill is wrapped so the bonus is deducted from what can be written.
-- * Recipes the mastery system ever grants are listed in CMM.NO_JOURNAL_RECIPES and filtered out
--   of SRJ.getGainedRecipes.
-- * Reading a journal can not feed mastery: SRJ stops adding XP to a skill at level 10.
require "CMM_Shared"

CMMNJ = CMMNJ or {}
CMM.NO_JOURNAL_RECIPES = CMM.NO_JOURNAL_RECIPES or {}

-- bonus XP this character got from the mastery system for one perk id
function CMMNJ.amount(player, perkID)
    if player == nil or perkID == nil then return 0 end
    if CMMS and CMMS.peek then
        local r = CMMS.peek(player)
        if r then return CM.num(r.nj and r.nj[perkID], 0) end
        if CMMS.state and CMMS.state() then return 0 end
    end
    if CMMC and CMMC.me and CMMC.player and player == CMMC.player() then
        local nj = CMMC.me.nj
        return CM.num(nj and nj[perkID], 0)
    end
    return 0
end

-- SRJ counts XP added through addXpNoMultiplier as "flat" XP; ours is not journal XP at all
function CMMNJ.flat(on)
    local mh = SRJ and SRJ.modDataHandler
    if mh and type(mh.setSRJAddingFlatXP) == "function" then pcall(mh.setSRJAddingFlatXP, on) end
end

function CMMNJ.installSRJ()
    if not (SRJ and type(SRJ.calculateGainedSkill) == "function") then return false end
    if rawget(SRJ, "__cmmNJ") then return true end
    SRJ.__cmmNJ = true
    local orig = SRJ.calculateGainedSkill
    SRJ.calculateGainedSkill = function(player, perk, startingLevels, deductibleXP, flatXP)
        local okId, id = pcall(function() return tostring(perk:getId()) end)
        local nj = 0
        if okId and id then nj = CMMNJ.amount(player, id) end
        local sv = SandboxVars and SandboxVars.SkillRecoveryJournal
        if nj <= 0 or type(sv) ~= "table" then
            return orig(player, perk, startingLevels, deductibleXP, flatXP)
        end
        -- SRJ only deducts when TranscribeTVXP is off; keep its TV/radio behaviour, add ours on top
        local tvRecorded = sv.TranscribeTVXP ~= false
        local base = deductibleXP
        if base == nil and SRJ.modDataHandler and SRJ.modDataHandler.getDeductedXP then
            local okB, b = pcall(SRJ.modDataHandler.getDeductedXP, player)
            if okB then base = b end
        end
        local d = {}
        if not tvRecorded and type(base) == "table" then
            for k, v in pairs(base) do d[k] = v end
        end
        d[id] = CM.num(d[id], 0) + nj
        local prev = sv.TranscribeTVXP
        sv.TranscribeTVXP = false
        local ok, a, b = pcall(orig, player, perk, startingLevels, d, flatXP)
        sv.TranscribeTVXP = prev
        if not ok then error(a) end
        return a, b
    end
    if type(SRJ.getGainedRecipes) == "function" then
        local origR = SRJ.getGainedRecipes
        SRJ.getGainedRecipes = function(player, exclude)
            local list = origR(player, exclude)
            if type(list) ~= "table" or not CM.any(CMM.NO_JOURNAL_RECIPES) then return list end
            local out = {}
            for i = 1, #list do
                if not CMM.NO_JOURNAL_RECIPES[list[i]] then out[#out + 1] = list[i] end
            end
            return out
        end
    end
    CMM.log("journal guard on: Skill Recovery Journal")
    return true
end

function CMMNJ.install()
    local ok, res = pcall(CMMNJ.installSRJ)
    if not ok then CMM.log("journal guard error: " .. tostring(res)) end
end

-- after every mod's lua is in
if Events.OnGameBoot then Events.OnGameBoot.Add(CMMNJ.install) end
if Events.OnServerStarted then Events.OnServerStarted.Add(CMMNJ.install) end
if Events.OnGameStart then Events.OnGameStart.Add(CMMNJ.install) end

return CMMNJ
