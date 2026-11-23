-- Pawn Arrow Colors tests: stubs of the WoW API, of Pawn, of ElvUI's bag module and of Blizzard's bags.
--
-- The runner (tools/addon_test.mjs) loads this file first in a fresh Lua state, then _harness.lua,
-- calls __before_addon_load() (snapshot of the globals), loads the addon files in TOC order and
-- finally the test file. Tests set up a simulated client with ReloadAddon(config): it removes every
-- global that did not exist before the addon was first loaded, installs fresh stubs for the
-- configuration and loads the addon again; it returns the addon table (ns).
--
-- The Pawn, ElvUI and Blizzard stand-ins below are written for these tests from the behavior the
-- addon relies on (who calls which function with which result); they contain no code of those addons.
--
-- Configuration (all fields optional):
--   pawn          false: Pawn is not loaded. Otherwise a table:
--     scales      list of { name, label, visible, provider, values } in the order of Pawn's scale
--                 list (default: "A" Holy, "B" Retribution, "C" Protection (hidden)); values are the
--                 stat weights (PawnCommon.Scales[name].Values), provider marks a plugin's scale
--     upgrades    item link -> list of internal scale names the item is an upgrade for
--     ilvl        item link -> true: an item level upgrade (only used when upgrades has no entry)
--     unknown     item link -> number of PawnIsItemAnUpgrade calls that return nothing first
--     throttle    item link -> number of throttled arrow checks that return nil first
--     nolink      item link -> number of PawnGetItemData calls that return an item without Link first
--                 (Pawn has no stats for the item yet; its arrow check then returns nil as well)
--     initialized false: Pawn's initialization never finishes (PawnIsReady keeps returning nil)
--     readyAfter  number of PawnIsReady calls after Pawn's login that still return nil
--     missing     { FunctionName = true }: these Pawn functions do not exist
--     advisor     false: Pawn's bag arrows (ShowBagUpgradeAdvisor) are off
--     items       item link -> { inv = "INVTYPE_...", stats = {...}, enchant = {...}, name, id, minLevel,
--                 rarity, canEquip = false }: with items, PawnGetItemData returns full item data and
--                 PawnIsItemAnUpgrade compares with the equipped items like Pawn ("Versus equipped gear")
--     equipped    inventory slot -> item link (GetInventoryItemLink("player", slot))
--     tracking    true: Pawn's "Track for each scale" (PawnOptions.UpgradeTracking)
--     options     scale name -> { DoNotShow1HUpgrades = true, DoNotShow2HUpgrades = true }
--     never       item ID -> true: PawnNeverShowUpgradesFor
--     answer      item link -> upgrade list Pawn returns as it is (a rule the stand-in does not model)
--   elvui         false/nil, or { noFunction = true }: ElvUI and its bag module are loaded
--   blizzard      false: no Blizzard container frames
--   saved         PawnArrowColorsCharDB as saved before the login
--   settings      false: no Settings API
--   level         the character's level (UnitLevel("player"), default 20)
--   hit           { melee, ranged, spell, rating }: the hit API of the client (GetHitModifier ... in
--                 percent, GetCombatRatingBonus for the hit ratings); a value "secret" stands for a
--                 secret value; without hit the client functions do not exist
--   dualWield     false: CanDualWield() returns false

REAL_PRINT = print
unpack = unpack or table.unpack
loadstring = loadstring or load

local baseline

-- Deep copy of a table of plain values.
function Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = Copy(x) end
    return out
end

function __before_addon_load()
    baseline = {}
    for k in pairs(_G) do baseline[k] = true end
    STUB = { log = {}, out = {} }
    -- minimal globals the addon needs at load time
    InstallStubs({})
end

-- ---------------------------------------------------------------------------------------------
-- Output, timers, hooks
-- ---------------------------------------------------------------------------------------------

local function installBasics()
    STUB.out = {}
    print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        STUB.out[#STUB.out + 1] = table.concat(parts, " ")
    end
    STUB.timers = {}
    C_Timer = {
        After = function(delay, fn)
            STUB.timers[#STUB.timers + 1] = { delay = delay, fn = fn }
        end,
    }
    issecretvalue = function(v) return STUB.secret ~= nil and v == STUB.secret end
    STUB.secret = nil

    -- hooksecurefunc([table,] name, fn): post-hook, the original runs first and keeps its return values.
    hooksecurefunc = function(a, b, c)
        local tbl, key, fn
        if type(a) == "string" then tbl, key, fn = _G, a, b else tbl, key, fn = a, b, c end
        local orig = tbl[key]
        assert(type(orig) == "function", "hooksecurefunc: " .. tostring(key) .. " is not a function")
        tbl[key] = function(...)
            local r = { orig(...) }
            fn(...)
            return unpack(r)
        end
    end

    STUB.frames = {}
    CreateFrame = function()
        local f = { events = {} }
        function f:RegisterEvent(e) self.events[e] = true end
        function f:UnregisterEvent(e) self.events[e] = nil end
        function f:SetScript(_, fn) self.onEvent = fn end
        STUB.frames[#STUB.frames + 1] = f
        return f
    end
    SlashCmdList = {}
end

-- Runs the timers that are due; new timers added meanwhile run in the next call.
function RunTimers(maxDelay)
    local due = STUB.timers
    STUB.timers = {}
    for _, t in ipairs(due) do
        if maxDelay == nil or t.delay <= maxDelay then t.fn() else STUB.timers[#STUB.timers + 1] = t end
    end
    return #due
end

-- Runs timers until none are left (at most n rounds).
function RunAllTimers(n)
    for _ = 1, n or 20 do
        if #STUB.timers == 0 then return end
        RunTimers()
    end
end

function FireEvent(event, ...)
    for _, f in ipairs(STUB.frames) do
        if f.events[event] and f.onEvent then f.onEvent(f, event, ...) end
    end
end

function Output()
    return table.concat(STUB.out, "\n")
end

function ClearOutput()
    STUB.out = {}
end

-- ---------------------------------------------------------------------------------------------
-- Textures
-- ---------------------------------------------------------------------------------------------

-- A texture with the state the addon reads and writes. calls counts every changing method call.
function NewTexture(parent, kind)
    local t = {
        parent = parent, shown = false, vertex = { 1, 1, 1, 1 }, desaturated = false,
        coords = { 0, 1, 0, 1 }, calls = 0,
    }
    if kind == "blizzard" then
        t.atlas, t.texture = "bags-greenarrow", nil
        t.coords = { 0.1, 0.2, 0.3, 0.4 } -- stands for the atlas part of the texture file
    else
        t.texture = STUB.elvuiTexture
    end
    function t:GetParent() return self.parent end
    function t:IsShown() return self.shown end
    function t:SetShown(v) self.shown = not not v end
    function t:Show() self.shown = true end
    function t:Hide() self.shown = false end
    function t:SetAtlas(a)
        self.calls = self.calls + 1
        self.atlas, self.texture, self.coords = a, nil, { 0.1, 0.2, 0.3, 0.4 }
    end
    function t:GetAtlas() return self.atlas end
    function t:SetTexture(p)
        self.calls = self.calls + 1
        self.texture, self.atlas = p, nil
    end
    function t:GetTexture() return self.texture end
    function t:SetTexCoord(...)
        self.calls = self.calls + 1
        self.coords = { ... }
    end
    function t:SetVertexColor(r, g, b, a)
        self.calls = self.calls + 1
        self.vertex = { r, g, b, a or 1 }
    end
    function t:SetDesaturated(v)
        self.calls = self.calls + 1
        self.desaturated = not not v
    end
    -- the methods as created, to tell later replacements (hooks) apart
    STUB.textureMethods = STUB.textureMethods or setmetatable({}, { __mode = "k" })
    local methods = {}
    for k, v in pairs(t) do
        if type(v) == "function" then methods[k] = v end
    end
    STUB.textureMethods[t] = methods
    return t
end

-- The original state of an arrow: { graphic, coords, vertex, desaturated }.
function ArrowState(t)
    return { graphic = t.atlas or t.texture, coords = t.coords, vertex = t.vertex, desaturated = t.desaturated }
end

-- ---------------------------------------------------------------------------------------------
-- Items in the bags
-- ---------------------------------------------------------------------------------------------

-- STUB.bags[bagID][slotID] = item link
local function containerAPI()
    STUB.bags = {}
    C_Container = {
        GetContainerItemInfo = function(bagID, slotID)
            local link = STUB.bags[bagID] and STUB.bags[bagID][slotID]
            if not link then return nil end
            return { hyperlink = link, stackCount = 1 }
        end,
        GetContainerNumSlots = function(bagID)
            if bagID >= 0 and bagID <= 4 then return 16 end
            return 0
        end,
    }
end

function PutItem(bagID, slotID, link)
    STUB.bags[bagID] = STUB.bags[bagID] or {}
    STUB.bags[bagID][slotID] = link
end

-- ---------------------------------------------------------------------------------------------
-- Pawn
-- ---------------------------------------------------------------------------------------------

local function defaultScales()
    return {
        { name = "A", label = "Holy", visible = true },
        { name = "B", label = "Retribution", visible = true },
        { name = "C", label = "Protection", visible = false },
    }
end

local function installPawn(cfg)
    STUB.pawn = cfg
    cfg.scales = cfg.scales or defaultScales()
    cfg.upgrades = cfg.upgrades or {}
    cfg.ilvl = cfg.ilvl or {}
    cfg.unknown = cfg.unknown or {}
    cfg.throttle = cfg.throttle or {}
    cfg.nolink = cfg.nolink or {}
    cfg.missing = cfg.missing or {}
    STUB.calls = { upgrade = 0, itemData = 0, scales = 0, arrow = 0 }
    STUB.readyCalls = 0
    STUB.pawnErrors = 0

    -- Like Pawn's file-local flag (Pawn.lua: "local PawnIsInitialized"): private to the stand-in, other
    -- addons reach it only through PawnIsReady(), which returns nil before and true after Pawn's login.
    local initialized
    STUB.pawnInitialize = function() initialized = true end
    -- Pawn reports a call before its initialization in the chat (VgerCore.Fail) and returns nothing.
    local function notInitialized(what)
        STUB.pawnErrors = STUB.pawnErrors + 1
        print("ERROR:  Can't " .. what .. " until Pawn is initialized")
    end

    -- Like Pawn's saved variable: the scales with their values (Pawn.lua keeps them in PawnCommon.Scales).
    PawnCommon = { ShowBagUpgradeAdvisor = cfg.advisor ~= false, Scales = {} }
    for _, s in ipairs(cfg.scales) do
        s.values = s.values or { Strength = 1 }
        PawnCommon.Scales[s.name] = { LocalizedName = s.label, Values = s.values, Provider = s.provider and "Plugin" or nil }
    end

    local function visible(name)
        for _, s in ipairs(cfg.scales) do
            if s.name == name then return s.visible end
        end
        return nil
    end
    local api = {}
    function api.PawnIsReady()
        STUB.readyCalls = STUB.readyCalls + 1
        if not initialized then return nil end
        if (cfg.readyAfter or 0) > 0 then
            cfg.readyAfter = cfg.readyAfter - 1
            return nil
        end
        return initialized
    end
    function api.PawnIsScaleVisible(name) return visible(name) end
    function api.PawnGetAllScalesEx()
        STUB.calls.scales = STUB.calls.scales + 1
        if not initialized then return notInitialized("get scale list") end
        local out = {}
        for _, s in ipairs(cfg.scales) do
            out[#out + 1] = { Name = s.name, LocalizedName = s.label, IsVisible = s.visible, IsProvider = s.provider and true or false }
        end
        return out
    end
    function api.PawnGetItemData(link)
        STUB.calls.itemData = STUB.calls.itemData + 1
        if (cfg.nolink[link] or 0) > 0 then
            cfg.nolink[link] = cfg.nolink[link] - 1
            return { Link = nil }
        end
        if cfg.items then return STUB.itemData(link) end
        return { Link = link }
    end
    -- Upgrade list for the visible scales the item is an upgrade for, sorted by display name.
    function api.PawnIsItemAnUpgrade(item)
        STUB.calls.upgrade = STUB.calls.upgrade + 1
        if cfg.items then return STUB.modelIsItemAnUpgrade(item) end
        local link = item.Link
        if (cfg.unknown[link] or 0) > 0 then
            cfg.unknown[link] = cfg.unknown[link] - 1
            return
        end
        local list
        for _, name in ipairs(cfg.upgrades[link] or {}) do
            if visible(name) then
                list = list or {}
                local label
                for _, s in ipairs(cfg.scales) do if s.name == name then label = s.label end end
                list[#list + 1] = { ScaleName = name, LocalizedScaleName = label, PercentUpgrade = 0.1 }
            end
        end
        if list then table.sort(list, function(a, b) return a.LocalizedScaleName < b.LocalizedScaleName end) end
        return list, cfg.ilvl[link] and 3 or nil
    end
    -- Like Pawn, the arrow check answers only once Pawn is initialized (before that: chat error, nil).
    function api.PawnShouldItemLinkHaveUpgradeArrowUnbudgeted(link, checkLevel)
        if not initialized then return notInitialized("check to see if items are upgrades") end
        if (cfg.throttle[link] or 0) > 0 then
            cfg.throttle[link] = cfg.throttle[link] - 1
            return nil
        end
        if (cfg.nolink[link] or 0) > 0 then
            cfg.nolink[link] = cfg.nolink[link] - 1
            return nil
        end
        if cfg.items then
            -- like Pawn (Pawn.lua:6055-6086): the level check, then PawnIsItemAnUpgrade by its global name
            local def = cfg.items[link]
            if not def then return false end
            if checkLevel and STUB.level < (def.minLevel or 1) then return false end
            local item = api.PawnGetItemData(link)
            local up, ilvl = PawnIsItemAnUpgrade(item)
            return up ~= nil or ilvl ~= nil
        end
        local hasScale = false
        for _, name in ipairs(cfg.upgrades[link] or {}) do
            if visible(name) then hasScale = true end
        end
        return hasScale or cfg.ilvl[link] == true
    end
    api.PawnShouldItemLinkHaveUpgradeArrow = function(link, checkLevel)
        STUB.calls.arrow = STUB.calls.arrow + 1
        return api.PawnShouldItemLinkHaveUpgradeArrowUnbudgeted(link, checkLevel)
    end
    -- Pawn's bag reset: refreshes its own bag arrows (a new refresh number ends the per-button skip).
    function api.PawnResetBags()
        STUB.resets = (STUB.resets or 0) + 1
        STUB.pawnRefreshCounter = (STUB.pawnRefreshCounter or 0) + 1
        if STUB.pawnBagRefresh then STUB.pawnBagRefresh() end
    end
    installPawnModel(cfg, api, visible)
    for name, fn in pairs(api) do
        if not cfg.missing[name] then _G[name] = fn end
    end
end


-- ---------------------------------------------------------------------------------------------
-- Pawn's item values and its comparison with the equipped items
-- ---------------------------------------------------------------------------------------------

-- Written for these tests from Pawn's behavior (Pawn 2.14.8, PawnGetItemData, PawnGetItemValue,
-- PawnGetSingleValueFromItem, PawnIsItemAnUpgrade without "Track for each scale"): linear values,
-- an X value (PawnIgnoreStatValue) makes the item worth 0, items are compared without enchantment,
-- a two-hand weapon is never compared with one-hand items, rings against the weaker ring, an
-- empty slot takes any item worth more than 0, an upgrade is at least 0.5% better.
local SLOT1 = {
    INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WAIST = 6,
    INVTYPE_LEGS = 7, INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_FINGER = 11, INVTYPE_TRINKET = 13,
    INVTYPE_CLOAK = 15, INVTYPE_WEAPON = 16, INVTYPE_SHIELD = 17, INVTYPE_2HWEAPON = 16, INVTYPE_WEAPONMAINHAND = 16,
    INVTYPE_RANGED = 18, INVTYPE_RANGEDRIGHT = 18, INVTYPE_RELIC = 18, INVTYPE_THROWN = 18, INVTYPE_WEAPONOFFHAND = 17,
    INVTYPE_HOLDABLE = 17,
}
local SLOT2 = { INVTYPE_FINGER = 12, INVTYPE_TRINKET = 14, INVTYPE_WEAPON = 17 }
local ONE_HAND = { INVTYPE_WEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true }

function installPawnModel(cfg, api, visible)
    PawnIgnoreStatValue = -1000000
    PawnBigUpgradeThreshold = 100
    PawnScaleBestGems = {}
    for _, s in ipairs(cfg.scales) do
        PawnScaleBestGems[s.name] = {}
        local opts = cfg.options and cfg.options[s.name] or {}
        PawnCommon.Scales[s.name].DoNotShow1HUpgrades = opts.DoNotShow1HUpgrades
        PawnCommon.Scales[s.name].DoNotShow2HUpgrades = opts.DoNotShow2HUpgrades
    end
    PawnOptions = { UpgradeTracking = cfg.tracking and true or false }
    PawnNeverShowUpgradesFor = cfg.never or {}
    local items = cfg.items or {}
    STUB.valueCalls = 0

    local function base(link)
        local def = items[link]
        return def and def.base or link
    end
    local function merged(def, withEnchant)
        local out = {}
        for k, v in pairs(def.stats or {}) do out[k] = v end
        if withEnchant then
            for k, v in pairs(def.enchant or {}) do out[k] = (out[k] or 0) + v end
        end
        return out
    end
    STUB.itemData = function(link)
        local def = items[link]
        if not def then return nil end
        local inv = def.inv == "INVTYPE_ROBE" and "INVTYPE_CHEST" or def.inv
        return {
            Link = link, Name = def.name or link, ID = def.id, InvType = inv, Rarity = def.rarity or 3,
            Stats = merged(def, true), UnenchantedStats = merged(def, false), CanEquip = def.canEquip ~= false,
        }
    end

    function api.PawnUnenchantItemLink(link, evenIfNotEnchanted)
        local b = base(link)
        if b ~= link then return b end
        if evenIfNotEnchanted then return link end
        return nil
    end
    function api.PawnGetItemValue(stats, _, _, scaleName)
        local scale = PawnCommon.Scales[scaleName]
        if not stats or not scale then return nil end
        local total = 0
        for stat, n in pairs(stats) do
            local w = scale.Values[stat]
            if w and w <= PawnIgnoreStatValue then return 0 end
            if w then total = total + n * w end
        end
        return total
    end
    function api.PawnGetSingleValueFromItem(item, scaleName)
        STUB.valueCalls = STUB.valueCalls + 1
        return api.PawnGetItemValue(item.Stats, nil, nil, scaleName) or 0, api.PawnGetItemValue(item.UnenchantedStats, nil, nil, scaleName) or 0
    end
    function api.PawnIsScaleVisible(name) return visible(name) and true or false end
    function api.PawnIsArmorBestTypeForPlayer(item)
        local st = item.UnenchantedStats or {}
        if st.IsPlate then return STUB.level >= 40 end
        return true
    end
    function api.PawnGetItemDataForInventorySlot(slot, unenchanted)
        local link = GetInventoryItemLink("player", slot)
        if not link then return nil, false end
        if unenchanted then link = base(link) end
        return api.PawnGetItemData(link), true
    end

    STUB.modelIsItemAnUpgrade = function(Item)
        -- cfg.answer[link]: Pawn answers with this list, standing for a rule of Pawn the addon does not
        -- reproduce (the addon must then leave the answer alone)
        if cfg.answer and cfg.answer[Item.Link] then return cfg.answer[Item.Link], nil, nil, nil, nil end
        local t = Item.InvType
        if not t or t == "" or t == "INVTYPE_BODY" or t == "INVTYPE_TABARD" or t == "INVTYPE_BAG" then return nil end
        local skip = t == "INVTYPE_TRINKET" or SLOT1[t] == nil
        local cand = api.PawnUnenchantItemLink(Item.Link, true)
        if ONE_HAND[t] or t == "INVTYPE_2HWEAPON" or t == "INVTYPE_RANGED" then
            local mainLink = GetInventoryItemLink("player", 16) or GetInventoryItemLink("player", 17)
            local main = mainLink and api.PawnGetItemData(mainLink)
            if main then
                if main.InvType == "INVTYPE_2HWEAPON" then
                    if ONE_HAND[t] then skip = true end
                elseif t == "INVTYPE_2HWEAPON" then
                    skip = true
                end
            end
        end
        local list, best, second
        if not skip then
            for _, s in ipairs(cfg.scales) do
                local scale = PawnCommon.Scales[s.name]
                if s.visible and not (scale.DoNotShow1HUpgrades and ONE_HAND[t]) and not (scale.DoNotShow2HUpgrades and t == "INVTYPE_2HWEAPON")
                    and api.PawnIsArmorBestTypeForPlayer(Item) then
                    local inv = t
                    local two = t == "INVTYPE_FINGER"
                    if t == "INVTYPE_WEAPON" then
                        local x = scale.Values.IsOffHand
                        two = x == nil or x > PawnIgnoreStatValue
                    elseif t == "INVTYPE_SHIELD" or t == "INVTYPE_HOLDABLE" then
                        inv = "INVTYPE_WEAPONOFFHAND"
                    end
                    local item1, had1 = api.PawnGetItemDataForInventorySlot(SLOT1[inv], true)
                    if had1 and not item1 then return end
                    local link1 = item1 and api.PawnUnenchantItemLink(item1.Link, true)
                    if not two and link1 and cand == link1 then return end
                    local item2, had2, link2
                    if two then item2, had2 = api.PawnGetItemDataForInventorySlot(SLOT2[inv], true) end
                    if had2 and not item2 then return end
                    if item2 then link2 = api.PawnUnenchantItemLink(item2.Link, true) end
                    local v1, v2
                    if item1 then v1 = PawnNeverShowUpgradesFor[item1.ID] and math.huge or select(2, api.PawnGetSingleValueFromItem(item1, s.name)) end
                    if item2 then v2 = PawnNeverShowUpgradesFor[item2.ID] and math.huge or select(2, api.PawnGetSingleValueFromItem(item2, s.name)) end
                    local bestData
                    if v1 and v2 then
                        if v1 >= v2 then bestData = { v1, link1, nil, v2, link2 } else bestData = { v2, link2, nil, v1, link1 } end
                    elseif two then
                        bestData = nil
                    elseif v1 then
                        bestData = { v1, link1 }
                    end
                    local _, value = api.PawnGetSingleValueFromItem(Item, s.name)
                    local entry
                    if bestData then
                        local bestValue = bestData[4] or bestData[1]
                        if cand == bestData[2] then
                            best = best or {}
                            best[s.name] = true
                        elseif cand == bestData[5] then
                            second = second or {}
                            second[s.name] = true
                        elseif value > bestValue * 1.005 then
                            entry = { ScaleName = s.name, LocalizedScaleName = s.label, PercentUpgrade = (value - bestValue) / (bestValue + 1e-10), ExistingItemLink = bestData[5] or bestData[2] }
                        end
                    elseif value > 0 then
                        entry = { ScaleName = s.name, LocalizedScaleName = s.label, PercentUpgrade = PawnBigUpgradeThreshold }
                    end
                    if entry then
                        list = list or {}
                        list[#list + 1] = entry
                    end
                end
            end
        end
        if list then table.sort(list, function(a, b) return string.lower(a.LocalizedScaleName) < string.lower(b.LocalizedScaleName) end) end
        return list, cfg.ilvl[Item.Link] and 3 or nil, best, second, nil
    end

    -- Pawn's tooltip update: the item from the tooltip, its upgrade answer, one line per visible scale
    -- with a value ("<scale>: <value>" and "(+N% upgrade)"), then Show.
    PawnCommon.ShowUpgradesOnTooltips = cfg.tooltipUpgrades ~= false
    function api.PawnGetItemLinkFromTooltipNameAndMethod(tooltipName, methodName, param1)
        if methodName == "SetHyperlink" and param1 then return param1 end
        local tooltip = _G[tooltipName]
        return tooltip and tooltip.link
    end
    function api.PawnUpdateTooltip(tooltipName, methodName, param1, ...)
        local tooltip = _G[tooltipName]
        local link = api.PawnGetItemLinkFromTooltipNameAndMethod(tooltipName, methodName, param1, ...)
        local item = link and api.PawnGetItemData(link)
        if not item then return end
        local upgrades
        if PawnCommon.ShowUpgradesOnTooltips then upgrades = PawnIsItemAnUpgrade(item) end
        for _, s in ipairs(cfg.scales) do
            if s.visible then
                local _, value = api.PawnGetSingleValueFromItem(item, s.name)
                if value > 0 then
                    local text = string.format("%s: %.1f", s.label, value)
                    for _, u in ipairs(upgrades or {}) do
                        if u.ScaleName == s.name then
                            text = text .. (u.PercentUpgrade >= PawnBigUpgradeThreshold and " (upgrade)" or string.format(" (+%.0f%% upgrade)", 100 * u.PercentUpgrade))
                        end
                    end
                    tooltip:AddLine(text)
                end
            end
        end
        tooltip:Show()
    end
end

-- A tooltip like GameTooltip: AddLine collects the lines, Show counts.
function NewTooltip(name)
    local t = { lines = {}, shown = 0 }
    function t:AddLine(text) self.lines[#self.lines + 1] = text end
    function t:Show() self.shown = self.shown + 1 end
    function t:ClearLines() self.lines = {} end
    function t:Text() return table.concat(self.lines, "\n") end
    _G[name] = t
    return t
end

-- Shows the tooltip of an item the way Pawn's hook on SetHyperlink does.
function HoverItem(link)
    local tip = GameTooltip or NewTooltip("GameTooltip")
    tip:ClearLines()
    tip.link = link
    PawnUpdateTooltip("GameTooltip", "SetHyperlink", link)
    return tip:Text()
end

-- The client's hit functions and the equipped items.
local function installCharacter(config)
    STUB.equipped = config.equipped or (type(config.pawn) == "table" and config.pawn.equipped) or {}
    GetInventoryItemLink = function(unit, slot)
        if unit ~= "player" then return nil end
        return STUB.equipped[slot]
    end
    local items = type(config.pawn) == "table" and config.pawn.items or {}
    C_Item = {
        GetItemInfoInstant = function(link)
            local def = items[link]
            if not def then return nil end
            return def.id, nil, nil, def.inv
        end,
        GetItemInfo = function(link)
            local def = items[link]
            if not def then return nil end
            return def.name or link, link, def.rarity or 3, 10, def.minLevel or 1
        end,
    }
    CanDualWield = function() return config.dualWield ~= false end
    STUB.hit = config.hit
    STUB.secret = STUB.secret or {}
    if config.hit then
        local function read(hand)
            return function()
                local v = STUB.hit[hand]
                if v == "secret" then return STUB.secret end
                return v or 0
            end
        end
        GetHitModifier = read("melee")
        GetRangedHitModifier = read("ranged")
        GetSpellHitModifier = read("spell")
        GetCombatRatingBonus = function()
            local v = STUB.hit.rating
            if v == "secret" then return STUB.secret end
            return v or 0
        end
    end
end

-- Puts an item into an inventory slot and fires the client's event.
function Equip(slot, link)
    STUB.equipped[slot] = link
    FireEvent("PLAYER_EQUIPMENT_CHANGED", slot, link == nil)
end

-- Stand-in for Pawn's bag integration with Blizzard's bags: post-hooks on UpdateItems of the
-- container frames; per button it asks the throttled arrow check, shows or hides UpgradeIcon with
-- SetShown, and retries on the next frame (C_Timer.After(0)) while the check returns nil. Like Pawn it
-- skips a button whose link it already checked since the last PawnResetBags (no SetShown then); the
-- stand-in keeps that state in its own table instead of on the button.
local function installPawnBags()
    local pending = {}
    local checked = setmetatable({}, { __mode = "k" }) -- button -> { refresh, link }
    STUB.pawnSkips = 0
    local function updateButton(button)
        if not PawnCommon.ShowBagUpgradeAdvisor then
            button.UpgradeIcon:SetShown(false)
            return
        end
        local info = C_Container.GetContainerItemInfo(button:GetBagID(), button:GetID())
        if not info then
            checked[button] = nil
            button.UpgradeIcon:SetShown(false)
            return
        end
        local last = checked[button]
        if last and last.refresh == (STUB.pawnRefreshCounter or 0) and last.link == info.hyperlink then
            STUB.pawnSkips = STUB.pawnSkips + 1
            return
        end
        local isUpgrade = PawnShouldItemLinkHaveUpgradeArrow(info.hyperlink, true)
        if isUpgrade == nil then
            checked[button] = nil
            if #pending == 0 then
                C_Timer.After(0, function()
                    local retry = pending
                    pending = {}
                    for _, b in ipairs(retry) do updateButton(b) end
                end)
            end
            pending[#pending + 1] = button
        else
            checked[button] = { refresh = STUB.pawnRefreshCounter or 0, link = info.hyperlink }
            button.UpgradeIcon:SetShown(isUpgrade)
        end
    end
    local function updateFrame(frame)
        for _, button in ipairs(frame.Items) do updateButton(button) end
    end
    STUB.pawnHookBags = function()
        hooksecurefunc(ContainerFrameCombinedBags, "UpdateItems", updateFrame)
        for i = 1, NUM_CONTAINER_FRAMES do hooksecurefunc(_G["ContainerFrame" .. i], "UpdateItems", updateFrame) end
    end
    STUB.pawnBagRefresh = function()
        if ContainerFrameCombinedBags.shown then updateFrame(ContainerFrameCombinedBags) end
        for i = 1, NUM_CONTAINER_FRAMES do
            local f = _G["ContainerFrame" .. i]
            if f.shown then updateFrame(f) end
        end
    end
end

-- ---------------------------------------------------------------------------------------------
-- Blizzard bags
-- ---------------------------------------------------------------------------------------------

local function newContainerFrame(name, bagID)
    local f = { name = name, bagID = bagID, Items = {}, shown = false, pool = {} }
    function f:UpdateItems()
        self.updateCount = (self.updateCount or 0) + 1
    end
    function f:GetID() return self.bagID end
    -- Shows the frame with buttons for the given slots of bagID (buttons come from the frame's pool).
    function f:Open(slots, bag)
        self.shown = true
        for _, b in ipairs(self.Items) do self.pool[#self.pool + 1] = b end
        self.Items = {}
        for _, slotID in ipairs(slots) do
            local button = table.remove(self.pool)
            if not button then
                button = { frame = self }
                function button:GetID() return self.slotID end
                function button:GetBagID() return self.bagID end
                function button:GetParent() return self.frame end
                button.UpgradeIcon = NewTexture(button, "blizzard")
            end
            button.bagID, button.slotID = bag or self.bagID, slotID
            self.Items[#self.Items + 1] = button
        end
        self:UpdateItems()
    end
    return f
end

local function installBlizzardBags()
    NUM_TOTAL_BAG_FRAMES = 4
    NUM_CONTAINER_FRAMES = 5
    ContainerFrameCombinedBags = newContainerFrame("ContainerFrameCombinedBags", 0)
    for i = 1, NUM_CONTAINER_FRAMES do
        _G["ContainerFrame" .. i] = newContainerFrame("ContainerFrame" .. i, i - 1)
    end
end

-- The button of a Blizzard container frame for a slot.
function BlizzardButton(frame, slotID)
    for _, b in ipairs(frame.Items) do
        if b.slotID == slotID then return b end
    end
end

-- ---------------------------------------------------------------------------------------------
-- ElvUI
-- ---------------------------------------------------------------------------------------------

local function installElvUI(cfg)
    STUB.elvuiTexture = "Interface\\AddOns\\ElvUI\\Media\\Textures\\BagUpgradeIcon.tga"
    -- Like ElvUI, B.BagFrames exists only after the bag module's Initialize (ElvUI's OnEnable at
    -- PLAYER_LOGIN, and only with ElvUI bags turned on); STUB.elvInitialize() does that step.
    local B = {}
    local E = { Media = { Textures = { BagUpgradeIcon = STUB.elvuiTexture } } }
    function E:GetModule(name, silent)
        if name == "Bags" then return B end
        if not silent then error("no module " .. name) end
    end
    ElvUI = { E, {}, {} }
    STUB.elvuiCalls = 0
    B.db = { upgradeIcon = true }
    if not cfg.noFunction then
        -- the arrow logic of ElvUI's bag module as the addon sees it: unthrottled Pawn check per slot,
        -- arrow hidden while the answer is nil (ElvUI then asks again from the slot's OnUpdate)
        function B:UpdateItemUpgradeIcon(slot)
            STUB.elvuiCalls = STUB.elvuiCalls + 1
            if not B.db.upgradeIcon or not slot.itemLink or not PawnShouldItemLinkHaveUpgradeArrowUnbudgeted then
                slot.UpgradeIcon:SetShown(false)
                slot.retry = nil
                return
            end
            local isUpgrade = PawnShouldItemLinkHaveUpgradeArrowUnbudgeted(slot.itemLink, true)
            if isUpgrade == nil then
                slot.UpgradeIcon:SetShown(false)
                slot.retry = true
            else
                slot.UpgradeIcon:SetShown(isUpgrade)
                slot.retry = nil
            end
        end
    end
    -- a bag frame and a bank frame with slots
    local function newFrame(bagIDs)
        local f = { BagIDs = bagIDs, Bags = {} }
        for _, bagID in ipairs(bagIDs) do
            f.Bags[bagID] = { holder = {} } -- non-numeric keys as in ElvUI
        end
        B.BagFrames[#B.BagFrames + 1] = f
        return f
    end
    STUB.elvInitialize = function()
        if B.BagFrames then return end
        B.BagFrames = {}
        STUB.elvBags = newFrame({ 0, 1 })
        STUB.elvBank = newFrame({ -1, 5 })
    end
    STUB.B = B
end

-- The slot frame of ElvUI's bag or bank frame, created on first use.
function ElvSlot(frame, bagID, slotID)
    local bag = frame.Bags[bagID]
    local slot = bag[slotID]
    if not slot then
        slot = {}
        slot.UpgradeIcon = NewTexture(slot, "elvui")
        bag[slotID] = slot
    end
    return slot
end

-- ElvUI's slot update for one slot: the item link, then the arrow.
function ElvUpdate(frame, bagID, slotID)
    local slot = ElvSlot(frame, bagID, slotID)
    slot.itemLink = STUB.bags[bagID] and STUB.bags[bagID][slotID] or nil
    STUB.B:UpdateItemUpgradeIcon(slot)
    return slot
end

-- ElvUI's OnUpdate retry for a slot that is waiting for Pawn.
function ElvRetry(slot)
    if slot.retry then STUB.B:UpdateItemUpgradeIcon(slot) end
end

-- ---------------------------------------------------------------------------------------------
-- Settings API
-- ---------------------------------------------------------------------------------------------

local function installSettings()
    STUB.settings = { categories = {}, settings = {}, controls = {} }
    Settings = { VarType = { Boolean = "boolean", String = "string", Number = "number" } }
    function Settings.RegisterVerticalLayoutCategory(name)
        local c = { name = name }
        function c:GetID() return "cat:" .. self.name end
        STUB.settings.categories[#STUB.settings.categories + 1] = c
        return c
    end
    function Settings.RegisterProxySetting(_, variable, varType, name, default, get, set)
        local s = { variable = variable, varType = varType, name = name, default = default, get = get, set = set }
        function s:GetValue() return self.get() end
        function s:SetValue(v) self.set(v) end
        STUB.settings.settings[variable] = s
        return s
    end
    function Settings.CreateCheckbox(_, setting, tooltip)
        STUB.settings.controls[#STUB.settings.controls + 1] = { kind = "checkbox", setting = setting, tooltip = tooltip }
    end
    function Settings.CreateDropdown(_, setting, options, tooltip)
        STUB.settings.controls[#STUB.settings.controls + 1] = { kind = "dropdown", setting = setting, options = options, tooltip = tooltip }
    end
    function Settings.CreateControlTextContainer()
        local c = { data = {} }
        function c:Add(value, label) self.data[#self.data + 1] = { value = value, label = label } end
        function c:GetData() return self.data end
        return c
    end
    function Settings.RegisterAddOnCategory(c) STUB.settings.registered = c end
    function Settings.OpenToCategory(id) STUB.settings.opened = id end
end

-- ---------------------------------------------------------------------------------------------
-- Install and reload
-- ---------------------------------------------------------------------------------------------

function InstallStubs(config)
    installBasics()
    installCharacter(config)
    STUB.level = config.level or 20
    UnitLevel = function(unit)
        if unit == "player" then return STUB.level end
        return nil
    end
    containerAPI()
    if config.pawn ~= false then
        installPawn(config.pawn or {})
    end
    if config.blizzard ~= false then
        installBlizzardBags()
        if config.pawn ~= false then installPawnBags() end
    end
    if config.elvui then installElvUI(config.elvui) end
    if config.settings ~= false then installSettings() end
    PawnArrowColorsCharDB = config.saved
end

function ReloadAddon(config)
    config = config or {}
    for k in pairs(_G) do
        if not baseline[k] then _G[k] = nil end
    end
    STUB = { log = {}, out = {} }
    InstallStubs(config)
    local ns = LoadAddon()
    STUB.ns = ns
    return ns
end

-- Login sequence: the addon's saved variables, Pawn's PLAYER_LOGIN (initialized, bag hooks), ElvUI's
-- bag module Initialize (unless opts.elvLate), then the addon's PLAYER_LOGIN, then the timers of the
-- next frame.
function Login(opts)
    opts = opts or {}
    FireEvent("ADDON_LOADED", "PawnArrowColors")
    if STUB.pawn and STUB.pawn.initialized ~= false then
        STUB.pawnInitialize()
        if STUB.pawnHookBags and PawnCommon.ShowBagUpgradeAdvisor then STUB.pawnHookBags() end
    end
    if STUB.elvInitialize and not opts.elvLate then STUB.elvInitialize() end
    FireEvent("PLAYER_LOGIN")
    if not opts.noTimers then RunAllTimers() end
end

-- A level up: the new level, then the event with it as its first payload value.
function LevelUp(level)
    STUB.level = level
    FireEvent("PLAYER_LEVEL_UP", level, 0, 0, 0)
end
