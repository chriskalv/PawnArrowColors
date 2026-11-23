-- Slash command and settings page.

local function start(cfg)
    local ns = ReloadAddon(cfg or {})
    Login()
    ClearOutput()
    return ns
end

local function slash(text)
    ClearOutput()
    SlashCmdList.PAWNARROWCOLORS(text)
    return Output()
end

describe("slash command", function()
    it("/pac and /pawnarrowcolors are registered", function()
        start()
        assert_eq(SLASH_PAWNARROWCOLORS1, "/pac")
        assert_eq(SLASH_PAWNARROWCOLORS2, "/pawnarrowcolors")
        assert_eq(type(SlashCmdList.PAWNARROWCOLORS), "function")
    end)

    it("before the login it only says that it is not ready", function()
        ReloadAddon({})
        local out = slash("list")
        assert_contains(out, "not ready yet")
        assert_eq(STUB.calls.scales, 0)
    end)

    it("/pac shows the state", function()
        start({ elvui = {} })
        local out = slash("")
        assert_contains(out, "arrow colors on, yellow style: Yellow arrow.")
        assert_contains(out, "main scale: Holy (default: first visible scale).")
        assert_contains(out, "colors arrows in: ElvUI bags, Blizzard bags.")
    end)

    it("/pac reminds of Pawn's bag arrow switch when it is off and ElvUI is missing", function()
        start({ pawn = { advisor = false } })
        assert_contains(slash(""), "Show bag upgrade advisor")
    end)

    it("/pac list numbers the visible scales and marks the main scale", function()
        start()
        local out = slash("list")
        assert_contains(out, "  1. Holy *")
        assert_contains(out, "  2. Retribution")
        assert_false(out:find("Protection", 1, true), "hidden scales are not listed")
    end)

    it("/pac main 2 chooses by number", function()
        local ns = start()
        assert_contains(slash("main 2"), "main scale: Retribution.")
        assert_eq(PawnArrowColorsCharDB.mainScale, "B")
        assert_eq(ns.ResolveMainScale().name, "B")
        assert_contains(slash("list"), "  2. Retribution *")
    end)

    it("/pac main <name> chooses by display name (any case) or internal name", function()
        start()
        slash("main retribution")
        assert_eq(PawnArrowColorsCharDB.mainScale, "B")
        slash("main A")
        assert_eq(PawnArrowColorsCharDB.mainScale, "A")
    end)

    it("/pac main with an unknown or hidden scale changes nothing", function()
        start({ saved = { mainScale = "B" } })
        assert_contains(slash("main Protection"), "no visible Pawn scale \"Protection\"")
        assert_contains(slash("main 7"), "no visible Pawn scale \"7\"")
        assert_eq(PawnArrowColorsCharDB.mainScale, "B")
    end)

    it("/pac main default goes back to the first visible scale", function()
        start({ saved = { mainScale = "B" } })
        assert_contains(slash("main default"), "main scale: default (Holy).")
        assert_nil(PawnArrowColorsCharDB.mainScale)
    end)

    it("/pac off, on and toggle", function()
        start()
        slash("off")
        assert_false(PawnArrowColorsCharDB.enabled)
        slash("on")
        assert_true(PawnArrowColorsCharDB.enabled)
        assert_contains(slash("toggle"), "arrow colors off.")
        assert_false(PawnArrowColorsCharDB.enabled)
        assert_contains(slash("toggle"), "arrow colors on.")
        assert_true(PawnArrowColorsCharDB.enabled)
    end)

    it("two visible scales with the same display name are told apart by their internal name", function()
        start({ pawn = { scales = {
            { name = "Ret", label = "Retribution", visible = true },
            { name = "\"PawnForever\":PALADIN3", label = "Retribution", visible = true },
        } } })
        local out = slash("list")
        assert_contains(out, "  1. Retribution (Ret) *")
        assert_contains(out, "  2. Retribution (\"PawnForever\":PALADIN3)")
        assert_contains(slash("main retribution"), "several visible Pawn scales are called \"retribution\"; choose by number")
        assert_nil(PawnArrowColorsCharDB.mainScale)
        assert_contains(slash("main 2"), "main scale: Retribution (\"PawnForever\":PALADIN3).")
        assert_eq(PawnArrowColorsCharDB.mainScale, "\"PawnForever\":PALADIN3")
        local control = STUB.settings.controls[2]
        assert_eq(control.options()[1].label, "Retribution (Ret)")
    end)

    it("/pac style tint and yellow", function()
        start()
        assert_contains(slash("style tint"), "Tinted original arrow")
        assert_eq(PawnArrowColorsCharDB.style, "tint")
        slash("style yellow")
        assert_eq(PawnArrowColorsCharDB.style, "texture")
        assert_contains(slash("style pink"), "style is yellow or tint")
        assert_eq(PawnArrowColorsCharDB.style, "texture")
    end)

    it("/pac refresh clears the cache", function()
        local ns = start({ pawn = { upgrades = { ["item:1"] = { "A" } } } })
        ns.Classify("item:1")
        slash("refresh")
        ns.Classify("item:1")
        assert_eq(STUB.calls.upgrade, 2)
    end)

    it("/pac options opens the settings page", function()
        start()
        slash("options")
        assert_eq(STUB.settings.opened, "cat:Pawn Arrow Colors")
    end)

    it("unknown commands show the help", function()
        start()
        local out = slash("dance")
        assert_contains(out, "unknown command \"dance\"")
        assert_contains(out, "/pac main <number or name>")
    end)
end)

describe("settings page", function()
    it("registers a category with the controls of every feature", function()
        start()
        assert_eq(STUB.settings.registered.name, "Pawn Arrow Colors")
        local kinds = {}
        for _, c in ipairs(STUB.settings.controls) do kinds[#kinds + 1] = c.kind .. ":" .. c.setting.variable end
        assert_eq(kinds, { "checkbox:PAWNARROWCOLORS_ENABLED", "dropdown:PAWNARROWCOLORS_MAINSCALE", "dropdown:PAWNARROWCOLORS_STYLE",
            "dropdown:PAWNARROWCOLORS_SCALEAGE", "checkbox:PAWNARROWCOLORS_HITCAP", "dropdown:PAWNARROWCOLORS_HITCAPVALUE" })
    end)

    it("the main scale dropdown lists the visible scales and sets the choice", function()
        start()
        local control = STUB.settings.controls[2]
        assert_eq(control.options(), { { value = "A", label = "Holy" }, { value = "B", label = "Retribution" } })
        assert_eq(control.setting:GetValue(), "A")
        control.setting:SetValue("B")
        assert_eq(PawnArrowColorsCharDB.mainScale, "B")
        assert_eq(control.setting:GetValue(), "B")
        control.setting:SetValue("")
        assert_nil(PawnArrowColorsCharDB.mainScale, "the default value means the default scale")
    end)

    it("the list follows Pawn's visible scales", function()
        start()
        STUB.pawn.scales[3].visible = true
        local control = STUB.settings.controls[2]
        assert_eq(#control.options(), 3)
    end)

    it("checkbox and style dropdown write the saved settings", function()
        start()
        STUB.settings.settings.PAWNARROWCOLORS_ENABLED:SetValue(false)
        assert_false(PawnArrowColorsCharDB.enabled)
        STUB.settings.settings.PAWNARROWCOLORS_STYLE:SetValue("tint")
        assert_eq(PawnArrowColorsCharDB.style, "tint")
        assert_eq(STUB.settings.controls[3].options(), { { value = "texture", label = "Yellow arrow" }, { value = "tint", label = "Tinted original arrow" } })
    end)

    it("with an incomplete Settings API no page is started and no error is shown", function()
        ReloadAddon({})
        Settings.CreateDropdown = nil
        Login()
        assert_nil(STUB.ns.settingsCategory)
        assert_eq(#STUB.settings.categories, 0, "no half-built category")
        assert_false(Output():find("could not be built", 1, true))
    end)

    it("without the Settings API only the slash command is offered", function()
        local ns = start({ settings = false })
        assert_nil(ns.settingsCategory)
        assert_contains(slash("options"), "the settings page is not available")
    end)
end)
