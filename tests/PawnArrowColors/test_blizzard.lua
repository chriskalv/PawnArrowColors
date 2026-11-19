-- Blizzard bags: Pawn's own arrow on Blizzard's UpgradeIcon texture.

local ORIGINAL = { graphic = "bags-greenarrow", coords = { 0.1, 0.2, 0.3, 0.4 }, vertex = { 1, 1, 1, 1 }, desaturated = false }

local function yellow(ns)
    return { graphic = ns.TEXTURE, coords = ns.ARROW_COORDS, vertex = { 1, 1, 1, 1 }, desaturated = false }
end

local UPGRADES = {
    ["item:main"] = { "A" },
    ["item:other"] = { "B" },
    ["item:both"] = { "A", "B" },
}

local function start(extra)
    local cfg = extra or {}
    cfg.pawn = cfg.pawn or {}
    cfg.pawn.upgrades = cfg.pawn.upgrades or Copy(UPGRADES)
    local ns = ReloadAddon(cfg)
    Login()
    return ns
end

local function arrow(frame, slotID)
    return BlizzardButton(frame, slotID).UpgradeIcon
end

describe("Blizzard bags", function()
    it("hooks the combined bag and every container frame", function()
        local ns = start()
        assert_true(ns.paths.blizzard.active)
        assert_false(ns.paths.elvui.active, "no ElvUI")
        assert_eq(#ns.paths.blizzard.frames, 6)
    end)

    it("upgrade for the main scale: the arrow stays green and untouched", function()
        start()
        PutItem(0, 1, "item:main")
        ContainerFrame1:Open({ 1 })
        local icon = arrow(ContainerFrame1, 1)
        assert_true(icon:IsShown())
        assert_eq(ArrowState(icon), ORIGINAL)
        assert_eq(icon.calls, 0)
    end)

    it("upgrade only for another scale: the arrow turns yellow, same place and size", function()
        local ns = start()
        PutItem(0, 2, "item:other")
        ContainerFrame1:Open({ 2 })
        local icon = arrow(ContainerFrame1, 2)
        assert_true(icon:IsShown(), "the addon does not hide Pawn's arrow")
        assert_eq(ArrowState(icon), yellow(ns))
    end)

    it("Pawn skips a button it already checked: the arrow keeps its color on the next UpdateItems", function()
        local ns = start()
        PutItem(0, 2, "item:other")
        PutItem(0, 3, "item:main")
        ContainerFrame1:Open({ 2, 3 })
        ContainerFrame1:UpdateItems()
        assert_eq(STUB.pawnSkips, 2, "Pawn did not call SetShown again")
        assert_eq(ArrowState(arrow(ContainerFrame1, 2)), yellow(ns))
        assert_eq(ArrowState(arrow(ContainerFrame1, 3)), ORIGINAL)
    end)

    it("an item Pawn has no stats for yet gets its color once Pawn's retry shows the arrow", function()
        local ns = start({ pawn = { nolink = { ["item:other"] = 1 } } })
        PutItem(0, 2, "item:other")
        ContainerFrame1:Open({ 2 })
        local icon = arrow(ContainerFrame1, 2)
        assert_false(icon:IsShown(), "Pawn waits as well")
        RunTimers(0)
        assert_true(icon:IsShown())
        assert_eq(ArrowState(icon), yellow(ns))
    end)

    it("upgrade for both: green", function()
        start()
        PutItem(0, 3, "item:both")
        ContainerFrame1:Open({ 3 })
        assert_eq(ArrowState(arrow(ContainerFrame1, 3)), ORIGINAL)
    end)

    it("no upgrade: no arrow and nothing touched", function()
        start()
        PutItem(0, 4, "item:none")
        ContainerFrame1:Open({ 4 })
        local icon = arrow(ContainerFrame1, 4)
        assert_false(icon:IsShown(), "the addon shows no arrow of its own")
        assert_eq(icon.calls, 0)
        assert_eq(STUB.calls.upgrade, 0, "no Pawn question for slots without an arrow")
    end)

    it("an item level upgrade without a scale upgrade is yellow", function()
        local ns = start({ pawn = { upgrades = {}, ilvl = { ["item:ilvl"] = true } } })
        PutItem(0, 1, "item:ilvl")
        ContainerFrame1:Open({ 1 })
        assert_eq(ArrowState(arrow(ContainerFrame1, 1)), yellow(ns))
    end)

    it("a reused button goes yellow -> green -> off and is back in its original state", function()
        local ns = start()
        PutItem(0, 1, "item:other")
        ContainerFrame1:Open({ 1 })
        local button = BlizzardButton(ContainerFrame1, 1)
        assert_eq(ArrowState(button.UpgradeIcon), yellow(ns))

        PutItem(0, 1, "item:main")
        ContainerFrame1:Open({ 1 })
        assert_true(BlizzardButton(ContainerFrame1, 1) == button, "the pool hands out the same button")
        assert_true(button.UpgradeIcon:IsShown())
        assert_eq(ArrowState(button.UpgradeIcon), ORIGINAL)

        PutItem(0, 1, "item:other")
        ContainerFrame1:Open({ 1 })
        assert_eq(ArrowState(button.UpgradeIcon), yellow(ns))
        PutItem(0, 1, "item:none")
        ContainerFrame1:Open({ 1 })
        assert_false(button.UpgradeIcon:IsShown())
        assert_eq(ArrowState(button.UpgradeIcon), ORIGINAL, "hidden arrows are put back as well")
        assert_nil(ns.painted[button.UpgradeIcon])
    end)

    it("Pawn's delayed retry (first nil, then the answer) is colored as well", function()
        local ns = start({ pawn = { throttle = { ["item:other"] = 2 } } })
        PutItem(0, 1, "item:other")
        ContainerFrame1:Open({ 1 })
        local icon = arrow(ContainerFrame1, 1)
        assert_false(icon:IsShown(), "Pawn has no answer yet")
        RunTimers()
        assert_false(icon:IsShown(), "still throttled")
        RunTimers()
        assert_true(icon:IsShown(), "Pawn's retry shows the arrow")
        assert_eq(ArrowState(icon), yellow(ns))
    end)

    it("works when Pawn's bag hooks are added after this addon's (advisor turned on later)", function()
        local ns = ReloadAddon({ pawn = { upgrades = Copy(UPGRADES), advisor = false } })
        Login()
        PawnCommon.ShowBagUpgradeAdvisor = true
        STUB.pawnHookBags()
        PutItem(1, 1, "item:other")
        ContainerFrame2:Open({ 1 })
        assert_eq(ArrowState(arrow(ContainerFrame2, 1)), yellow(ns))
    end)

    it("the combined bag is covered", function()
        local ns = start()
        PutItem(0, 1, "item:other")
        PutItem(1, 1, "item:main")
        ContainerFrameCombinedBags:Open({ 1 }, 0)
        assert_eq(ArrowState(arrow(ContainerFrameCombinedBags, 1)), yellow(ns))
    end)

    it("changing the main scale repaints the visible arrows", function()
        local ns = start()
        PutItem(0, 1, "item:main")
        PutItem(0, 2, "item:other")
        ContainerFrame1:Open({ 1, 2 })
        assert_eq(ArrowState(arrow(ContainerFrame1, 1)), ORIGINAL)
        assert_eq(ArrowState(arrow(ContainerFrame1, 2)), yellow(ns))
        ns.SetMainScale("B")
        RunAllTimers()
        assert_eq(ArrowState(arrow(ContainerFrame1, 1)), yellow(ns))
        assert_eq(ArrowState(arrow(ContainerFrame1, 2)), ORIGINAL)
    end)

    it("PawnResetBags after a change in Pawn repaints with fresh answers", function()
        local ns = start()
        PutItem(0, 1, "item:other")
        ContainerFrame1:Open({ 1 })
        assert_eq(ArrowState(arrow(ContainerFrame1, 1)), yellow(ns))
        STUB.pawn.upgrades["item:other"] = { "A", "B" }
        PawnResetBags()
        RunAllTimers()
        assert_eq(ArrowState(arrow(ContainerFrame1, 1)), ORIGINAL)
    end)

    it("an arrow whose item Pawn cannot rate yet stays green and is checked again later", function()
        local ns = start({ pawn = { unknown = { ["item:other"] = 1 } } })
        PutItem(0, 1, "item:other")
        ContainerFrame1:Open({ 1 })
        local icon = arrow(ContainerFrame1, 1)
        assert_eq(ArrowState(icon), ORIGINAL)
        RunAllTimers()
        assert_eq(ArrowState(icon), yellow(ns))
    end)

    it("the retries for unrated items are limited", function()
        local ns = start({ pawn = { unknown = { ["item:other"] = 1000 } } })
        PutItem(0, 1, "item:other")
        ContainerFrame1:Open({ 1 })
        RunAllTimers(100)
        assert_eq(ns.retries, ns.MAX_RETRIES)
        assert_eq(#STUB.timers, 0)
    end)

    it("turning the colors off puts every arrow back, turning them on paints again", function()
        local ns = start()
        PutItem(0, 1, "item:other")
        ContainerFrame1:Open({ 1 })
        ns.SetEnabled(false)
        RunAllTimers()
        assert_eq(ArrowState(arrow(ContainerFrame1, 1)), ORIGINAL)
        ContainerFrame1:Open({ 1 })
        assert_eq(ArrowState(arrow(ContainerFrame1, 1)), ORIGINAL, "stays green while off")
        ns.SetEnabled(true)
        RunAllTimers()
        assert_eq(ArrowState(arrow(ContainerFrame1, 1)), yellow(ns))
    end)

    it("style tint: the original arrow desaturated and tinted, put back on green", function()
        local ns = start({ saved = { style = "tint" } })
        PutItem(0, 1, "item:other")
        ContainerFrame1:Open({ 1 })
        local icon = arrow(ContainerFrame1, 1)
        assert_eq(ArrowState(icon), { graphic = "bags-greenarrow", coords = { 0.1, 0.2, 0.3, 0.4 }, vertex = { 1, 0.82, 0.1, 1 }, desaturated = true })
        PutItem(0, 1, "item:main")
        ContainerFrame1:Open({ 1 })
        assert_eq(ArrowState(icon), ORIGINAL)
    end)

    it("switching the style while an arrow is yellow repaints it in the new style", function()
        local ns = start()
        PutItem(0, 1, "item:other")
        ContainerFrame1:Open({ 1 })
        local icon = arrow(ContainerFrame1, 1)
        ns.SetStyle("tint")
        RunAllTimers()
        assert_eq(ArrowState(icon), { graphic = "bags-greenarrow", coords = { 0.1, 0.2, 0.3, 0.4 }, vertex = { 1, 0.82, 0.1, 1 }, desaturated = true })
        ns.SetStyle("texture")
        RunAllTimers()
        assert_eq(ArrowState(icon), yellow(ns))
    end)

    it("no Blizzard bag frames: the path is off with one message", function()
        local ns = ReloadAddon({ blizzard = false })
        Login()
        assert_true(ns.setupDone)
        assert_false(ns.paths.blizzard.active)
        assert_contains(Output(), "Blizzard's bag frames were not found")
    end)

    it("the addon writes no fields to Blizzard's buttons or arrows apart from its secure hooks", function()
        start()
        PutItem(0, 1, "item:other")
        ContainerFrame1:Open({ 1 })
        local button = BlizzardButton(ContainerFrame1, 1)
        local keys = {}
        for k in pairs(button) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        assert_eq(keys, { "GetBagID", "GetID", "GetParent", "UpgradeIcon", "bagID", "frame", "slotID" })
        -- the arrow texture: the stand-in's methods and simulated texture state, plus nothing but the
        -- three methods replaced by hooksecurefunc
        local methods = STUB.textureMethods[button.UpgradeIcon]
        local state = { parent = true, shown = true, vertex = true, desaturated = true, coords = true,
            calls = true, atlas = true, texture = true }
        local added = {}
        for k, v in pairs(button.UpgradeIcon) do
            if type(v) == "function" then
                if v ~= methods[k] then added[#added + 1] = tostring(k) end
            elseif not state[k] then
                added[#added + 1] = tostring(k)
            end
        end
        table.sort(added)
        assert_eq(added, { "Hide", "SetShown", "Show" })
    end)
end)
