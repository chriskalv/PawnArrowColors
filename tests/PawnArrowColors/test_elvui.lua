-- ElvUI bags and bank: ElvUI's own arrow texture slot.UpgradeIcon, shown by B:UpdateItemUpgradeIcon.

local ELV_TEXTURE = "Interface\\AddOns\\ElvUI\\Media\\Textures\\BagUpgradeIcon.tga"
local ORIGINAL = { graphic = ELV_TEXTURE, coords = { 0, 1, 0, 1 }, vertex = { 1, 1, 1, 1 }, desaturated = false }

local function yellow(ns)
    return { graphic = ns.TEXTURE, coords = ns.FULL_COORDS, vertex = { 1, 1, 1, 1 }, desaturated = false }
end

local UPGRADES = {
    ["item:main"] = { "A" },
    ["item:other"] = { "B" },
    ["item:both"] = { "B", "A" },
}

local function start(extra)
    local cfg = extra or {}
    cfg.pawn = cfg.pawn or {}
    cfg.pawn.upgrades = cfg.pawn.upgrades or Copy(UPGRADES)
    if cfg.elvui == nil then cfg.elvui = {} end
    local ns = ReloadAddon(cfg)
    Login()
    return ns
end

describe("ElvUI bags", function()
    it("hooks ElvUI's bag module next to the Blizzard path", function()
        local ns = start()
        assert_true(ns.paths.elvui.active)
        assert_true(ns.paths.blizzard.active)
        assert_eq(Output(), "", "no message when everything is found")
    end)

    it("upgrade for the main scale: green and untouched", function()
        start()
        PutItem(0, 1, "item:main")
        local slot = ElvUpdate(STUB.elvBags, 0, 1)
        assert_true(slot.UpgradeIcon:IsShown())
        assert_eq(ArrowState(slot.UpgradeIcon), ORIGINAL)
        assert_eq(slot.UpgradeIcon.calls, 0)
    end)

    it("upgrade only for another scale: yellow over the whole slot like ElvUI's arrow", function()
        local ns = start()
        PutItem(0, 2, "item:other")
        local slot = ElvUpdate(STUB.elvBags, 0, 2)
        assert_true(slot.UpgradeIcon:IsShown())
        assert_eq(ArrowState(slot.UpgradeIcon), yellow(ns))
    end)

    it("upgrade for both: green", function()
        start()
        PutItem(0, 3, "item:both")
        assert_eq(ArrowState(ElvUpdate(STUB.elvBags, 0, 3).UpgradeIcon), ORIGINAL)
    end)

    it("no upgrade: no arrow, nothing touched, no Pawn question from this addon", function()
        start()
        PutItem(0, 4, "item:none")
        local slot = ElvUpdate(STUB.elvBags, 0, 4)
        assert_false(slot.UpgradeIcon:IsShown())
        assert_eq(slot.UpgradeIcon.calls, 0)
        assert_eq(STUB.calls.upgrade, 0)
    end)

    it("the bank is covered", function()
        local ns = start()
        PutItem(-1, 1, "item:other")
        PutItem(5, 2, "item:main")
        assert_eq(ArrowState(ElvUpdate(STUB.elvBank, -1, 1).UpgradeIcon), yellow(ns))
        assert_eq(ArrowState(ElvUpdate(STUB.elvBank, 5, 2).UpgradeIcon), ORIGINAL)
    end)

    it("a reused slot goes yellow -> green -> off and is back in its original state", function()
        local ns = start()
        PutItem(0, 1, "item:other")
        local slot = ElvUpdate(STUB.elvBags, 0, 1)
        assert_eq(ArrowState(slot.UpgradeIcon), yellow(ns))
        PutItem(0, 1, "item:main")
        ElvUpdate(STUB.elvBags, 0, 1)
        assert_true(slot.UpgradeIcon:IsShown())
        assert_eq(ArrowState(slot.UpgradeIcon), ORIGINAL)
        PutItem(0, 1, "item:other")
        ElvUpdate(STUB.elvBags, 0, 1)
        PutItem(0, 1, nil)
        ElvUpdate(STUB.elvBags, 0, 1)
        assert_false(slot.UpgradeIcon:IsShown())
        assert_eq(ArrowState(slot.UpgradeIcon), ORIGINAL)
    end)

    it("ElvUI's retry while Pawn has no answer is colored as well", function()
        local ns = start({ pawn = { throttle = { ["item:other"] = 1 } } })
        PutItem(0, 1, "item:other")
        local slot = ElvUpdate(STUB.elvBags, 0, 1)
        assert_false(slot.UpgradeIcon:IsShown())
        assert_eq(slot.UpgradeIcon.calls, 0)
        ElvRetry(slot)
        assert_true(slot.UpgradeIcon:IsShown())
        assert_eq(ArrowState(slot.UpgradeIcon), yellow(ns))
    end)

    it("ElvUI's own setting off: ElvUI hides the arrow, the addon puts its colors back", function()
        start()
        PutItem(0, 1, "item:other")
        local slot = ElvUpdate(STUB.elvBags, 0, 1)
        STUB.B.db.upgradeIcon = false
        ElvUpdate(STUB.elvBags, 0, 1)
        assert_false(slot.UpgradeIcon:IsShown())
        assert_eq(ArrowState(slot.UpgradeIcon), ORIGINAL)
    end)

    it("a new main scale repaints ElvUI's visible arrows without calling ElvUI", function()
        local ns = start()
        PutItem(0, 1, "item:main")
        PutItem(-1, 1, "item:other")
        local a = ElvUpdate(STUB.elvBags, 0, 1)
        local b = ElvUpdate(STUB.elvBank, -1, 1)
        local elvCalls = STUB.elvuiCalls
        ns.SetMainScale("B")
        RunAllTimers()
        assert_eq(STUB.elvuiCalls, elvCalls, "ElvUI's function is not called by the addon")
        assert_eq(ArrowState(a.UpgradeIcon), yellow(ns))
        assert_eq(ArrowState(b.UpgradeIcon), ORIGINAL)
    end)

    it("ElvUI's arrow graphic set again by ElvUI is painted yellow again", function()
        local ns = start()
        PutItem(0, 1, "item:other")
        local slot = ElvUpdate(STUB.elvBags, 0, 1)
        slot.UpgradeIcon:SetTexture(ELV_TEXTURE) -- ElvUI re-skins the slot
        ElvUpdate(STUB.elvBags, 0, 1)
        assert_eq(ArrowState(slot.UpgradeIcon), yellow(ns))
    end)

    it("ElvUI without UpdateItemUpgradeIcon: that path is off with one message, Blizzard runs", function()
        local ns = start({ elvui = { noFunction = true } })
        assert_false(ns.paths.elvui.active)
        assert_true(ns.paths.blizzard.active)
        assert_contains(Output(), "ElvUI's bag module has no UpdateItemUpgradeIcon")
    end)

    it("without ElvUI only the Blizzard path runs, without a message", function()
        local ns = start({ elvui = false })
        assert_false(ns.paths.elvui.active)
        assert_true(ns.paths.blizzard.active)
        assert_eq(Output(), "")
    end)

    it("set up before ElvUI's bag module has its frames: no error, colored once ElvUI is ready", function()
        local ns = ReloadAddon({ pawn = { upgrades = Copy(UPGRADES) }, elvui = {} })
        Login({ elvLate = true })
        assert_true(ns.setupDone)
        assert_true(ns.paths.elvui.active)
        assert_nil(STUB.B.BagFrames, "like ElvUI, no frame list before its Initialize")
        ns.paths.elvui.Refresh()
        SlashCmdList.PAWNARROWCOLORS("refresh")
        RunAllTimers()
        STUB.elvInitialize()
        PutItem(0, 1, "item:other")
        local slot = ElvUpdate(STUB.elvBags, 0, 1)
        assert_eq(ArrowState(slot.UpgradeIcon), yellow(ns))
    end)

    it("ElvUI asks before Pawn is ready: no arrow and no color until Pawn answers", function()
        local ns = ReloadAddon({ pawn = { initialized = false, upgrades = Copy(UPGRADES) }, elvui = {} })
        Login({ noTimers = true })
        PutItem(0, 1, "item:other")
        local slot = ElvUpdate(STUB.elvBags, 0, 1)
        assert_false(slot.UpgradeIcon:IsShown())
        assert_true(slot.retry, "ElvUI asks again later")
        assert_true(STUB.pawnErrors >= 1, "like Pawn, the early check is refused")
        assert_eq(ArrowState(slot.UpgradeIcon), ORIGINAL)
        STUB.pawnInitialize()
        RunAllTimers()
        assert_true(ns.setupDone)
        ElvRetry(slot)
        assert_true(slot.UpgradeIcon:IsShown())
        assert_eq(ArrowState(slot.UpgradeIcon), yellow(ns))
    end)

    it("style tint keeps ElvUI's graphic", function()
        local ns = start({ saved = { style = "tint" } })
        PutItem(0, 1, "item:other")
        local slot = ElvUpdate(STUB.elvBags, 0, 1)
        assert_eq(ArrowState(slot.UpgradeIcon), { graphic = ELV_TEXTURE, coords = { 0, 1, 0, 1 }, vertex = { 1, 0.82, 0.1, 1 }, desaturated = true })
    end)
end)
