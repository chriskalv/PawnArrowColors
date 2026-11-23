-- Pawn Arrow Colors: adjusted upgrade decisions (hit cap and weapon pairs).
--
-- Pawn decides in its public function PawnIsItemAnUpgrade(Item) whether an item is an upgrade and by
-- how much, per visible scale. Pawn itself calls that function by its global name for its tooltip
-- (PawnUpdateTooltip, Pawn.lua:1813) and for the bag arrows (PawnShouldItemLinkHaveUpgradeArrowUnbudgeted,
-- Pawn.lua:6069/6079, which Pawn's own bag code and ElvUI ask), and this addon asks it for the color
-- (Core.lua). The addon therefore replaces the global PawnIsItemAnUpgrade by a function that calls
-- Pawn's original and then changes its answer for the scales the features concern. Pawn's tooltip
-- percentages, Pawn's and ElvUI's arrows and the green or yellow color then follow the same answer.
-- Pawn's own value line in the tooltip (the item's score) stays Pawn's linear value; a line added
-- below it says what was not counted and what was compared.
--
-- The change is made only where the addon can reproduce Pawn's own comparison: Pawn compares against
-- the equipped items ("Versus equipped gear", Pawn's default). For the hit cap the addon first
-- recomputes Pawn's answer without the cap; only when that matches Pawn's answer for the scale does it
-- put in the answer with the cap. While Pawn tracks the best items of each scale ("Track for each
-- scale") nothing is changed. Any error leaves Pawn's answers as they are for the rest of the session
-- and says so once.

local _, ns = ...

-- Pawn's functions and values the adjustments read (each checked in tests/pawn_names.test.mjs).
ns.ADJUST_PAWN = {
    "PawnGetSingleValueFromItem", "PawnGetItemDataForInventorySlot", "PawnUnenchantItemLink", "PawnIsScaleVisible",
    "PawnIsArmorBestTypeForPlayer", "PawnGetItemValue",
}

ns.EPSILON = 1e-10 -- like Pawn: keeps the percentage finite for items worth 0
ns.UPGRADE_FACTOR = 1.005 -- like Pawn: an upgrade is at least 0.5% better
ns.SLOT_MAINHAND, ns.SLOT_OFFHAND = 16, 17

-- The slots Pawn compares an item type with (inventory slot numbers of the client; Forever has a
-- ranged slot). INVTYPE_WEAPON uses the off hand as second slot only when the scale lets one-hand
-- weapons go into the off hand.
ns.TYPE_SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
    INVTYPE_FINGER = { 11, 12 }, INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
ns.ONE_HAND = {
    INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true,
}
ns.OFF_HAND_WEAPON = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true }

ns.notes = {} -- item link (Pawn's) -> list of tooltip lines from the last decision
ns.adjustStats = { calls = 0, changed = 0, mismatch = 0 }

local function isSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

function ns.TrackingOn()
    return type(PawnOptions) == "table" and PawnOptions.UpgradeTracking and true or false
end

-- Whether any of the features is on.
function ns.AdjustWanted()
    return ns.db and (ns.db.hitCap or ns.db.weaponPairs) and true or false
end

-- ---------------------------------------------------------------------------------------------
-- Equipped items
-- ---------------------------------------------------------------------------------------------

-- The equipped items as Pawn compares them, the character's level and hit, cached until the gear,
-- the level or the hit changes. nil while an item has no data in Pawn yet (then nothing is changed).
--   slots[slot] = { item = Pawn's data without enchantment, link = its link without enchantment,
--                   stats = the stats with enchantment (what the item adds now), id, invType, rarity, slot }
function ns.Gear()
    if ns.gear then return ns.gear end
    local gear = { slots = {}, hit = {}, hitProblem = {}, level = ns.PlayerLevel() }
    for slot = 1, 18 do
        local link = GetInventoryItemLink("player", slot)
        if link ~= nil then
            if isSecret(link) then return nil end
            local item = PawnGetItemDataForInventorySlot(slot, true)
            local full = PawnGetItemData(link)
            if type(item) ~= "table" or type(full) ~= "table" or item.Link == nil then return nil end
            gear.slots[slot] = {
                item = item, link = PawnUnenchantItemLink(item.Link, true), stats = full.Stats or {}, id = item.ID,
                invType = item.InvType, rarity = item.Rarity, slot = slot,
            }
        end
    end
    local off = gear.slots[ns.SLOT_OFFHAND]
    gear.dualWield = off ~= nil and ns.OFF_HAND_WEAPON[off.invType] == true
    ns.lastHit = {}
    for _, hand in ipairs({ "melee", "ranged", "spell" }) do
        local v, problem = ns.ReadHit(hand)
        gear.hit[hand], gear.hitProblem[hand] = v, problem
        ns.lastHit[hand] = { value = v, problem = problem }
        if problem == "secret" then gear.secret = true end
    end
    ns.gear = gear
    return gear
end

-- The value Pawn compares for an item and a scale (the value without enchantment).
function ns.CompareValue(item, scaleName)
    local _, v = PawnGetSingleValueFromItem(item, scaleName)
    if type(v) ~= "number" then error("Pawn returned no value for a scale") end
    return v
end

local function neverShow(entry)
    return entry and type(PawnNeverShowUpgradesFor) == "table" and entry.id ~= nil and PawnNeverShowUpgradesFor[entry.id] ~= nil
end
ns.NeverShow = neverShow

-- Whether Pawn compares the item with the equipped ones at all for this scale: the scale's switches
-- "Don't show upgrades for 1H / 2H items" and Pawn's armor rule (types the class grows out of).
function ns.ScaleConsidered(item, scale)
    local t = item.InvType
    if scale.DoNotShow1HUpgrades and ns.ONE_HAND[t] then return false end
    if scale.DoNotShow2HUpgrades and t == "INVTYPE_2HWEAPON" then return false end
    return PawnIsArmorBestTypeForPlayer(item) and true or false
end

-- Pawn's rule "a two-hand weapon is never compared with one-hand weapons and off-hand items":
-- "1h" when the item is a one-hand type and a two-hand weapon is equipped, "2h" when the item is a
-- two-hand weapon and something else is in the hands, nil otherwise (also with an artifact).
function ns.HandMismatch(item, gear)
    local t = item.InvType
    if not (ns.ONE_HAND[t] or t == "INVTYPE_2HWEAPON") then return nil end
    local main = gear.slots[ns.SLOT_MAINHAND] or gear.slots[ns.SLOT_OFFHAND]
    if not main or main.rarity == 6 or item.Rarity == 6 then return nil end
    if main.invType == "INVTYPE_2HWEAPON" then
        return ns.ONE_HAND[t] and "1h" or nil
    end
    return t == "INVTYPE_2HWEAPON" and "2h" or nil
end

-- ---------------------------------------------------------------------------------------------
-- Pawn's comparison with the equipped items, with or without the hit cap
-- ---------------------------------------------------------------------------------------------

-- Recomputes Pawn's decision for one scale against the equipped items. ctx: the hit rule
-- (HitCap.lua) or nil for Pawn's own linear values. Returns a verdict or nil when Pawn's comparison
-- cannot be reproduced (then Pawn's answer stays):
--   { kind = "upgrade", percent, existing = link } | { kind = "none" } | { kind = "best" } | { kind = "second" }
-- and with ctx the numbers for the tooltip in verdict.hit.
function ns.ModelScale(item, scaleName, scale, gear, ctx)
    if not ns.ScaleConsidered(item, scale) then return { kind = "none" } end
    local t = item.InvType
    local slots = ns.TYPE_SLOTS[t]
    if not slots then return nil end
    local two = t == "INVTYPE_FINGER"
    if t == "INVTYPE_WEAPON" then
        local x = scale.Values and scale.Values.IsOffHand
        two = x == nil or x > PawnIgnoreStatValue
    end
    local e1 = gear.slots[slots[1]]
    local e2 = two and gear.slots[slots[2]] or nil
    local cand = PawnUnenchantItemLink(item.Link, true)
    if not two and e1 and e1.link == cand then return nil end -- Pawn: an equipped item is no upgrade, for no scale
    if neverShow(e1) or neverShow(e2) then return nil end

    local candHit = ns.ItemHit(item)
    local function valueOf(entry, slot)
        local v = ns.CompareValue(entry.item, scaleName)
        if not ctx then return v end
        local room = ns.HitRoom(ctx, gear, { slot })
        local h = ns.ItemHit(entry.item)
        local capped, counted = ns.CappedValue(v, h, room, ctx, ns.ItemExtraHit(entry.item, ctx))
        return capped, { total = h, counted = counted, room = room }
    end
    local candValue = ns.CompareValue(item, scaleName)

    local lo, loValue, loHit
    if e1 and e2 then
        local v1, h1 = valueOf(e1, slots[1])
        local v2, h2 = valueOf(e2, slots[2])
        local hiEntry
        if v1 >= v2 then
            hiEntry, lo, loValue, loHit = e1, e2, v2, h2
        else
            hiEntry, lo, loValue, loHit = e2, e1, v1, h1
        end
        if cand == hiEntry.link then return { kind = "best" } end
        if cand == lo.link then return { kind = "second" } end
    elseif e1 and not two then
        lo = e1
        loValue, loHit = valueOf(e1, slots[1])
    end

    local candHitInfo
    if ctx then
        local room = ns.HitRoom(ctx, gear, lo and { lo.slot } or {})
        local counted
        candValue, counted = ns.CappedValue(candValue, candHit, room, ctx, ns.ItemExtraHit(item, ctx))
        candHitInfo = { total = candHit, counted = counted, room = room }
    end
    local verdict
    if not lo then
        -- an empty slot (or one of two): Pawn calls any item worth more than 0 an upgrade
        verdict = candValue > 0 and { kind = "upgrade", percent = PawnBigUpgradeThreshold } or { kind = "none" }
    elseif candValue > loValue * ns.UPGRADE_FACTOR then
        verdict = { kind = "upgrade", percent = (candValue - loValue) / (loValue + ns.EPSILON), existing = lo.link }
    else
        verdict = { kind = "none" }
    end
    if ctx then verdict.hit = { cand = candHitInfo, existing = loHit, existingItem = lo and lo.item } end
    return verdict
end

-- Pawn's answer for one scale in the same terms as a verdict.
local function pawnVerdict(scaleName, entries, best, second)
    if entries[scaleName] then return { kind = "upgrade", percent = entries[scaleName].PercentUpgrade } end
    if type(best) == "table" and best[scaleName] then return { kind = "best" } end
    if type(second) == "table" and second[scaleName] then return { kind = "second" } end
    return { kind = "none" }
end

local function sameVerdict(a, b)
    if a.kind ~= b.kind then return false end
    if a.kind ~= "upgrade" then return true end
    return math.abs(a.percent - b.percent) <= 1e-6 * math.max(1, math.abs(b.percent))
end
ns.SameVerdict = sameVerdict

-- ---------------------------------------------------------------------------------------------
-- Tooltip lines
-- ---------------------------------------------------------------------------------------------

local NOTE_COLOR = { 0.6, 0.8, 1 }

local function pct(v)
    return string.format("%.1f%%", v)
end

local function itemName(item)
    return type(item) == "table" and type(item.Name) == "string" and item.Name or "the equipped item"
end

-- The line for the hit cap of one scale, or nil when no hit went uncounted.
function ns.HitNote(label, ctx, info)
    local cand, ex = info.cand, info.existing
    local candCut = cand and cand.total > cand.counted
    local exCut = ex and ex.total > ex.counted
    if not candCut and not exCut then return nil end
    local parts = {}
    if cand and cand.total > 0 then parts[#parts + 1] = string.format("this item %s of %s", pct(cand.counted), pct(cand.total)) end
    if ex and ex.total > 0 then parts[#parts + 1] = string.format("%s %s of %s", itemName(info.existingItem), pct(ex.counted), pct(ex.total)) end
    return string.format("%s: hit counted up to the cap %s (you %s): %s", label, pct(ctx.cap), pct(ctx.hit), table.concat(parts, ", "))
end

-- ---------------------------------------------------------------------------------------------
-- The adjusted answer
-- ---------------------------------------------------------------------------------------------

local KEEP = {}

local function entryFor(scaleName, scale, verdict)
    return {
        ScaleName = scaleName, LocalizedScaleName = scale.LocalizedName or scaleName,
        PercentUpgrade = verdict.percent, ExistingItemLink = verdict.existing,
    }
end

local function byName(a, b)
    return string.lower(a.LocalizedScaleName) < string.lower(b.LocalizedScaleName)
end

-- Works out the adjusted answer for Pawn's answer (n values r1..r5). Returns KEEP when Pawn's answer
-- stays, otherwise the five values.
function ns.AdjustUpgrade(item, n, upgrades, ilvl, best, second, needsEnh)
    if n == 0 or type(item) ~= "table" or type(item.Link) ~= "string" then return KEEP end
    ns.notes[item.Link] = nil
    if ns.TrackingOn() then return KEEP end
    local gear = ns.Gear()
    if not gear then return KEEP end
    ns.adjustStats.calls = ns.adjustStats.calls + 1

    local entries = {}
    if type(upgrades) == "table" then
        for _, u in ipairs(upgrades) do
            if type(u) == "table" and u.ScaleName ~= nil then entries[u.ScaleName] = u end
        end
    end
    local mismatch = ns.HandMismatch(item, gear)
    local candHit = ns.ItemHit(item)
    local changed, notes = false, {}

    for scaleName, scale in pairs(PawnCommon.Scales) do
        if type(scale) == "table" and PawnIsScaleVisible(scaleName) then
            local label = scale.LocalizedName or scaleName
            local verdict, note
            if mismatch then
                if ns.db.weaponPairs and ns.PairVerdict then
                    verdict, note = ns.PairVerdict(item, scaleName, scale, gear, mismatch, label)
                end
            elseif ns.db.hitCap then
                local ctx = ns.HitContext(scaleName, gear)
                if ctx and not (ctx.kind == "weapon" and gear.dualWield) then
                    local slots = ns.TYPE_SLOTS[item.InvType]
                    local anyHit = candHit > 0
                    for _, slot in ipairs(slots or {}) do
                        local e = gear.slots[slot]
                        if e and ns.ItemHit(e.item) > 0 then anyHit = true end
                    end
                    if anyHit then
                        local raw = ns.ModelScale(item, scaleName, scale, gear, nil)
                        if raw and sameVerdict(raw, pawnVerdict(scaleName, entries, best, second)) then
                            verdict = ns.ModelScale(item, scaleName, scale, gear, ctx)
                            if verdict and verdict.hit then note = ns.HitNote(label, ctx, verdict.hit) end
                        elseif raw then
                            ns.adjustStats.mismatch = ns.adjustStats.mismatch + 1
                        end
                    end
                end
            end
            if note then notes[#notes + 1] = note end
            if verdict and (verdict.kind == "upgrade" or verdict.kind == "none") then
                local old = entries[scaleName]
                if verdict.kind == "upgrade" then
                    if not old or not sameVerdict(verdict, { kind = "upgrade", percent = old.PercentUpgrade }) then
                        entries[scaleName] = entryFor(scaleName, scale, verdict)
                        changed = true
                    end
                elseif old then
                    entries[scaleName] = nil
                    changed = true
                end
            end
        end
    end

    if #notes > 0 then
        table.sort(notes)
        ns.notes[item.Link] = notes
    end
    if not changed then return KEEP end
    ns.adjustStats.changed = ns.adjustStats.changed + 1
    local list = {}
    for _, e in pairs(entries) do list[#list + 1] = e end
    table.sort(list, byName)
    return #list > 0 and list or nil, ilvl, best, second, needsEnh
end

-- Pawn's answer, or the adjusted one. Never raises an error: after an error Pawn's answers stay for the
-- rest of the session.
function ns.WrapAnswer(item, ...)
    if ns.adjustBroken or not ns.AdjustWanted() then return ... end
    local n = select("#", ...)
    local ok, a, b, c, d, e = pcall(ns.AdjustUpgrade, item, n, ...)
    if not ok then
        ns.adjustBroken = true
        ns.adjustProblem = "an error in the hit cap or weapon pairs: " .. tostring(a)
        ns.WarnOnce("adjusterror", "hit cap and weapon pairs stopped after an error; Pawn's own upgrade results are used until /reload. (" .. tostring(a) .. ")")
        return ...
    end
    if a == KEEP then return ... end
    return a, b, c, d, e
end

-- ---------------------------------------------------------------------------------------------
-- Set-up, invalidation, tooltip
-- ---------------------------------------------------------------------------------------------

-- Forgets the equipped items and asks Pawn to rate its bag arrows again (its bag code skips buttons
-- it already rated). Pawn's PawnResetBags runs the addon's own invalidation through the hook in Core.lua.
-- ElvUI's arrows do not follow PawnResetBags; Bags.lua lets ElvUI decide them again.
function ns.Recompute()
    ns.gear = nil
    if ns.pairsChanged then ns.pairsChanged() end
    if not ns.setupDone then return end
    local reset = false
    if type(PawnResetBags) == "function" and ns.adjustActive then
        reset = pcall(PawnResetBags)
    end
    if not reset then ns.Invalidate() end
    if ns.adjustActive and ns.paths.elvui and ns.paths.elvui.Reevaluate then ns.paths.elvui.Reevaluate() end
end

table.insert(ns.onInvalidate, function()
    ns.gear = nil
    ns.notes = {}
end)

-- The gear changes at once; Pawn's own data follow on its reset (Core.lua).
ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.gear = nil end)

local function addNotes(tooltipName, methodName, ...)
    if not ns.adjustActive or ns.adjustBroken then return end
    -- Pawn asks PawnIsItemAnUpgrade for its tooltip only with "show upgrades in tooltips" on
    -- (Pawn.lua:1813); without that question the notes would be left over from a bag check.
    if not (type(PawnCommon) == "table" and PawnCommon.ShowUpgradesOnTooltips) then return end
    local tooltip = _G[tooltipName]
    if type(tooltip) ~= "table" or type(tooltip.AddLine) ~= "function" then return end
    local ok, link = pcall(PawnGetItemLinkFromTooltipNameAndMethod, tooltipName, methodName, ...)
    if not ok or link == nil or isSecret(link) or type(link) ~= "string" then return end
    local okItem, item = pcall(PawnGetItemData, link)
    if not okItem or type(item) ~= "table" or type(item.Link) ~= "string" then return end
    local notes = ns.notes[item.Link]
    if not notes then return end
    for _, line in ipairs(notes) do tooltip:AddLine(line, NOTE_COLOR[1], NOTE_COLOR[2], NOTE_COLOR[3], true) end
    if type(tooltip.Show) == "function" then tooltip:Show() end
end

-- Replaces PawnIsItemAnUpgrade once Pawn is ready; without one of the Pawn names the features stay
-- off and say so once.
function ns.SetupAdjust()
    if ns.adjustActive then return true end
    local missing
    for _, name in ipairs(ns.ADJUST_PAWN) do
        if type(_G[name]) ~= "function" then missing = missing or name end
    end
    if not missing then
        if type(PawnCommon) ~= "table" or type(PawnCommon.Scales) ~= "table" then missing = "PawnCommon.Scales"
        elseif type(PawnIgnoreStatValue) ~= "number" then missing = "PawnIgnoreStatValue"
        elseif type(PawnBigUpgradeThreshold) ~= "number" then missing = "PawnBigUpgradeThreshold"
        elseif type(GetInventoryItemLink) ~= "function" then missing = "GetInventoryItemLink"
        end
    end
    if missing then
        ns.adjustProblem = string.format("Pawn's %s was not found (another Pawn version?)", missing)
        ns.WarnOnce("adjust", ns.adjustProblem .. "; hit cap and weapon pairs are off, Pawn's results stay as they are.")
        return false
    end
    local original = PawnIsItemAnUpgrade
    ns.originalIsItemAnUpgrade = original
    PawnIsItemAnUpgrade = function(item, doNotRescan)
        return ns.WrapAnswer(item, original(item, doNotRescan))
    end
    ns.adjustActive = true
    if type(PawnUpdateTooltip) == "function" and type(PawnGetItemLinkFromTooltipNameAndMethod) == "function" then
        hooksecurefunc("PawnUpdateTooltip", addNotes)
    else
        ns.WarnOnce("tooltipnotes", "Pawn's tooltip function was not found; the tooltip does not say what the hit cap and the weapon pairs compared.")
    end
    -- Pawn may have rated its bag arrows before the replacement: let it rate them again.
    ns.Recompute()
    return true
end

table.insert(ns.onSetup, ns.SetupAdjust)
