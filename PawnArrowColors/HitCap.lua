-- Pawn Arrow Colors: hit cap.
--
-- Pawn values every stat linearly: hit above the point where nothing misses any more still counts in
-- full. With the hit cap on, the hit of an item counts for a scale only as far as it still lowers the
-- chance to miss. Upgrade.lua applies it when it compares an item with the equipped one (both sides
-- alike); this file holds the caps, which hit a scale counts against, and the character's hit.
--
-- Caps (percent of hit, automatic setting), from the attack tables of the MythicSim Forever engine:
--   below level 60, against a target two levels above the character: weapons 6.0 (base miss 6%),
--   spells 5.0 (base miss 6%, a spell always keeps 1%);
--   on level 60, against a boss (three levels above): weapons 9.0 (base miss 8% plus 1% hit
--   suppression), spells 16.0 (base miss 17%, less the 1% that always stays).
-- A fixed number replaces both. While the character wields two weapons, white swings miss far more
-- than that and the weapon cap is not applied.

local _, ns = ...

ns.HIT_CAPS = {
    leveling = { weapon = 6.0, spell = 5.0 },
    boss = { weapon = 9.0, spell = 16.0 },
}
ns.HIT_BOSS_LEVEL = 60
ns.HIT_KINDS = { weapon = true, spell = true }
-- Which cap a scale counts against comes from its weights (ns.ScaleHitKind): the weight of the
-- physical main stats and attack power against the weight of spell power.
ns.PHYSICAL_STATS = { "Strength", "Agility", "Ap", "Rap" }
ns.SPELL_POWER_STATS = {
    "SpellPower", "SpellDamage", "Healing", "SpellDamageAndHealing", "SpellDamageNoHealing", "ArcaneSpellDamage",
    "FireSpellDamage", "FrostSpellDamage", "HolySpellDamage", "NatureSpellDamage", "ShadowSpellDamage",
}
-- The weapon cap while the physical weight is at least this share of the spell power weight. A
-- hybrid that fights with its weapon and with spells (a Protection Paladin: seals, Judgement and
-- white swings roll against the melee table) stays on the weapon cap; a caster that only melees
-- on the side (Shockadin) goes to the spell cap.
ns.HIT_PHYSICAL_SHARE = 1 / 3
ns.WEAPON_DPS_STATS = { "Dps", "MeleeDps", "MainHandDps", "OffHandDps", "OneHandDps", "TwoHandDps", "RangedDps" }
-- Rating indices of the client (Blizzard_UIPanels_Game: CR_HIT_MELEE 6, CR_HIT_RANGED 7, CR_HIT_SPELL 8).
local CR_INDEX = { melee = 6, ranged = 7, spell = 8 }

table.insert(ns.dbInits, function(db)
    if type(db.hitCap) ~= "boolean" then db.hitCap = true end
    local v = db.hitCapValue
    if v ~= "auto" and not (type(v) == "number" and v > 0 and v <= 100) then db.hitCapValue = "auto" end
    if type(db.hitCapKind) ~= "table" then db.hitCapKind = {} end
    for name, kind in pairs(db.hitCapKind) do
        if type(name) ~= "string" or not ns.HIT_KINDS[kind] then db.hitCapKind[name] = nil end
    end
end)

local function isSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- The values of a scale (Pawn's saved weights), or nil.
function ns.ScaleValues(name)
    local scales = type(PawnCommon) == "table" and PawnCommon.Scales
    local scale = type(scales) == "table" and scales[name]
    return type(scale) == "table" and type(scale.Values) == "table" and scale.Values or nil
end

local function largest(values, stats)
    local best = 0
    for _, stat in ipairs(stats) do
        local w = values[stat]
        if type(w) == "number" and w > best then best = w end
    end
    return best
end

-- Which cap a scale counts against: "weapon" or "spell", and whether that was set by hand.
-- Rule: P = the largest weight of Strength, Agility, Ap, Rap; S = the largest weight of a spell
-- power stat. Spell cap when S > 0 and P < S * ns.HIT_PHYSICAL_SHARE, weapon cap when P > 0
-- otherwise. With neither (a scale of hit and weapon DPS only): the weapon cap when a weapon DPS
-- stat has a positive weight, otherwise the spell cap. Weapon DPS alone does not decide: casters'
-- scales often weigh a wand's RangedDps highly. /pac hitcap <scale> weapon | spell overrides it.
function ns.ScaleHitKind(name)
    local set = ns.db and ns.db.hitCapKind[name]
    if set then return set, true end
    local values = ns.ScaleValues(name) or {}
    local physical, spell = largest(values, ns.PHYSICAL_STATS), largest(values, ns.SPELL_POWER_STATS)
    if spell > 0 and physical < spell * ns.HIT_PHYSICAL_SHARE then return "spell", false end
    if physical > 0 then return "weapon", false end
    return largest(values, ns.WEAPON_DPS_STATS) > 0 and "weapon" or "spell", false
end

-- For the weapon cap: ranged when the scale weighs ranged DPS more than any melee DPS stat.
function ns.WeaponHand(name)
    local values = ns.ScaleValues(name) or {}
    local ranged = type(values.RangedDps) == "number" and values.RangedDps or 0
    for _, stat in ipairs(ns.WEAPON_DPS_STATS) do
        local w = values[stat]
        if stat ~= "RangedDps" and type(w) == "number" and w >= ranged then return "melee" end
    end
    return ranged > 0 and "ranged" or "melee"
end

-- The cap in percent for a kind ("weapon" or "spell") at a level, and its source ("auto" or "fixed").
function ns.HitCap(kind, level)
    local fixed = ns.db and ns.db.hitCapValue
    if type(fixed) == "number" then return fixed, "fixed" end
    local band = (level or 0) >= ns.HIT_BOSS_LEVEL and ns.HIT_CAPS.boss or ns.HIT_CAPS.leveling
    return band[kind], "auto"
end

-- The character's hit chance from gear, talents and buffs in percent for "melee", "ranged" or
-- "spell", as the character sheet adds it up (rating bonus plus hit modifier). Returns nil and
-- "secret" while the client hides player stats (in combat and in instances, SecretWhenUnitStatsRestricted),
-- nil and "missing" without the functions.
function ns.ReadHit(hand)
    local fn = (hand == "spell" and GetSpellHitModifier) or (hand == "ranged" and GetRangedHitModifier) or GetHitModifier
    if type(fn) ~= "function" then return nil, "missing" end
    local ok, mod = pcall(fn)
    if not ok then return nil, "missing" end
    if isSecret(mod) then return nil, "secret" end
    if type(mod) ~= "number" then return nil, "missing" end
    local bonus = 0
    if type(GetCombatRatingBonus) == "function" then
        local okBonus, b = pcall(GetCombatRatingBonus, CR_INDEX[hand] or CR_INDEX.melee)
        if okBonus then
            if isSecret(b) then return nil, "secret" end
            if type(b) == "number" then bonus = b end
        end
    end
    return mod + bonus
end

-- The value of 1% hit for a scale as Pawn counts it (with the scale's normalization), cached until the
-- next invalidation. 0 when the scale gives hit no positive weight.
ns.hitUnit = {}
function ns.HitUnitValue(name)
    local cached = ns.hitUnit[name]
    if cached then return cached end
    local values = ns.ScaleValues(name)
    local w = values and values.HitRating
    local unit = 0
    -- PawnGetItemValue normalizes with Pawn's own totals; it needs the scale's gem data, which Pawn
    -- keeps for every scale after its set-up (without it Pawn would report an assertion).
    if type(w) == "number" and w > 0 and type(PawnScaleBestGems) == "table" and PawnScaleBestGems[name] ~= nil then
        local v = PawnGetItemValue({ HitRating = 1 }, nil, nil, name)
        if type(v) == "number" and v > 0 then unit = v end
    end
    ns.hitUnit[name] = unit
    return unit
end

table.insert(ns.onInvalidate, function() ns.hitUnit = {} end)

-- The hit rule for one scale with the current gear, or nil (and a reason) when it does not apply:
-- { kind, hand, cap, hit = the character's hit now, unit = value of 1% hit, spell = true for the
-- spell cap }.
function ns.HitContext(name, gear)
    if not (ns.db and ns.db.hitCap) then return nil, "off" end
    local unit = ns.HitUnitValue(name)
    if unit <= 0 then return nil, "no hit weight" end
    local kind = ns.ScaleHitKind(name)
    local hand = kind == "spell" and "spell" or ns.WeaponHand(name)
    local hit = gear.hit[hand]
    if hit == nil then return nil, gear.hitProblem[hand] or "missing" end
    local cap = ns.HitCap(kind, gear.level)
    if not cap then return nil, "no cap" end
    return { kind = kind, hand = hand, cap = cap, hit = hit, unit = unit, spell = kind == "spell" }
end

-- The hit an equipped item adds to the character now (with its enchantment), for the rule's kind:
-- HitRating, and for the spell cap also SpellHitRating (lines "with spells", which Pawn on Forever
-- reads as SpellHitRating and values 0).
function ns.HitAdded(entry, ctx)
    local stats = entry.stats or {}
    local h = type(stats.HitRating) == "number" and stats.HitRating or 0
    if ctx.spell and type(stats.SpellHitRating) == "number" then h = h + stats.SpellHitRating end
    return h
end

-- The hit of an item as Pawn values it in a comparison (without enchantment).
function ns.ItemHit(item)
    local stats = type(item) == "table" and item.UnenchantedStats
    local h = type(stats) == "table" and stats.HitRating
    return type(h) == "number" and h > 0 and h or 0
end

-- The hit of an item that Pawn does not value but that still fills the room under the cap: its
-- SpellHitRating for the spell cap, 0 otherwise. Both sides of a comparison (the candidate and the
-- equipped item) are measured alike: this hit fills the room first, the valued hit gets what is left.
function ns.ItemExtraHit(item, ctx)
    if not (ctx and ctx.spell) then return 0 end
    local stats = type(item) == "table" and item.UnenchantedStats
    local h = type(stats) == "table" and stats.SpellHitRating
    return type(h) == "number" and h > 0 and h or 0
end

-- The hit that still counts after the equipped items in the given slots are taken off:
-- cap - (the character's hit - what those items add), at least 0.
function ns.HitRoom(ctx, gear, slots)
    local base = ctx.hit
    for _, slot in ipairs(slots) do
        local entry = gear.slots[slot]
        if entry then base = base - ns.HitAdded(entry, ctx) end
    end
    local room = ctx.cap - base
    return room > 0 and room or 0, base
end

-- The value of a set of items that would fill those slots, with hit beyond the room not counted.
-- values, hits: sums over the set; extra: hit of the set Pawn does not value (ns.ItemExtraHit).
-- Returns the value and the hit that counts. An item Pawn values at 0 or less (an X value of the
-- scale) stays as it is, and the result never goes below 0.
function ns.CappedValue(value, hit, room, ctx, extra)
    if not ctx or value <= 0 then return value, hit end
    room = room - (extra or 0)
    if room < 0 then room = 0 end
    if hit <= room then return value, hit end
    local capped = value - ctx.unit * (hit - room)
    return capped > 0 and capped or 0, room
end

-- ---------------------------------------------------------------------------------------------
-- Changing the settings
-- ---------------------------------------------------------------------------------------------

function ns.SetHitCap(on)
    ns.db.hitCap = not not on
    ns.Recompute()
end

-- value: "auto" or a number of percent.
function ns.SetHitCapValue(value)
    ns.db.hitCapValue = value
    ns.Recompute()
end

-- kind: "weapon", "spell" or nil (automatic).
function ns.SetScaleHitKind(name, kind)
    ns.db.hitCapKind[name] = kind
    ns.Recompute()
end

-- Re-reads the character's hit after events that may change it; a change means new decisions. A
-- hidden (secret) value is not compared: the decisions made before stay until the hit can be read
-- again (decisions made while it is hidden leave Pawn's answers as they are, Upgrade.lua).
function ns.CheckHit()
    ns.hitCheckPending = false
    if not ns.adjustActive or not ns.lastHit then return end
    local changed = false
    for _, hand in ipairs({ "melee", "ranged", "spell" }) do
        local now, problem = ns.ReadHit(hand)
        local before = ns.lastHit[hand]
        if problem ~= "secret" and (now ~= before.value or problem ~= before.problem) then
            ns.lastHit[hand] = { value = now, problem = problem }
            changed = true
        end
    end
    if changed then ns.Recompute() end
end

function ns.QueueHitCheck()
    if ns.hitCheckPending then return end
    ns.hitCheckPending = true
    C_Timer.After(ns.HIT_CHECK_DELAY, ns.CheckHit)
end
ns.HIT_CHECK_DELAY = 0.5

ns.On("UNIT_STATS", function(_, unit) if unit == "player" then ns.QueueHitCheck() end end)
ns.On("COMBAT_RATING_UPDATE", function() ns.QueueHitCheck() end)
ns.On("PLAYER_REGEN_ENABLED", function() ns.QueueHitCheck() end)
ns.On("CHARACTER_POINTS_CHANGED", function() ns.QueueHitCheck() end)
ns.On("PLAYER_TALENT_UPDATE", function() ns.QueueHitCheck() end)
-- a new level: other caps (level 60) and other values in Pawn
ns.On("PLAYER_LEVEL_UP", function() if ns.adjustActive then ns.Recompute() end end)

-- ---------------------------------------------------------------------------------------------
-- Slash command, status, settings
-- ---------------------------------------------------------------------------------------------

local function capText(kind, level)
    local cap, source = ns.HitCap(kind, level)
    return string.format("%.1f%%", cap) .. (source == "fixed" and " (fixed)" or "")
end

function ns.PrintHitStatus()
    if not ns.db.hitCap then
        ns.Print("hit cap: off (/pac hitcap on).")
        return
    end
    if not ns.adjustActive then
        ns.Print("hit cap: on, but not active: " .. (ns.adjustProblem or "Pawn is not ready") .. ".")
        return
    end
    local level = ns.PlayerLevel()
    local against = (level or 0) >= ns.HIT_BOSS_LEVEL and "against bosses" or "against targets two levels above you"
    ns.Print(string.format("hit cap: on, weapons %s, spells %s (%s).", capText("weapon", level), capText("spell", level),
        type(ns.db.hitCapValue) == "number" and "your number" or against))
    local parts = {}
    for _, hand in ipairs({ "melee", "ranged", "spell" }) do
        local v, problem = ns.ReadHit(hand)
        parts[#parts + 1] = hand .. " " .. (v and string.format("%.1f%%", v) or (problem == "secret" and "hidden by the client" or "unknown"))
    end
    print("  your hit: " .. table.concat(parts, ", "))
    if ns.TrackingOn() then print("  not applied while Pawn compares with the best items of each scale (\"Track for each scale\")") end
    local list = ns.GetVisibleScales()
    for i, s in ipairs(list) do
        local kind, set = ns.ScaleHitKind(s.name)
        local unit = ns.HitUnitValue(s.name)
        local text = unit > 0 and string.format("%s cap%s", kind, set and " (set)" or "") or "hit has no weight, not capped"
        print(string.format("  %d. %s: %s", i, ns.ScaleText(s, list), text))
    end
end

table.insert(ns.statusLines, function() if ns.pawnOK then ns.PrintHitStatus() end end)
table.insert(ns.helpLines, "  /pac hitcap on | off | auto | <percent> - count hit only up to the cap (default auto)")
table.insert(ns.helpLines, "  /pac hitcap <scale number> weapon | spell | auto - which cap a scale counts against")

ns.commands.hitcap = function(rest)
    local words = {}
    for w in string.gmatch(rest, "%S+") do words[#words + 1] = w end
    local first = string.lower(words[1] or "")
    if first == "" then
        ns.PrintHitStatus()
    elseif first == "on" or first == "off" then
        ns.SetHitCap(first == "on")
        ns.PrintHitStatus()
    elseif first == "auto" and #words == 1 then
        ns.SetHitCapValue("auto")
        ns.PrintHitStatus()
    elseif #words == 1 and tonumber(first) then
        local n = tonumber(first)
        if n > 0 and n <= 100 then
            ns.SetHitCapValue(n)
            ns.PrintHitStatus()
        else
            ns.Print("the hit cap is a number of percent above 0, for example 6 or 5.4.")
        end
    else
        local kindWord = string.lower(words[#words] or "")
        local query = table.concat(words, " ", 1, #words - 1)
        if not (kindWord == "weapon" or kindWord == "spell" or kindWord == "auto") or query == "" then
            ns.Print("hitcap takes on, off, auto, a number, or a scale and weapon, spell or auto.")
            return
        end
        local scale, problem = ns.FindScale(query)
        if not scale then
            ns.Print(problem == "ambiguous" and ("several visible Pawn scales are called \"" .. query .. "\"; choose by number.")
                or ("no visible Pawn scale \"" .. query .. "\"; /pac list shows them."))
            return
        end
        ns.SetScaleHitKind(scale.name, kindWord ~= "auto" and kindWord or nil)
        local kind, set = ns.ScaleHitKind(scale.name)
        ns.Print(string.format("%s counts hit against the %s cap%s.", ns.ScaleText(scale), kind, set and "" or " (automatic)"))
    end
end

table.insert(ns.settingsBuilders, function(category, varType)
    local enabled = Settings.RegisterProxySetting(category, "PAWNARROWCOLORS_HITCAP", varType.Boolean or "boolean",
        "Hit cap", true,
        function() return ns.db.hitCap end,
        function(value) ns.SetHitCap(value) end)
    Settings.CreateCheckbox(category, enabled,
        "Hit above the cap does not count: for every visible scale with a hit weight, Pawn's upgrade percentages and the arrows count an item's hit only as far as it still lowers your chance to miss. The equipped item is treated the same way.")
    local value = Settings.RegisterProxySetting(category, "PAWNARROWCOLORS_HITCAPVALUE", varType.String or "string",
        "Hit cap value", "auto",
        function() return type(ns.db.hitCapValue) == "number" and tostring(ns.db.hitCapValue) or "auto" end,
        function(v) ns.SetHitCapValue(tonumber(v) or "auto") end)
    Settings.CreateDropdown(category, value, function()
        local container = Settings.CreateControlTextContainer()
        container:Add("auto", "Automatic (by level)")
        local current = ns.db.hitCapValue
        for i = 1, 17 do container:Add(tostring(i), i .. "%") end
        if type(current) == "number" and (current ~= math.floor(current) or current > 17) then
            container:Add(tostring(current), current .. "%")
        end
        return container:GetData()
    end, "Automatic: below level 60 weapons 6% and spells 5% (a target two levels above you), on level 60 weapons 9% and spells 16% (bosses). A number replaces both; /pac hitcap 5.4 sets any number.")
end)
