-- Pawn Arrow Colors: weapon pairs.
--
-- Pawn never compares a two-hand weapon with one-hand weapons, shields and off-hand items (Pawn.lua
-- 3648-3674): with a two-hand weapon equipped no one-hand item is an upgrade, and the other way round.
-- With weapon pairs on, Upgrade.lua asks this file for those cases, per visible scale:
--
-- - a two-hand weapon, while one-hand items are equipped: its value against the sum of the equipped
--   main hand and off hand;
-- - a one-hand, main-hand or off-hand weapon, a shield or an off-hand item, while a two-hand weapon
--   is equipped: its value plus the best fitting partner from the bags (for this scale) against the
--   two-hand weapon. A main-hand candidate without a partner counts alone; an off-hand candidate
--   without a main-hand partner is no upgrade.
--
-- Pawn's own rules stay: an X value of the scale makes an item worth 0 (so it is neither a candidate
-- nor a partner), the scale's switches "Don't show upgrades for 1H / 2H items", and no change while
-- Pawn tracks the best items of each scale (Upgrade.lua). A partner must be usable now: the
-- character's level at least the item's required level, not an item Pawn marks as never usable for
-- the class. A one-hand weapon is a partner for the off hand only when the scale lets one-hand
-- weapons go there (no X on IsOffHand) and the character can dual wield. The hit cap applies to the
-- pair values. Only the bags are searched (not the bank).

local _, ns = ...

ns.MAIN_SIDE = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true }
ns.OFF_SIDE = { INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }

table.insert(ns.dbInits, function(db)
    if type(db.weaponPairs) ~= "boolean" then db.weaponPairs = true end
end)

local function isSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

ns.pairCache = {} -- scale name .. "\0" .. item link -> { verdict, note }

function ns.pairsChanged()
    ns.pairCache = {}
end

-- The weapons, shields and off-hand items in the bags: { { link, inv }, ... }, cached until the bags
-- change (BAG_UPDATE_DELAYED). ns.bagSignature: the sorted links, to see whether a change matters.
function ns.BagHandItems()
    if ns.bagItems then return ns.bagItems end
    local list, links = {}, {}
    local last = type(NUM_BAG_SLOTS) == "number" and NUM_BAG_SLOTS or 4
    if type(C_Container) == "table" and type(C_Container.GetContainerNumSlots) == "function" and type(C_Item) == "table"
        and type(C_Item.GetItemInfoInstant) == "function" then
        for bag = 0, last do
            local n = C_Container.GetContainerNumSlots(bag) or 0
            for slot = 1, n do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local link = type(info) == "table" and info.hyperlink or nil
                if link ~= nil and not isSecret(link) then
                    local _, _, _, inv = C_Item.GetItemInfoInstant(link)
                    if ns.MAIN_SIDE[inv] or ns.OFF_SIDE[inv] then
                        list[#list + 1] = { link = link, inv = inv }
                        links[#links + 1] = link
                    end
                end
            end
        end
    end
    table.sort(links)
    ns.bagItems = list
    ns.bagSignature = table.concat(links, "\n")
    return list
end

-- Whether the scale lets a one-hand weapon go into the off hand and the character can dual wield.
local function offHandWeaponAllowed(scale)
    local x = scale.Values and scale.Values.IsOffHand
    if x ~= nil and x <= PawnIgnoreStatValue then return false end
    if type(CanDualWield) == "function" then
        local ok, can = pcall(CanDualWield)
        if ok and not isSecret(can) and can == false then return false end
    end
    return true
end

-- The partners from the bags for a candidate: items for the other hand, usable now, worth more than 0
-- for the scale. side: where the partner goes ("off" or "main").
function ns.PairPartners(item, side, scaleName, scale)
    local cand = PawnUnenchantItemLink(item.Link, true)
    local bag = ns.BagHandItems()
    local copies = 0
    for _, b in ipairs(bag) do
        if PawnUnenchantItemLink(b.link, true) == cand then copies = copies + 1 end
    end
    local level = ns.PlayerLevel()
    local offWeapon = offHandWeaponAllowed(scale)
    local out = {}
    for _, b in ipairs(bag) do
        local fits
        if side == "off" then
            fits = b.inv == "INVTYPE_SHIELD" or b.inv == "INVTYPE_HOLDABLE"
                or ((b.inv == "INVTYPE_WEAPON" or b.inv == "INVTYPE_WEAPONOFFHAND") and offWeapon)
        else
            fits = ns.MAIN_SIDE[b.inv] == true
        end
        -- the candidate itself is not its own partner; a second copy in the bags is
        if fits and (PawnUnenchantItemLink(b.link, true) ~= cand or copies >= 2) then
            local data = PawnGetItemData(b.link)
            local _, _, _, _, minLevel = C_Item.GetItemInfo(b.link)
            if type(data) == "table" and data.Link ~= nil and data.CanEquip ~= false and type(minLevel) == "number"
                and level and minLevel <= level and ns.CompareValue(data, scaleName) > 0 then
                out[#out + 1] = data
            end
        end
    end
    return out
end

local function sumOf(list, scaleName)
    local v, h = 0, 0
    for _, it in ipairs(list) do
        v = v + ns.CompareValue(it, scaleName)
        h = h + ns.ItemHit(it)
    end
    return v, h
end

local function name(item)
    return type(item) == "table" and type(item.Name) == "string" and item.Name or "?"
end

local function hitText(ctx, total, counted)
    if not ctx or total <= counted then return "" end
    return string.format("; hit %.1f%% of %.1f%% counted (cap %.1f%%)", counted, total, ctx.cap)
end

-- The decision for one scale when Pawn does not compare (Upgrade.lua: HandMismatch). mismatch: "2h"
-- (a two-hand candidate, one-hand items equipped) or "1h". Returns a verdict ({ kind = "upgrade",
-- percent, existing } or { kind = "none" }) and the tooltip line.
function ns.PairVerdict(item, scaleName, scale, gear, mismatch, label)
    local key = scaleName .. "\0" .. item.Link
    local cached = ns.pairCache[key]
    if cached then return cached.verdict, cached.note end
    local verdict, note = ns.ComputePair(item, scaleName, scale, gear, mismatch, label)
    ns.pairCache[key] = { verdict = verdict, note = note }
    return verdict, note
end

function ns.ComputePair(item, scaleName, scale, gear, mismatch, label)
    local none = { kind = "none" }
    if not ns.ScaleConsidered(item, scale) then return none end
    local main, off = gear.slots[ns.SLOT_MAINHAND], gear.slots[ns.SLOT_OFFHAND]
    if ns.NeverShow(main) or ns.NeverShow(off) then return none end
    local candValue = ns.CompareValue(item, scaleName)
    if candValue <= 0 then return none end

    local ctx = ns.HitContext(scaleName, gear)
    local room = ctx and ns.HitRoom(ctx, gear, { ns.SLOT_MAINHAND, ns.SLOT_OFFHAND }) or 0
    local weaponCtx = ctx and ctx.kind == "weapon"

    -- the equipped side
    local equipped = {}
    if main then equipped[#equipped + 1] = main.item end
    if off then equipped[#equipped + 1] = off.item end
    local eqValue, eqHit = sumOf(equipped, scaleName)
    local eqCtx = ctx
    if weaponCtx and gear.dualWield then eqCtx = nil end
    local eqCapped, eqCounted = ns.CappedValue(eqValue, eqHit, room, eqCtx)

    local candSet, partner, sideText
    local candDual = false
    if mismatch == "2h" then
        candSet = { item }
    else
        local side = ns.OFF_SIDE[item.InvType] and "main" or "off" -- where the partner goes
        if item.InvType == "INVTYPE_WEAPONOFFHAND" and not offHandWeaponAllowed(scale) then return none end
        -- two weapons in the hands: the candidate in the off hand is a weapon, or the partner there is
        local function dual(p)
            if side == "main" then return item.InvType == "INVTYPE_WEAPONOFFHAND" end
            return p ~= nil and ns.OFF_HAND_WEAPON[p.InvType] == true
        end
        local best, bestValue
        for _, p in ipairs(ns.PairPartners(item, side, scaleName, scale)) do
            local v, h = sumOf({ item, p }, scaleName)
            local capped = ns.CappedValue(v, h, room, (weaponCtx and dual(p)) and nil or ctx)
            if not bestValue or capped > bestValue then best, bestValue = p, capped end
        end
        partner = best
        candDual = partner ~= nil and dual(partner)
        if not partner and side == "main" then
            return none, string.format("%s: no main-hand weapon for it in your bags, not compared with %s", label, name(main and main.item))
        end
        candSet = partner and { item, partner } or { item }
        sideText = partner and ("with " .. name(partner)) or "alone (no item for the off hand in your bags)"
    end
    local candValueSum, candHit = sumOf(candSet, scaleName)
    local candCapped, candCounted = ns.CappedValue(candValueSum, candHit, room, (weaponCtx and candDual) and nil or ctx)

    local verdict, note
    if candCapped > eqCapped * ns.UPGRADE_FACTOR then
        verdict = {
            kind = "upgrade", percent = (candCapped - eqCapped) / (eqCapped + ns.EPSILON),
            existing = main and main.link or (off and off.link),
        }
    else
        verdict = none
    end
    if mismatch == "2h" then
        local against = off and string.format("%s + %s", name(main and main.item), name(off.item)) or name(main and main.item or off and off.item)
        note = string.format("%s: against %s%s", label, against, hitText(ctx, candHit, candCounted))
    else
        note = string.format("%s: %s, against %s%s", label, sideText, name(main and main.item), hitText(ctx, candHit, candCounted))
    end
    if ctx and eqHit > eqCounted then
        note = note .. string.format("; equipped hit %.1f%% of %.1f%% counted", eqCounted, eqHit)
    end
    return verdict, note
end

-- ---------------------------------------------------------------------------------------------
-- Invalidation
-- ---------------------------------------------------------------------------------------------

table.insert(ns.onInvalidate, function() ns.pairCache = {} end)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() ns.pairCache = {} end)

table.insert(ns.onSetup, function()
    ns.bagItems = nil
    ns.BagHandItems()
end)

-- The bags changed: when the weapons and off-hand items in them are others now, the decisions change
-- and Pawn rates its bag arrows again.
ns.On("BAG_UPDATE_DELAYED", function()
    local before = ns.bagSignature
    ns.bagItems = nil
    ns.BagHandItems()
    if ns.bagSignature ~= before then
        ns.pairCache = {}
        if ns.db.weaponPairs and ns.adjustActive then ns.Recompute() end
    end
end)

-- ---------------------------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------------------------

function ns.SetWeaponPairs(on)
    ns.db.weaponPairs = not not on
    ns.Recompute()
end

function ns.PrintPairsStatus()
    if not ns.db.weaponPairs then
        ns.Print("weapon pairs: off (/pac pairs on).")
        return
    end
    if not ns.adjustActive then
        ns.Print("weapon pairs: on, but not active: " .. (ns.adjustProblem or "Pawn is not ready") .. ".")
        return
    end
    local n = #ns.BagHandItems()
    ns.Print(string.format("weapon pairs: on; two-hand weapons are compared with one-hand pairs, %d weapon%s and off-hand item%s in your bags%s.",
        n, n == 1 and "" or "s", n == 1 and "" or "s", ns.TrackingOn() and " (not applied while Pawn tracks each scale)" or ""))
end

table.insert(ns.statusLines, function() if ns.pawnOK then ns.PrintPairsStatus() end end)
table.insert(ns.helpLines, "  /pac pairs on | off - compare two-hand weapons with one-hand weapon and off-hand pairs")

ns.commands.pairs = function(rest)
    local arg = string.lower(rest)
    if arg == "on" or arg == "off" then
        ns.SetWeaponPairs(arg == "on")
        ns.PrintPairsStatus()
    elseif arg == "" then
        ns.PrintPairsStatus()
    else
        ns.Print("pairs is on or off.")
    end
end

table.insert(ns.settingsBuilders, function(category, varType)
    local enabled = Settings.RegisterProxySetting(category, "PAWNARROWCOLORS_WEAPONPAIRS", varType.Boolean or "boolean",
        "Weapon pairs", true,
        function() return ns.db.weaponPairs end,
        function(value) ns.SetWeaponPairs(value) end)
    Settings.CreateCheckbox(category, enabled,
        "Compare a two-hand weapon with your equipped main hand and off hand, and a one-hand weapon, shield or off-hand item together with the best partner from your bags with your equipped two-hand weapon. Pawn alone never compares these.")
end)
