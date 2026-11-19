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
--     scales      list of { name, label, visible } in the order of Pawn's scale list
--                 (default: "A" Holy, "B" Retribution, "C" Protection (hidden))
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
--   elvui         false/nil, or { noFunction = true }: ElvUI and its bag module are loaded
--   blizzard      false: no Blizzard container frames
--   saved         PawnArrowColorsCharDB as saved before the login
--   settings      false: no Settings API

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

    PawnCommon = { ShowBagUpgradeAdvisor = cfg.advisor ~= false }

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
            out[#out + 1] = { Name = s.name, LocalizedName = s.label, IsVisible = s.visible, IsProvider = false }
        end
        return out
    end
    function api.PawnGetItemData(link)
        STUB.calls.itemData = STUB.calls.itemData + 1
        if (cfg.nolink[link] or 0) > 0 then
            cfg.nolink[link] = cfg.nolink[link] - 1
            return { Link = nil }
        end
        return { Link = link }
    end
    -- Upgrade list for the visible scales the item is an upgrade for, sorted by display name.
    function api.PawnIsItemAnUpgrade(item)
        STUB.calls.upgrade = STUB.calls.upgrade + 1
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
    function api.PawnShouldItemLinkHaveUpgradeArrowUnbudgeted(link)
        if (cfg.throttle[link] or 0) > 0 then
            cfg.throttle[link] = cfg.throttle[link] - 1
            return nil
        end
        if (cfg.nolink[link] or 0) > 0 then
            cfg.nolink[link] = cfg.nolink[link] - 1
            return nil
        end
        local hasScale = false
        for _, name in ipairs(cfg.upgrades[link] or {}) do
            if visible(name) then hasScale = true end
        end
        return hasScale or cfg.ilvl[link] == true
    end
    api.PawnShouldItemLinkHaveUpgradeArrow = function(link)
        STUB.calls.arrow = STUB.calls.arrow + 1
        return api.PawnShouldItemLinkHaveUpgradeArrowUnbudgeted(link)
    end
    -- Pawn's bag reset: refreshes its own bag arrows (a new refresh number ends the per-button skip).
    function api.PawnResetBags()
        STUB.resets = (STUB.resets or 0) + 1
        STUB.pawnRefreshCounter = (STUB.pawnRefreshCounter or 0) + 1
        if STUB.pawnBagRefresh then STUB.pawnBagRefresh() end
    end
    for name, fn in pairs(api) do
        if not cfg.missing[name] then _G[name] = fn end
    end
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
    local B = { BagFrames = {} }
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
    STUB.elvBags = newFrame({ 0, 1 })
    STUB.elvBank = newFrame({ -1, 5 })
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

-- Login sequence: the addon's saved variables, Pawn's PLAYER_LOGIN (initialized, bag hooks), then the
-- addon's PLAYER_LOGIN, then the timers of the next frame.
function Login(opts)
    opts = opts or {}
    FireEvent("ADDON_LOADED", "PawnArrowColors")
    if STUB.pawn and STUB.pawn.initialized ~= false then
        STUB.pawnInitialize()
        if STUB.pawnHookBags and PawnCommon.ShowBagUpgradeAdvisor then STUB.pawnHookBags() end
    end
    FireEvent("PLAYER_LOGIN")
    if not opts.noTimers then RunAllTimers() end
end
