-- Pawn Arrow Colors: slash command (/pac, /pawnarrowcolors) and the page in the game settings
-- (Options > AddOns > Pawn Arrow Colors, built with Blizzard's Settings API, no library).

local _, ns = ...

local function styleName(style)
    return ns.STYLE_LABELS[style] or style
end

-- Finds a visible scale by list number, internal name or display name (case-insensitive).
function ns.FindScale(query)
    local list = ns.GetVisibleScales()
    local n = tonumber(query)
    if n then return list[n] end
    for _, s in ipairs(list) do
        if s.name == query then return s end
    end
    local lower = string.lower(query)
    for _, s in ipairs(list) do
        if string.lower(s.label) == lower or string.lower(s.name) == lower then return s end
    end
    return nil
end

local function printStatus()
    if not ns.loggedIn then
        ns.Print("not ready yet; try again after the login.")
        return
    end
    ns.Print(string.format("arrow colors %s, yellow style: %s.", ns.db.enabled and "on" or "off", styleName(ns.db.style)))
    if not ns.pawnOK then
        ns.Print("Pawn is not available, nothing is colored.")
        return
    end
    local main, isSaved = ns.ResolveMainScale()
    if main then
        ns.Print(string.format("main scale: %s%s.", main.label, isSaved and "" or " (default: first visible scale)"))
    else
        ns.Print("main scale: none, Pawn shows no scale for this character.")
    end
    local active = {}
    for _, name in ipairs(ns.PATH_ORDER) do
        local path = ns.paths[name]
        if path.active then active[#active + 1] = path.label end
    end
    ns.Print("colors arrows in: " .. (#active > 0 and table.concat(active, ", ") or "nothing (no bag path found)") .. ".")
    if not ns.paths.elvui.active and type(PawnCommon) == "table" and not PawnCommon.ShowBagUpgradeAdvisor then
        ns.Print("Pawn's own bag arrows are off: Pawn > Options > \"Show bag upgrade advisor\".")
    end
end

local function printList()
    local list = ns.GetVisibleScales()
    if #list == 0 then
        ns.Print(ns.PawnReady() and "Pawn shows no scale for this character." or "Pawn is not ready.")
        return
    end
    local main = ns.ResolveMainScale()
    ns.Print("visible Pawn scales (green = upgrade for the main scale, marked with *):")
    for i, s in ipairs(list) do
        local mark = (main and main.name == s.name) and " *" or ""
        print(string.format("  %d. %s%s", i, s.label, mark))
    end
end

local function printHelp()
    ns.Print("commands:")
    print("  /pac - show the state")
    print("  /pac list - list the visible Pawn scales with numbers")
    print("  /pac main <number or name> - choose the main scale")
    print("  /pac main default - first visible scale as the main scale")
    print("  /pac on | off - color the arrows or leave them all green")
    print("  /pac style yellow | tint - own yellow arrow, or the original arrow tinted yellow")
    print("  /pac refresh - forget the cached results and repaint")
    print("  /pac options - open the settings page")
end

function ns.SlashCommand(input)
    input = type(input) == "string" and input or ""
    local cmd, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = string.lower(cmd or "")
    rest = rest or ""

    if cmd == "" or cmd == "status" then
        printStatus()
    elseif cmd == "help" or cmd == "?" then
        printHelp()
    elseif not ns.loggedIn then
        ns.Print("not ready yet; try again after the login.")
    elseif cmd == "list" or cmd == "scales" then
        printList()
    elseif cmd == "main" or cmd == "scale" then
        if rest == "" then
            printList()
            ns.Print("choose with /pac main <number or name>.")
        elseif string.lower(rest) == "default" or string.lower(rest) == "reset" then
            ns.SetMainScale(nil)
            local main = ns.ResolveMainScale()
            ns.Print("main scale: default (" .. (main and main.label or "no visible scale") .. ").")
        else
            local scale = ns.FindScale(rest)
            if scale then
                ns.SetMainScale(scale.name)
                ns.Print("main scale: " .. scale.label .. ".")
            else
                ns.Print("no visible Pawn scale \"" .. rest .. "\"; /pac list shows them.")
            end
        end
    elseif cmd == "on" or cmd == "off" or cmd == "toggle" then
        local on = (cmd == "on") or (cmd == "toggle" and not ns.db.enabled)
        ns.SetEnabled(on)
        ns.Print("arrow colors " .. (on and "on" or "off") .. ".")
    elseif cmd == "style" then
        local arg = string.lower(rest)
        local style = (arg == "yellow" or arg == "texture") and "texture" or (arg == "tint") and "tint" or nil
        if style then
            ns.SetStyle(style)
            ns.Print("yellow style: " .. styleName(style) .. ".")
        else
            ns.Print("style is yellow or tint.")
        end
    elseif cmd == "refresh" then
        ns.Invalidate()
        ns.Print("cache cleared.")
    elseif cmd == "options" or cmd == "config" then
        if ns.settingsCategory and Settings and Settings.OpenToCategory then
            Settings.OpenToCategory(ns.settingsCategory:GetID())
        else
            ns.Print("the settings page is not available; use the slash commands.")
        end
    else
        ns.Print("unknown command \"" .. cmd .. "\".")
        printHelp()
    end
end

SLASH_PAWNARROWCOLORS1 = "/pac"
SLASH_PAWNARROWCOLORS2 = "/pawnarrowcolors"
SlashCmdList.PAWNARROWCOLORS = ns.SlashCommand

-- ---------------------------------------------------------------------------------------------
-- Settings page
-- ---------------------------------------------------------------------------------------------

local SETTINGS_API = {
    "RegisterVerticalLayoutCategory", "RegisterProxySetting", "CreateCheckbox", "CreateDropdown",
    "CreateControlTextContainer", "RegisterAddOnCategory",
}

local function buildSettings()
    local category = Settings.RegisterVerticalLayoutCategory("Pawn Arrow Colors")
    local varType = Settings.VarType or {}

    local enabled = Settings.RegisterProxySetting(category, "PAWNARROWCOLORS_ENABLED", varType.Boolean or "boolean",
        "Color the arrows", true,
        function() return ns.db.enabled end,
        function(value) ns.SetEnabled(value) end)
    Settings.CreateCheckbox(category, enabled,
        "Yellow arrow for items that are an upgrade only for other visible Pawn scales. Off: every arrow stays green.")

    local main = Settings.RegisterProxySetting(category, "PAWNARROWCOLORS_MAINSCALE", varType.String or "string",
        "Main scale", "",
        function()
            local scale = ns.ResolveMainScale()
            return scale and scale.name or ""
        end,
        function(value)
            if value == "" then ns.SetMainScale(nil) else ns.SetMainScale(value) end
        end)
    Settings.CreateDropdown(category, main, function()
        local container = Settings.CreateControlTextContainer()
        local list = ns.GetVisibleScales()
        for _, s in ipairs(list) do container:Add(s.name, s.label) end
        if #list == 0 then container:Add("", "(no visible Pawn scale)") end
        return container:GetData()
    end, "The green arrow stays on items that are an upgrade for this scale. The list shows the scales Pawn shows for this character.")

    local style = Settings.RegisterProxySetting(category, "PAWNARROWCOLORS_STYLE", varType.String or "string",
        "Yellow arrow", "texture",
        function() return ns.db.style end,
        function(value) ns.SetStyle(value) end)
    Settings.CreateDropdown(category, style, function()
        local container = Settings.CreateControlTextContainer()
        for _, s in ipairs(ns.STYLES) do container:Add(s, ns.STYLE_LABELS[s]) end
        return container:GetData()
    end, "Yellow arrow: an own yellow arrow graphic. Tinted original arrow: the green arrow of Pawn or ElvUI, desaturated and tinted yellow.")

    Settings.RegisterAddOnCategory(category)
    return category
end

-- Returns true when the page was added. Without the Settings API only the slash command is offered.
function ns.RegisterSettings()
    if ns.settingsCategory then return true end
    if type(Settings) ~= "table" then return false end
    for _, name in ipairs(SETTINGS_API) do
        if type(Settings[name]) ~= "function" then return false end
    end
    local ok, category = pcall(buildSettings)
    if not ok then
        ns.WarnOnce("settings", "the settings page could not be built; use /pac.")
        return false
    end
    ns.settingsCategory = category
    return true
end
