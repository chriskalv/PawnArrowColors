-- Scale age: the level each visible own scale was first seen on, and the hint when it is old.

local function scales()
    return {
        { name = "A", label = "Holy", visible = true, values = { Intellect = 1, Healing = 0.8 } },
        { name = "B", label = "Retribution", visible = true, values = { Strength = 1, HitRating = 9 } },
        { name = "C", label = "Protection", visible = false, values = { Stamina = 1 } },
        { name = "\"PawnForever\":PALADIN2", label = "Retribution (Forever)", visible = true, provider = true, values = { Strength = 1 } },
    }
end

local function start(cfg)
    cfg = cfg or {}
    cfg.pawn = cfg.pawn or {}
    cfg.pawn.scales = cfg.pawn.scales or scales()
    local ns = ReloadAddon(cfg)
    Login()
    return ns
end

local function slash(text)
    ClearOutput()
    SlashCmdList.PAWNARROWCOLORS(text)
    return Output()
end

describe("scale age", function()
    it("remembers the login level for every visible own scale, not for hidden or plugin scales", function()
        local ns = start({ level = 20 })
        local ages = PawnArrowColorsCharDB.scaleAge
        assert_eq(ages.A.level, 20)
        assert_eq(ages.B.level, 20)
        assert_nil(ages.C, "hidden scale")
        assert_nil(ages["\"PawnForever\":PALADIN2"], "plugin scale")
        assert_eq(Output(), "", "no hint for new scales")
        assert_eq(ns.ScaleAge("A"), 0)
    end)

    it("the identifier depends on name and values only, not on the order of the values", function()
        local ns = start()
        local sig = ns.ScaleSignature("B")
        PawnCommon.Scales.B.Values = { HitRating = 9, Strength = 1 }
        assert_eq(ns.ScaleSignature("B"), sig)
        PawnCommon.Scales.B.Values.HitRating = 8.5
        assert_true(ns.ScaleSignature("B") ~= sig)
        assert_nil(ns.ScaleSignature("missing"))
    end)

    it("hint after three levels on a level up, once per level, with old and new level", function()
        local ns = start({ level = 20 })
        LevelUp(21)
        LevelUp(22)
        assert_eq(Output(), "", "two levels are not enough")
        LevelUp(23)
        local out = Output()
        assert_contains(out, "the weights of the scale Holy are from level 20, you are level 23 now; consider determining them again.")
        assert_contains(out, "the weights of the scale Retribution are from level 20, you are level 23 now")
        assert_not_contains(out, "Protection")
        assert_not_contains(out, "Forever")
        ClearOutput()
        ns.CheckScaleAges()
        assert_eq(Output(), "", "at most once per level")
        LevelUp(24)
        assert_contains(Output(), "you are level 24 now")
    end)

    it("hint at the login when the saved level is old enough, not again after a reload on the same level", function()
        local first = start({ level = 30 })
        local saved = Copy(PawnArrowColorsCharDB)
        first = nil
        start({ level = 33, saved = saved })
        assert_contains(Output(), "the weights of the scale Holy are from level 30, you are level 33 now")
        local again = Copy(PawnArrowColorsCharDB)
        ClearOutput()
        start({ level = 33, saved = again })
        assert_not_contains(Output(), "the weights of the scale")
    end)

    it("changed values start the count again at the current level", function()
        local ns = start({ level = 20 })
        LevelUp(22)
        PawnCommon.Scales.A.Values.Intellect = 1.2
        PawnResetBags() -- Pawn after a change of a scale
        assert_eq(PawnArrowColorsCharDB.scaleAge.A.level, 22)
        assert_eq(PawnArrowColorsCharDB.scaleAge.B.level, 20)
        ClearOutput()
        LevelUp(23)
        assert_not_contains(Output(), "Holy")
        assert_contains(Output(), "Retribution")
        assert_eq(ns.ScaleAge("A"), 1)
    end)

    it("no hint on level 60", function()
        start({ level = 57 })
        LevelUp(60)
        assert_eq(Output(), "")
    end)

    it("0 turns the hint off; the levels are remembered all the same", function()
        local ns = start({ level = 20, saved = { scaleAgeLevels = 0 } })
        LevelUp(25)
        assert_eq(Output(), "")
        assert_eq(PawnArrowColorsCharDB.scaleAge.A.level, 20)
        ns.SetScaleAgeLevels(5)
        assert_contains(Output(), "you are level 25 now")
    end)

    it("invalid saved settings are replaced by the defaults", function()
        start({ saved = { scaleAgeLevels = -2, scaleAge = { A = "x", B = { sig = 1, level = 3 } } } })
        assert_eq(PawnArrowColorsCharDB.scaleAgeLevels, 3)
        assert_eq(PawnArrowColorsCharDB.scaleAge.A.level, 20, "rebuilt from the login")
    end)

    it("/pac age shows the state per scale and sets the number of levels", function()
        start({ level = 20 })
        LevelUp(22)
        local out = slash("age")
        assert_contains(out, "scale age hint: after 3 levels, below level 60.")
        assert_contains(out, "Holy: weights from level 20, now 22 (2 levels)")
        assert_not_contains(out, "Forever")
        out = slash("age 2")
        assert_eq(PawnArrowColorsCharDB.scaleAgeLevels, 2)
        assert_contains(out, "you are level 22 now", "the hint follows at once")
        slash("age off")
        assert_eq(PawnArrowColorsCharDB.scaleAgeLevels, 0)
        assert_contains(slash("age"), "scale age hint: off")
        slash("age on")
        assert_eq(PawnArrowColorsCharDB.scaleAgeLevels, 3)
        assert_contains(slash("age soon"), "age takes a whole number")
        assert_contains(slash(""), "scale age hint: after 3 levels")
    end)

    it("the settings page offers off and 1 to 10 levels", function()
        start({ level = 20 })
        local setting = STUB.settings.settings.PAWNARROWCOLORS_SCALEAGE
        assert_eq(setting:GetValue(), 3)
        setting:SetValue(0)
        assert_eq(PawnArrowColorsCharDB.scaleAgeLevels, 0)
        local options
        for _, c in ipairs(STUB.settings.controls) do
            if c.setting == setting then options = c.options() end
        end
        assert_eq(#options, 11)
        assert_eq(options[1], { value = 0, label = "Off" })
    end)

    it("a level up before Pawn is ready does nothing", function()
        local ns = ReloadAddon({ pawn = { initialized = false, scales = scales() } })
        Login({ noTimers = true })
        LevelUp(30)
        assert_eq(next(PawnArrowColorsCharDB.scaleAge), nil)
        assert_false(ns.setupDone)
    end)
end)
