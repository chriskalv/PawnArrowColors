-- Pawn Arrow Colors: scale age.
--
-- Stat weights measured at one level grow old while the character levels. For every visible scale
-- the player made (no scale of a plugin such as Pawn Forever) the addon remembers per character on
-- which level it first saw the current content of the scale: an identifier from the scale's name and
-- all of its values. When the values change, the count starts again at the current level.
--
-- Once the character is a set number of levels further (default 3, 0 turns the hint off) and below
-- level 60, the chat says so after the login and after a level up, at most once per scale and level.

local _, ns = ...

ns.AGE_DEFAULT = 3
ns.AGE_MAX = 10 -- largest choice on the settings page; /pac age takes any whole number
ns.AGE_LAST_LEVEL = 60 -- no hint on this level (weights for the last level are not outgrown)

table.insert(ns.dbInits, function(db)
    local n = db.scaleAgeLevels
    if type(n) ~= "number" or n < 0 or n ~= math.floor(n) then db.scaleAgeLevels = ns.AGE_DEFAULT end
    if type(db.scaleAge) ~= "table" then db.scaleAge = {} end
    for name, rec in pairs(db.scaleAge) do
        if type(name) ~= "string" or type(rec) ~= "table" or type(rec.sig) ~= "string" or type(rec.level) ~= "number" then
            db.scaleAge[name] = nil
        end
    end
end)

-- A short identifier for a text: two polynomial hashes modulo primes below 2^24, so that every step
-- stays an exact whole number below 2^31 (Lua 5.1 has no bit operations).
local function hash(text)
    local h1, h2 = 5381, 7919
    for i = 1, #text do
        local b = string.byte(text, i)
        h1 = (h1 * 33 + b) % 16777213
        h2 = (h2 * 31 + b) % 16777199
    end
    return string.format("%d-%d", h1, h2)
end

-- The identifier of a scale's current content: its name and every value, sorted by stat name.
-- nil when Pawn has no values for it.
function ns.ScaleSignature(name)
    local scales = type(PawnCommon) == "table" and PawnCommon.Scales
    local scale = type(scales) == "table" and scales[name]
    local values = type(scale) == "table" and scale.Values
    if type(values) ~= "table" then return nil end
    local keys = {}
    for k, v in pairs(values) do
        if type(k) == "string" and type(v) == "number" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local parts = { name }
    for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. string.format("%.6g", values[k]) end
    local text = table.concat(parts, ";")
    return #keys .. ":" .. hash(text)
end

-- The character's level, or nil while it cannot be read.
function ns.PlayerLevel()
    if type(UnitLevel) ~= "function" then return nil end
    local level = UnitLevel("player")
    if type(level) ~= "number" or (issecretvalue and issecretvalue(level)) or level < 1 then return nil end
    return level
end

-- The scales the age hint looks at: visible and not from a plugin.
function ns.AgeScales()
    local list = {}
    for _, s in ipairs(ns.GetVisibleScales()) do
        if not s.provider then list[#list + 1] = s end
    end
    return list
end

-- Remembers the level for every scale whose content is new to the addon. level: the current level.
function ns.UpdateScaleAges(level)
    level = level or ns.PlayerLevel()
    if not level or not ns.db then return end
    for _, s in ipairs(ns.AgeScales()) do
        local sig = ns.ScaleSignature(s.name)
        if sig then
            local rec = ns.db.scaleAge[s.name]
            if not rec or rec.sig ~= sig then
                ns.db.scaleAge[s.name] = { sig = sig, level = level }
            end
        end
    end
end

-- The age of a scale's weights in levels, the level they were first seen on, or nil.
function ns.ScaleAge(name, level)
    level = level or ns.PlayerLevel()
    local rec = ns.db and ns.db.scaleAge[name]
    if not rec or not level then return nil end
    return level - rec.level, rec.level
end

-- Prints the hint for every scale that is old enough, once per scale and level. Returns the number of
-- lines printed.
function ns.CheckScaleAges(level)
    level = level or ns.PlayerLevel()
    local n = ns.db and ns.db.scaleAgeLevels or 0
    if not level or n <= 0 or level >= ns.AGE_LAST_LEVEL then return 0 end
    local printed = 0
    local list = ns.AgeScales()
    for _, s in ipairs(list) do
        local rec = ns.db.scaleAge[s.name]
        if rec and level - rec.level >= n and rec.warned ~= level then
            rec.warned = level
            printed = printed + 1
            ns.Print(string.format("the weights of the scale %s are from level %d, you are level %d now; consider determining them again.",
                ns.ScaleText(s, list), rec.level, level))
        end
    end
    return printed
end

function ns.SetScaleAgeLevels(n)
    ns.db.scaleAgeLevels = n
    ns.CheckScaleAges()
end

-- After the set-up (the login): remember new scales, then the hint.
table.insert(ns.onSetup, function()
    ns.UpdateScaleAges()
    ns.CheckScaleAges()
end)

-- Pawn resets its bag arrows when a scale changes: remember the new content (no hint until the next
-- login or level up).
table.insert(ns.onInvalidate, function()
    if ns.setupDone then ns.UpdateScaleAges() end
end)

-- PLAYER_LEVEL_UP carries the new level (UnitLevel can still return the old one during the event).
ns.On("PLAYER_LEVEL_UP", function(_, level)
    if type(level) ~= "number" or (issecretvalue and issecretvalue(level)) then level = nil end
    ns.UpdateScaleAges(level)
    ns.CheckScaleAges(level)
end)
