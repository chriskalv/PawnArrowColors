-- Pawn Arrow Colors: core.
--
-- Saved settings, access to Pawn, the decision "main scale or another scale" per item link with its
-- cache, and painting one arrow texture yellow or back to its original state. The bag hooks live in
-- Bags.lua, the scale age hint in Age.lua, the hit cap in HitCap.lua, the adjusted upgrade answer in
-- Upgrade.lua, the weapon pairs in Pairs.lua, the slash command and the settings page in Options.lua.
--
-- Rule: an arrow that Pawn (Blizzard bags) or ElvUI (ElvUI bags) shows stays as it is (green) when the
-- item is an upgrade for the main scale; it turns yellow when the item is not an upgrade for the main
-- scale, that is an upgrade only for other visible scales (or an item level upgrade only). The colors
-- never show or hide an arrow themselves. Since 1.1.0 the hit cap and the weapon pairs (HitCap.lua,
-- Pairs.lua) change Pawn's own upgrade answer (Upgrade.lua); Pawn and ElvUI then show or hide their
-- arrows by that answer, and the colors follow it like any other.

local ADDON_NAME, ns = ...

ns.name = ADDON_NAME
ns.version = "1.1.0"

-- The yellow arrow (64 x 64, drawn by tools/make_arrow.mjs). The arrow covers pixels 0..43 x 0..47 of
-- the square, like ElvUI's arrow; on Blizzard slots only that part is shown, so that it fills the
-- rectangle of Blizzard's arrow atlas.
ns.TEXTURE = "Interface\\AddOns\\PawnArrowColors\\Textures\\ArrowYellow"
ns.ARROW_COORDS = { 0, 44 / 64, 0, 48 / 64 }
ns.FULL_COORDS = { 0, 1, 0, 1 }
-- Tint for the style "tint": the original arrow desaturated and colored with this.
ns.TINT = { 1, 0.82, 0.1 }
ns.BLIZZARD_ATLAS = "bags-greenarrow"

ns.STYLES = { "texture", "tint" }
ns.STYLE_LABELS = { texture = "Yellow arrow", tint = "Tinted original arrow" }

ns.MAX_RETRIES = 10 -- refresh passes for links that Pawn cannot rate yet, per invalidation
ns.RETRY_DELAY = 1

ns.loggedIn = false
ns.pawnOK = false
ns.cache = {} -- item link -> "main" | "other"
ns.painted = setmetatable({}, { __mode = "k" }) -- arrow texture -> { kind, texture }
ns.paths = {} -- name -> path table (Bags.lua)
ns.warned = {}
ns.stats = { classified = 0, pawnCalls = 0 }

local PREFIX = "|cff33ff99Pawn Arrow Colors|r: "

function ns.Print(msg)
    print(PREFIX .. msg)
end

-- Prints a message only once per session and key.
function ns.WarnOnce(key, msg)
    if ns.warned[key] then return end
    ns.warned[key] = true
    ns.Print(msg)
end

-- ---------------------------------------------------------------------------------------------
-- Saved settings (per character)
-- ---------------------------------------------------------------------------------------------

-- Functions that check and default the saved settings of the other files (Age.lua, HitCap.lua, Pairs.lua);
-- each is called with the table of saved settings.
ns.dbInits = {}

-- What the features add to Options.lua: status lines of /pac (functions), help lines (text),
-- commands (name -> function(rest)) and builders of settings (function(category, varType)).
ns.statusLines = {}
ns.helpLines = {}
ns.commands = {}
ns.settingsBuilders = {}

local function isStyle(v)
    for _, s in ipairs(ns.STYLES) do
        if s == v then return true end
    end
    return false
end
ns.IsStyle = isStyle

function ns.InitDB()
    if type(PawnArrowColorsCharDB) ~= "table" then PawnArrowColorsCharDB = {} end
    local db = PawnArrowColorsCharDB
    if type(db.enabled) ~= "boolean" then db.enabled = true end
    if not isStyle(db.style) then db.style = "texture" end
    if db.mainScale ~= nil and (type(db.mainScale) ~= "string" or db.mainScale == "") then db.mainScale = nil end
    for _, init in ipairs(ns.dbInits) do init(db) end
    ns.db = db
    return db
end

-- ---------------------------------------------------------------------------------------------
-- Pawn
-- ---------------------------------------------------------------------------------------------

-- Every name the addon reads from Pawn is a global function or saved variable of Pawn (Pawn's own
-- flag for its initialization is a local variable of Pawn.lua and cannot be read by other addons;
-- PawnIsReady is Pawn's public way to ask for it). tests/pawn_names.test.mjs keeps that list.
ns.REQUIRED_PAWN = { "PawnIsReady", "PawnGetItemData", "PawnIsItemAnUpgrade", "PawnGetAllScalesEx" }

-- Returns true, or false and the name of the first missing Pawn function (nil when none of them exists,
-- that is Pawn is not loaded).
function ns.CheckPawn()
    local missing, found = nil, false
    for _, name in ipairs(ns.REQUIRED_PAWN) do
        if type(_G[name]) == "function" then
            found = true
        elseif not missing then
            missing = name
        end
    end
    if not missing then return true end
    return false, found and missing or nil
end

-- Asks Pawn whether it is ready to rate items (true after Pawn's own PLAYER_LOGIN handler finished).
-- Never raises an error; false when PawnIsReady is missing or fails.
function ns.AskPawnReady()
    if type(PawnIsReady) ~= "function" then return false end
    local ok, ready = pcall(PawnIsReady)
    return ok and ready and true or false
end

-- True once the addon is set up: logged in and Pawn reported ready (Pawn stays ready afterwards).
function ns.IsPawnReady()
    return ns.loggedIn and ns.pawnOK and true or false
end

-- The scales visible for this character, in the order of Pawn's scale list:
-- { { name = internal name, label = display name, provider = true for a scale of a plugin }, ... }
function ns.GetVisibleScales()
    local list = {}
    if not ns.IsPawnReady() then return list end
    local ok, all = pcall(PawnGetAllScalesEx)
    if not ok or type(all) ~= "table" then return list end
    for _, s in ipairs(all) do
        if type(s) == "table" and s.IsVisible and type(s.Name) == "string" then
            local label = type(s.LocalizedName) == "string" and s.LocalizedName ~= "" and s.LocalizedName or s.Name
            list[#list + 1] = { name = s.Name, label = label, provider = s.IsProvider and true or false }
        end
    end
    return list
end

-- The main scale: the saved one if Pawn still shows it for this character, otherwise the first visible
-- scale. Returns the entry { name, label } and true when it is the saved choice, or nil without any
-- visible scale. Cached until the next invalidation.
function ns.ResolveMainScale()
    if ns.mainResolved then return ns.mainScale, ns.mainIsSaved end
    if not ns.IsPawnReady() then return nil, false end
    local list = ns.GetVisibleScales()
    local saved = ns.db and ns.db.mainScale
    local chosen, isSaved
    if saved then
        for _, s in ipairs(list) do
            if s.name == saved then
                chosen, isSaved = s, true
                break
            end
        end
        if not chosen and ns.missingNotice ~= saved then
            ns.missingNotice = saved
            ns.Print(string.format("the saved main scale %s is not a visible Pawn scale for this character; using %s.",
                saved, list[1] and list[1].label or "none (no visible scale)"))
        end
    end
    if not chosen then chosen, isSaved = list[1], false end
    ns.mainScale, ns.mainIsSaved, ns.mainResolved = chosen, isSaved, true
    return chosen, isSaved
end

-- ---------------------------------------------------------------------------------------------
-- Decision per item link
-- ---------------------------------------------------------------------------------------------

-- Returns "main" (upgrade for the main scale), "other" (Pawn shows an arrow, but not for the main
-- scale) or nil (Pawn cannot tell yet, or the addon is not ready). Only "main" and "other" are cached.
function ns.Classify(link)
    if not ns.IsPawnReady() then return nil end
    if issecretvalue and issecretvalue(link) then return nil end
    if type(link) ~= "string" or link == "" then return nil end
    local cached = ns.cache[link]
    if cached then return cached end

    ns.stats.pawnCalls = ns.stats.pawnCalls + 1
    local okItem, item = pcall(PawnGetItemData, link)
    if not okItem or type(item) ~= "table" or item.Link == nil then return nil end
    local ok, upgrades, itemLevelIncrease = pcall(PawnIsItemAnUpgrade, item)
    if not ok then return nil end

    local result
    if type(upgrades) == "table" then
        result = "other"
        local main = ns.ResolveMainScale()
        if main then
            for _, u in ipairs(upgrades) do
                if type(u) == "table" and u.ScaleName == main.name then
                    result = "main"
                    break
                end
            end
        end
    elseif itemLevelIncrease ~= nil then
        result = "other" -- an item level upgrade only
    else
        return nil -- Pawn returns nothing while it lacks data for the equipped items
    end
    ns.cache[link] = result
    ns.stats.classified = ns.stats.classified + 1
    return result
end

-- ---------------------------------------------------------------------------------------------
-- Painting
-- ---------------------------------------------------------------------------------------------

-- ElvUI's own arrow texture (read only), used to restore an ElvUI arrow.
function ns.ElvUITexture()
    local E = type(ElvUI) == "table" and ElvUI[1]
    local media = type(E) == "table" and type(E.Media) == "table" and E.Media.Textures
    local tex = type(media) == "table" and media.BagUpgradeIcon
    if type(tex) == "string" or type(tex) == "number" then return tex end
    return nil
end

-- Puts an arrow back into its original state: graphic, texture coordinates, color, saturation.
-- Does nothing to an arrow this addon has not changed.
function ns.Restore(icon)
    local orig = ns.painted[icon]
    if not orig then return end
    if orig.kind == "blizzard" then
        icon:SetAtlas(orig.atlas or ns.BLIZZARD_ATLAS) -- also sets the atlas texture coordinates; size stays
    else
        local texture = ns.ElvUITexture() or orig.texture
        if texture then icon:SetTexture(texture) end
        -- ElvUI sets these coordinates itself when it builds the slot (SetTexCoord(0, 1, 0, 1)); the
        -- yellow arrow uses the same ones, so this line only guards against a later change of either.
        icon:SetTexCoord(unpack(ns.FULL_COORDS))
    end
    icon:SetVertexColor(1, 1, 1, 1)
    icon:SetDesaturated(false)
    ns.painted[icon] = nil
end

-- Paints an arrow yellow in the chosen style. kind: "blizzard" or "elvui".
-- A change of the style goes through ns.SetStyle, which restores every arrow first, so an arrow that is
-- already painted always carries the current style.
function ns.MakeYellow(icon, kind)
    local orig = ns.painted[icon]
    if not orig then
        -- the original state, taken before the first change
        orig = { kind = kind }
        if kind == "blizzard" then
            orig.atlas = icon.GetAtlas and icon:GetAtlas() or nil
        else
            orig.texture = icon:GetTexture()
        end
        ns.painted[icon] = orig
    end
    -- applied every time: the bag addon may have set its own graphic again in the meantime
    if ns.db.style == "tint" then
        icon:SetDesaturated(true)
        icon:SetVertexColor(ns.TINT[1], ns.TINT[2], ns.TINT[3], 1)
    else
        icon:SetTexture(ns.TEXTURE)
        icon:SetTexCoord(unpack(kind == "blizzard" and ns.ARROW_COORDS or ns.FULL_COORDS))
        icon:SetVertexColor(1, 1, 1, 1)
        icon:SetDesaturated(false)
    end
end

-- Colors one visible arrow for the item link.
function ns.Paint(icon, kind, link)
    if not ns.db or not ns.db.enabled then
        ns.Restore(icon)
        return
    end
    local class = ns.Classify(link)
    if class == "other" then
        ns.MakeYellow(icon, kind)
    else
        ns.Restore(icon)
        if class == nil and ns.IsPawnReady() and link ~= nil then ns.ScheduleRetry() end
    end
end

-- Every arrow back to its original state (when the coloring is turned off).
function ns.RestoreAll()
    local icons = {}
    for icon in pairs(ns.painted) do icons[#icons + 1] = icon end
    for _, icon in ipairs(icons) do ns.Restore(icon) end
end

-- ---------------------------------------------------------------------------------------------
-- Cache and refresh
-- ---------------------------------------------------------------------------------------------

-- Repaints the visible arrows of every active bag path.
function ns.RefreshVisible()
    ns.refreshPending = false
    if not ns.loggedIn then return end
    if ns.db and not ns.db.enabled then
        ns.RestoreAll()
        return
    end
    for _, path in pairs(ns.paths) do
        if path.active and path.Refresh then path.Refresh() end
    end
end

-- Repaints on the next frame (several invalidations in one frame lead to one pass).
function ns.QueueRefresh()
    if ns.refreshPending or not ns.loggedIn then return end
    ns.refreshPending = true
    C_Timer.After(0, ns.RefreshVisible)
end

function ns.ScheduleRetry()
    if ns.retryPending or (ns.retries or 0) >= ns.MAX_RETRIES then return end
    ns.retryPending = true
    ns.retries = (ns.retries or 0) + 1
    C_Timer.After(ns.RETRY_DELAY, function()
        ns.retryPending = false
        ns.RefreshVisible()
    end)
end

-- Functions of the other files that forget their own cached results; called by ns.Invalidate.
ns.onInvalidate = {}

-- Forgets every decision and the main scale (Pawn reset its bags, the gear or the main scale changed),
-- then repaints the visible arrows on the next frame.
--
-- As a post-hook on PawnResetBags this runs after Pawn's own bag refresh; the arrows Pawn shows during
-- that refresh are still painted from the old results and get their new color one frame later. That
-- delay of one frame is intended: it keeps one repaint pass for any number of invalidations.
function ns.Invalidate()
    ns.equipPending = false
    ns.cache = {}
    ns.mainResolved, ns.mainScale, ns.mainIsSaved = nil, nil, nil
    ns.retries = 0
    for _, fn in ipairs(ns.onInvalidate) do fn() end
    ns.QueueRefresh()
end

-- ---------------------------------------------------------------------------------------------
-- Changing the settings
-- ---------------------------------------------------------------------------------------------

function ns.SetEnabled(on)
    ns.db.enabled = not not on
    if not ns.db.enabled then ns.RestoreAll() end
    ns.Invalidate()
end

-- name: internal scale name, or nil for the default (first visible scale).
function ns.SetMainScale(name)
    ns.db.mainScale = name
    ns.missingNotice = nil
    ns.Invalidate()
end

function ns.SetStyle(style)
    if not isStyle(style) then return false end
    ns.db.style = style
    ns.RestoreAll()
    ns.Invalidate()
    return true
end

-- ---------------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------------

ns.SETUP_TRIES = 20 -- tries to find Pawn ready, one every SETUP_DELAY seconds, before giving up
ns.SETUP_DELAY = 0.5

-- A gear change: Pawn checks the equipped items itself (throttled to 0.25 s, not in combat) and then
-- calls PawnResetBags, which invalidates through the hook above. Asking Pawn before that would rate
-- the bags against the old gear, so the addon only invalidates itself when Pawn has not done so within
-- this delay (in combat, or without PawnResetBags).
ns.EQUIP_DELAY = 1

function ns.OnEquipmentChanged()
    if ns.equipPending then return end
    ns.equipPending = true
    C_Timer.After(ns.EQUIP_DELAY, function()
        if ns.equipPending then ns.Invalidate() end
    end)
end

-- Functions of the other files that run once the addon is set up (Pawn ready), before the first repaint.
ns.onSetup = {}

local function setupTimer()
    ns.setupPending = false
    ns.Setup()
end

-- Hooks the bag paths once Pawn is ready. Returns true when the addon is set up.
-- Without one of Pawn's functions (another Pawn version, or no Pawn) the addon stays off and says so
-- once. While Pawn is not ready yet it tries again every SETUP_DELAY seconds, SETUP_TRIES times;
-- ns.pawnProblem holds the reason for /pac. ns.RetrySetup starts a new round after giving up.
function ns.Setup()
    if ns.setupDone then return true end
    if not ns.loggedIn then return false end
    local ok, missing = ns.CheckPawn()
    if not ok then
        if missing then
            ns.pawnProblem = string.format("Pawn's function %s was not found (another Pawn version?)", missing)
        else
            ns.pawnProblem = "Pawn is not loaded"
        end
        ns.WarnOnce("pawn", ns.pawnProblem .. "; the arrows keep Pawn's colors.")
        return false
    end
    if not ns.AskPawnReady() then
        ns.setupTries = (ns.setupTries or 0) + 1
        if ns.setupTries <= ns.SETUP_TRIES then
            ns.pawnProblem = "Pawn has not finished loading yet"
            if not ns.setupPending then
                ns.setupPending = true
                C_Timer.After(ns.SETUP_DELAY, setupTimer)
            end
        else
            ns.pawnProblem = "Pawn did not finish loading"
            ns.WarnOnce("pawninit", "Pawn did not finish loading; the arrows keep Pawn's colors. /pac refresh tries again.")
        end
        return false
    end
    ns.pawnProblem = nil
    ns.pawnOK = true
    ns.setupDone = true

    if type(PawnResetBags) == "function" then
        hooksecurefunc("PawnResetBags", ns.Invalidate)
    else
        ns.WarnOnce("reset", "Pawn's function PawnResetBags was not found; after changing Pawn's scales type /pac refresh.")
    end
    for _, name in ipairs(ns.PATH_ORDER or {}) do
        local path = ns.paths[name]
        path.active = path.Setup() and true or false
    end
    for _, fn in ipairs(ns.onSetup) do fn() end
    if ns.RegisterSettings then ns.RegisterSettings() end
    ns.QueueRefresh()
    return true
end

-- Tries the set-up again with a fresh count of tries (from /pac and /pac refresh), also after Setup
-- gave up. While a round of tries is still running it leaves that round as it is. A new round that
-- gives up again says so again. Returns true when the addon is set up.
function ns.RetrySetup()
    if ns.setupDone then return true end
    if not ns.loggedIn then return false end
    if ns.setupPending then return ns.Setup() end
    ns.setupTries = 0
    ns.warned.pawninit = nil
    return ns.Setup()
end

-- Events of the other files: ns.On(event, fn) registers fn(event, ...) for an event after the login.
-- An event the client does not know is skipped (RegisterEvent raises an error for it).
ns.handlers = {}

function ns.On(event, fn)
    local list = ns.handlers[event]
    if not list then
        list = {}
        ns.handlers[event] = list
        if ns.eventFrame and ns.loggedIn then pcall(ns.eventFrame.RegisterEvent, ns.eventFrame, event) end
    end
    list[#list + 1] = fn
end

local events = CreateFrame("Frame")
ns.eventFrame = events
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, arg1, ...)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            ns.InitDB()
            events:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "PLAYER_LOGIN" then
        if not ns.db then ns.InitDB() end
        ns.loggedIn = true
        events:UnregisterEvent("PLAYER_LOGIN")
        events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
        for name in pairs(ns.handlers) do pcall(events.RegisterEvent, events, name) end
        ns.Setup()
    else
        if event == "PLAYER_EQUIPMENT_CHANGED" and ns.setupDone then ns.OnEquipmentChanged() end
        local list = ns.handlers[event]
        if list and ns.setupDone then
            for _, fn in ipairs(list) do fn(event, arg1, ...) end
        end
    end
end)
